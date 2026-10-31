import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0044: a streaming snapshot's text index must be entry-for-entry
/// equal to a canonical full rebuild whenever the layout engine's block
/// diff proves a prefix unchanged — including the trailing-whitespace trim
/// restore, pending `<br>` breaks and dropped whitespace-only entries at
/// the prefix boundary — and must fall back to the full build otherwise.
/// ADR 0048: the diff prefix proves content, not geometry, so partially
/// measured lazy previouses engage the same incremental path, restored
/// stream tails are also restored when they sit inside a partial prefix,
/// and the incremental build carries its prefix checkpoints so chained
/// rounds keep reusing every round.
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

  /// Lazy variant of [expectStreamingIndexEquals]: both rounds go through
  /// `layoutViewport` so the previous cache is a partial measured window.
  (WeftLayoutResult, WeftLayoutResult) expectLazyIndexEquals(
    WeftLayoutResult previous,
    String nextHtml, {
    int revision = 2,
    double width = 360,
  }) {
    final next = _normalize(nextHtml, revision: revision);
    final current = engine.layoutViewport(
      next,
      width: width,
      viewportStart: 0,
      viewportEnd: 800,
      previous: previous,
    );
    final canonical = engine.layoutViewport(
      next,
      width: width,
      viewportStart: 0,
      viewportEnd: 800,
    );
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.debugIsLazy, isTrue);
    _expectTextIndexEquals(current.textIndex!, canonical.textIndex!);
    return (current, canonical);
  }

  WeftLayoutResult lazyLayout(String html, {int revision = 1}) {
    return engine.layoutViewport(
      _normalize(html, revision: revision),
      width: 360,
      viewportStart: 0,
      viewportEnd: 800,
    );
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

  test('a trimmed tail inside a partial prefix is restored mid-stream', () {
    // The previous document ends with a silent child after its emitting
    // block, so finish() trimmed an entry that sits INSIDE the reused
    // prefix once the diff stops at the edited child (ADR 0048).
    final previous = engine.layout(
      _normalize('<p>Alpha with tail space </p><div></div>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha with tail space </p><div>Beta</div>',
    );
    expect(current.textIndex!.text, 'Alpha with tail space \nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a dropped entry inside a partial prefix is restored mid-stream', () {
    final previous = engine.layout(
      _normalize('<p>Alpha</p><p> </p><div></div>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    expect(previous.textIndex!.entries, hasLength(1),
        reason: 'the whitespace-only entry is dropped, but only the last '
            'emitting child sits before a silent child');
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha</p><p> </p><div>Beta</div>',
    );
    expect(current.textIndex!.text, 'Alpha\n \nBeta');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a restored tail mid-prefix keeps a longer suffix intact', () {
    final previous = engine.layout(
      _normalize('<p>Alpha with tail space </p><div></div><div></div>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>Alpha with tail space </p><div>Beta</div><div></div>',
    );
    expect(current.textIndex!.text, 'Alpha with tail space \nBeta');
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
    // 3 prefix blocks + 4 suffix blocks shifted by the taller replacement
    // (ADR 0046); the text index still rebuilds only the suffix (ADR 0044).
    expect(current.debugReusedBlockCount, 7);
    expect(current.textIndex!.text, canonical.textIndex!.text);
    final seam = current.textIndex!.entries
        .firstWhere((entry) => entry.text.startsWith('第 2 段被替换'));
    expect(seam.globalStart, greaterThan(0));
  });

  test('a head insert reuses the shifted suffix and adopts its entries', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectStreamingIndexEquals(
      previous,
      '<p>置顶的新首段。Weft prepends content, so no prefix can be '
      'verified.</p>${_richArticle(3)}',
    );
    // Blocks shift and reuse (ADR 0046); with an empty forward prefix the
    // text index adopts the backward diff's entries shifted past the head
    // walk instead of rebuilding in full (ADR 0051).
    expect(current.debugReusedBlockCount, 4);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0),
        reason: 'the carried suffix entries shift and remap instead of '
            'rebuilding (ADR 0051)');
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

  test('a partially measured lazy previous reuses its measured prefix', () {
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
      reason: 'the lazy window must be partial so engagement proves the '
          'gate relaxation (ADR 0048), not full-window coverage',
    );
    final (current, canonical) = expectLazyIndexEquals(
      previous,
      '${_richArticle(30)}${_richArticle(3, start: 30)}',
    );
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0),
        reason: 'the diff-proven measured window is a content prefix, so '
            'the index must reuse it despite the partial geometry');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a lazy mid-document edit reuses the measured prefix', () {
    final previous = lazyLayout(_richArticle(30));
    addTearDown(previous.dispose);
    final (current, canonical) = expectLazyIndexEquals(
      previous,
      '${_richArticle(2)}<p>第 2 段被替换为一段长得多的全新正文内容, '
      'the replacement is much longer than the original paragraph.'
      '</p>${_richArticle(27, start: 3)}',
    );
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0),
        reason: 'the edit sits inside the measured window, so a partial '
            'prefix is proven and reused');
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('chained lazy rounds keep reusing index entries every round', () {
    var html = _richArticle(30);
    var current = lazyLayout(html);
    addTearDown(current.dispose);
    for (var round = 1; round <= 3; round++) {
      html += _richArticle(3, start: 27 + 3 * (round - 1));
      final document = _normalize(html, revision: round + 1);
      final next = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: 0,
        viewportEnd: 800,
        previous: current,
      );
      current.dispose();
      current = next;
      addTearDown(current.dispose);
      final canonical = engine.layoutViewport(
        document,
        width: 360,
        viewportStart: 0,
        viewportEnd: 800,
      );
      addTearDown(canonical.dispose);
      expect(next.debugIsLazy, isTrue);
      expect(next.textIndex!.debugReusedEntryCount, greaterThan(0),
          reason: 'round $round must reuse — the previous incremental build '
              'carries its prefix checkpoints, so the chain never alternates '
              'back to a full build (ADR 0048)');
      _expectTextIndexEquals(next.textIndex!, canonical.textIndex!);
    }
  });

  test('two consecutive mid-document edits both reuse index entries', () {
    final a = engine.layout(_normalize(_richArticle(6)), width: 360);
    addTearDown(a.dispose);
    final b = engine.layout(
      _normalize(
        '${_richArticle(2)}<p>第 2 段第一轮替换。</p>${_richArticle(3, start: 3)}',
        revision: 2,
      ),
      width: 360,
      previous: a,
    );
    addTearDown(b.dispose);
    expect(b.textIndex!.debugReusedEntryCount, greaterThan(0));
    final (c, canonical) = expectStreamingIndexEquals(
      b,
      '${_richArticle(2)}<p>第 2 段第二轮替换，这次内容又不一样了。</p>'
      '${_richArticle(3, start: 3)}',
      revision: 3,
    );
    expect(c.textIndex!.debugReusedEntryCount, greaterThan(0),
        reason: 'the first incremental build carries its prefix checkpoints, '
            'so the second consecutive edit still reuses (ADR 0048)');
    _expectTextIndexEquals(c.textIndex!, canonical.textIndex!);
  });

  test('interleaved body whitespace shortens the prefix, never correctness',
      () {
    final previous = lazyLayout('<p>Alpha</p>\n${_richArticle(30, start: 1)}');
    addTearDown(previous.dispose);
    expect(previous.debugIsLazy, isTrue);
    final (current, canonical) = expectLazyIndexEquals(
      previous,
      '<p>Alpha</p>\n${_richArticle(30, start: 1)}'
      '${_richArticle(3, start: 31)}',
    );
    // The raw child count stops at the whitespace text node (raw child 1,
    // which no diff block can map), so exactly the first block's entry is
    // reused and the rest of the stream is re-walked from its checkpoint.
    expect(current.textIndex!.debugReusedEntryCount, 1);
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a plain previous seeds a lazy next through the incremental path', () {
    final previous = engine.layout(_normalize(_richArticle(30)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectLazyIndexEquals(
      previous,
      '${_richArticle(30)}${_richArticle(3, start: 30)}',
    );
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('a lazy previous falls back to the full build for a plain next', () {
    final previous = lazyLayout(_richArticle(30));
    addTearDown(previous.dispose);
    final next = _normalize(
      '${_richArticle(30)}${_richArticle(3, start: 30)}',
      revision: 2,
    );
    final current = engine.layout(next, width: 360, previous: previous);
    final canonical = engine.layout(next, width: 360);
    addTearDown(current.dispose);
    addTearDown(canonical.dispose);
    expect(current.textIndex!.debugReusedEntryCount, 0,
        reason: 'a lazy cache cannot seed a plain diff, so the plain round '
            'rebuilds in full');
    _expectTextIndexEquals(current.textIndex!, canonical.textIndex!);
  });

  test('a lazy head insert keeps the full index build', () {
    final previous = lazyLayout(_richArticle(30));
    addTearDown(previous.dispose);
    final (current, canonical) = expectLazyIndexEquals(
      previous,
      '<p>置顶的新首段。Weft prepends content, so no prefix can be '
      'verified.</p>${_richArticle(30)}',
    );
    expect(current.textIndex!.debugReusedEntryCount, 0,
        reason: 'lazy rounds build no backward suffix map (ADR 0046), so '
            'the plain-only entry shift (ADR 0051) cannot engage and the '
            'index rebuilds in full');
    expect(current.textIndex!.text, canonical.textIndex!.text);
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
