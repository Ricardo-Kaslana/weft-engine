import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeftLayoutResult layout(String html, {double width = 400}) {
    final document = const WeftNormalizer().normalize(html, id: 'selection');
    final result = const WeftLayoutEngine().layout(document, width: width);
    addTearDown(result.dispose);
    return result;
  }

  TextAnchor anchor(WeftTextIndex index, int entry, int offset) {
    return TextAnchor(index.entries[entry].nodeId, offset);
  }

  test('logical index joins paragraphs with single newlines', () {
    final result = layout('<p>Alpha</p><p>Beta</p>');
    final index = result.textIndex!;
    expect(index.text, 'Alpha\nBeta');
    expect(index.entries.map((entry) => entry.nodeId), hasLength(2));
  });

  test('br contributes one newline and nested blocks do not multiply', () {
    final result = layout('<p>One<br>Two</p><div><div>Nested</div></div>');
    final index = result.textIndex!;
    expect(index.text, 'One\nTwo\nNested');
  });

  test('whitespace is collapsed in the painted text', () {
    final result = layout('<p>  Alpha\n  and\tBeta  </p>');
    final index = result.textIndex!;
    expect(index.text, 'Alpha and Beta');
  });

  test('pre keeps raw whitespace and explicit newlines', () {
    final result = layout(
      '<pre>keep  spacing\nexactly</pre>',
    );
    final index = result.textIndex!;
    expect(index.text, 'keep  spacing\nexactly');
  });

  test('selection across paragraphs maps rects in both blocks', () {
    final result = layout('<p>Alpha block</p><p>Beta block</p>');
    final index = result.textIndex!;
    // From inside "Alpha" to the end of "Beta".
    final selection = TextSelectionRange(
      anchor: anchor(index, 0, 2),
      extent: anchor(index, 1, 4),
    );
    final rects = result.selectionRects(selection);
    expect(rects, isNotEmpty);
    // The two paragraphs are laid out at different y positions.
    final tops = rects.map((rect) => rect.top).toSet();
    expect(tops.length, greaterThanOrEqualTo(2));

    final copy = result.selectionText(selection);
    expect(copy, 'pha block\nBeta');
  });

  test('reverse selection normalizes to document order', () {
    final result = layout('<p>Alpha</p><p>Beta</p>');
    final index = result.textIndex!;
    final selection = TextSelectionRange(
      anchor: anchor(index, 1, 2),
      extent: anchor(index, 0, 1),
    );
    expect(result.selectionText(selection), 'lpha\nBe');
  });

  test('collapsed selection produces no rects or text', () {
    final result = layout('<p>Alpha</p>');
    final index = result.textIndex!;
    final anchorPoint = anchor(index, 0, 1);
    final selection = TextSelectionRange.collapsed(anchorPoint);
    expect(result.selectionRects(selection), isEmpty);
    expect(result.selectionText(selection), isNull);
  });

  test('anchors in unknown nodes are dropped safely', () {
    final result = layout('<p>Alpha</p>');
    const selection = TextSelectionRange(
      anchor: const TextAnchor(999, 0),
      extent: const TextAnchor(1000, 1),
    );
    expect(result.selectionRects(selection), isEmpty);
    expect(result.selectionText(selection), isNull);
  });

  test('out of range offsets clamp to node bounds', () {
    final result = layout('<p>Alpha</p><p>Beta</p>');
    final index = result.textIndex!;
    final selection = TextSelectionRange(
      anchor: anchor(index, 0, 0),
      extent: anchor(index, 1, 99),
    );
    expect(result.selectionText(selection), 'Alpha\nBeta');
    expect(result.selectionRects(selection), isNotEmpty);
  });

  test('selection rects stay inside the painted line boxes', () {
    final result = layout(
      '<p style="width: 200px">alpha bravo charlie delta echo foxtrot</p>',
    );
    final index = result.textIndex!;
    final selection = TextSelectionRange(
      anchor: anchor(index, 0, 0),
      extent: anchor(index, 0, index.entries[0].text.length),
    );
    final rects = result.selectionRects(selection);
    expect(rects.length, greaterThan(1)); // wraps onto multiple lines
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(-0.5));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    }
  });

  test('link text participates in selection text', () {
    final result = layout(
      '<p>Visit <a href="https://example.com/x">the docs</a> today</p>',
    );
    final index = result.textIndex!;
    expect(index.text, 'Visit the docs today');
    // Entries: "Visit the docs" and " today". Select from the space to the
    // end.
    final selection = TextSelectionRange(
      anchor: anchor(index, 0, 6),
      extent: anchor(index, index.entries.length - 1, 6),
    );
    expect(result.selectionText(selection), 'the docs today');
  });

  test('table cell text is selectable across cells', () {
    final result = layout(
      '<table><tr><td>Cell A</td><td>Cell B</td></tr></table>',
    );
    final index = result.textIndex!;
    expect(index.text, 'Cell A\nCell B');
    final selection = TextSelectionRange(
      anchor: anchor(index, 0, 5),
      extent: anchor(index, 1, 4),
    );
    expect(result.selectionText(selection), 'A\nCell');
  });
}
