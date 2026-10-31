import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0051: when a streaming snapshot's change sits at the head, the
/// backward diff proves the trailing body children unchanged and the text
/// index adopts their previous entries — shifted past the fresh head walk
/// and re-mapped onto the new document's node ids — instead of rebuilding
/// the whole stream. Adopted rounds must be entry-for-entry equal to a
/// canonical full rebuild; the stream's leading edge (where the previous
/// build stripped the first entry's whitespace) cannot be adopted across,
/// so the child that spanned it is re-walked fresh; every fallback
/// (body-level whitespace, a lazy previous) stays canonical too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  /// Lays [nextHtml] out against [previous]'s result and asserts the
  /// resulting text index equals a canonical full rebuild entry for entry.
  (WeftLayoutResult, WeftLayoutResult) expectAdoptedIndexEquals(
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

  test('a head insert adopts the carried suffix entries', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<p>置顶的新首段。Weft prepends content, so no prefix can be '
      'verified.</p>${_richArticle(3)}',
    );
    // Blocks shift and reuse through the suffix translation (ADR 0046);
    // the entries come back shifted and id-remapped instead of rebuilt.
    expect(current.debugReusedBlockCount, 4);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
    expect(current.textIndex!.debugReusedEntryCount,
        lessThan(previous.textIndex!.entries.length),
        reason: 'the head paragraph and the leading-edge entry are '
            'fresh-walked, not adopted');
    _expectLayoutEquals(current, canonical);
  });

  test('a hidden head block adopts every previous entry verbatim', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<div style="display:none">隐藏的头部块</div>${_richArticle(3)}',
    );
    // The hidden head emits nothing, so the walk state after it is the
    // stream's initial state: the seam matches at the very first carried
    // child and the shift delta is zero.
    expect(current.textIndex!.debugReusedEntryCount,
        previous.textIndex!.entries.length);
    expect(current.textIndex!.text, previous.textIndex!.text);
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('leading whitespace on the old first block survives the seam', () {
    final previous = engine.layout(
      _normalize('<p>   前导空白段落</p>${_richArticle(3, start: 1)}'),
      width: 360,
    );
    addTearDown(previous.dispose);
    expect(previous.textIndex!.entries.first.text, '前导空白段落',
        reason: 'the full build strips the stream-leading whitespace');
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<p>置顶快讯第 1 轮。</p>'
      '<p>   前导空白段落</p>${_richArticle(3, start: 1)}',
    );
    // Mid-stream the leading whitespace is interior and must reappear; the
    // adopted entry was built without it, so the child spanning the
    // leading edge is re-walked fresh and everything after it is adopted.
    expect(current.textIndex!.text, contains(' 前导空白段落'));
    expect(current.textIndex!.text, canonical.textIndex!.text);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
  });

  test('a <br> at the head tail pays the seam break before adoption', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<p>置顶快讯<br></p>${_richArticle(3)}',
    );
    // The head walk leaves a hard break pending; the seam does not match
    // the stream's initial state, so the first old child is re-walked and
    // the break lands between the head entry and the adopted range.
    expect(current.textIndex!.text, contains('置顶快讯\n\n'));
    expect(current.textIndex!.text, canonical.textIndex!.text);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
  });

  test('an empty trailing head block keeps the break pending', () {
    final previous = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<p>置顶快讯</p><div></div>${_richArticle(3)}',
    );
    expect(current.textIndex!.text, canonical.textIndex!.text);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
  });

  test('a head deletion adopts the shifted suffix with a negative delta', () {
    final previous = engine.layout(
      _normalize('${_richArticle(3)}${_richArticle(2, start: 3)}'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      _richArticle(2, start: 3),
    );
    // The first previous blocks are gone; the remaining ones are proven by
    // the backward diff and their entries shift to the front of the stream.
    expect(current.debugReusedBlockCount, 3);
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });

  test('chained head inserts keep adopting every round', () {
    final a = engine.layout(_normalize(_richArticle(3)), width: 360);
    addTearDown(a.dispose);
    final bHtml = '<p>置顶快讯第 1 轮。</p>${_richArticle(3)}';
    final b = engine.layout(
      _normalize(bHtml, revision: 2),
      width: 360,
      previous: a,
    );
    addTearDown(b.dispose);
    expect(b.textIndex!.debugReusedEntryCount, greaterThan(0));
    _expectTextIndexEquals(
      b.textIndex!,
      engine.layout(_normalize(bHtml, revision: 2), width: 360).textIndex!,
    );
    final cHtml = '<p>置顶快讯第 2 轮。</p>$bHtml';
    final (c, canonical) = expectAdoptedIndexEquals(
      b,
      cHtml,
      revision: 3,
    );
    expect(c.textIndex!.debugReusedEntryCount, greaterThan(0));
    expect(c.textIndex!.text, canonical.textIndex!.text);
  });

  test('body-level whitespace between blocks trims the adoption', () {
    // The previous body must be free of body-level text children — the
    // block diff's cache gate (ADR 0046) refuses documents whose raw child
    // count exceeds their block count — so the whitespace is inserted on
    // the new side, where it only stops the raw trailing count.
    final previous = engine.layout(
      _normalize('<p>Alpha</p><p>Beta</p><p>Gamma</p>'),
      width: 360,
    );
    addTearDown(previous.dispose);
    final (current, canonical) = expectAdoptedIndexEquals(
      previous,
      '<p>置顶快讯。</p><p>Alpha</p>\n<p>Beta</p><p>Gamma</p>',
    );
    // The backward diff proves Beta and Gamma, but the body-level text
    // node stops the raw trailing count: Alpha and the whitespace are
    // re-walked fresh and only the trailing blocks' entries are adopted.
    expect(current.textIndex!.debugReusedEntryCount, greaterThan(0));
    expect(current.textIndex!.debugReusedEntryCount,
        lessThan(previous.textIndex!.entries.length));
    expect(current.textIndex!.text, canonical.textIndex!.text);
  });
}

WeftDocumentSnapshot _normalize(String html, {int revision = 1}) {
  return const WeftNormalizer().normalize(
    html,
    id: 'suffix-entry-adoption',
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
      'adopted suffix entries.</p>',
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

/// Full layout-result equality: the adopted-index round must be
/// indistinguishable from a canonical full rebuild, including the command
/// and link node ids the id remap feeds.
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
    }
  }
  expect(actual.links, hasLength(expected.links.length));
  for (var i = 0; i < actual.links.length; i++) {
    expect(actual.links[i].nodeId, expected.links[i].nodeId,
        reason: 'link $i nodeId');
    expect(actual.links[i].href, expected.links[i].href);
    expect(actual.links[i].rects, expected.links[i].rects,
        reason: 'link $i rects');
  }
}
