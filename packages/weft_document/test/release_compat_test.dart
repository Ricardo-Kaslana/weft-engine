import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:weft_document/weft_document.dart';

/// Rollback rehearsal (ADR 0034, docs/release-runbook.md §5).
///
/// This suite is the automated evidence for the phase 5 acceptance item
/// "回滚路径经过演练": it pins the version-gate behavior a host relies on
/// when pinning back to an older engine, and proves the committed
/// normalization vectors (produced by earlier releases) still reproduce
/// byte-for-byte on the current engine.
void main() {
  final root = _workspaceRoot();
  final vectorDir = Directory('${root.path}/conformance/normalization');
  final vectors = <File>[];
  if (vectorDir.existsSync()) {
    for (final entity in vectorDir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        vectors.add(entity);
      }
    }
    vectors.sort((a, b) => a.path.compareTo(b.path));
  }

  test('commit-produced vectors still reproduce on the current engine', () {
    expect(vectors.length, greaterThanOrEqualTo(21));
    for (final file in vectors) {
      final vector =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final snapshot = (vector['snapshot']! as Map);
      final produced = WeftDocumentJson.encodeToString(
        WeftNormalizer(
          customTags:
              ((vector['normalizer']! as Map)['customTags'] as List<Object?>)
                  .cast<String>()
                  .toSet(),
        ).normalize(
          vector['input']! as String,
          id: snapshot['id']! as String,
          revision: snapshot['revision']! as int,
        ),
      );
      final pinned = WeftDocumentJson.encodeToString(WeftDocumentJson.decode(
        vector['expected']! as Map<String, Object?>,
      ));
      expect(produced, pinned, reason: 'vector ${file.path} drifted');
    }
  });

  group('version gates a host relies on when rolling back', () {
    test('a newer snapshot format is rejected, never misread', () {
      final json = WeftDocumentJson.encode(WeftDocumentSnapshot(
        id: 'future',
        revision: 1,
        normalizedHtml: '<p>hi</p>',
        body: WeftElement(
          id: 0,
          tag: 'body',
          children: [const WeftText(id: 1, text: 'hi')],
        ),
      ))
        ..['version'] = WeftDocumentJson.version + 1;

      expect(
        () => WeftDocumentJson.decode(json),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('newer than this engine supports'),
              contains('${WeftDocumentJson.version + 1}'),
            ),
          ),
        ),
      );
    });

    test('a foreign payload is rejected by the format tag', () {
      expect(
        () => WeftDocumentJson.decode(<String, Object?>{
          'format': 'weft.document2',
          'version': WeftDocumentJson.version,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('the release contract anchor values are the documented ones', () {
      // docs/release-runbook.md §2 pins these values; changing them is a
      // compatibility event that must update the runbook in the same commit.
      expect(WeftDocumentJson.formatId, 'weft.document');
      expect(WeftDocumentJson.version, 1);
    });
  });
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
