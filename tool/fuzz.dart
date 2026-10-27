// Long-running fuzz driver for the Weft normalizer.
//
//   dart run tool/fuzz.dart [--iterations N] [--seed S] [--continue]
//                           [--out build/fuzz]
//
// The CI gate runs the short seeded suite in packages/weft_document/test/
// fuzz_test.dart; this tool is for hardening sweeps before a release
// (release runbook): hundreds of thousands of mutations, reproducible by
// seed, with the exact failing markup written to --out for triage. Any
// crash is either fixed in the pipeline or pinned as a normalization
// vector — never silenced.
import 'dart:io';

import '../tool/fuzzing.dart' as fuzzing;

void main(List<String> arguments) {
  var iterations = 20000;
  var seed = 20261027;
  var stopOnCrash = true;
  var out = 'build/fuzz';
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    switch (argument) {
      case '--iterations':
        iterations = int.parse(arguments[++i]);
      case '--seed':
        seed = int.parse(arguments[++i]);
      case '--continue':
        stopOnCrash = false;
      case '--out':
        out = arguments[++i];
      default:
        stderr.writeln('unknown argument: $argument');
        exitCode = 64;
        return;
    }
  }

  final config = fuzzing.FuzzConfig(
    iterations: iterations,
    seed: seed,
    stopOnCrash: stopOnCrash,
    roundTripEvery: 50,
  );

  var crashIndex = 0;
  Directory(out).createSync(recursive: true);
  final stopwatch = Stopwatch()..start();
  try {
    final result = fuzzing.runFuzz(
      config,
      onCrash: (report) {
        final file = File('$out/crash-$crashIndex.txt');
        file.writeAsStringSync(report);
        stdout.writeln('crash $crashIndex written to ${file.path}');
        crashIndex += 1;
      },
    );
    stopwatch.stop();
    stdout.writeln(
      'fuzz done: ${result.executed} normalizations in '
      '${stopwatch.elapsedMilliseconds}ms, '
      '${result.crashes.length} crashes collected',
    );
    if (result.crashes.isNotEmpty) {
      exitCode = 1;
    }
  } on Object catch (error, stackTrace) {
    stopwatch.stop();
    stderr.writeln('fuzz stopped on crash after '
        '${stopwatch.elapsedMilliseconds}ms: $error');
    stderr.writeln(stackTrace.toString());
    exitCode = 1;
  }
}
