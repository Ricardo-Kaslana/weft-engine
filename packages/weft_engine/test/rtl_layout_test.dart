import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

WeftDocumentSnapshot _normalize(String html, {String id = 'rtl'}) =>
    const WeftNormalizer().normalize(html, id: id);

WeftLayoutResult _layout(
  WeftDocumentSnapshot document, {
  double width = 320,
  Map<int, ui.Image> images = const {},
}) {
  return const WeftLayoutEngine()
      .layout(document, width: width, images: images);
}

Future<ui.Image> _createImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366CC),
  );
  return recorder.endRecording().toImageSync(width, height);
}

WeftElement _firstElement(WeftDocumentSnapshot document) =>
    document.body!.children.whereType<WeftElement>().first;

WeftTextPaintCommand _commandFor(
  WeftLayoutResult result,
  NodeId nodeId, {
  bool withRuns = true,
}) {
  return result.commands.whereType<WeftTextPaintCommand>().firstWhere(
        (command) =>
            command.nodeId == nodeId &&
            (withRuns ? command.runs.isNotEmpty : command.runs.isEmpty),
      );
}

ui.Rect _union(List<ui.Rect> rects) {
  var result = rects.first;
  for (final rect in rects.skip(1)) {
    result = result.expandToInclude(rect);
  }
  return result;
}

NodeId _firstTextNodeId(WeftElement element) {
  for (final child in element.children) {
    if (child is WeftText && child.text.trim().isNotEmpty) return child.id;
  }
  throw StateError('element has no text child');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dir rtl lays the paragraph out right-aligned with an rtl painter', () {
    final document = _normalize(
      '<p>Left control</p><p dir="rtl">مرحبا بالعالم</p>',
    );
    final result = _layout(document);
    final elements = document.body!.children.whereType<WeftElement>().toList();

    final ltr = _commandFor(result, elements[0].id);
    expect(ltr.painter.textDirection, ui.TextDirection.ltr);

    final rtl = _commandFor(result, elements[1].id);
    expect(rtl.painter.textDirection, ui.TextDirection.rtl);
    // With textAlign.start the RTL paragraph hugs the right content edge.
    final textId = _firstTextNodeId(elements[1]);
    final rtlRects = result.textRectsForNode(textId, 0, 13);
    final rtlUnion = _union(rtlRects);
    expect(rtlUnion.right, greaterThan(300));
    // The 208px-wide line hugs the right edge instead of starting at 0.
    expect(rtlUnion.left, greaterThan(100));

    final controlRects = result.textRectsForNode(
      _firstTextNodeId(elements[0]),
      0,
      12,
    );
    expect(_union(controlRects).left, lessThan(20));
  });

  test('dir auto resolves through the first strong character', () {
    final document = _normalize(
      '<p dir="auto">Hello world</p>'
      '<p dir="auto">مرحبا world</p>'
      '<p dir="auto">...123!!!</p>'
      '<div dir="rtl"><p dir="auto">...123!!!</p></div>',
    );
    final result = _layout(document);
    final elements = document.body!.children.whereType<WeftElement>().toList();
    final nested = elements[3].children.whereType<WeftElement>().single;

    expect(_commandFor(result, elements[0].id).painter.textDirection,
        ui.TextDirection.ltr);
    expect(_commandFor(result, elements[1].id).painter.textDirection,
        ui.TextDirection.rtl);
    // No strong character inherits the parent direction.
    expect(_commandFor(result, elements[2].id).painter.textDirection,
        ui.TextDirection.ltr);
    expect(_commandFor(result, nested.id).painter.textDirection,
        ui.TextDirection.rtl);
  });

  test('nested dir and CSS direction override the inherited direction', () {
    final document = _normalize(
      '<div dir="rtl"><p>rtl inherited</p><p dir="ltr">ltr override</p></div>'
      '<p style="direction: rtl">css rtl</p>',
    );
    final result = _layout(document);
    final div = _firstElement(document);
    final paragraphs = div.children.whereType<WeftElement>().toList();
    final cssParagraph = document.body!.children.whereType<WeftElement>().last;

    expect(_commandFor(result, paragraphs[0].id).painter.textDirection,
        ui.TextDirection.rtl);
    expect(_commandFor(result, paragraphs[1].id).painter.textDirection,
        ui.TextDirection.ltr);
    expect(_commandFor(result, cssParagraph.id).painter.textDirection,
        ui.TextDirection.rtl);
  });

  test('lang reaches the painter locale and the default stays zh', () {
    final document = _normalize(
      '<p>default</p><p lang="ar">arabic</p>'
      '<p lang="he-IL">hebrew israel</p>',
    );
    final result = _layout(document);
    final elements = document.body!.children.whereType<WeftElement>().toList();

    expect(
        _commandFor(result, elements[0].id).painter.locale?.languageCode, 'zh');
    expect(
        _commandFor(result, elements[1].id).painter.locale?.languageCode, 'ar');
    final hebrew = _commandFor(result, elements[2].id).painter.locale;
    expect(hebrew?.languageCode, 'he');
    expect(hebrew?.countryCode, 'IL');
  });

  test('RTL lists mirror the indent and the marker side', () {
    final document = _normalize(
      '<ul dir="rtl"><li>عنصر</li></ul>'
      '<ul><li>item</li></ul>',
    );
    final result = _layout(document);
    final lists = document.body!.children.whereType<WeftElement>().toList();
    final rtlItem = lists[0].children.whereType<WeftElement>().single;
    final ltrItem = lists[1].children.whereType<WeftElement>().single;

    final rtlTextRects = result.textRectsForNode(
      _firstTextNodeId(rtlItem),
      0,
      1,
    );
    expect(rtlTextRects, isNotEmpty);
    // The mirrored indent leaves 40px of padding on the right.
    expect(rtlTextRects.first.right, lessThan(285));
    final ltrTextRects = result.textRectsForNode(
      _firstTextNodeId(ltrItem),
      0,
      1,
    );
    expect(ltrTextRects.first.left, greaterThan(35));

    final rtlMarker = _commandFor(result, rtlItem.id, withRuns: false);
    final ltrMarker = _commandFor(result, ltrItem.id, withRuns: false);
    // The RTL marker sits to the right of the text, the LTR one to the left.
    expect(rtlMarker.offset.dx, greaterThan(rtlTextRects.first.right));
    expect(ltrMarker.offset.dx + ltrMarker.painter.width,
        lessThan(ltrTextRects.first.left));
  });

  test('RTL text next to a float keeps breaking lines correctly', () async {
    final html = StringBuffer();
    html.write('<div dir="rtl">');
    html.write('<img src="asset:x.png" alt="x" width="60" height="60" '
        'style="float: left">');
    for (var i = 0; i < 24; i++) {
      html.write('مرحبا بالعالم ');
    }
    html.write('</div>');
    final document = _normalize(html.toString(), id: 'rtl-float');
    final image = await _createImage(60, 60);
    addTearDown(image.dispose);
    final block = _firstElement(document);
    final imgElement = block.children.whereType<WeftElement>().first;
    final result = _layout(
      document,
      images: {imgElement.id: image},
    );

    final lineCommands = result.commands
        .whereType<WeftTextPaintCommand>()
        .where((command) => command.nodeId == block.id)
        .toList();
    // The float path is active and the probe-based breaker advances line by
    // line instead of looping or swallowing the text.
    expect(lineCommands.length, greaterThan(2));
    for (final command in lineCommands) {
      expect(command.painter.textDirection, ui.TextDirection.rtl);
    }
    final covered = lineCommands.fold<int>(
      0,
      (total, command) =>
          total +
          command.runs.fold<int>(
            0,
            (sum, run) => sum + run.nodeEnd - run.nodeStart,
          ),
    );
    var textLength = 0;
    for (final child in block.children) {
      if (child is WeftText) textLength += child.text.length;
    }
    // Every one of the 24 lines ends at a collapsible space, and line-end
    // spaces are consumed without being painted, so 24 characters stay
    // outside the painted runs.
    expect(covered, textLength - 24);
  });

  test('the RTL caret hugs the right edge of the anchor glyph box', () {
    final document = _normalize(
      '<p>left</p><p dir="rtl">مرحبا</p>',
    );
    final result = _layout(document);
    final rtl = document.body!.children.whereType<WeftElement>().toList()[1];
    final textId = _firstTextNodeId(rtl);
    final glyph = result.textRectsForNode(textId, 0, 1).first;

    final caret = result.caretRectForAnchor(TextAnchor(textId, 0));
    expect(caret, isNotNull);
    expect(caret!.left, closeTo(glyph.right - 2, 0.5));

    final ltr = document.body!.children.whereType<WeftElement>().first;
    final ltrGlyph = result
        .textRectsForNode(
          _firstTextNodeId(ltr),
          0,
          1,
        )
        .first;
    final ltrCaret = result.caretRectForAnchor(
      TextAnchor(_firstTextNodeId(ltr), 0),
    );
    expect(ltrCaret!.left, closeTo(ltrGlyph.left, 0.5));
  });
}
