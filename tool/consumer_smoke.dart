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

/// Verifies that `weft` can be consumed outside this workspace via a Git
/// dependency.
///
/// By default the probe clones the current repository at `HEAD` from a
/// `file://` URL, creates a disposable Flutter package, resolves `weft` from
/// `packages/weft`, and runs its widget test. Pass `--ref <tag-or-sha>` to test
/// a release tag, `--git-url <url>` to test a remote repository, or `--keep`
/// to retain the generated project for inspection.
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
  final project = Directory.systemTemp.createTempSync('weft_consumer_');

  stdout.writeln('Consumer smoke: $gitUrl at $ref');
  try {
    _writeProject(project, gitUrl: gitUrl, ref: ref);
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
}) {
  Directory('${project.path}/lib').createSync(recursive: true);
  Directory('${project.path}/test').createSync(recursive: true);
  File('${project.path}/pubspec.yaml').writeAsStringSync('''
name: weft_consumer_smoke
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.35.5"

dependencies:
  flutter:
    sdk: flutter
  weft:
    git:
      url: ${jsonEncode(gitUrl)}
      ref: ${jsonEncode(ref)}
      path: packages/weft

dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  File('${project.path}/lib/main.dart').writeAsStringSync(_consumerApp);
  File('${project.path}/test/consumer_smoke_test.dart')
      .writeAsStringSync(_consumerTest);
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
