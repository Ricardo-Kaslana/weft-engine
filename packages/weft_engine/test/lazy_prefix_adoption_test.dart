import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0049: a streaming snapshot's lazy round adopts the previous pass's
/// admission verdict and per-child estimate state for the block diff's
/// proven prefix, so only the changed suffix is re-verified and re-estimated.
/// Every adopted round must produce measured geometry, links, tag regions
/// and the text index identical to a canonical lazy layout of the same
/// document at the same viewport, and the guards (ineligible suffixes, head
/// inserts, plain previouses) must fall back to the full walk without
/// breaking that equality.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();
  const viewportHeight = 800.0;

  WeftDocumentSnapshot _normalize(String html, {int revision = 1}) {
    return const WeftNormalizer().normalize(
      html,
      id: 'lazy-prefix-adoption',
      revision: revision,
    );
  }

  /// The viewport top that puts the document bottom at the viewport bottom —
  /// the scrolled-session shape whose measured prefix covers most blocks.
  double _deepStart(WeftDocumentSnapshot document) {
    final probe = engine.layoutViewport(
      document,
      width: 360,
      viewportStart: 0,
      viewportEnd: viewportHeight,
    );
    final deep = probe.size.height - viewportHeight;
    probe.dispose();
    return deep < 0 ? 0 : deep;
  }

  WeftLayoutResult _lazyLayout(
    String html, {
    int revision = 1,
    required double viewportStart,
    Map<int, ui.Image> images = const <int, ui.Image>{},
    WeftLayoutResult? previous,
  }) {
    return engine.layoutViewport(
      _normalize(html, revision: revision),
      width: 360,
      viewportStart: viewportStart,
      viewportEnd: viewportStart + viewportHeight,
      images: images,
      previous: previous,
    );
  }

  /// Measured-geometry equality between two lazy rounds of the same
  /// document at the same viewport. `size` is excluded: the unmeasured
  /// suffix's estimated extent depends on the round's sample history, which
  /// a cold canonical build does not share.
  void _expectLazyLayoutEquals(
    WeftLayoutResult actual,
    WeftLayoutResult expected,
  ) {
    expect(actual.boxes, hasLength(expected.boxes.length));
    for (var i = 0; i < actual.boxes.length; i++) {
      expect(actual.boxes[i].nodeId, expected.boxes[i].nodeId,
          reason: 'box $i nodeId');
      expect(actual.boxes[i].rect, expected.boxes[i].rect,
          reason: 'box $i rect');
    }
    expect(actual.commands, hasLength(expected.commands.length));
    for (var i = 0; i < actual.commands.length; i++) {
      final command = actual.commands[i];
      final other = expected.commands[i];
      expect(command.runtimeType, other.runtimeType, reason: 'command $i');
      expect(command.nodeId, other.nodeId, reason: 'command $i nodeId');
      expect(command.bounds, other.bounds, reason: 'command $i bounds');
      if (command is WeftTextPaintCommand) {
        final text = other as WeftTextPaintCommand;
        expect(command.offset, text.offset, reason: 'command $i offset');
        expect(command.painter.text!.toPlainText(),
            text.painter.text!.toPlainText(),
            reason: 'command $i text');
        expect(command.runs, hasLength(text.runs.length),
            reason: 'command $i runs');
        for (var j = 0; j < command.runs.length; j++) {
          expect(command.runs[j].nodeId, text.runs[j].nodeId);
          expect(command.runs[j].painterStart, text.runs[j].painterStart);
          expect(command.runs[j].painterEnd, text.runs[j].painterEnd);
        }
      } else if (command is WeftRectPaintCommand) {
        expect(command.rect, (other as WeftRectPaintCommand).rect);
        expect(command.color, other.color);
      } else if (command is WeftImagePaintCommand) {
        expect(
            command.destination, (other as WeftImagePaintCommand).destination);
      }
    }
    expect(actual.links, hasLength(expected.links.length));
    for (var i = 0; i < actual.links.length; i++) {
      expect(actual.links[i].nodeId, expected.links[i].nodeId);
      expect(actual.links[i].href, expected.links[i].href);
      expect(actual.links[i].rects, expected.links[i].rects,
          reason: 'link $i rects');
    }
    expect(actual.tagRegions, hasLength(expected.tagRegions.length));
    final actualTextIndex = actual.textIndex!;
    final expectedTextIndex = expected.textIndex!;
    expect(
        actualTextIndex.entries, hasLength(expectedTextIndex.entries.length));
    for (var i = 0; i < actualTextIndex.entries.length; i++) {
      expect(actualTextIndex.entries[i].nodeId,
          expectedTextIndex.entries[i].nodeId,
          reason: 'entry $i nodeId');
      expect(actualTextIndex.entries[i].text, expectedTextIndex.entries[i].text,
          reason: 'entry $i text');
      expect(actualTextIndex.entries[i].globalStart,
          expectedTextIndex.entries[i].globalStart,
          reason: 'entry $i start');
    }
    expect(actualTextIndex.text, expectedTextIndex.text);
  }

  WeftLayoutResult _expectAdoptedRoundEquals({
    required WeftLayoutResult previous,
    required String nextHtml,
    int revision = 2,
    required double viewportStart,
    Map<int, ui.Image> images = const <int, ui.Image>{},
  }) {
    final current = _lazyLayout(
      nextHtml,
      revision: revision,
      viewportStart: viewportStart,
      images: images,
      previous: previous,
    );
    final canonical = _lazyLayout(
      nextHtml,
      revision: revision,
      viewportStart: viewportStart,
      images: images,
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isTrue);
    expect(canonical.debugIsLazy, isTrue);
    _expectLazyLayoutEquals(current, canonical);
    return current;
  }

  test('a scrolled tail append adopts the prefix and matches canonical', () {
    final base = _article(30);
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    expect(previous.debugIsLazy, isTrue);
    final current = _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '$base${_article(3, start: 30)}',
      viewportStart: deep,
    );
    // Incremental admission: the adopted round visits only the appended
    // suffix, strictly fewer elements than the cold round's full walk.
    expect(current.debugEligibilityVisitCount, greaterThan(0));
    expect(current.debugEligibilityVisitCount,
        lessThan(previous.debugEligibilityVisitCount),
        reason: 'the adopted round must not re-walk the proven prefix');
  });

  test('a mid-document edit inside the window adopts the prefix', () {
    final base = _article(30);
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '${_article(15)}'
          '<p>第 15 段被替换为一段长得多的全新正文内容, the replacement is '
          'much longer than the original paragraph.</p>'
          '${_article(14, start: 16)}',
      viewportStart: deep,
    );
  });

  test('a table inside the adopted prefix never re-enters the descent', () {
    final base = '<table><tr><td style="border:1px solid #333333">'
        '表格单元格</td></tr></table>${_article(20, start: 1)}';
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    expect(previous.debugIsLazy, isTrue);
    // The table child's estimate state carries no resolved descendants in
    // the new snapshot's style cache; adopting its persisted minimum paint
    // offset is what keeps the walk away from the hard cache reads.
    _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '$base${_article(3, start: 21)}',
      viewportStart: deep,
    );
  });

  test('body-level list items keep their markers across the seam', () {
    // The third body-level li REPLACES an early paragraph, so it is
    // measured inside the window and its marker exposes the recovered
    // ordered-item counter (the two prefix li's).
    final base = '<li>第一项</li><li>第二项</li>'
        '<p>普通段落。Weft body text for the lazy prefix adoption suite, '
        'long enough to wrap at 360px.</p>${_article(20, start: 3)}';
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    final current = _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '<li>第一项</li><li>第二项</li>'
          '<li>第三项（替换段落）。</li>${_article(20, start: 3)}',
      viewportStart: deep,
    );
    expect(current.textIndex!.text, contains('第三项'));
  });

  test('a float image in the prefix keeps exclusion geometry', () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final base = '<p><img src="asset:adopt-float.png" style="float:left" '
        'width="96" height="72">首段浮图。</p>${_article(20, start: 1)}';
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(
      base,
      viewportStart: deep,
      images: _imagesFor(first, image),
    );
    addTearDown(previous.dispose);
    final next = _normalize(
      '$base${_article(3, start: 21)}',
      revision: 2,
    );
    final current = _lazyLayout(
      '$base${_article(3, start: 21)}',
      revision: 2,
      viewportStart: deep,
      images: _imagesFor(next, image),
      previous: previous,
    );
    final canonical = _lazyLayout(
      '$base${_article(3, start: 21)}',
      revision: 2,
      viewportStart: deep,
      images: _imagesFor(next, image),
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isTrue);
    _expectLazyLayoutEquals(current, canonical);
  });

  test('margin collapse state survives the adoption boundary', () {
    // The 30px-bottom paragraph sits INSIDE the adopted prefix; the edited
    // last block (measured at the deep viewport) carries a 20px top margin,
    // so the recovered pendingMargin must collapse exactly like a
    // from-scratch prepare would.
    final base = '${_article(19)}'
        '<p style="margin-bottom:30px">带下边距的段。</p><p>普通尾段。</p>';
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '${_article(19)}'
          '<p style="margin-bottom:30px">带下边距的段。</p>'
          '<p style="margin-top:20px">尾段被替换，只带上边距。</p>',
      viewportStart: deep,
    );
  });

  test('an ineligible suffix falls back to the full plain layout', () {
    final base = _article(30);
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    final next = _normalize(
      '$base<div style="float:left">非图片浮动使文档不合格。</div>',
      revision: 2,
    );
    final current = _lazyLayout(
      '$base<div style="float:left">非图片浮动使文档不合格。</div>',
      revision: 2,
      viewportStart: deep,
      previous: previous,
    );
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isFalse,
        reason: 'a non-image float in the suffix must fail admission');
    _expectLazyLayoutEquals(current, canonical);
  });

  test('a newly ineligible edit keeps plain suffix reuse via the re-run', () {
    // The previous round is a plain layout. The next round requests a
    // viewport and its edited block contains a non-image float, so the
    // suffix admission fails: the provisional lazy-mode diff must be
    // re-run in plain mode or the suffix translation would be lost.
    final base = _article(20);
    final previous = engine.layout(_normalize(base), width: 360);
    addTearDown(previous.dispose);
    final nextHtml = '${_article(10)}'
        '<p>第 10 段被替换，自带块级非图片浮动。</p>'
        '<p style="float:left">替换段自带的浮动使其不合格。</p>'
        '${_article(9, start: 11)}';
    final next = _normalize(nextHtml, revision: 2);
    final current = engine.layoutViewport(
      next,
      width: 360,
      viewportStart: 0,
      viewportEnd: viewportHeight,
      previous: previous,
    );
    final canonical = engine.layoutViewport(
      next,
      width: 360,
      viewportStart: 0,
      viewportEnd: viewportHeight,
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isFalse);
    expect(current.debugReusedBlockCount, next.body!.children.length - 2,
        reason: 'the plain re-run must restore the suffix translation: '
            'prefix up to the edit plus shifted suffix (the edited block '
            'and its float paragraph are the two fresh blocks)');
    _expectLazyLayoutEquals(current, canonical);
  });

  test('a head insert falls back to the full walk and matches canonical', () {
    final base = _article(30);
    final first = _normalize(base);
    final deep = _deepStart(first);
    final previous = _lazyLayout(base, viewportStart: deep);
    addTearDown(previous.dispose);
    final current = _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '<p>置顶新段。No prefix can be verified.</p>$base',
      viewportStart: deep,
    );
    expect(current.textIndex!.debugReusedEntryCount, 0,
        reason: 'k=0 keeps the full index build (ADR 0048)');
  });

  test('a plain previous seeds a lazy round through the full walk', () {
    final base = _article(30);
    final previous = engine.layout(_normalize(base), width: 360);
    addTearDown(previous.dispose);
    final deep = _deepStart(_normalize('$base${_article(3, start: 30)}'));
    final current = _expectAdoptedRoundEquals(
      previous: previous,
      nextHtml: '$base${_article(3, start: 30)}',
      viewportStart: deep,
    );
    expect(current.debugIsLazy, isTrue);
  });

  test('chained scrolled rounds keep adopting and matching canonical', () {
    var html = _article(30);
    var current =
        _lazyLayout(html, viewportStart: _deepStart(_normalize(html)));
    addTearDown(current.dispose);
    final coldVisits = current.debugEligibilityVisitCount;
    for (var round = 1; round <= 3; round++) {
      html += _article(3, start: 27 + 3 * (round - 1));
      final document = _normalize(html, revision: round + 1);
      final deep = _deepStart(document);
      final next = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: deep,
        viewportEnd: deep + viewportHeight,
        previous: current,
      );
      current.dispose();
      current = next;
      addTearDown(current.dispose);
      final canonical = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: deep,
        viewportEnd: deep + viewportHeight,
      );
      addTearDown(canonical.dispose);
      expect(next.debugIsLazy, isTrue);
      expect(next.debugEligibilityVisitCount, greaterThan(0));
      expect(next.debugEligibilityVisitCount, lessThan(coldVisits),
          reason: 'round $round must adopt the prefix verdict, not re-walk '
              'the whole document');
      _expectLazyLayoutEquals(next, canonical);
    }
  });
}

/// Rich article body with a heading every three paragraphs, inline emphasis
/// and links, so block, inline and heading structures all cross the seam.
String _article(int count, {int start = 0}) {
  final buffer = StringBuffer();
  for (var i = start; i < start + count; i++) {
    if (i % 3 == 0) {
      buffer.write('<h3>章节 $i:lazy 前缀采用</h3>');
    }
    buffer.write(
      '<p>第 $i 段。Weft streams <em>强调 $i</em> and '
      '<a href="https://example.com/a$i">links $i</a> through the '
      'adopted lazy prefix.</p>',
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
    const Rect.fromLTWH(0, 0, 96, 72),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(96, 72);
  picture.dispose();
  return image;
}
