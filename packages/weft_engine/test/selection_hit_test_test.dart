import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image floatImage;

  setUpAll(() async {
    floatImage = await _createImage(48, 48, const Color(0xFF3366CC));
  });

  tearDownAll(() {
    floatImage.dispose();
  });

  WeftLayoutResult layout(String html, {double width = 400}) {
    final document = const WeftNormalizer().normalize(html, id: 'hit-test');
    final result = const WeftLayoutEngine().layout(document, width: width);
    addTearDown(result.dispose);
    return result;
  }

  WeftLayoutResult layoutWithFloat(String html) {
    final document = const WeftNormalizer().normalize(html, id: 'hit-float');
    final images = <int, ui.Image>{};
    void visit(WeftNode node) {
      if (node is! WeftElement) return;
      if (node.tag == 'img') images[node.id] = floatImage;
      for (final child in node.children) {
        visit(child);
      }
    }

    final body = document.body;
    if (body != null) visit(body);
    final result = const WeftLayoutEngine().layout(
      document,
      width: 240,
      images: images,
    );
    addTearDown(result.dispose);
    return result;
  }

  List<WeftTextPaintCommand> textCommands(WeftLayoutResult result) {
    return result.commands.whereType<WeftTextPaintCommand>().toList();
  }

  /// Document-space point at the center of the painter range [start, end).
  Offset pointForRange(WeftTextPaintCommand command, int start, int end) {
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

  test('anchorAt maps a second-line point to that line offset', () {
    final result = layout(
      '<p style="width: 200px">alpha bravo charlie delta echo foxtrot</p>',
    );
    final index = result.textIndex!;
    expect(index.entries, hasLength(1));
    final nodeId = index.entries.single.nodeId;
    final command = textCommands(result).single;
    final painter = command.painter;
    final lines = painter.computeLineMetrics();
    expect(
      lines.length,
      greaterThanOrEqualTo(2),
      reason: 'the paragraph must wrap onto multiple lines',
    );

    final second = lines[1];
    final local = Offset(
      second.left + 2,
      second.baseline - second.ascent + second.height / 2,
    );
    final anchor = result.anchorAt(command.offset + local);
    expect(anchor, isNotNull);
    expect(anchor!.nodeId, nodeId);

    // The anchor must resolve inside the clicked line's text range.
    final line = painter.getLineBoundary(painter.getPositionForOffset(local));
    expect(
      anchor.offset,
      inInclusiveRange(
        line.start,
        math.min(line.end, painter.plainText.length),
      ),
    );
  });

  test('anchorAt resolves dx-shifted float wrap lines beside the float', () {
    final result = layoutWithFloat(
      '<p><img src="memory://float.png" width="48" height="48" '
      'style="float: left; margin: 0 8px 4px 0">alpha bravo charlie delta '
      'echo foxtrot golf hotel</p>',
    );
    final index = result.textIndex!;
    expect(index.entries, hasLength(1));
    final nodeId = index.entries.single.nodeId;

    final shifted =
        textCommands(result).where((command) => command.offset.dx > 0).toList();
    expect(
      shifted,
      isNotEmpty,
      reason: 'text must wrap beside the floated image',
    );
    final command = shifted.first;
    final painter = command.painter;
    final plain = painter.plainText;
    final wordStart = plain.indexOf(' ') + 1;
    var wordEnd = plain.indexOf(' ', wordStart);
    if (wordEnd < 0) wordEnd = plain.length;
    expect(wordEnd, greaterThan(wordStart));

    final anchor = result.anchorAt(pointForRange(command, wordStart, wordEnd));
    expect(anchor, isNotNull);
    expect(anchor!.nodeId, nodeId);
    // Node offsets account for the line's position inside the node.
    final run = command.runs.single;
    expect(
      anchor.offset,
      inInclusiveRange(
        run.nodeStart + wordStart - run.painterStart,
        run.nodeStart + wordEnd - run.painterStart,
      ),
    );

    // Points over the float's own area do not anchor into the wrapped line.
    final overFloat = Offset(
      command.offset.dx / 2,
      command.offset.dy + painter.height / 2,
    );
    expect(result.anchorAt(overFloat), isNull);
  });

  test('anchorAt resolves points inside table cells', () {
    final result = layout(
      '<table><tr><td>Cell A</td><td>Cell B</td></tr></table>',
    );
    final index = result.textIndex!;
    expect(index.entries, hasLength(2));
    final cellCommand = textCommands(result).singleWhere(
      (command) => command.painter.plainText == 'Cell A',
    );

    final anchor = result.anchorAt(pointForRange(cellCommand, 0, 4));
    expect(anchor, isNotNull);
    expect(anchor!.nodeId, index.entries[0].nodeId);
    expect(anchor.offset, inInclusiveRange(0, 4));

    final word = result.wordSelectionAt(pointForRange(cellCommand, 0, 4));
    expect(word, isNotNull);
    expect(result.selectionText(word!), 'Cell');
  });

  test('wordSelectionAt selects the whole word under the point', () {
    final result = layout('<p>alpha bravo charlie</p>');
    final nodeId = result.textIndex!.entries.single.nodeId;
    final command = textCommands(result).single;

    // Click the middle of "bravo" (chars 6..11).
    final selection = result.wordSelectionAt(pointForRange(command, 6, 11));
    expect(selection, isNotNull);
    expect(selection!.anchor, TextAnchor(nodeId, 6));
    expect(selection.extent, TextAnchor(nodeId, 11));
    expect(result.selectionText(selection), 'bravo');
  });

  test('anchorAt returns null for points outside painted text', () {
    final document = const WeftNormalizer().normalize(
      '<p style="margin: 24px 0">Alpha</p><p style="margin: 24px 0">Beta</p>',
      id: 'hit-gap',
    );
    final result = const WeftLayoutEngine().layout(document, width: 400);
    addTearDown(result.dispose);

    final paragraphs = document.body!.children
        .whereType<WeftElement>()
        .where((element) => element.tag == 'p')
        .toList();
    expect(paragraphs, hasLength(2));
    final rects = paragraphs
        .map(
          (element) =>
              result.boxes.singleWhere((box) => box.nodeId == element.id).rect,
        )
        .toList();
    expect(
      rects[1].top - rects[0].bottom,
      greaterThan(10),
      reason: 'the collapsed margins must leave a visible gap',
    );

    // Inside the vertical gap between the two paragraphs.
    final gapY = (rects[0].bottom + rects[1].top) / 2;
    expect(result.anchorAt(Offset(50, gapY)), isNull);
    // Below the whole document.
    expect(result.anchorAt(Offset(50, result.size.height + 50)), isNull);
  });
}

Future<ui.Image> _createImage(int width, int height, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}
