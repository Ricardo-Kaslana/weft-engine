import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

/// Normalization consistency vectors (ADR 0034).
///
/// The committed files under `conformance/normalization/` are the contract
/// between a server-side producer (runs [WeftNormalizer] once, ships the
/// encoded snapshot) and any client consumer (decodes the snapshot instead
/// of re-parsing HTML). Every CI run re-normalizes the recorded input and
/// demands byte-identical output, so normalization drift between releases
/// — or between a server and a client on different weft_document versions —
/// fails loudly here instead of shipping divergent content.
///
/// Regenerating vectors is a reviewed change: run
/// `dart run tool/normalization_vectors.dart` and inspect the diff, the
/// same policy as the browser geometry references.
void main() {
  final root = _workspaceRoot();
  final vectorDir = Directory('${root.path}/conformance/normalization');
  final files = <File>[];
  if (vectorDir.existsSync()) {
    for (final entity in vectorDir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
  }

  test('normalization vectors exist', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final vector = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    test('vector $name reproduces its pinned snapshot', () {
      final id = (vector['snapshot']! as Map)['id']! as String;
      final revision = (vector['snapshot']! as Map)['revision']! as int;
      final customTags =
          ((vector['normalizer']! as Map)['customTags'] as List<Object?>)
              .cast<String>();
      final input = vector['input']! as String;

      final snapshot = WeftNormalizer(customTags: customTags.toSet())
          .normalize(input, id: id, revision: revision);

      final expected = vector['expected']! as Map<String, Object?>;
      final expectedCanonical =
          WeftDocumentJson.encodeToString(WeftDocumentJson.decode(expected));
      final produced = WeftDocumentJson.encodeToString(snapshot);

      expect(
        produced,
        expectedCanonical,
        reason: 'Normalization output drifted from the pinned vector. '
            'If the change is intended, regenerate with '
            '`dart run tool/normalization_vectors.dart` and review the diff.',
      );

      // The pinned snapshot itself must survive a decode/re-encode cycle
      // unchanged, proving the wire format is stable for consumers.
      expect(
        WeftDocumentJson.encodeToString(
          WeftDocumentJson.decodeFromString(expectedCanonical),
        ),
        expectedCanonical,
      );
    });

    test('vector $name reports actionable support state', () {
      final expected = vector['expected']! as Map<String, Object?>;
      final decoded = WeftDocumentJson.decode(expected);
      final issues = decoded.supportReport.issues;
      expect(issues.length, lessThanOrEqualTo(100));
      for (final issue in issues) {
        expect(issue.code, isNotEmpty);
        expect(issue.message, isNotEmpty);
      }
      if (decoded.supportReport.requiresWebView) {
        expect(decoded.supportReport.issues, isNotEmpty);
      }
    });
  }
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
