import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0046: blocks past the changed region are reused shifted by one
/// shared vertical delta. Every streaming shape that leaves a trailing
/// unchanged suffix — mid-document edits, head inserts, deletions — must
/// produce layouts entry-for-entry identical to a canonical full rebuild,
/// and the float / list-marker guards must fall back to fresh measurement
/// without breaking that equality.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  test('a longer mid-document edit reuses the shifted suffix', () {
    final first = _normalize(_article(8, start: 0));
    final previous = engine.layout(first, width: 360);
    final next = _normalize(
      '${_article(4, start: 0)}'
      '<p>第 4 段被替换成一段长得多的全新正文内容，行数随之增加，'
      'the replacement paragraph is much longer than the original one and '
      'pushes everything below it further down the document.</p>'
      '${_article(3, start: 5)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();

    expect(current.debugReusedBlockCount, 8,
        reason: '5 prefix blocks (h3 + p0..p3) + 3 suffix blocks (p5..p7)');
    _expectLayoutEquals(current, canonical);
  });

  test('a shorter mid-document edit shifts the suffix upward', () {
    final first = _normalize(_article(8, start: 0));
    final previous = engine.layout(first, width: 360);
    final next = _normalize(
      '${_article(4, start: 0)}<p>短替换。</p>${_article(3, start: 5)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    expect(current.debugReusedBlockCount, 8,
        reason: '5 prefix blocks + 3 suffix blocks at a lifted offset');
    _expectLayoutEquals(current, canonical);
  });

  test('deleting a block reuses the shifted suffix', () {
    final first = _normalize(_article(9, start: 0));
    final previous = engine.layout(first, width: 360);
    final next = _normalize(
      '${_article(3, start: 0)}${_article(5, start: 4)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    expect(current.debugReusedBlockCount, 11,
        reason: '4 prefix blocks + 7 suffix blocks re-mapped through the '
            'middle id shift');
    _expectLayoutEquals(current, canonical);
  });

  test('a head insert reuses every previous block shifted down', () {
    final first = _normalize(_article(8, start: 0));
    final previous = engine.layout(first, width: 360);
    final next = _normalize(
      '<p>置顶快讯。Weft streaming prepends a fresh block above unchanged '
      'content, so the whole previous document becomes the shifted '
      'suffix.</p>${_article(8, start: 0)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    expect(current.debugReusedBlockCount, 10,
        reason: 'every previous block must come back as the shifted suffix');
    _expectLayoutEquals(current, canonical);
  });

  test('a float inside the edited block falls back to fresh measurement',
      () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final first = _normalize(
      '${_article(3, start: 0)}'
      '<p><img src="asset:suffix-edit.png" style="float:left" width="96" '
      'height="72">第 3 段自带浮动图片。</p>'
      '${_article(3, start: 4)}',
    );
    final previous =
        engine.layout(first, width: 360, images: _imagesFor(first, image));
    final next = _normalize(
      '${_article(3, start: 0)}'
      '<p><img src="asset:suffix-edit.png" style="float:left" width="96" '
      'height="200">第 3 段被替换，浮动图更高。</p>'
      '${_article(3, start: 4)}',
      revision: 2,
    );
    final current = engine.layout(
      next,
      width: 360,
      previous: previous,
      images: _imagesFor(next, image),
    );
    final canonical = engine.layout(
      next,
      width: 360,
      images: _imagesFor(next, image),
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    expect(current.debugReusedBlockCount, 0,
        reason: 'a plain float document never seeds an incremental cache '
            '(ADR 0025), so nothing reuses; the walk-time float guard stays '
            'defense in depth for future cache sources');
    _expectLayoutEquals(current, canonical);
  });

  test('a prefix float reaching into the suffix falls back to fresh layout',
      () async {
    final image = await _createImage(height: 300);
    addTearDown(image.dispose);
    final first = _normalize(
      '<p><img src="asset:suffix-tall.png" style="float:left" width="120" '
      'height="300">锚点段落，浮动图有三段高。</p>${_article(7, start: 1)}',
    );
    final previous =
        engine.layout(first, width: 360, images: _imagesFor(first, image));
    final next = _normalize(
      '<p><img src="asset:suffix-tall.png" style="float:left" width="120" '
      'height="300">锚点段落，浮动图有三段高。</p>'
      '${_article(2, start: 1)}'
      '<p>第 3 段被替换。The edited block sits beside the float.</p>'
      '${_article(4, start: 4)}',
      revision: 2,
    );
    final current = engine.layout(
      next,
      width: 360,
      previous: previous,
      images: _imagesFor(next, image),
    );
    final canonical =
        engine.layout(next, width: 360, images: _imagesFor(next, image));
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    expect(current.debugReusedBlockCount, 0,
        reason: 'float documents do not seed a plain cache; the '
            'reaches-into-suffix guard stays defense in depth');
    _expectLayoutEquals(current, canonical);
  });

  test('body-level list items stop the suffix scan but keep equality', () {
    final first = _normalize(
      '${_article(2, start: 0)}<li>顶层列表项。</li>${_article(3, start: 2)}',
    );
    final previous = engine.layout(first, width: 360);
    final next = _normalize(
      '${_article(2, start: 0)}<li>顶层列表项被替换。</li>${_article(3, start: 2)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    previous.dispose();
    _expectLayoutEquals(current, canonical);
  });

  test('chained rounds keep matching the canonical build', () {
    final a = engine.layout(_normalize(_article(6, start: 0)), width: 360);
    final bHtml =
        '${_article(2, start: 0)}<p>第 2 段被中部编辑。</p>${_article(3, start: 3)}';
    final b =
        engine.layout(_normalize(bHtml, revision: 2), width: 360, previous: a);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    expect(b.debugReusedBlockCount, greaterThan(2));
    final cHtml = '$bHtml${_article(2, start: 6)}';
    final c =
        engine.layout(_normalize(cHtml, revision: 3), width: 360, previous: b);
    final canonical = engine.layout(_normalize(cHtml, revision: 3), width: 360);
    addTearDown(c.dispose);
    addTearDown(canonical.dispose);
    expect(c.debugReusedBlockCount, greaterThan(5),
        reason: 'the translated cache must keep seeding later rounds');
    _expectLayoutEquals(c, canonical);
  });

  test('incremental and canonical suffix layouts rasterize identically',
      () async {
    const prefix = '<h3 style="margin: 8px 0">标题</h3>'
        '<p style="background-color:#ddeeff">Alpha <strong>bold</strong> '
        'with enough text to wrap across several lines at 280px.</p>'
        '<table><tr><td style="border:1px solid #333333">Cell</td></tr></table>';
    final first = _normalize('${prefix}${_article(3, start: 1)}');
    final previous = engine.layout(first, width: 280);
    final next = _normalize(
      '${prefix}<p>第 1 段被替换为不同的正文内容。</p>${_article(3, start: 2)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 280, previous: previous);
    final canonical = engine.layout(next, width: 280);
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
    id: 'suffix-translation',
    revision: revision,
  );
}

/// Rich article body with a heading every four paragraphs, inline emphasis
/// and links, so block, inline and heading structures all cross the seam.
String _article(int count, {required int start}) {
  final buffer = StringBuffer();
  for (var i = start; i < start + count; i++) {
    if (i % 4 == 0) {
      buffer.write('<h3>章节 $i:后缀平移等价</h3>');
    }
    buffer.write(
      '<p>第 $i 段。Weft streams <em>强调 $i</em> and '
      '<a href="https://example.com/a$i">links $i</a> through the '
      'translated suffix.</p>',
    );
  }
  return buffer.toString();
}

Map<int, ui.Image> _imagesFor(WeftDocumentSnapshot document, ui.Image image) {
  final images = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      if (node.tag == 'img') images[node.id] = image;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  visit(document.body!);
  return images;
}

Future<ui.Image> _createImage({double width = 120, double height = 72}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  picture.dispose();
  return image;
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

/// Full value equality between two layout results, including the text index
/// entry-for-entry (ADR 0044) — the suffix clones must be indistinguishable
/// from a canonical full rebuild.
void _expectLayoutEquals(WeftLayoutResult actual, WeftLayoutResult expected) {
  expect(actual.size, expected.size);
  expect(actual.boxes, hasLength(expected.boxes.length));
  for (var i = 0; i < actual.boxes.length; i++) {
    expect(actual.boxes[i].nodeId, expected.boxes[i].nodeId,
        reason: 'box $i nodeId');
    expect(actual.boxes[i].rect, expected.boxes[i].rect, reason: 'box $i rect');
  }
  expect(actual.commands, hasLength(expected.commands.length));
  for (var i = 0; i < actual.commands.length; i++) {
    final command = actual.commands[i];
    final other = expected.commands[i];
    expect(command.runtimeType, other.runtimeType, reason: 'command $i type');
    expect(command.nodeId, other.nodeId, reason: 'command $i nodeId');
    expect(command.bounds, other.bounds, reason: 'command $i bounds');
    if (command is WeftTextPaintCommand) {
      final text = other as WeftTextPaintCommand;
      expect(command.offset, text.offset, reason: 'command $i offset');
      expect(
          command.painter.text!.toPlainText(), text.painter.text!.toPlainText(),
          reason: 'command $i text');
      expect(command.runs, hasLength(text.runs.length),
          reason: 'command $i runs');
      for (var j = 0; j < command.runs.length; j++) {
        expect(command.runs[j].nodeId, text.runs[j].nodeId);
        expect(command.runs[j].painterStart, text.runs[j].painterStart);
        expect(command.runs[j].painterEnd, text.runs[j].painterEnd);
        expect(command.runs[j].nodeStart, text.runs[j].nodeStart);
        expect(command.runs[j].nodeEnd, text.runs[j].nodeEnd);
      }
    } else if (command is WeftRectPaintCommand) {
      expect(command.rect, (other as WeftRectPaintCommand).rect,
          reason: 'command $i rect');
      expect(command.color, other.color, reason: 'command $i color');
    } else if (command is WeftImagePaintCommand) {
      expect(command.destination, (other as WeftImagePaintCommand).destination,
          reason: 'command $i destination');
    }
  }
  expect(actual.links, hasLength(expected.links.length));
  for (var i = 0; i < actual.links.length; i++) {
    expect(actual.links[i].nodeId, expected.links[i].nodeId);
    expect(actual.links[i].href, expected.links[i].href);
    expect(actual.links[i].rects, expected.links[i].rects,
        reason: 'link $i rects');
  }
  _expectTextIndexEquals(actual.textIndex!, expected.textIndex!);
}

void _expectTextIndexEquals(WeftTextIndex actual, WeftTextIndex expected) {
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
  expect(actual.length, expected.length);
  expect(actual.text, expected.text);
}
