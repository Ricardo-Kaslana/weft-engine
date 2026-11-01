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
  final project = Directory.systemTemp.createTempSync('weft_ios_');

  stdout.writeln('iOS smoke: $gitUrl at $ref');
  try {
    await _run(project, 'flutter', [
      'create',
      '--platforms=ios',
      '--org',
      'dev.weft',
      '--project-name',
      'weft_ios_smoke',
      '.',
    ]);
    _writeProject(project, gitUrl: gitUrl, ref: ref);
    await _run(project, 'flutter', const ['pub', 'get']);
    await _run(project, 'pod', const ['install', '--project-directory=ios']);
    await _run(project, 'flutter', const [
      'build',
      'ios',
      '--no-codesign',
      '--release',
    ]);
    _verifySymbols(project);
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
}) {
  File('${project.path}/pubspec.yaml').writeAsStringSync('''
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
''');
  File('${project.path}/lib/main.dart').writeAsStringSync(_iosApp);
}

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
  List<String> arguments,
) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: project.path,
    environment: _noProxyEnvironment(),
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final status = await process.exitCode;
  if (status != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed ($status)');
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
