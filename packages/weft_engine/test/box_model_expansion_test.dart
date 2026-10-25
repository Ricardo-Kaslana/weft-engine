import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image picture;

  setUpAll(() async {
    picture = await _createImage(200, 100, const Color(0xFF3366CC));
  });

  tearDownAll(() {
    picture.dispose();
  });

  group('explicit block height', () {
    test('px height fixes the border box and overflowing content paints', () {
      final document = const WeftNormalizer().normalize(
        '<div id="box" style="height: 30px; background: #eeeeee">'
        '<p style="margin: 0">First line of text</p>'
        '<p style="margin: 0">Second line</p></div>',
        id: 'height-overflow',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      final box = _boxFor(layout, document, 'box');
      expect(box.rect, const Rect.fromLTWH(0, 0, 300, 30));
      // The two 24px lines add up to 48px of content; the border box stays at
      // the explicit 30px and the second line keeps painting past its bottom.
      expect(layout.size.height, 30);
      final texts = _textCommands(layout);
      expect(texts, hasLength(2));
      expect(texts.last.offset.dy, 24);
      expect(texts.last.offset.dy + texts.last.painter.height, greaterThan(30));
    });

    test('em and rem heights convert against their own references', () {
      final document = const WeftNormalizer().normalize(
        '<div id="em" style="height: 2em; font-size: 20px">X</div>'
        '<div id="rem" style="height: 2rem">Y</div>',
        id: 'height-units',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'em').rect.height, 40);
      expect(_boxFor(layout, document, 'rem').rect.height, 32);
      expect(layout.size.height, 72);
    });

    test('height follows the same box-sizing conversion as width', () {
      final document = const WeftNormalizer().normalize(
        '<div id="content" style="height: 100px; padding: 10px 0; '
        'border: 2px solid #000">Text</div>'
        '<div id="border" style="height: 100px; padding: 10px 0; '
        'border: 2px solid #000; box-sizing: border-box">Text</div>',
        id: 'height-box-sizing',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'content').rect.height, 124);
      expect(_boxFor(layout, document, 'border').rect.height, 100);
      expect(layout.size.height, 224);
    });

    test('an empty block with a height keeps its box instead of collapsing',
        () {
      final document = const WeftNormalizer().normalize(
        '<p style="margin: 0">A</p>'
        '<div id="spacer" style="height: 50px; margin: 10px 0"></div>'
        '<p style="margin: 0">B</p>',
        id: 'height-spacer',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'spacer').rect,
          const Rect.fromLTWH(0, 34, 300, 50));
      expect(_textCommands(layout).last.offset.dy, 94);
      expect(layout.size.height, 118);

      // Without the height the same block collapses through and adds nothing.
      final collapsed = const WeftNormalizer().normalize(
        '<p style="margin: 0">A</p>'
        '<div style="margin: 10px 0"></div>'
        '<p style="margin: 0">B</p>',
        id: 'height-spacer-collapsed',
      );
      final collapsedLayout =
          const WeftLayoutEngine().layout(collapsed, width: 300);
      addTearDown(collapsedLayout.dispose);
      expect(_textCommands(collapsedLayout).last.offset.dy, 34);
      expect(collapsedLayout.size.height, 58);
    });

    test('a height block still collapses margins with its neighbors', () {
      final document = const WeftNormalizer().normalize(
        '<div id="h" style="height: 40px; margin-bottom: 20px"></div>'
        '<p id="after" style="margin: 10px 0 0 0">After</p>',
        id: 'height-adjacent-collapse',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'h').rect.height, 40);
      // The adjacent 20px and 10px margins collapse to the largest value.
      expect(_textCommands(layout).last.offset.dy, 60);
    });

    test('a last child margin does not escape an explicit height', () {
      final document = const WeftNormalizer().normalize(
        '<div id="h" style="height: 40px">'
        '<p style="margin: 0 0 30px 0">In</p></div>'
        '<p id="after" style="margin: 0">After</p>'
        '<div id="auto"><p style="margin: 0 0 30px 0">In</p></div>'
        '<p id="afterAuto" style="margin: 0">After</p>',
        id: 'height-bottom-collapse',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      // CSS folds the last child's bottom margin through an auto-height box
      // only, so the fixed 40px box ends at its own bottom edge and the next
      // sibling follows immediately.
      expect(_boxFor(layout, document, 'h').rect.height, 40);
      // The auto-height control still lets the 30px child margin collapse
      // through and push the following paragraph down.
      expect(_boxFor(layout, document, 'auto').rect.height, 24);
      final baselines =
          _textCommands(layout).map((command) => command.offset.dy);
      expect(baselines, [0, 40, 64, 118]);
    });

    test('percentage heights resolve as auto', () {
      final document = const WeftNormalizer().normalize(
        '<div id="box" style="height: 50%">X</div>'
        '<div id="empty" style="height: 50%; margin: 5px 0"></div>'
        '<p style="margin: 0">After</p>',
        id: 'height-percent',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 300);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'box').rect.height, 24);
      // A percentage height never materializes a box, so the empty block
      // keeps collapsing through its margins.
      expect(
        layout.boxes.where(
          (box) => box.nodeId == _findById(document.body!, 'empty').id,
        ),
        isEmpty,
      );
      expect(_textCommands(layout).last.offset.dy, 24 + 5);
    });
  });

  group('percentage block width', () {
    test('50% width centers through auto margins', () {
      final document = const WeftNormalizer().normalize(
        '<div id="box" style="width: 50%; margin: 0 auto">X</div>',
        id: 'percent-centered',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'box').rect,
          const Rect.fromLTWH(100, 0, 200, 24));
    });

    test(
        'percentage resolves against the containing block, not the '
        'margin-reduced space', () {
      final document = const WeftNormalizer().normalize(
        '<div id="single" style="width: 50%; margin-left: 40px">X</div>'
        '<div id="both" style="width: 50%; margin-left: 40px; '
        'margin-right: 60px">Y</div>',
        id: 'percent-margins',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      // CSS percentages are relative to the containing block content width,
      // so the margins shift the box without shrinking it.
      expect(_boxFor(layout, document, 'single').rect,
          const Rect.fromLTWH(40, 0, 200, 24));
      expect(_boxFor(layout, document, 'both').rect,
          const Rect.fromLTWH(40, 24, 200, 24));
    });

    test('min and max width clamp a percentage width', () {
      final document = const WeftNormalizer().normalize(
        '<div id="max" style="width: 80%; max-width: 200px">A</div>'
        '<div id="min" style="width: 10%; min-width: 120px">B</div>',
        id: 'percent-clamp',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'max').rect.width, 200);
      expect(_boxFor(layout, document, 'min').rect.width, 120);
    });

    test('nested percentages compound against each containing block', () {
      final document = const WeftNormalizer().normalize(
        '<div id="outer" style="width: 50%; margin: 0 auto">'
        '<div id="inner" style="width: 50%">X</div></div>',
        id: 'percent-nested',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      final outer = _boxFor(layout, document, 'outer');
      final inner = _boxFor(layout, document, 'inner');
      expect(outer.rect, const Rect.fromLTWH(100, 0, 200, 24));
      // 50% of the outer content width (200) = 25% of the viewport.
      expect(inner.rect.width, 100);
      expect(inner.rect.left, outer.rect.left);
    });

    test('content-box padding adds chrome on top of the percentage', () {
      final document = const WeftNormalizer().normalize(
        '<div id="box" style="width: 50%; padding: 10px">X</div>',
        id: 'percent-chrome',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      final box = _boxFor(layout, document, 'box');
      expect(box.rect.width, 220);
      expect(_textCommands(layout).single.offset.dx, 10);
    });
  });

  group('auto horizontal margins', () {
    test('a single auto side takes all the remaining space', () {
      final document = const WeftNormalizer().normalize(
        '<div id="left" style="width: 100px; margin-right: auto">A</div>'
        '<div id="right" style="width: 100px; margin-left: auto">B</div>',
        id: 'auto-single-side',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'left').rect.left, 0);
      expect(_boxFor(layout, document, 'right').rect.left, 300);
    });

    test('an auto-width block fills the line so auto margins do nothing', () {
      final document = const WeftNormalizer().normalize(
        '<div id="fill" style="margin: 0 auto">A</div>',
        id: 'auto-fill',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      expect(_boxFor(layout, document, 'fill').rect,
          const Rect.fromLTWH(0, 0, 400, 24));
    });

    test('auto margins compensate a negative sibling margin', () {
      final document = const WeftNormalizer().normalize(
        '<div id="box" style="width: 100px; margin-left: auto; '
        'margin-right: -50px">A</div>',
        id: 'auto-negative-margin',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      // 400 - 100 - (-50) = 350 of slack goes to the auto side, so the box
      // hugs the right edge including the negative margin overhang.
      expect(_boxFor(layout, document, 'box').rect,
          const Rect.fromLTWH(350, 0, 100, 24));
    });

    test('auto margin centering is independent of text alignment', () {
      final document = const WeftNormalizer().normalize(
        '<div id="left" style="width: 200px; margin: 0 auto; '
        'text-align: left">X</div>'
        '<div id="center" style="width: 200px; margin: 0 auto; '
        'text-align: center">X</div>',
        id: 'auto-text-align',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      // The box position comes from the margins alone; text-align only
      // arranges glyphs inside the box.
      expect(_boxFor(layout, document, 'left').rect.left, 100);
      expect(_boxFor(layout, document, 'center').rect.left, 100);
    });
  });

  group('replaced content and tables keep their own sizing', () {
    test('a block image ignores auto margin distribution', () {
      final document = const WeftNormalizer().normalize(
        '<img id="pic" src="asset:pic.png" '
        'style="display: block; width: 100px; margin: 0 auto">',
        id: 'image-auto-margin',
      );
      final layout = const WeftLayoutEngine().layout(
        document,
        width: 400,
        images: {_findById(document.body!, 'pic').id: picture},
      );
      addTearDown(layout.dispose);

      // Documented deviation (ADR 0021): image boxes keep auto margins at
      // zero instead of centering.
      final image = layout.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.left, 0);
      expect(image.destination.width, 100);
    });

    test('a table ignores auto margins and percentage width', () {
      final document = const WeftNormalizer().normalize(
        '<table id="t" style="width: 50%; margin: 0 auto">'
        '<tr><td>A</td></tr></table>',
        id: 'table-auto-margin',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      // The table grid keeps its content-driven width at the left edge;
      // neither the percentage nor the auto margins redistribute it.
      final table = _boxFor(layout, document, 't');
      expect(table.rect.left, 0);
      expect(table.rect.width, lessThan(200));
      expect(table.rect.width, greaterThan(0));
    });

    test('hr keeps its full-width 1px box and accepts the new widths', () {
      final document = const WeftNormalizer().normalize(
        '<hr id="plain">'
        '<hr id="fancy" style="width: 50%; margin: 0 auto">',
        id: 'hr-widths',
      );
      final layout = const WeftLayoutEngine().layout(document, width: 400);
      addTearDown(layout.dispose);

      final plain = _boxFor(layout, document, 'plain');
      expect(plain.rect.width, 400);
      expect(plain.rect.height, 1);

      final fancy = _boxFor(layout, document, 'fancy');
      expect(fancy.rect.width, 200);
      expect(fancy.rect.left, 100);
      expect(fancy.rect.height, 1);
    });
  });

  group('floats and explicit heights', () {
    test('a float does not stretch a fixed-height block beside it', () {
      final document = const WeftNormalizer().normalize(
        '<img id="pic" src="asset:pic.png" '
        'style="float: left; width: 100px" height="50">'
        '<div id="h" style="height: 40px">Text beside the float</div>',
        id: 'float-height',
      );
      final layout = const WeftLayoutEngine().layout(
        document,
        width: 400,
        images: {_findById(document.body!, 'pic').id: picture},
      );
      addTearDown(layout.dispose);

      // The block box stays full width with its explicit height; only the
      // text lines dodge the float.
      final box = _boxFor(layout, document, 'h');
      expect(box.rect, const Rect.fromLTWH(0, 0, 400, 40));
      expect(_textCommands(layout).last.offset.dx, 100);
      // The floated image still extends the document extent below the block.
      expect(layout.size.height, 50);
    });
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

List<WeftTextPaintCommand> _textCommands(WeftLayoutResult layout) {
  return layout.commands
      .whereType<WeftTextPaintCommand>()
      .where(
          (command) => (command.painter.text?.toPlainText() ?? '').isNotEmpty)
      .toList();
}

WeftLayoutBox _boxFor(
  WeftLayoutResult layout,
  WeftDocumentSnapshot document,
  String id,
) {
  final node = _findById(document.body!, id);
  return layout.boxes.singleWhere((box) => box.nodeId == node.id);
}

WeftElement _findById(WeftNode node, String id) {
  if (node is WeftElement) {
    if (node.idAttribute == id) return node;
    for (final child in node.children) {
      final match = _findByIdOrNull(child, id);
      if (match != null) return match;
    }
  }
  throw StateError('Element with id "$id" was not found.');
}

WeftElement? _findByIdOrNull(WeftNode node, String id) {
  if (node is! WeftElement) return null;
  if (node.idAttribute == id) return node;
  for (final child in node.children) {
    final match = _findByIdOrNull(child, id);
    if (match != null) return match;
  }
  return null;
}
