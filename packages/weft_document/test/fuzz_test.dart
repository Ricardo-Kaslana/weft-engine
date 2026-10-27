import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

import '../../../tool/fuzzing.dart';

/// Seed-based fuzzing of the normalization pipeline (ADR 0034).
///
/// The committed conformance corpus is mutated deterministically; every
/// iteration must either produce a valid snapshot with well-formed
/// diagnostics or — when the input trips a limit — the explicit fallback
/// issues. A crash here means the normalizer threw on hostile markup, which
/// is never acceptable: fix the pipeline or pin the input as a vector.
void main() {
  test('seeded fuzz run satisfies snapshot invariants', () {
    final result = runFuzz(const FuzzConfig(iterations: 400, seed: 20261027));
    expect(result.executed, greaterThan(400));
    expect(result.crashes, isEmpty);
  });

  test('different seed covers different mutations', () {
    final result = runFuzz(const FuzzConfig(iterations: 120, seed: 77));
    expect(result.crashes, isEmpty);
  });

  test('snapshot invariants reject malformed trees', () {
    const limits =
        WeftNormalizationLimits(maxNodes: 10, maxDepth: 8, maxIssues: 4);
    // Duplicate ids must be caught.
    expect(
      () => checkSnapshotInvariants(
        WeftDocumentSnapshot(
          id: 'x',
          revision: 1,
          normalizedHtml: '<p>a</p>',
          body: WeftElement(
            id: 0,
            tag: 'body',
            children: [
              const WeftText(id: 1, text: 'a'),
              const WeftText(id: 1, text: 'b'),
            ],
          ),
        ),
        limits,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('duplicate node id'),
        ),
      ),
    );

    // Missing body without an error issue must be caught.
    expect(
      () => checkSnapshotInvariants(
        const WeftDocumentSnapshot(
          id: 'x',
          revision: 1,
          normalizedHtml: '',
          body: null,
        ),
        limits,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no error-severity issue'),
        ),
      ),
    );
  });
}
