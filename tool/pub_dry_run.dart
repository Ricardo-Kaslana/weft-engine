import 'dart:convert';
import 'dart:io';

/// Packages in dependency order with the toolchain they must be published with.
///
/// Flutter packages depend on `sdk: flutter`, so only `flutter pub` can archive
/// them; the rest are pure Dart.
const _packages = <String, String>{
  'weft_runtime_api': 'dart',
  'weft_document': 'dart',
  'weft_capabilities': 'dart',
  'weft_runtime_fake': 'dart',
  'weft_runtime_contract': 'dart',
  'weft_engine': 'flutter',
  'weft_quickjs': 'flutter',
  'weft': 'flutter',
};

/// `pub` always warns about uncommitted files; CI publishes from a clean
/// checkout, so that warning is not a release blocker.
final _gitDirtyWarning = RegExp(
  r'^\* \d+ checked-in files? (?:is|are) modified in git\.$',
);

/// Runs `pub publish --dry-run` for every package and fails on any blocking
/// validation issue.
///
/// Warnings are treated as failures on purpose: pub downgrades most authoring
/// mistakes (missing README, undeclared test imports, mismatched library names)
/// to warnings, and a package that is worth publishing should be clean.
Future<void> main(List<String> arguments) async {
  if (!File('pubspec.yaml').existsSync() ||
      !File('pubspec.yaml').readAsStringSync().contains('workspace:')) {
    stderr.writeln('Run this command from the Weft workspace root.');
    exitCode = 2;
    return;
  }

  var failures = 0;
  for (final entry in _packages.entries) {
    final name = entry.key;
    final tool = entry.value;
    final dir = Directory('packages/$name');
    if (!dir.existsSync()) {
      stderr.writeln('missing package directory: ${dir.path}');
      failures += 1;
      continue;
    }

    final pubspec = File('${dir.path}/pubspec.yaml').readAsStringSync();
    if (pubspec.contains('publish_to: none')) {
      stderr.writeln('$name still declares `publish_to: none`.');
      failures += 1;
      continue;
    }

    stdout.write('$name ($tool) ... ');
    final result = await Process.run(
      tool,
      const ['pub', 'publish', '--dry-run'],
      workingDirectory: dir.path,
      runInShell: Platform.isWindows,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: _noProxyEnvironment(),
    );
    final output = '${result.stdout}\n${result.stderr}';
    final issues = _blockingIssues(output);
    // `pub` exits 65 whenever validation reports anything, warnings included,
    // so the parsed result decides. A run that never reached "Validating
    // package" failed earlier (resolution, network) and must not pass.
    final validated = output.contains('Validating package') &&
        (output.contains('Package has') || output.contains('No issues found'));

    if (!validated || issues.isNotEmpty) {
      failures += 1;
      stdout.writeln('FAILED');
      stdout.writeln(output.trim());
      continue;
    }
    final size = RegExp(
      r'Total compressed archive size: (.+)\.',
    ).firstMatch(output)?.group(1);
    stdout.writeln(size == null ? 'ok' : 'ok ($size)');
  }

  if (failures > 0) {
    stderr.writeln('\npub dry-run failed for $failures package(s).');
    exitCode = 1;
    return;
  }
  stdout.writeln(
      '\nAll ${_packages.length} packages pass pub publish --dry-run.');
}

/// Validation bullets that must block the gate.
List<String> _blockingIssues(String output) {
  final issues = <String>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trimRight();
    if (!trimmed.startsWith('* ')) continue;
    if (_gitDirtyWarning.hasMatch(trimmed)) continue;
    issues.add(trimmed);
  }
  return issues;
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
