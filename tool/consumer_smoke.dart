import 'dart:convert';
import 'dart:io';

const _consumerApp = '''
import 'package:flutter/widgets.dart';
import 'package:weft/weft.dart';

void main() {
  final controller = WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(
        '<h1>External consumer</h1><p>Git dependency resolved.</p>',
        id: 'consumer-app',
      ),
    );
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: WeftView(controller: controller),
    ),
  );
}
''';

const _consumerTest = '''
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  testWidgets('git dependency installs and renders through WeftView', (
    tester,
  ) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<h1>External consumer</h1><p>Git dependency resolved.</p>',
          id: 'consumer-smoke',
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 360,
          height: 400,
          child: WeftView(controller: controller, enableLazyLayout: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(WeftView), findsOneWidget);
    expect(find.byType(WeftSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
''';

/// Verifies that `weft` can be consumed outside this workspace.
///
/// The probe creates a disposable Flutter package, resolves `weft` at `HEAD`
/// from a `file://` URL, and runs its widget test.
///
/// `--mode git` (default) is the pre-publication install path: packages depend
/// on each other by version constraint, which pub can only satisfy from
/// pub.dev, so the probe adds `dependency_overrides` that pin every Weft
/// package to the same git ref. `--mode published` instead resolves plain
/// version constraints from pub.dev and must be used once the packages are
/// published.
///
/// Pass `--ref <tag-or-sha>` to test a release tag, `--version <published
/// version>` for the hosted mode, `--git-url <url>` to test a remote
/// repository, or `--keep` to retain the generated project for inspection.
Future<void> main(List<String> arguments) async {
  final root = Directory.current.absolute;
  if (!File('${root.path}/pubspec.yaml').existsSync() ||
      !File('${root.path}/pubspec.yaml')
          .readAsStringSync()
          .contains(RegExp(r'^workspace:', multiLine: true))) {
    stderr.writeln('Run this command from the Weft workspace root.');
    exitCode = 2;
    return;
  }

  final ref = _option(arguments, '--ref') ?? _git(root, ['rev-parse', 'HEAD']);
  final gitUrl = _option(arguments, '--git-url') ??
      Uri.file(root.path, windows: Platform.isWindows).toString();
  final keep = arguments.contains('--keep');
  final mode = _option(arguments, '--mode') ?? 'git';
  if (mode != 'git' && mode != 'published') {
    stderr.writeln('Unknown --mode "$mode" (expected git or published).');
    exitCode = 2;
    return;
  }
  final version = _option(arguments, '--version') ??
      RegExp(r'^version: (.+)$', multiLine: true)
          .firstMatch(
            File('${root.path}/packages/weft/pubspec.yaml').readAsStringSync(),
          )
          ?.group(1)
          ?.trim();
  if (version == null) {
    stderr.writeln('Could not read the weft version from its pubspec.');
    exitCode = 2;
    return;
  }
  final project = Directory.systemTemp.createTempSync('weft_consumer_');

  stdout.writeln('Consumer smoke ($mode): $gitUrl at $ref, weft $version');
  try {
    _writeProject(
      project,
      gitUrl: gitUrl,
      ref: ref,
      mode: mode,
      version: version,
    );
    await _run(project, 'flutter', const ['pub', 'get']);
    await _run(project, 'flutter', const ['test', '--no-pub']);
    stdout.writeln('Consumer smoke passed.');
  } finally {
    if (keep) {
      stdout.writeln('Kept consumer project at ${project.path}');
    } else {
      project.deleteSync(recursive: true);
    }
  }
}

void _writeProject(
  Directory project, {
  required String gitUrl,
  required String ref,
  required String mode,
  required String version,
}) {
  Directory('${project.path}/lib').createSync(recursive: true);
  Directory('${project.path}/test').createSync(recursive: true);
  final weftDependency = mode == 'git'
      ? '''
  weft:
    git:
      url: ${jsonEncode(gitUrl)}
      ref: ${jsonEncode(ref)}
      path: packages/weft
'''
      : '''
  weft: ^$version
''';
  File('${project.path}/pubspec.yaml').writeAsStringSync('''
name: weft_consumer_smoke
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.35.5"

dependencies:
  flutter:
    sdk: flutter
$weftDependency
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  if (mode == 'git') {
    File('${project.path}/pubspec_overrides.yaml').writeAsStringSync(
      _gitOverrides(gitUrl: gitUrl, ref: ref),
    );
  }
  File('${project.path}/lib/main.dart').writeAsStringSync(_consumerApp);
  File('${project.path}/test/consumer_smoke_test.dart')
      .writeAsStringSync(_consumerTest);
}

/// Pins every Weft package to the same git ref.
///
/// Until the packages exist on pub.dev, a git dependency on `weft` alone cannot
/// resolve: its siblings are declared as `^<version>` and pub only looks for
/// them on the hosted server. This is the pre-publication install path users
/// need, and [main] documents it.
String _gitOverrides({required String gitUrl, required String ref}) {
  const siblings = <String>[
    'weft_runtime_api',
    'weft_document',
    'weft_capabilities',
    'weft_runtime_fake',
    'weft_runtime_contract',
    'weft_engine',
    'weft_quickjs',
  ];
  final buffer = StringBuffer('dependency_overrides://n');
  for (final name in siblings) {
    buffer.writeln('  $name:');
    buffer.writeln('    git:');
    buffer.writeln('      url: ${jsonEncode(gitUrl)}');
    buffer.writeln('      ref: ${jsonEncode(ref)}');
    buffer.writeln('      path: packages/$name');
  }
  return buffer.toString();
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
    throw StateError(
      'git ${arguments.join(' ')} failed: ${result.stderr}',
    );
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
