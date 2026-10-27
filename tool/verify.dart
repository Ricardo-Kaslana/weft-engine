import 'dart:io';

const dartPackages = <String>[
  'packages/weft_document',
  'packages/weft_runtime_api',
  'packages/weft_capabilities',
  'packages/weft_quickjs',
  'packages/weft_runtime_fake',
  'packages/weft_runtime_contract',
];

const flutterPackages = <String>[
  'packages/weft_engine',
  'packages/weft',
  'example/weft_lab',
];

String localNoProxy() {
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
  return entries.join(',');
}

Future<int> run(
    String executable, List<String> arguments, String directory) async {
  stdout.writeln('> $executable ${arguments.join(' ')} ($directory)');
  final noProxy = localNoProxy();
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    environment: {'NO_PROXY': noProxy, 'no_proxy': noProxy},
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return process.exitCode;
}

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    throw StateError('Run this command from the workspace root.');
  }

  for (final package in dartPackages) {
    final result = await run('dart', const ['test'], package);
    if (result != 0) {
      exitCode = result;
      return;
    }
  }

  // The workspace pub get has already resolved dependencies; --no-pub keeps
  // repetitive runs from re-hitting the package mirror.
  for (final package in flutterPackages) {
    final result = await run('flutter', const ['test', '--no-pub'], package);
    if (result != 0) {
      exitCode = result;
      return;
    }
  }
}
