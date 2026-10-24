import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = _workspaceRoot();
  final manifestFile = File('${root.path}/conformance/manifest.json');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final cases =
      (manifest['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

  test('conformance manifest has unique cases and existing fixtures', () {
    expect(manifest['version'], 1);
    expect(cases, isNotEmpty);
    final ids = cases.map((item) => item['id'] as String).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final item in cases) {
      final file = File('${root.path}/conformance/${item['file']}');
      expect(file.existsSync(), isTrue, reason: 'Missing ${file.path}');
    }
  });

  for (final item in cases) {
    final id = item['id'] as String;
    test('corpus $id normalizes and lays out without overflow', () {
      final source = File(
        '${root.path}/conformance/${item['file']}',
      ).readAsStringSync();
      final width = (item['width'] as num).toDouble();
      final snapshot = const WeftNormalizer().normalize(
        source,
        id: 'conformance-$id',
      );
      final report = snapshot.supportReport;
      expect(
        report.canRender,
        isTrue,
        reason: report.issues
            .map((issue) => '${issue.code}: ${issue.message}')
            .join('\n'),
      );

      final layout = const WeftLayoutEngine().layout(snapshot, width: width);
      addTearDown(layout.dispose);

      expect(
        layout.size.height,
        greaterThanOrEqualTo((item['minHeight'] as num).toDouble()),
      );
      expect(
        layout.commands.whereType<WeftTextPaintCommand>().length,
        greaterThanOrEqualTo(item['minTextCommands'] as int),
      );
      expect(
        layout.boxes.length,
        greaterThanOrEqualTo(item['minBoxes'] as int),
      );
      expect(
        layout.links.map((link) => link.href),
        item['linkHrefs'] as List<dynamic>,
      );

      for (final box in layout.boxes) {
        expect(box.rect.left, greaterThanOrEqualTo(-0.5));
        expect(box.rect.right, lessThanOrEqualTo(width + 0.5));
        expect(box.rect.top, greaterThanOrEqualTo(-0.5));
        expect(box.rect.bottom, lessThanOrEqualTo(layout.size.height + 0.5));
      }
      for (final link in layout.links) {
        for (final rect in link.rects) {
          expect(rect.left, greaterThanOrEqualTo(-0.5));
          expect(rect.right, lessThanOrEqualTo(width + 0.5));
        }
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
