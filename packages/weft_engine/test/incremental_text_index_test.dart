import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0044: a streaming snapshot's text index must be entry-for-entry
/// equal to a canonical full rebuild whenever the layout engine's block
/// diff proves a prefix unchanged — including the trailing-whitespace trim
/// restore, pending `<br>` breaks and dropped whitespace-only entries at
/// the prefix boundary — and must fall back to the full build otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  /// Lays [nextHtml] out against [previous]'s result and asserts the
  /// resulting text index equals a canonical full rebuild entry for entry.
  (WeftLayoutResult, WeftLayoutResult) expectStreamingIndexEquals(
    WeftLayoutResult previous,
    String nextHtml, {
    int revision = 2,
    double width = 360,
  }) {
    final next = _normalize(nextHtml, revision: revision);
    final current = engine.layout(next, width: width, previous: previous);
    final canonical = engine.layout(next, width: width);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    _expectTextIndexEquals(current.textIndex!, canonical.textIndex!);
    return (current, canonical);
  }

  test('tail append over a rich article matches the full build', () {
    final previous = engine.layout(_normalize(_richArticle(6)), width: 360);
    addTearDown(previous.dispose);
    expect(previous.textIndex, isNotNull);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '${_richArticle(6)}${_richArticle(9, start: 6)}',
    );
    expect(current.debugReusedBlockCount, greaterThan(0));
    expect(current.textIndex!.text, contains('第 8 段'));
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('trailing whitespace on the boundary entry is restored', () {
    final previous = engine.layout(
      _normalize('<p>Alpha with tail space </p>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    expect(previous.textIndex!.entries.last.text.endsWith(' '), isFalse,
        reason: 'the full build trims the stream tail');
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha with tail space </p><p>Beta</p>',
    );
    // The restored space is now the interior seam between the entries.
    expect(current.textIndex!.text, 'Alpha with tail space \nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('pending <br> breaks at the boundary are carried into the suffix', () {
    final previous = engine.layout(
      _normalize('<p>Alpha<br><br></p>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha<br><br></p><p>Beta</p>',
    );
    expect(current.textIndex!.text, 'Alpha\n\n\nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a dropped whitespace-only boundary entry is restored', () {
    final previous = engine.layout(
      _normalize('<p>Alpha</p><p> </p>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    expect(previous.textIndex!.entries, hasLength(1),
        reason: 'the whitespace-only tail entry is dropped by the full build');
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha</p><p> </p><p>Beta</p>',
    );
    expect(current.textIndex!.text, 'Alpha\n \nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('hidden and empty boundary blocks resume with the right break state',
      () {
    final previous = engine.layout(
      _normalize('<p>Alpha</p><p style="display:none">gone</p><div></div>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha</p><p style="display:none">gone</p><div></div><p>Beta</p>',
    );
    expect(current.textIndex!.text, 'Alpha\nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('mid-document edit rebuilds the suffix with shifted offsets', () {
    final previous = engine.layout(_normalize(_richArticle(6)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '${_richArticle(2)}<p>第 2 段被替换为一段长得多的全新正文内容, '
      'the replacement is much longer than the original paragraph.'
      '</p>${_richArticle(3, start: 3)}',
    );
    expect(current.debugReusedBlockCount, 3);
    expect(current.textIndex!.text, canonical.textIndex!.text);
    final seam = current.textIndex!.entries
        .firstWhere((entry) => entry.text.startsWith('第 2 段被替换'));
    expect(seam.globalStart, greaterThan(0));
  });

  test('head insert cannot reuse and equals the full build', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>置顶的新首段。Weft prepends content, so no prefix can be '
      'verified.</p>${_richArticle(3)}',
    );
    expect(current.debugReusedBlockCount, 0);
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a byte-identical snapshot rebuilds to the previous index', () {
    final html = _richArticle(4);
    final previous = engine.layout(_normalize(html), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      html,
      revision: 2,
    );
    expect(current.debugReusedBlockCount, greaterThan(0));
    expect(current.textIndex!.text, previous.textIndex!.text);
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('chained streaming rounds keep matching the full build', () {
    final a = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(a.dispose);
    final b = engine.layout(
      _normalize('${_richArticle(3)}${_richArticle(3, start: 3)}', revision: 2),
      width: 360,
      previous: a,
    );
    addTearDown(b.dispose);
    _expectTextIndexEquals(
      b.textIndex!,
      engine
          .layout(
            _normalize('${_richArticle(3)}${_richArticle(3, start: 3)}',
                revision: 2),
            width: 360,
          )
          .textIndex!,
    );
    final (c, canonical) = expectStreamingIndexEquals(
      b,
      '${_richArticle(3)}${_richArticle(6, start: 3)}${_richArticle(3, start: 9)}',
      revision: 3,
    );
    expect(c.textIndex!.text, canonical.textIndex!.text);
  });

  test('lists, nesting, leading whitespace and CJK survive the seam', () {
    final previous = engine.layout(
      _normalize(
        '<div><p>嵌套块内的段落</p></div>'
        '<ol><li>第一项</li><li>第二项</li></ol>'
        '<p>   前导空白段落</p><p>中文段落，标点禁则。Weft engine。</p>',
      ),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<div><p>嵌套块内的段落</p></div>'
      '<ol><li>第一项</li><li>第二项</li></ol>'
      '<p>   前导空白段落</p><p>中文段落，标点禁则。Weft engine。</p>'
      '<p>追加的中文段落。</p>',
    );
    expect(current.textIndex!.text, canonical.textIndex!.text);
    expect(current.textIndex!.text, contains('追加的中文段落'));
  });

  test('an index-less whitespace document grows through the same path', () {
    final previous = engine.layout(_normalize('<p> </p>'), width: 360);
    addTearDown(previous.dispose);
    expect(previous.textIndex!.entries, isEmpty);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p> </p><p>Beta</p>',
    );
    expect(current.textIndex!.text, 'Beta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a stylesheet change falls back to the full build', () {
    final previous = engine.layout(
      _normalize('<style>p{color:#333}</style>${_richArticle(3)}'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final next = _normalize(
      '<style>p{color:#111}</style>${_richArticle(3)}${_richArticle(3, start: 3)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugReusedBlockCount, 0,
        reason: 'the stylesheet signature must block the block diff');
    _expectTextIndexEquals(current.textIndex!, canonical.textIndex!);
  });

  test('a partially measured lazy previous falls back to the full build', () {
    final first = _normalize(_richArticle(30));
    final previous = engine.layoutViewport(
      first,
      width: 360,
      viewportStart: 0,
      viewportEnd: 800,
    );
    addTearDown(previous.dispose);
    expect(previous.debugIsLazy, isTrue);
    expect(
      previous.incrementalCache!.blocks.length,
      lessThan(first.body!.children.length),
      reason: 'the lazy window must be partial for this fallback to apply',
    );
    final next = _normalize('${_richArticle(30)}${_richArticle(3, start: 30)}',
        revision: 2);
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
    _expectTextIndexEquals(current.textIndex!, canonical.textIndex!);
  });

  test('selection across the seam matches the canonical rects and text', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '${_richArticle(3)}${_richArticle(3, start: 3)}',
    );
    final entries = current.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries.first.nodeId, 0),
      extent: TextAnchor(entries.last.nodeId, 2),
    );
    expect(
        current.selectionRects(selection), canonical.selectionRects(selection));
    expect(
        current.selectionText(selection), canonical.selectionText(selection));
    expect(current.selectionText(selection), isNotEmpty);
  });
}

WeftDocumentSnapshot _normalize(String html, {int revision = 1}) {
  return const WeftNormalizer().normalize(
    html,
    id: 'incremental-text-index',
    revision: revision,
  );
}

/// Rich article body with a heading every three paragraphs, inline emphasis
/// and links, so block and inline structures both cross the seam.
String _richArticle(int count, {int start = 0}) {
  final buffer = StringBuffer();
  for (var i = start; i < start + count; i++) {
    if (i % 3 == 0) {
      buffer.write('<h3>章节 $i:流式文本索引等价</h3>');
    }
    buffer.write(
      '<p>第 $i 段。Weft streams <em>强调 $i</em> and '
      '<a href="https://example.com/a$i">links $i</a> through the '
      'incremental index.</p>',
    );
  }
  return buffer.toString();
}

/// Entry-for-entry text index equality (ADR 0044).
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
  for (final entry in expected.entries) {
    final other = actual.entryByNode[entry.nodeId];
    expect(other, isNotNull, reason: 'entry for node ${entry.nodeId}');
    expect(other!.globalStart, entry.globalStart);
    expect(other.text, entry.text);
  }
  expect(actual.length, expected.length);
  expect(actual.text, expected.text);
}
