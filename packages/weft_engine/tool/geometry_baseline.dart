import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';

/// Shared helpers for browser geometry baselines: loading committed Chrome
/// references, mapping their `data-geo` keys onto document elements, and
/// loading the pinned conformance fonts. Used by the generic conformance
/// geometry gate and the layout dump tool.

Directory workspaceRoot() {
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

Future<void> loadConformanceFonts(Directory root) async {
  final fontDir = '${root.path}/conformance/fonts';
  final roboto = FontLoader('WeftRoboto');
  for (final file in const [
    'Roboto-Regular.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Italic.ttf',
    'Roboto-BoldItalic.ttf',
  ]) {
    final bytes = await File('$fontDir/$file').readAsBytes();
    roboto.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await roboto.load();

  final mono = FontLoader('WeftRobotoMono');
  for (final file in const [
    'RobotoMono-Regular.ttf',
    'RobotoMono-Bold.ttf',
  ]) {
    final bytes = await File('$fontDir/$file').readAsBytes();
    mono.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await mono.load();
}

/// Reads `conformance/reference/<caseId>.geometry.json`, failing with
/// regeneration instructions when it is missing.
Map<String, dynamic> loadGeometryReference(Directory root, String caseId) {
  final file = File(
    '${root.path}/conformance/reference/$caseId.geometry.json',
  );
  if (!file.existsSync()) {
    fail(
      'Missing geometry reference for "$caseId". Generate it with:\n'
      '  node tool/browser_references.mjs --case $caseId --emit-reference',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// One Chrome reference element: its marker key, tag and border-box rect.
final class ReferenceElement {
  const ReferenceElement({
    required this.key,
    required this.tag,
    required this.rect,
  });

  final String key;
  final String tag;
  final Rect rect;
}

List<ReferenceElement> referenceElements(Map<String, dynamic> reference) {
  final elements = reference['elements'] as Map<String, dynamic>;
  return [
    for (final entry in elements.entries)
      () {
        final value = entry.value as Map<String, dynamic>;
        return ReferenceElement(
          key: entry.key,
          tag: value['tag'] as String,
          rect: Rect.fromLTWH(
            (value['left'] as num).toDouble(),
            (value['top'] as num).toDouble(),
            (value['width'] as num).toDouble(),
            (value['height'] as num).toDouble(),
          ),
        );
      }(),
  ];
}

/// Zips reference markers (in document order, which is how the extraction
/// script writes them) with the document's elements of the same tags.
/// The sanitizer strips `data-geo`, so position is the only mapping; any
/// mismatch fails loudly instead of skipping silently.
List<(ReferenceElement, WeftElement)> mapReferenceToDocument(
  List<ReferenceElement> reference,
  WeftElement body,
) {
  final wantedTags = reference.map((element) => element.tag).toSet();
  final documentElements = <WeftElement>[];
  void visit(WeftNode node) {
    if (node is! WeftElement) return;
    if (wantedTags.contains(node.tag)) {
      documentElements.add(node);
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(body);

  if (documentElements.length != reference.length) {
    fail(
      'Geometry mapping mismatch: the reference has ${reference.length} '
      'markers (${reference.map((e) => '${e.tag}#${e.key}').join(', ')}), '
      'but the document yields ${documentElements.length} elements with '
      'tags {${wantedTags.join(', ')}}. Update the case or regenerate the '
      'reference.',
    );
  }
  final pairs = <(ReferenceElement, WeftElement)>[];
  for (var index = 0; index < reference.length; index++) {
    final expected = reference[index];
    final element = documentElements[index];
    if (element.tag != expected.tag) {
      fail(
        'Geometry mapping mismatch at position $index: reference expects '
        '<${expected.tag}> (${expected.key}) but the document has '
        '<${element.tag}>. Update the case or regenerate the reference.',
      );
    }
    pairs.add((expected, element));
  }
  return pairs;
}

/// Decodes the conformance PNG fixtures referenced by a case's
/// `assets/<name>` image sources. Call inside `tester.runAsync` or a plain
/// async test; results are cached per source path.
Future<Map<int, ui.Image>> resolveCaseImages(
  Directory root,
  WeftDocumentSnapshot document,
) async {
  final images = <int, ui.Image>{};
  final body = document.body;
  if (body == null) return images;
  Future<void> visit(WeftNode node) async {
    if (node is WeftElement) {
      final src = node.tag == 'img' ? node.attribute('src') : null;
      if (src != null && src.startsWith('assets/')) {
        final cached = _decodedAssets[src];
        if (cached != null) {
          images[node.id] = cached;
        } else {
          final bytes = await File(
            '${root.path}/conformance/$src',
          ).readAsBytes();
          final completer = Completer<ui.Image>();
          ui.decodeImageFromList(bytes, completer.complete);
          final image = await completer.future;
          _decodedAssets[src] = image;
          images[node.id] = image;
        }
      }
      for (final child in node.children) {
        await visit(child);
      }
    }
  }

  await visit(body);
  return images;
}

final _decodedAssets = <String, ui.Image>{};

/// Comparison tolerance per tag: text blocks match Chrome within half a
/// pixel; replaced and table elements inherit the ~1px rounding of
/// shrink-to-fit measurement.
double toleranceFor(String tag) {
  switch (tag) {
    case 'p':
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
    case 'hr':
      return 0.5;
    default:
      return 1.5;
  }
}
