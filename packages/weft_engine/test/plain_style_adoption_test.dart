import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0050: the block diff proves which top-level children are unchanged,
/// and computed style is a pure function of content plus stylesheet — so a
/// streaming round seeds the walk's style cache with the previous round's
/// resolved styles for the mapped prefix and suffix instead of re-matching
/// every selector. Adopted rounds must be indistinguishable from canonical
/// full rebuilds, the counter must track exactly the mapped children, and
/// every fallback (stylesheet change, same snapshot) must keep the counter
/// at zero without breaking equality.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  test('a mid-document edit adopts every mapped child style', () {
    final base = _styledArticle(20);
    final previous = engine.layout(_normalize(base), width: 360);
    addTearDown(previous.dispose);
    final next = _normalize(
      '${_styledArticle(10)}'
      '<p>第 10 段被替换为一段长得多的全新正文内容，行数随之增加，'
      'the replacement paragraph is much longer than the original.</p>'
      '${_styledArticle(9, start: 11)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugReusedBlockCount, next.body!.children.length - 1);
    expect(current.debugAdoptedStyleCount, next.body!.children.length - 1,
        reason: 'prefix plus shifted suffix cover every child but the '
            'edited one');
    _expectLayoutEquals(current, canonical);
  });

  test('chained rounds keep adopting and matching canonical', () {
    final a = engine.layout(_normalize(_styledArticle(12)), width: 360);
    addTearDown(a.dispose);
    final bHtml = '${_styledArticle(6)}'
        '<p>第 6 段第一轮被替换。</p>${_styledArticle(5, start: 7)}';
    final b = engine.layout(
      _normalize(bHtml, revision: 2),
      width: 360,
      previous: a,
    );
    addTearDown(b.dispose);
    expect(b.debugAdoptedStyleCount, greaterThan(0));
    final cHtml = '${_styledArticle(6)}'
        '<p>第 6 段第二轮被替换，内容又不一样了。</p>${_styledArticle(5, start: 7)}';
    final c = engine.layout(
      _normalize(cHtml, revision: 3),
      width: 360,
      previous: b,
    );
    final canonical = engine.layout(_normalize(cHtml, revision: 3), width: 360);
    addTearDown(c.dispose);
    addTearDown(canonical.dispose);
    expect(c.debugAdoptedStyleCount,
        _normalize(cHtml, revision: 3).body!.children.length - 1,
        reason: 'the previous round was itself adopted; its cache still '
            'holds every mapped style');
    _expectLayoutEquals(c, canonical);
  });

  test('a stylesheet change falls back and adopts nothing', () {
    final previous = engine.layout(
      _normalize('<style>p{color:#333333}</style>${_styledArticle(10)}'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final next = _normalize(
      '<style>p{color:#111111}</style>${_styledArticle(10)}'
      '${_styledArticle(3, start: 10)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugReusedBlockCount, 0);
    expect(current.debugAdoptedStyleCount, 0,
        reason: 'the stylesheet signature gate empties the diff, so there '
            'is nothing to adopt from');
    _expectLayoutEquals(current, canonical);
  });

  test('a 256-rule stylesheet adopts and stays canonical', () {
    final base = _classArticle(20, rules: 256);
    final previous = engine.layout(_normalize(base), width: 360);
    addTearDown(previous.dispose);
    final next = _normalize(
      '${_classArticle(10, rules: 256)}'
      '<p class="s7">第 10 段被替换。</p>'
      '${_classArticle(9, start: 11, rules: 256)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugAdoptedStyleCount, next.body!.children.length - 1);
    _expectLayoutEquals(current, canonical);
  });

  test('a lazy round over a plain previous still matches canonical', () {
    final base = _styledArticle(20);
    final previous = engine.layout(_normalize(base), width: 360);
    addTearDown(previous.dispose);
    final next = _normalize(
      '${_styledArticle(10)}'
      '<p>第 10 段在 lazy 轮中被替换。</p>${_styledArticle(9, start: 11)}',
      revision: 2,
    );
    final current = engine.layoutViewport(
      next,
      width: 360,
      viewportStart: 0,
      viewportEnd: 800,
      previous: previous,
    );
    final canonical = engine.layoutViewport(
      next,
      width: 360,
      viewportStart: 0,
      viewportEnd: 800,
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isTrue);
    expect(current.debugAdoptedStyleCount, greaterThan(0),
        reason: 'the plain previous holds every style, so the measured '
            'window prefix adopts');
    _expectLayoutEquals(current, canonical);
  });

  test('a same-snapshot relayout adopts nothing', () {
    final document = _normalize(_styledArticle(10));
    final first = engine.layout(document, width: 360);
    addTearDown(first.dispose);
    final second = engine.layout(document, width: 360, previous: first);
    addTearDown(second.dispose);
    expect(second.debugAdoptedStyleCount, 0,
        reason: 'the style cache is the previous map itself');
    _expectLayoutEquals(second, first);
  });

  test('tables and images in the prefix adopt through their reuse paths',
      () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    const head = '<style>p { margin: 6px 0; }</style>'
        '<table><tr><td style="border:1px solid #333333">'
        '<p>单元格内段落。</p></td></tr></table>'
        '<p><img src="asset:adopt.png" width="96" height="48">块级图片。</p>';
    final base = '$head${_styledArticle(12, start: 2)}';
    final first = _normalize(base);
    final previous = engine.layout(
      first,
      width: 360,
      images: _imagesFor(first, image),
    );
    addTearDown(previous.dispose);
    final next = _normalize(
      '$head${_styledArticle(10, start: 2)}'
      '<p>第 11 段被替换为不同的正文内容。</p>'
      '${_styledArticle(2, start: 12)}',
      revision: 2,
    );
    final current = engine.layout(
      next,
      width: 360,
      images: _imagesFor(next, image),
      previous: previous,
    );
    final canonical = engine.layout(
      next,
      width: 360,
      images: _imagesFor(next, image),
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugAdoptedStyleCount, greaterThan(0));
    _expectLayoutEquals(current, canonical);
  });
}

WeftDocumentSnapshot _normalize(String html, {int revision = 1}) {
  return const WeftNormalizer().normalize(
    html,
    id: 'plain-style-adoption',
    revision: revision,
  );
}

/// Article body with inline styles plus a small stylesheet, so both the
/// cascade path and per-element declarations cross the adoption seam.
String _styledArticle(int count, {int start = 0}) {
  final buffer = StringBuffer();
  if (start == 0) {
    buffer.write('<style>p { margin: 6px 0; }</style>');
  }
  for (var i = start; i < start + count; i++) {
    if (i % 4 == 0) {
      buffer.write(
        '<h3 style="margin:8px 0">章节 $i:样式采用</h3>',
      );
    }
    buffer.write(
      '<p style="padding-left:4px">第 $i 段。Weft streams '
      '<em>强调 $i</em> and <a href="https://example.com/a$i">links $i</a> '
      'through the adopted style cache.</p>',
    );
  }
  return buffer.toString();
}

/// Article whose paragraphs carry one of [rules] distinct classes, with a
/// stylesheet declaring one matching rule per class.
String _classArticle(int count, {int start = 0, required int rules}) {
  final buffer = StringBuffer();
  if (start == 0) {
    final sheet = StringBuffer();
    for (var i = 0; i < rules; i++) {
      sheet.write('.s$i { color: #33445${i % 10}; }');
    }
    buffer.write('<style>$sheet</style>');
  }
  for (var i = start; i < start + count; i++) {
    buffer.write(
      '<p class="s${i % rules}">第 $i 段。Class-matched paragraph for the '
      'large-stylesheet adoption seam, long enough to wrap at 360px.</p>',
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

Future<ui.Image> _createImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 48),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 48);
  picture.dispose();
  return image;
}

/// Full value equality between two layout results, including the text index
/// entry-for-entry (ADR 0044) — the adopted-style round must be
/// indistinguishable from a canonical full rebuild.
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
