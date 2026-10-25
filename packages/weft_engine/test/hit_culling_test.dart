import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeftDocumentSnapshot normalize(String html, String id) {
    final document = const WeftNormalizer().normalize(html, id: id);
    expect(
      document.supportReport.canRender,
      isTrue,
      reason: 'test document "$id" must be renderable',
    );
    return document;
  }

  WeftLayoutResult layout(WeftDocumentSnapshot document, {double width = 360}) {
    final result = const WeftLayoutEngine().layout(document, width: width);
    addTearDown(result.dispose);
    return result;
  }

  /// Every point whose resolution is worth comparing: one per painted text
  /// entry, one per link rect, points in the gaps between top-level blocks
  /// and points outside the document. All are resolved against the full
  /// back-to-front scans and against the chunk-culled path of the same
  /// layout; the two must agree exactly.
  List<Offset> samplePoints(
      WeftLayoutResult result, WeftDocumentSnapshot document) {
    final points = <Offset>[];
    void add(Offset point) {
      if (points.any((existing) => existing == point)) return;
      points.add(point);
    }

    final index = result.textIndex!;
    for (final entry in index.entries) {
      final rects = result.textRectsForNode(entry.nodeId, 0, 1);
      if (rects.isEmpty) continue;
      add(rects.first.center);
    }
    for (final link in result.links) {
      for (final rect in link.rects) {
        add(rect.center);
      }
    }
    // Gaps between consecutive top-level children, ordered by their box top.
    final topLevel = result.boxes.toList()
      ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    for (var i = 1; i < topLevel.length; i++) {
      final above = topLevel[i - 1].rect;
      final below = topLevel[i].rect;
      if (below.top <= above.bottom) continue;
      add(Offset(above.left + 2, (above.bottom + below.top) / 2));
    }
    // Above, below and right of the document.
    add(Offset(result.size.width / 2, -40));
    add(Offset(result.size.width / 2, result.size.height + 40));
    add(Offset(result.size.width + 40, result.size.height / 2));
    return points;
  }

  test('culled anchorAt, wordSelectionAt and linkAt match full scans', () {
    final buffer = StringBuffer();
    for (var i = 0; i < 30; i++) {
      buffer.write('<h3>章节 $i 命中裁剪对照</h3>');
      buffer.write(
        '<p>第 $i 段 mixed text with <em>强调 $i</em> and '
        '<a href="https://example.com/l$i">inline link 第 $i 段</a> '
        'wrapping onto several lines.</p>',
      );
      if (i == 15) {
        // Extra commands inside one chunk: table cells and list markers.
        buffer.write(
          '<table><tr><td>cell a</td>'
          '<td><a href="https://example.com/t">cell link</a></td></tr></table>'
          '<ul><li>item one</li><li>item two</li></ul>',
        );
      }
    }
    final document = normalize(buffer.toString(), 'hit-culling-equivalence');
    final result = layout(document);
    final points = samplePoints(result, document);
    expect(points.length, greaterThan(60));

    // Resolve everything through the full back-to-front scans first: the
    // result has no attached document yet.
    final fullAnchors = <TextAnchor?>[];
    final fullWords = <TextSelectionRange?>[];
    final fullLinks = <WeftLinkRegion?>[];
    for (final point in points) {
      fullAnchors.add(result.anchorAt(point));
      fullWords.add(result.wordSelectionAt(point));
      fullLinks.add(result.linkAt(point));
    }

    // Then attach and resolve again through the culled path.
    result.attachDocument(document);
    var anchorHits = 0;
    var wordHits = 0;
    var linkHits = 0;
    for (var i = 0; i < points.length; i++) {
      final culledAnchor = result.anchorAt(points[i]);
      final culledWord = result.wordSelectionAt(points[i]);
      final culledLink = result.linkAt(points[i]);
      expect(culledAnchor, fullAnchors[i], reason: 'anchor at ${points[i]}');
      expect(culledWord, fullWords[i], reason: 'word at ${points[i]}');
      expect(culledLink, fullLinks[i], reason: 'link at ${points[i]}');
      if (fullAnchors[i] != null) anchorHits++;
      if (fullWords[i] != null) wordHits++;
      if (fullLinks[i] != null) linkHits++;
    }
    // The corpus must actually exercise hits, gaps and misses, or the
    // comparison proves nothing.
    expect(anchorHits, greaterThan(60));
    expect(wordHits, greaterThan(60));
    expect(linkHits, greaterThan(20));
    expect(anchorHits, lessThan(points.length));
    expect(fullLinks.any((link) => link == null), isTrue);
  });

  /// Point at the center of [command]'s glyphs for [start]..[end].
  Offset glyphPoint(WeftTextPaintCommand command, int start, int end) {
    final boxes = command.painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    expect(boxes, isNotEmpty);
    final box = boxes.first;
    return Offset(
      command.offset.dx + (box.left + box.right) / 2,
      command.offset.dy + (box.top + box.bottom) / 2,
    );
  }

  WeftTextPaintCommand chromeTextCommand(
    WeftLayoutResult result,
    WeftDocumentSnapshot document,
  ) {
    final body = document.body!;
    return result.commands.whereType<WeftTextPaintCommand>().singleWhere(
          (command) => command.nodeId == body.id,
        );
  }

  test('chrome chunk participates in hits: loose body text anchors', () {
    final document = normalize(
      '<body style="background-color: #ffeecc">'
          '<p>One paragraph</p>loose body text<p>Two paragraph</p>'
          '</body>',
      'hit-culling-chrome',
    );
    final result = layout(document);
    result.attachDocument(document);

    // Body-owned text carries the body node id on its command; its runs
    // still resolve into the logical index through the text node.
    final command = chromeTextCommand(result, document);
    final point = glyphPoint(command, 0, 5);
    final anchor = result.anchorAt(point);
    expect(anchor, isNotNull);
    final entry = result.textIndex!.entries
        .firstWhere((candidate) => candidate.text.contains('loose'));
    expect(anchor!.nodeId, entry.nodeId);

    // The chrome commands sit between the children's command ranges; the
    // culled path must agree with the full scan at the same point.
    final fullResult = layout(document);
    expect(fullResult.anchorAt(point), anchor);
  });

  test('a chrome text command overlapping a preceding chunk keeps flat order',
      () {
    // The paragraph's negative bottom margin pulls the body's loose inline
    // text up into the paragraph's last line, so both commands' bounds
    // contain the same point and back-to-front order decides the winner:
    // the loose text, painted after the paragraph in the flat list.
    final document = normalize(
      '<p style="margin-bottom: -18px">First block with enough wrapped text '
          'to fill several lines at this width.</p>loose tail text',
      'hit-culling-chrome-overlap',
    );
    final result = layout(document, width: 260);
    final paragraph = result.boxes
        .singleWhere((box) => box.nodeId == document.body!.children[0].id)
        .rect;
    final looseCommand = chromeTextCommand(result, document);
    final looseRect = looseCommand.bounds;
    expect(
      looseRect.top,
      lessThan(paragraph.bottom),
      reason: 'the negative margin must overlap the two bounds',
    );

    final overlap = Offset(
      math.min(paragraph.right, looseRect.right) - 5,
      (math.max(paragraph.top, looseRect.top) +
              math.min(paragraph.bottom, looseRect.bottom)) /
          2,
    );

    final fullResult = layout(document, width: 260);
    final fullAnchor = fullResult.anchorAt(overlap);
    expect(fullAnchor, isNotNull);
    // The full scan visits the loose text first because it paints later in
    // the flat list; the culled path must pick the same winner.
    final looseEntry = result.textIndex!.entries
        .firstWhere((candidate) => candidate.text.contains('loose'));
    expect(fullAnchor!.nodeId, looseEntry.nodeId);
    result.attachDocument(document);
    expect(result.anchorAt(overlap), fullAnchor);
    expect(
      result.wordSelectionAt(overlap),
      fullResult.wordSelectionAt(overlap),
    );
  });

  test('points in chunk gaps and outside the document anchor nothing', () {
    final document = normalize(
      '<p style="margin: 24px 0">Alpha</p><p style="margin: 24px 0">Beta</p>',
      'hit-culling-gaps',
    );
    final result = layout(document);
    result.attachDocument(document);

    final paragraphs = document.body!.children;
    final first =
        result.boxes.singleWhere((box) => box.nodeId == paragraphs[0].id).rect;
    final second =
        result.boxes.singleWhere((box) => box.nodeId == paragraphs[1].id).rect;
    expect(second.top - first.bottom, greaterThan(10));

    final gapY = (first.bottom + second.top) / 2;
    expect(result.anchorAt(Offset(50, gapY)), isNull);
    expect(result.wordSelectionAt(Offset(50, gapY)), isNull);
    expect(result.linkAt(Offset(50, gapY)), isNull);
    expect(result.anchorAt(Offset(50, result.size.height + 50)), isNull);
    expect(result.anchorAt(Offset(-30, first.center.dy)), isNull);
    expect(
        result.linkAt(Offset(result.size.width + 30, first.center.dy)), isNull);
  });

  test('a point exactly on a chunk bound still resolves through the command',
      () {
    // Rect.contains excludes right/bottom edges while the text hit check
    // accepts them; the candidate filter must not cull those points.
    final document = normalize(
      '<p>Edge text</p>',
      'hit-culling-edge',
    );
    final result = layout(document, width: 200);
    final entry = result.textIndex!.entries.single;
    final glyph = result.textRectsForNode(entry.nodeId, 0, 4).first;
    final command = result.commands.whereType<WeftTextPaintCommand>().single;
    // A point on the command's bottom edge, offset onto a painted glyph.
    final bottomEdge = Offset(
      command.offset.dx + (glyph.left + glyph.right) / 2,
      command.bounds.bottom,
    );
    final fullResult = layout(document, width: 200);
    final expected = fullResult.anchorAt(bottomEdge);
    result.attachDocument(document);
    expect(result.anchorAt(bottomEdge), expected);
  });
}
