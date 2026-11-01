import 'dart:convert';
import 'dart:io';

const _iosApp = r'''
import 'package:flutter/material.dart';
import 'package:weft_quickjs/weft_quickjs.dart';

void main() {
  final available = QuickJsNativeLibrary.isLoadable;
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Text('QuickJS native library: $available'),
      ),
    ),
  );
}
''';

/// Builds a disposable iOS host against the current repository and verifies
/// that QuickJS was linked into the app bundle.
///
/// This runs on macOS only. It creates a temporary Flutter app with a Git
/// dependency on `packages/weft_quickjs`, runs CocoaPods, builds an unsigned
/// device app, and checks the `weft_*` symbols in the resulting binary.
/// Pass `--ref <tag-or-sha>` to test a release tag or `--keep` to retain the
/// generated project for inspection.
///
/// `--runtime` additionally runs an integration test on a booted iOS
/// simulator: it loads the native entry points from the app image, evaluates a
/// script, interrupts an infinite loop at the wall-clock budget, and proves a
/// fresh session still works afterwards. Build and symbol checks alone cannot
/// show that the shipped binary actually executes JavaScript.
Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    stderr.writeln('iOS smoke requires macOS with Xcode and CocoaPods.');
    exitCode = 2;
    return;
  }

  final root = Directory.current.absolute;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this command from the Weft workspace root.');
    exitCode = 2;
    return;
  }

  final ref = _option(arguments, '--ref') ?? _git(root, ['rev-parse', 'HEAD']);
  final gitUrl = _option(arguments, '--git-url') ??
      Uri.file(root.path, windows: Platform.isWindows).toString();
  final keep = arguments.contains('--keep');
  final runtime = arguments.contains('--runtime');
  final project = Directory.systemTemp.createTempSync('weft_ios_');

  stdout.writeln('iOS smoke: $gitUrl at $ref');
  try {
    await _run(
      project,
      'flutter',
      [
        'create',
        '--platforms=ios',
        '--org',
        'dev.weft',
        '--project-name',
        'weft_ios_smoke',
        '.',
      ],
      timeout: const Duration(minutes: 5),
    );
    _writeProject(project, gitUrl: gitUrl, ref: ref, runtime: runtime);
    await _run(
      project,
      'flutter',
      const ['pub', 'get'],
      timeout: const Duration(minutes: 5),
    );
    await _run(
      project,
      'pod',
      const ['install', '--project-directory=ios'],
      timeout: const Duration(minutes: 8),
    );
    await _run(
      project,
      'flutter',
      const ['build', 'ios', '--no-codesign', '--release'],
      timeout: const Duration(minutes: 20),
    );
    _verifySymbols(project);
    if (runtime) {
      final simulator = await _bootSimulator();
      await _runSimulatorSmoke(project, simulator);
      stdout.writeln('iOS runtime smoke passed on $simulator.');
    }
  } finally {
    if (keep) {
      stdout.writeln('Kept iOS project at ${project.path}');
    } else {
      project.deleteSync(recursive: true);
    }
  }
}

void _writeProject(
  Directory project, {
  required String gitUrl,
  required String ref,
  required bool runtime,
}) {
  File(
    '${project.path}/pubspec.yaml',
  ).writeAsStringSync(
      buildIosSmokePubspec(gitUrl: gitUrl, ref: ref, runtime: runtime));
  File('${project.path}/lib/main.dart').writeAsStringSync(_iosApp);
  if (runtime) {
    Directory('${project.path}/integration_test').createSync(recursive: true);
    File(
      '${project.path}/integration_test/runtime_smoke_test.dart',
    ).writeAsStringSync(iosRuntimeSmokeTest);
  }
}

/// Renders the disposable host's `pubspec.yaml`.
///
/// Kept pure so both modes can be parsed and checked without macOS; `--runtime`
/// adds the SDK test packages and the explicit `weft_runtime_api` dependency
/// the integration test imports.
String buildIosSmokePubspec({
  required String gitUrl,
  required String ref,
  required bool runtime,
}) {
  final devDependencies = runtime
      ? '''

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
'''
      : '';
  final extraDependency = runtime
      ? '''
  weft_runtime_api:
    git:
      url: ${jsonEncode(gitUrl)}
      ref: ${jsonEncode(ref)}
      path: packages/weft_runtime_api
'''
      : '';
  return '''
name: weft_ios_smoke
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.35.5"

dependencies:
  flutter:
    sdk: flutter
  weft_quickjs:
    git:
      url: ${jsonEncode(gitUrl)}
      ref: ${jsonEncode(ref)}
      path: packages/weft_quickjs
$extraDependency$devDependencies''';
}

/// Boots an available iPhone simulator and returns its UDID.
///
/// CI runners ship simulators shut down; `flutter test -d` needs a booted one.
Future<String> _bootSimulator() async {
  final list = await _xcrun(['simctl', 'list', 'devices', 'available']);
  final pattern = RegExp(
    r'^\s+(iPhone[^(]*?)\s+\(([0-9A-Fa-f-]{36})\)\s+\((Shutdown|Booted)\)',
    multiLine: true,
  );
  final matches = pattern.allMatches(list).toList();
  if (matches.isEmpty) {
    throw StateError('No available iPhone simulator found.');
  }
  final booted = matches.where((match) => match.group(3) == 'Booted');
  final chosen = booted.isNotEmpty ? booted.first : matches.first;
  final udid = chosen.group(2)!;
  stdout.writeln(
    'iOS runtime smoke: ${chosen.group(1)!.trim()} ($udid, ${chosen.group(3)})',
  );
  if (chosen.group(3) == 'Shutdown') {
    await _xcrun(['simctl', 'boot', udid]);
  }
  await _waitForBoot(udid);
  return udid;
}

/// Waits for the simulator to finish booting, failing instead of hanging.
Future<void> _waitForBoot(String udid) async {
  final result = await Process.run('xcrun', [
    'simctl',
    'bootstatus',
    udid,
    '-b',
  ]).timeout(
    const Duration(minutes: 4),
    onTimeout: () => throw StateError('simctl bootstatus timed out for $udid'),
  );
  if (result.exitCode != 0) {
    throw StateError('simctl bootstatus failed: ${result.stderr}');
  }
}

/// Runs `xcrun` and returns stdout, failing on a non-zero exit.
Future<String> _xcrun(List<String> arguments) async {
  final result = await Process.run('xcrun', arguments).timeout(
    const Duration(minutes: 4),
    onTimeout: () => throw StateError('xcrun ${arguments.join(' ')} timed out'),
  );
  if (result.exitCode != 0) {
    throw StateError('xcrun ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

/// Runs the runtime integration test on [simulator], retrying once on a fresh
/// boot.
///
/// The hosted macOS runner occasionally fails to attach to the app's VM
/// service ("log reader failed unexpectedly"), which surfaces as a test-harness
/// timeout rather than an assertion failure. Rebooting the simulator clears it;
/// a real regression fails both attempts, so the retry cannot mask one. The
/// per-test timeout stays short so a stuck connection costs minutes, not the
/// job's whole budget.
Future<void> _runSimulatorSmoke(Directory project, String simulator) async {
  for (var attempt = 1;; attempt++) {
    try {
      await _run(
        project,
        'flutter',
        [
          'test',
          'integration_test/runtime_smoke_test.dart',
          '-d',
          simulator,
          '--timeout',
          '180s',
          '--no-pub',
        ],
        timeout: const Duration(minutes: 8),
      );
      return;
    } on StateError {
      if (attempt >= 2) rethrow;
      stdout.writeln(
        'iOS runtime smoke attempt $attempt failed; rebooting the simulator '
        'and retrying once.',
      );
      await _restartSimulator(simulator);
    }
  }
}

Future<void> _restartSimulator(String udid) async {
  await Process.run('xcrun', ['simctl', 'shutdown', udid]).timeout(
    const Duration(minutes: 2),
    onTimeout: () => ProcessResult(0, 0, '', ''),
  );
  await _xcrun(['simctl', 'boot', udid]);
  await _waitForBoot(udid);
}

/// Integration test copied into the disposable host for `--runtime`.
///
/// It runs inside the iOS simulator, so it proves the shipped binary executes
/// JavaScript rather than only containing the symbols.
const iosRuntimeSmokeTest = r'''
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:weft_quickjs/weft_quickjs.dart';
import 'package:weft_runtime_api/weft_runtime_api.dart';

final class _NoopBridge implements BridgeDispatcher {
  @override
  Future<JsValue> dispatch(BridgeCall call) async {
    throw StateError('capability ${call.capability} is not enabled');
  }
}

RuntimeConfig _config(String documentId) => RuntimeConfig(
      documentId: documentId,
      memoryLimitBytes: 16 * 1024 * 1024,
      stackLimitBytes: 512 * 1024,
    );

const _budget = ExecutionBudget(timeout: Duration(seconds: 5));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resolves the QuickJS entry points from the app image', (
    tester,
  ) async {
    final library = QuickJsNativeLibrary.load();
    expect(library, isNotNull);
    expect(QuickJsNativeLibrary.isLoadable, isTrue);
  });

  testWidgets('evaluates JavaScript on the device', (tester) async {
    final session =
        await QuickJsFfiBackend().open(_config('eval'), _NoopBridge());
    addTearDown(session.dispose);

    final result = await session.execute(
      const ScriptUnit(id: 'sum', source: '1 + 2 * 3'),
      _budget,
    );

    expect(result.isSuccess, isTrue, reason: result.failure?.message);
    expect(result.value, 7);
  });

  testWidgets('interrupts an infinite loop and recovers in a fresh session', (
    tester,
  ) async {
    final watch = Stopwatch()..start();
    final session = await QuickJsFfiBackend().open(
      _config('interrupt'),
      _NoopBridge(),
    );
    final interrupted = await session.execute(
      const ScriptUnit(id: 'spin', source: 'while (true) {}'),
      const ExecutionBudget(timeout: Duration(milliseconds: 200)),
    );
    watch.stop();
    await session.dispose();

    expect(interrupted.isSuccess, isFalse);
    expect(interrupted.failure?.kind, RuntimeFailureKind.timeout);
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));

    final recovered = await QuickJsFfiBackend().open(
      _config('recover'),
      _NoopBridge(),
    );
    addTearDown(recovered.dispose);
    final result = await recovered.execute(
      const ScriptUnit(id: 'after', source: '6 * 7'),
      _budget,
    );

    expect(result.isSuccess, isTrue, reason: result.failure?.message);
    expect(result.value, 42);
  });
}
''';

const _expectedSymbols = <String>{
  '_weft_new_runtime',
  '_weft_set_deadline',
  '_weft_now_ms',
  '_weft_free_runtime',
  '_weft_eval',
  '_weft_pump_jobs',
  '_weft_install_bridge',
  '_weft_resolve',
  '_weft_send_event',
  '_weft_free_string',
};

void _verifySymbols(Directory project) {
  final app = Directory('${project.path}/build/ios/iphoneos/Runner.app');
  if (!app.existsSync()) {
    throw StateError('iOS app bundle not found at ${app.path}');
  }

  final symbolsByBinary = <String, Set<String>>{};
  for (final entity in app.listSync(recursive: true)) {
    if (entity is! File) continue;
    final result = Process.runSync('nm', ['-gU', entity.path]);
    if (result.exitCode != 0) continue;
    final found = <String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final match = RegExp(
        r'\b[Tt]\s+(_weft_[A-Za-z0-9_]+)$',
      ).firstMatch(line.trim());
      if (match != null) found.add(match.group(1)!);
    }
    if (found.isNotEmpty) {
      symbolsByBinary[entity.path] = found;
    }
  }

  final symbols = symbolsByBinary.values.expand((set) => set).toSet();
  final missing = _expectedSymbols.difference(symbols);
  final unexpected = symbols.difference(_expectedSymbols);
  if (missing.isNotEmpty || unexpected.isNotEmpty) {
    throw StateError(
      'QuickJS symbol verification failed.\n'
      'Missing: ${missing.toList()..sort()}\n'
      'Unexpected: ${unexpected.toList()..sort()}\n'
      'Found in: $symbolsByBinary',
    );
  }
  stdout.writeln(
    'iOS smoke passed: all ${_expectedSymbols.length} QuickJS symbols linked.',
  );
  symbolsByBinary.forEach((path, found) {
    stdout.writeln('  $path: ${found.toList()..sort()}');
  });
}

Future<void> _run(
  Directory project,
  String executable,
  List<String> arguments, {
  Duration? timeout,
}) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: project.path,
    environment: _noProxyEnvironment(),
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  // Every external command gets a hard ceiling: `flutter test` can hang forever
  // waiting for a device connection that never arrives, and a hung job burns
  // the whole workflow budget without producing a useful failure.
  final status = await process.exitCode.timeout(
    timeout ?? const Duration(minutes: 30),
    onTimeout: () {
      stdout.writeln('! $executable exceeded $timeout; killing it.');
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  if (status != 0) {
    throw StateError(
      '$executable ${arguments.join(' ')} failed ($status)'
      '${status == -1 ? ' after exceeding $timeout' : ''}',
    );
  }
}

Map<String, String> _noProxyEnvironment() {
  final configured = Platform.environment['NO_PROXY'] ??
      Platform.environment['no_proxy'] ??
      '';
  final entries = <String>{'localhost', '127.0.0.1', '::1'};
  if (configured.trim().isNotEmpty) {
    entries.addAll(
      configured
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty),
    );
  }
  final value = entries.join(',');
  return {'NO_PROXY': value, 'no_proxy': value};
}

String _git(Directory root, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return (result.stdout as String).trim();
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0) return null;
  if (index + 1 >= arguments.length) {
    throw ArgumentError.value(arguments, name, 'Missing value for $name');
  }
  return arguments[index + 1];
}
