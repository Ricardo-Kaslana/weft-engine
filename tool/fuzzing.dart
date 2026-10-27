// Seed-based fuzzing engine for the Weft normalizer (ADR 0034).
//
// Shared by:
// - `packages/weft_document/test/fuzz_test.dart` (short deterministic run in
//   the CI gate), and
// - `tool/fuzz.dart` (long-running CLI with crash reproduction output).
//
// The corpus is the committed conformance HTML plus the normalization
// vectors. Mutations keep a fixed seed policy so failures reproduce exactly;
// any crash must be fixed or turned into a pinned vector, never silenced.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:weft_document/weft_document.dart';

/// One seeded normalization exercise.
final class FuzzCase {
  const FuzzCase(this.name, this.input, this.limits);

  final String name;
  final String input;
  final WeftNormalizationLimits limits;
}

final class FuzzConfig {
  const FuzzConfig({
    this.iterations = 400,
    this.seed = 20261027,
    this.stopOnCrash = true,
    this.roundTripEvery = 20,
  });

  final int iterations;
  final int seed;

  /// Whether the first crash aborts the run (tool default) or is collected
  /// and the run continues (CI suite reports all of them at once).
  final bool stopOnCrash;

  /// Every Nth case also verifies encode→decode→encode byte stability;
  /// full-tree decode is the slow part, so it is sampled.
  final int roundTripEvery;
}

final class FuzzResult {
  final int executed;
  final List<Object> crashes;

  const FuzzResult(this.executed, this.crashes);
}

final _mutationAlphabet = <String>[
  '<',
  '>',
  '"',
  "'",
  '&',
  '/',
  '=',
  ';',
  ':',
  '#',
  '!',
  '-',
  '(',
  ')',
  '{',
  '}',
  'p',
  'i',
  'f',
  '<div',
  '</p>',
  '<table>',
  '<td>',
  '<tr>',
  '<style>',
  '<script>',
  '<img ',
  '<weft-badge ',
  '<!--',
  '-->',
  '&#',
  '&#x',
  '&amp',
  '&lt',
  '\u0000',
  '\n',
  '中文',
  '😃',
  ' ',
  'a',
];

/// Deterministically loads the committed corpus: every conformance case and
/// every normalization vector input.
List<FuzzCase> loadCorpus({WeftNormalizationLimits? limits}) {
  final root = _workspaceRoot();
  final htmls = <String>[];
  final casesDir = Directory('${root.path}/conformance/cases');
  if (casesDir.existsSync()) {
    for (final entity in casesDir.listSync().whereType<File>()) {
      if (entity.path.endsWith('.html')) {
        htmls.add(entity.readAsStringSync());
      }
    }
  }
  final vectorsDir = Directory('${root.path}/conformance/normalization');
  if (vectorsDir.existsSync()) {
    for (final entity in vectorsDir.listSync().whereType<File>()) {
      if (!entity.path.endsWith('.json')) continue;
      final vector =
          jsonDecode(entity.readAsStringSync()) as Map<String, Object?>;
      htmls.add(vector['input']! as String);
    }
  }
  if (htmls.isEmpty) {
    throw StateError('No corpus found; run from the Weft workspace.');
  }
  // Small limits keep every iteration cheap while still exercising the
  // node/depth/issue cap paths; the unit suites cover default-limit runs.
  return [
    for (var i = 0; i < htmls.length; i++)
      FuzzCase(
        'corpus-$i',
        htmls[i],
        limits ??
            const WeftNormalizationLimits(
              maxNodes: 4000,
              maxDepth: 48,
              maxIssues: 24,
            ),
      ),
  ];
}

/// Applies one random mutation and returns the mutated markup. Operators
/// cover structural damage (truncation, slicing, duplication), token-level
/// damage (alphabet flips, entity storms), and resource pressure (nesting
/// bombs, attribute storms).
String mutate(String html, Random rng) {
  if (html.isEmpty) html = '<body><p>seed</p></body>';
  final operator = rng.nextInt(8);
  switch (operator) {
    case 0: // truncate
      return html.substring(0, rng.nextInt(html.length));
    case 1: // flip up to 8 characters
      final chars = html.runes.toList();
      for (var i = 0; i < 8 && chars.isNotEmpty; i++) {
        final index = rng.nextInt(chars.length);
        final replacement =
            _mutationAlphabet[rng.nextInt(_mutationAlphabet.length)];
        chars[index] = replacement.runes.first;
      }
      return String.fromCharCodes(chars);
    case 2: // duplicate a slice
      final start = rng.nextInt(html.length);
      final end = start + rng.nextInt(html.length - start + 1);
      final insertAt = rng.nextInt(html.length);
      return html.replaceRange(insertAt, insertAt, html.substring(start, end));
    case 3: // delete a slice
      final start = rng.nextInt(html.length);
      final end = start + rng.nextInt(html.length - start + 1);
      return html.replaceRange(start, end, '');
    case 4: // inject tag soup
      final insertAt = rng.nextInt(html.length + 1);
      final fragment = _mutationAlphabet[rng.nextInt(_mutationAlphabet.length)];
      return html.replaceRange(insertAt, insertAt, fragment);
    case 5: // nesting bomb
      final depth = 8 + rng.nextInt(64);
      final tag = ['div', 'span', 'em', 'blockquote'][rng.nextInt(4)];
      final inner = html.substring(0, html.length < 512 ? html.length : 512);
      return '<body>${'<$tag>' * depth}$inner${'</$tag>' * depth}</body>';
    case 6: // attribute storm
      final attrCount = 4 + rng.nextInt(24);
      final buffer = StringBuffer('<p');
      for (var i = 0; i < attrCount; i++) {
        buffer.write(' attr$i="${_mutationAlphabet[rng.nextInt(
          _mutationAlphabet.length,
        )]}"');
      }
      buffer.write(
          '>${html.substring(0, html.length < 256 ? html.length : 256)}</p>');
      return buffer.toString();
    default: // entity storm
      final insertAt = rng.nextInt(html.length);
      const entities = ['&', '&#0;', '&#xZZ;', '&nosuch;', '&amp;amp;'];
      return html.replaceRange(
        insertAt,
        insertAt,
        entities[rng.nextInt(entities.length)] * (1 + rng.nextInt(5)),
      );
  }
}

/// Structural invariants every normalized snapshot must satisfy, regardless
/// of how hostile the input was (ADR 0034 hardening).
void checkSnapshotInvariants(
  WeftDocumentSnapshot snapshot,
  WeftNormalizationLimits limits,
) {
  final body = snapshot.body;
  if (body == null) {
    if (snapshot.normalizedHtml.isNotEmpty) {
      throw StateError('body is null but normalizedHtml is not empty');
    }
    if (!snapshot.supportReport.hasErrors) {
      throw StateError('body is null but no error-severity issue reported');
    }
  } else {
    // normalizedHtml is the serialization of the body's children: a
    // non-empty body must serialize to something, and an empty body
    // serializes to '' by definition (it renders nothing).
    final bodyHasChildren = body.children.isNotEmpty;
    if (bodyHasChildren && snapshot.normalizedHtml.isEmpty) {
      throw StateError('body has children but normalizedHtml is empty');
    }
    if (!bodyHasChildren && snapshot.normalizedHtml.isNotEmpty) {
      throw StateError('empty body but normalizedHtml is not empty');
    }
  }
  if (snapshot.supportReport.issues.length > limits.maxIssues) {
    throw StateError(
      'issues (${snapshot.supportReport.issues.length}) exceed maxIssues '
      '(${limits.maxIssues})',
    );
  }

  var nodeCount = 0;
  final seenIds = <int>{};
  void walk(WeftNode node, int parentId) {
    nodeCount += 1;
    if (nodeCount > limits.maxNodes) {
      throw StateError('node count exceeds maxNodes');
    }
    if (node.id < 0) throw StateError('negative node id');
    if (!seenIds.add(node.id)) {
      throw StateError('duplicate node id ${node.id}');
    }
    if (parentId >= 0 && node.id <= parentId) {
      throw StateError('node id ${node.id} not greater than parent $parentId');
    }
    if (node is WeftElement) {
      for (final child in node.children) {
        walk(child, node.id);
      }
    }
  }

  if (snapshot.body != null) walk(snapshot.body!, -1);
  if (nodeCount > limits.maxNodes) {
    throw StateError('node count $nodeCount exceeds maxNodes');
  }
}

FuzzResult runFuzz(FuzzConfig config, {void Function(String)? onCrash}) {
  final corpus = loadCorpus();
  final rng = Random(config.seed);
  final crashes = <Object>[];
  var executed = 0;
  const normalizer = WeftNormalizer();

  for (var i = 0; i < config.iterations; i++) {
    final seedCase = corpus[rng.nextInt(corpus.length)];
    var input = seedCase.input;
    final mutationCount = 1 + rng.nextInt(3);
    for (var m = 0; m < mutationCount; m++) {
      input = mutate(input, rng);
    }
    final limits = seedCase.limits;
    executed += 1;
    try {
      final snapshot = WeftNormalizer(limits: limits)
          .normalize(input, id: 'fuzz', revision: 1);
      checkSnapshotInvariants(snapshot, limits);
      if (config.roundTripEvery > 0 && i % config.roundTripEvery == 0) {
        final encoded = WeftDocumentJson.encodeToString(snapshot);
        final decoded = WeftDocumentJson.decodeFromString(encoded);
        final reencoded = WeftDocumentJson.encodeToString(decoded);
        if (reencoded != encoded) {
          throw StateError('round trip changed the snapshot encoding');
        }
      }
    } on Object catch (error) {
      if (onCrash != null) {
        onCrash('seed=${config.seed} iteration=$i case=${seedCase.name}\n'
            '--- input ---\n$input');
      }
      crashes.add(error);
      if (config.stopOnCrash) rethrow;
    }
  }
  // Exercise the default-limit normalizer once per run with the untouched
  // corpus so the plain configuration stays covered too.
  if (config.iterations > 0) {
    for (final seedCase
        in loadCorpus(limits: const WeftNormalizationLimits())) {
      final snapshot =
          normalizer.normalize(seedCase.input, id: 'fuzz-plain', revision: 1);
      checkSnapshotInvariants(snapshot, seedCase.limits);
      executed += 1;
    }
  }
  return FuzzResult(executed, crashes);
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
              RegExp(r'^workspace:', multiLine: true),
            )) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not find the Weft workspace root.');
    }
    current = parent;
  }
}
