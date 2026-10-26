import 'dart:math' as math;

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

  test('100k-character document supports random cross-paragraph selections',
      () {
    final buffer = StringBuffer();
    // Deterministic mix of CJK, emoji (surrogate pairs) and Latin text; the
    // paragraph count puts the logical stream past 100k characters.
    for (var i = 0; i < 850; i++) {
      buffer.write(
        '<p>段落 $i:混合 CJK 与 emoji \ud83d\ude00 内容,'
        'paragraph $i keeps Latin words flowing across several lines so '
        'selections frequently cross block boundaries. 中文测试</p>',
      );
    }
    final document = const WeftNormalizer().normalize(
      buffer.toString(),
      id: 'selection-100k',
    );
    expect(document.supportReport.canRender, isTrue);
    final result = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(result.dispose);
    final index = result.textIndex!;
    expect(index.text.length, greaterThanOrEqualTo(100000));

    bool isLoneSurrogate(String text) {
      for (var i = 0; i < text.length; i++) {
        final unit = text.codeUnitAt(i);
        final isLead = (unit & 0xFC00) == 0xD800;
        final isTrail = (unit & 0xFC00) == 0xDC00;
        if (isLead &&
            (i + 1 >= text.length ||
                (text.codeUnitAt(i + 1) & 0xFC00) != 0xDC00)) {
          return true;
        }
        if (isTrail &&
            (i == 0 || (text.codeUnitAt(i - 1) & 0xFC00) != 0xD800)) {
          return true;
        }
      }
      return false;
    }

    int snapToCodePointStart(String text, int offset) {
      if (offset >= text.length) return text.length;
      if ((text.codeUnitAt(offset) & 0xFC00) == 0xDC00) return offset - 1;
      return offset;
    }

    final random = math.Random(20261027);
    for (var pick = 0; pick < 40; pick++) {
      final first = random.nextInt(index.entries.length);
      final second = random.nextInt(index.entries.length);
      final startEntry = index.entries[math.min(first, second)];
      final endEntry = index.entries[math.max(first, second)];
      final startOffset = snapToCodePointStart(
        startEntry.text,
        random.nextInt(startEntry.text.length + 1),
      );
      final endOffset = snapToCodePointStart(
        endEntry.text,
        random.nextInt(endEntry.text.length + 1),
      );
      final selection = TextSelectionRange(
        anchor: TextAnchor(startEntry.nodeId, startOffset),
        extent: TextAnchor(endEntry.nodeId, endOffset),
      );
      // The resolved global range must equal the copied text length: a real
      // invariant that catches silent index corruption at scale.
      final globalStart = startEntry.globalStart + startOffset;
      final globalEnd = endEntry.globalStart + endOffset;
      final copied = result.selectionText(selection);
      expect(copied, isNotNull);
      expect(
        copied!.length,
        globalEnd - globalStart,
        reason: 'pick $pick copied text length mismatch',
      );
      expect(
        isLoneSurrogate(copied),
        isFalse,
        reason: 'pick $pick split a surrogate pair',
      );

      // Glyph ink boxes (emoji fallback fonts, fullwidth punctuation) can
      // overhang the layout advance by a few pixels; the layout commands
      // themselves stay inside the width (corpus gate), and paint clips at
      // the surface edge.
      for (final rect in result.selectionRects(selection)) {
        expect(rect.left, greaterThanOrEqualTo(-0.5));
        expect(rect.right, lessThanOrEqualTo(372));
        expect(rect.top, greaterThanOrEqualTo(-0.5));
        expect(rect.bottom, lessThanOrEqualTo(result.size.height + 0.5));
      }
    }

    // The gesture path resolves anchors from real glyph points; the copy must
    // stay surrogate-safe through it as well.
    final emojiEntry =
        index.entries.firstWhere((entry) => entry.text.contains('\ud83d'));
    final rects =
        result.textRectsForNode(emojiEntry.nodeId, 0, emojiEntry.text.length);
    expect(rects, isNotEmpty);
    final gestureAnchor = result.anchorAt(rects.first.center);
    expect(gestureAnchor, isNotNull);
    final gestureRange = TextSelectionRange(
      anchor: gestureAnchor!,
      extent: TextAnchor(
        index.entries.last.nodeId,
        index.entries.last.text.length,
      ),
    );
    expect(
      isLoneSurrogate(result.selectionText(gestureRange)!),
      isFalse,
    );
  });

  test('selection survives streaming append and is safely cleared on edits',
      () {
    const engine = WeftLayoutEngine();
    final first = const WeftNormalizer().normalize(
      '<p>Alpha paragraph</p><p>Beta paragraph</p>',
      id: 'remap',
    );
    final initial = engine.layout(first, width: 360);
    final index = initial.textIndex!;
    final betaEntry =
        index.entries.firstWhere((entry) => entry.text.startsWith('Beta'));
    final selection = TextSelectionRange(
      anchor: TextAnchor(betaEntry.nodeId, 0),
      extent: TextAnchor(betaEntry.nodeId, betaEntry.text.length),
    );
    expect(initial.selectionRects(selection), isNotEmpty);

    // A same-id streaming append keeps the unchanged prefix, so the old
    // anchors still resolve against the new layout.
    final appended = const WeftNormalizer().normalize(
      '<p>Alpha paragraph</p><p>Beta paragraph</p><p>Gamma paragraph</p>',
      id: 'remap',
    );
    final remapped = engine.layout(appended, width: 360, previous: initial);
    addTearDown(remapped.dispose);
    expect(remapped.selectionRects(selection), isNotEmpty);
    expect(remapped.selectionText(selection), 'Beta paragraph');
    initial.dispose();

    // An edit that removes the selected node safely drops the selection
    // instead of producing stale geometry.
    final edited = const WeftNormalizer().normalize(
      '<p>Alpha paragraph</p>',
      id: 'remap-edited',
    );
    final cleared = engine.layout(edited, width: 360);
    addTearDown(cleared.dispose);
    expect(cleared.selectionRects(selection), isEmpty);
    expect(cleared.selectionText(selection), isNull);
  });
}
