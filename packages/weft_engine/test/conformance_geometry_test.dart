import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

import '../tool/geometry_baseline.dart' as baseline;

/// Generic browser geometry gate: every manifest case with `geometry: true`
/// is laid out and compared element-by-element against its committed Chrome
/// reference. New cases only need a case file plus a regenerated reference:
///
///   node tool/browser_references.mjs --case <id> --emit-reference
///   flutter test test/conformance_geometry_test.dart --plain-name "geometry <id>"
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final root = baseline.workspaceRoot();
  final manifest = jsonDecode(
    File('${root.path}/conformance/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (manifest['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((item) => item['geometry'] == true)
      .toList();

  setUpAll(() async {
    expect(cases, isNotEmpty,
        reason: 'No geometry-enabled cases in the manifest.');
    await baseline.loadConformanceFonts(root);
  });

  for (final item in cases) {
    final id = item['id'] as String;
    test('geometry $id', () async {
      final width = (item['width'] as num).toDouble();
      final source = File(
        '${root.path}/conformance/${item['file']}',
      ).readAsStringSync();
      final document = const WeftNormalizer().normalize(source, id: id);
      expect(
        document.supportReport.canRender,
        isTrue,
        reason: 'Geometry case $id requested fallback.',
      );
      expect(document.body, isNotNull);

      final images = await baseline.resolveCaseImages(root, document);
      final layout = const WeftLayoutEngine().layout(
        document,
        width: width,
        images: images,
      );
      addTearDown(layout.dispose);

      final reference = baseline.loadGeometryReference(root, id);
      final pairs = baseline.mapReferenceToDocument(
        baseline.referenceElements(reference),
        document.body!,
      );

      final boxesByNode = <int, Rect>{
        for (final box in layout.boxes) box.nodeId: box.rect,
      };
      var maxDelta = 0.0;
      for (final (expected, element) in pairs) {
        final actual = boxesByNode[element.id];
        expect(
          actual,
          isNotNull,
          reason: 'No layout box for ${expected.tag}#${expected.key}.',
        );
        final tolerance = baseline.toleranceFor(expected.tag);
        expectRectClose(
          actual!,
          expected.rect,
          tolerance,
          label: '${expected.tag}#${expected.key}',
        );
        maxDelta = rectDelta(actual, expected.rect)
            .reduce((a, b) => a > b ? a : b)
            .abs();
      }

      expect(
        layout.size.height,
        moreOrLessEquals(
          (reference['documentHeight'] as num).toDouble(),
          epsilon: 2,
        ),
        reason: 'Document height diverged from Chrome (max element delta '
            '${maxDelta.toStringAsFixed(2)}px).',
      );
    });
  }
}

void expectRectClose(Rect actual, Rect expected, double epsilon,
    {required String label}) {
  for (final (name, aValue, eValue) in [
    ('left', actual.left, expected.left),
    ('top', actual.top, expected.top),
    ('width', actual.width, expected.width),
    ('height', actual.height, expected.height),
  ]) {
    expect(
      aValue,
      moreOrLessEquals(eValue, epsilon: epsilon),
      reason: '$label $name diverged from Chrome: '
          '$aValue vs $eValue (tolerance $epsilon).',
    );
  }
}

List<double> rectDelta(Rect actual, Rect expected) {
  return [
    actual.left - expected.left,
    actual.top - expected.top,
    actual.width - expected.width,
    actual.height - expected.height,
  ];
}
