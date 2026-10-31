import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tail append reuses prefix painters and survives previous dispose', () {
    const engine = WeftLayoutEngine();
    final first = _normalize(
      '<p>Alpha with <em>emphasis</em></p><p>Beta</p><p>Gamma</p>',
    );
    final appended = _normalize(
      '<p>Alpha with <em>emphasis</em></p><p>Beta</p><p>Gamma</p>'
      '<p>Delta with a <a href="https://example.com">link</a></p>',
      revision: 2,
    );
    final previous = engine.layout(first, width: 280);
    final prefixPainters = previous.commands
        .whereType<WeftTextPaintCommand>()
        .map((command) => command.painter)
        .toList();

    final current = engine.layout(appended, width: 280, previous: previous);
    final canonical = engine.layout(appended, width: 280);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);

    expect(current.debugReusedBlockCount, 3);
    expect(current.incrementalCache, isNotNull);
    final currentPainters = current.commands
        .whereType<WeftTextPaintCommand>()
        .map((command) => command.painter)
        .toList();
    for (var i = 0; i < prefixPainters.length; i++) {
      expect(identical(currentPainters[i], prefixPainters[i]), isTrue);
    }
    _expectLayoutEquals(current, canonical);

    previous.dispose();
    final entries = current.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries.first.nodeId, 1),
      extent: TextAnchor(entries.last.nodeId, 2),
    );
    expect(current.selectionRects(selection), isNotEmpty);
    expect(
        current.selectionRects(selection), canonical.selectionRects(selection));
    expect(
        current.selectionText(selection), canonical.selectionText(selection));
    final caret = TextAnchor(entries.first.nodeId, 0);
    expect(
        current.caretRectForAnchor(caret), canonical.caretRectForAnchor(caret));

    current.attachDocument(appended);
    canonical.attachDocument(appended);
    for (final command in current.commands.whereType<WeftTextPaintCommand>()) {
      final point = command.bounds.center;
      final anchor = current.anchorAt(point);
      final expectedAnchor = canonical.anchorAt(point);
      expect(anchor?.nodeId, expectedAnchor?.nodeId);
      expect(anchor?.offset, expectedAnchor?.offset);
      expect(current.linkAt(point)?.href, canonical.linkAt(point)?.href);
    }
  });

  test('growing the last paragraph only relayouts the changed tail', () {
    const engine = WeftLayoutEngine();
    final first = _normalize('<p>Stable one</p><p>Stable two</p><p>Grow</p>');
    final appended = _normalize(
      '<p>Stable one</p><p>Stable two</p><p>Growing text with more tokens</p>',
      revision: 2,
    );
    final previous = engine.layout(first, width: 240);
    final current = engine.layout(appended, width: 240, previous: previous);
    final canonical = engine.layout(appended, width: 240);
    addTearDown(previous.dispose);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);

    expect(current.debugReusedBlockCount, 2);
    _expectLayoutEquals(current, canonical);
  });

  test('successive snapshots keep reusing the growing prefix', () {
    const engine = WeftLayoutEngine();
    var previous = engine.layout(_normalize('<p>Paragraph 0</p>'), width: 240);
    addTearDown(() => previous.dispose());

    for (var revision = 2; revision <= 4; revision++) {
      final html = StringBuffer();
      for (var i = 0; i < revision; i++) {
        html.write('<p>Paragraph $i</p>');
      }
      final document = _normalize(html.toString(), revision: revision);
      final current = engine.layout(document, width: 240, previous: previous);
      final canonical = engine.layout(document, width: 240);
      expect(current.debugReusedBlockCount, revision - 1);
      _expectLayoutEquals(current, canonical);
      previous.dispose();
      canonical.dispose();
      previous = current;
    }
  });

  test('layout input changes fall back to a canonical full layout', () {
    const engine = WeftLayoutEngine();
    final first =
        _normalize('<style>p { margin: 3px }</style><p>One</p><p>Two</p>');
    final restyled = _normalize(
      '<style>p { margin: 7px }</style><p>One</p><p>Two</p><p>Three</p>',
      revision: 2,
    );
    final previous = engine.layout(first, width: 240);
    final current = engine.layout(restyled, width: 240, previous: previous);
    final canonical = engine.layout(restyled, width: 240);
    final resized = engine.layout(first, width: 200, previous: previous);
    final resizedCanonical = engine.layout(first, width: 200);
    addTearDown(previous.dispose);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    addTearDown(resized.dispose);
    addTearDown(resizedCanonical.dispose);

    expect(current.debugReusedBlockCount, 0);
    expect(resized.debugReusedBlockCount, 0);
    _expectLayoutEquals(current, canonical);
    _expectLayoutEquals(resized, resizedCanonical);
  });

  test('reuses prefix tables and block images across margin changes', () async {
    final image = await _createImage(40, 30);
    addTearDown(image.dispose);
    const engine = WeftLayoutEngine();
    const prefix = '<p style="margin: 12px 0">Alpha</p>'
        '<img src="asset:cover.png" style="display:block">'
        '<table><tr><td>Cell</td></tr></table>';
    final first = _normalize(prefix);
    final appended = _normalize(
      '${prefix}<p style="margin-top: -4px">Tail text</p>',
      revision: 2,
    );
    final previous = engine.layout(
      first,
      width: 280,
      images: _imagesFor(first, image),
    );
    final current = engine.layout(
      appended,
      width: 280,
      images: _imagesFor(appended, image),
      previous: previous,
    );
    final canonical = engine.layout(
      appended,
      width: 280,
      images: _imagesFor(appended, image),
    );
    addTearDown(previous.dispose);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);

    expect(current.debugReusedBlockCount, 3);
    _expectLayoutEquals(current, canonical);
  });

  test('float inputs conservatively fall back and suffix floats stay exact',
      () async {
    final image = await _createImage(50, 40);
    addTearDown(image.dispose);
    const engine = WeftLayoutEngine();
    final floating = _normalize(
      '<p>Before</p><img src="asset:float.png" style="float:left">'
      '<p>Text wrapping around the float</p>',
    );
    final floatingAppended = _normalize(
      '<p>Before</p><img src="asset:float.png" style="float:left">'
      '<p>Text wrapping around the float</p><p>Tail</p>',
      revision: 2,
    );
    final previous = engine.layout(
      floating,
      width: 260,
      images: _imagesFor(floating, image),
    );
    final current = engine.layout(
      floatingAppended,
      width: 260,
      images: _imagesFor(floatingAppended, image),
      previous: previous,
    );
    final canonical = engine.layout(
      floatingAppended,
      width: 260,
      images: _imagesFor(floatingAppended, image),
    );
    addTearDown(previous.dispose);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);

    expect(previous.incrementalCache, isNull);
    expect(current.debugReusedBlockCount, 0);
    _expectLayoutEquals(current, canonical);

    final plain = _normalize('<p>One</p><p>Two</p>');
    final withSuffixFloat = _normalize(
      '<p>One</p><p>Two</p>'
      '<img src="asset:float.png" style="float:left"><p>After float</p>',
      revision: 2,
    );
    final plainLayout = engine.layout(plain, width: 260);
    final suffixLayout = engine.layout(
      withSuffixFloat,
      width: 260,
      images: _imagesFor(withSuffixFloat, image),
      previous: plainLayout,
    );
    final suffixCanonical = engine.layout(
      withSuffixFloat,
      width: 260,
      images: _imagesFor(withSuffixFloat, image),
    );
    addTearDown(plainLayout.dispose);
    addTearDown(suffixLayout.dispose);
    addTearDown(suffixCanonical.dispose);

    expect(suffixLayout.debugReusedBlockCount, 0);
    expect(suffixLayout.incrementalCache, isNull);
    _expectLayoutEquals(suffixLayout, suffixCanonical);
  });

  test('structural and remaining global input changes disable reuse', () {
    const engine = WeftLayoutEngine();
    final first = _normalize('<p>One</p><p>Two</p>');
    final inserted =
        _normalize('<h1>New</h1><p>One</p><p>Two</p>', revision: 2);
    final previous = engine.layout(first, width: 240);
    final insertedLayout =
        engine.layout(inserted, width: 240, previous: previous);
    final insertedCanonical = engine.layout(inserted, width: 240);
    final scaled = engine.layout(
      first,
      width: 240,
      textScaler: const TextScaler.linear(1.2),
      previous: previous,
    );
    final scaledCanonical = engine.layout(
      first,
      width: 240,
      textScaler: const TextScaler.linear(1.2),
    );
    final rulesChanged = engine.layout(
      first,
      width: 240,
      lineBreakRules: WeftLineBreakRules.off,
      previous: previous,
    );
    final rulesCanonical = engine.layout(
      first,
      width: 240,
      lineBreakRules: WeftLineBreakRules.off,
    );
    addTearDown(previous.dispose);
    addTearDown(insertedLayout.dispose);
    addTearDown(insertedCanonical.dispose);
    addTearDown(scaled.dispose);
    addTearDown(scaledCanonical.dispose);
    addTearDown(rulesChanged.dispose);
    addTearDown(rulesCanonical.dispose);

    expect(insertedLayout.debugReusedBlockCount, 0);
    expect(scaled.debugReusedBlockCount, 0);
    expect(rulesChanged.debugReusedBlockCount, 0);
    _expectLayoutEquals(insertedLayout, insertedCanonical);
    _expectLayoutEquals(scaled, scaledCanonical);
    _expectLayoutEquals(rulesChanged, rulesCanonical);
  });

  test('incremental and full layouts rasterize identical pixels', () async {
    const engine = WeftLayoutEngine();
    const prefix = '<h3 style="margin: 8px 0">Title</h3>'
        '<p style="background-color:#ddeeff">Alpha <strong>bold</strong></p>'
        '<table><tr><td style="border:1px solid #333333">Cell</td></tr></table>';
    final first = _normalize(prefix);
    final appended =
        _normalize('${prefix}<p>Tail with more text</p>', revision: 2);
    final previous = engine.layout(first, width: 280);
    final current = engine.layout(appended, width: 280, previous: previous);
    final canonical = engine.layout(appended, width: 280);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();

    final actual = await _rasterize(current);
    final expected = await _rasterize(canonical);
    final actualBytes = await actual.toByteData();
    final expectedBytes = await expected.toByteData();
    addTearDown(actual.dispose);
    addTearDown(expected.dispose);
    expect(
        actualBytes!.buffer.asUint8List(), expectedBytes!.buffer.asUint8List());
  });
}

WeftDocumentSnapshot _normalize(String html, {int revision = 1}) {
  return const WeftNormalizer().normalize(
    html,
    id: 'incremental-layout',
    revision: revision,
  );
}

void _expectLayoutEquals(WeftLayoutResult actual, WeftLayoutResult expected) {
  expect(actual.size, expected.size);
  expect(actual.boxes, hasLength(expected.boxes.length));
  for (var i = 0; i < actual.boxes.length; i++) {
    expect(actual.boxes[i].nodeId, expected.boxes[i].nodeId);
    expect(actual.boxes[i].rect, expected.boxes[i].rect);
  }
  expect(actual.commands, hasLength(expected.commands.length));
  for (var i = 0; i < actual.commands.length; i++) {
    final command = actual.commands[i];
    final other = expected.commands[i];
    expect(command.runtimeType, other.runtimeType);
    expect(command.nodeId, other.nodeId);
    expect(command.bounds, other.bounds);
    if (command is WeftTextPaintCommand) {
      final text = other as WeftTextPaintCommand;
      expect(command.offset, text.offset);
      expect(command.painter.text!.toPlainText(),
          text.painter.text!.toPlainText());
      expect(command.painter.width, text.painter.width);
      expect(command.painter.height, text.painter.height);
      expect(command.runs, hasLength(text.runs.length));
      for (var j = 0; j < command.runs.length; j++) {
        final run = command.runs[j];
        final expectedRun = text.runs[j];
        expect(run.nodeId, expectedRun.nodeId);
        expect(run.painterStart, expectedRun.painterStart);
        expect(run.painterEnd, expectedRun.painterEnd);
        expect(run.nodeStart, expectedRun.nodeStart);
        expect(run.nodeEnd, expectedRun.nodeEnd);
      }
    } else if (command is WeftRectPaintCommand) {
      expect(command.rect, (other as WeftRectPaintCommand).rect);
      expect(command.color, other.color);
    } else if (command is WeftImagePaintCommand) {
      expect(command.destination, (other as WeftImagePaintCommand).destination);
      expect(identical(command.image, other.image), isTrue);
    }
  }
  expect(actual.links, hasLength(expected.links.length));
  for (var i = 0; i < actual.links.length; i++) {
    expect(actual.links[i].nodeId, expected.links[i].nodeId);
    expect(actual.links[i].href, expected.links[i].href);
    expect(actual.links[i].text, expected.links[i].text);
    expect(actual.links[i].rects, expected.links[i].rects);
  }
  expect(actual.textIndex?.text, expected.textIndex?.text);
  _expectTextIndexEquals(actual.textIndex, expected.textIndex);
}

/// Entry-for-entry text index equality (ADR 0044): the incremental rebuild
/// must produce the same nodeIds, painted texts and global offsets as the
/// canonical full build.
void _expectTextIndexEquals(
  WeftTextIndex? actual,
  WeftTextIndex? expected,
) {
  if (actual == null || expected == null) {
    expect(actual, isNull);
    expect(expected, isNull);
    return;
  }
  expect(actual.entries, hasLength(expected.entries.length));
  for (var i = 0; i < actual.entries.length; i++) {
    expect(actual.entries[i].nodeId, expected.entries[i].nodeId,
        reason: 'entry $i nodeId');
    expect(actual.entries[i].text, expected.entries[i].text,
        reason: 'entry $i text');
    expect(actual.entries[i].globalStart, expected.entries[i].globalStart,
        reason: 'entry $i globalStart');
  }
  expect(actual.entryByNode, hasLength(expected.entryByNode.length));
  for (final entry in expected.entries) {
    final other = actual.entryByNode[entry.nodeId];
    expect(other, isNotNull, reason: 'entry for node ${entry.nodeId}');
    expect(other!.globalStart, entry.globalStart);
    expect(other.text, entry.text);
  }
  expect(actual.length, expected.length);
  expect(actual.text, expected.text);
}

Map<int, ui.Image> _imagesFor(WeftDocumentSnapshot document, ui.Image image) {
  final result = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is! WeftElement) return;
    if (node.tag == 'img') result[node.id] = image;
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(document.body!);
  return result;
}

Future<ui.Image> _createImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height).whenComplete(picture.dispose);
}

Future<ui.Image> _rasterize(WeftLayoutResult layout) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  for (final command in layout.commands) {
    command.paint(canvas, ui.Offset.zero);
  }
  final picture = recorder.endRecording();
  return picture
      .toImage(layout.size.width.ceil(), layout.size.height.ceil())
      .whenComplete(picture.dispose);
}
