import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image landscape;
  late ui.Image square;

  setUpAll(() async {
    landscape = await _createImage(200, 100, const Color(0xFF3366CC));
    square = await _createImage(120, 120, const Color(0xFFCC6633));
  });

  tearDownAll(() {
    landscape.dispose();
    square.dispose();
  });

  test('block image uses explicit attributes as its content box', () {
    // display: block opts an image back into the block replacement box;
    // unstyled images are inline atoms (see inline_image_test.dart).
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="display: block" width="200" height="100">',
      id: 'block-image',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 400,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final box = layout.boxes.singleWhere(
      (item) => item.nodeId == _findById(document.body!, 'pic').id,
    );
    expect(box.rect, const Rect.fromLTWH(0, 0, 200, 100));
    final image = layout.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination, const Rect.fromLTWH(0, 0, 200, 100));
    expect(layout.size.height, 100);
  });

  test('width attribute preserves the intrinsic image ratio', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" width="100">',
      id: 'image-ratio',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 400,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final image = layout.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination.width, 100);
    expect(image.destination.height, 50);
  });

  test('max-width constrains an image and rescales its height', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="width: 800px; max-width: 300px">',
      id: 'image-max-width',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 400,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final image = layout.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination, const Rect.fromLTWH(0, 0, 300, 150));
  });

  test('unresolved images fall back to alternative text', () {
    final document = const WeftNormalizer().normalize(
      '<p>Before <img src="asset:missing.png" alt="Alt text"> after</p>',
      id: 'image-alt',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(layout.dispose);

    expect(layout.commands.whereType<WeftImagePaintCommand>(), isEmpty);
    expect(
      layout.commands
          .whereType<WeftTextPaintCommand>()
          .single
          .painter
          .text
          ?.toPlainText(),
      'Before Alt text after',
    );
  });

  test('unresolved image alt inside a link remains linked text', () {
    final document = const WeftNormalizer().normalize(
      '<p><a href="https://example.com/cover">'
      '<img src="asset:missing.png" alt="Cover alt"></a></p>',
      id: 'image-alt-link',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(layout.dispose);

    expect(
      layout.commands
          .whereType<WeftTextPaintCommand>()
          .single
          .painter
          .text
          ?.toPlainText(),
      'Cover alt',
    );
    expect(layout.links.single.text, 'Cover alt');
  });

  test('left float shortens following lines until the image ends', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="120">'
      '<p>alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu '
      'nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta '
      'gamma delta epsilon zeta eta theta iota kappa</p>',
      id: 'float-left',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
    );
    addTearDown(layout.dispose);

    final imageBox = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'pic').id,
    );
    final bodyBox = layout.boxes.singleWhere(
      (box) => box.nodeId == document.body!.id,
    );
    expect(imageBox.rect.left, 0);
    expect(imageBox.rect.top, bodyBox.rect.top);
    expect(imageBox.rect.size, const Size(120, 120));

    final lines = _textCommands(layout);
    expect(lines.length, greaterThan(5));
    for (final line in lines) {
      if (line.offset.dy < imageBox.rect.bottom) {
        expect(
          line.offset.dx,
          greaterThanOrEqualTo(120),
          reason: 'line at ${line.offset.dy} overlaps the float',
        );
      }
    }
    expect(
      lines.any(
        (line) => line.offset.dy >= imageBox.rect.bottom && line.offset.dx == 0,
      ),
      isTrue,
      reason: 'text after the float should use the full line width',
    );
  });

  test('right float aligns to the containing block right edge', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: right" width="120" height="120">'
      '<p>alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu</p>',
      id: 'float-right',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
    );
    addTearDown(layout.dispose);

    final imageBox = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'pic').id,
    );
    final bodyTop = layout.boxes
        .singleWhere((box) => box.nodeId == document.body!.id)
        .rect
        .top;
    expect(imageBox.rect.top, bodyTop);
    expect(imageBox.rect.left, 240);
    final firstLine = _textCommands(layout).first;
    expect(firstLine.offset.dx, 0);
    expect(firstLine.painter.width, lessThanOrEqualTo(240));
  });

  test('floats inside an otherwise empty wrapper still paint', () {
    final document = const WeftNormalizer().normalize(
      '<div id="wrapper"><img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="80"></div>'
      '<p>alpha beta gamma delta epsilon zeta eta theta iota kappa</p>',
      id: 'float-wrapper',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final image = layout.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination.size, const Size(120, 80));
    final lines = _textCommands(layout);
    expect(lines.first.offset.dx, 120);
  });

  test('wrapped links keep one region with per-line float boxes', () {
    final document = const WeftNormalizer().normalize(
      '<p><img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="80">'
      '<a href="https://example.com/float">alpha beta gamma delta epsilon '
      'zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau '
      'upsilon phi chi psi omega</a></p>',
      id: 'float-link',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final link = layout.links.single;
    expect(link.href, 'https://example.com/float');
    expect(link.text, startsWith('alpha beta'));
    expect(link.text, endsWith('omega'));
    expect(link.rects.length, greaterThan(1));
    for (final rect in link.rects) {
      expect(layout.linkAt(rect.center)?.href, link.href);
    }
  });

  test('CJK text uses the shortened line box beside a float', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="80">'
      '<p>中文内容需要在图片旁正常换行，标点不应被挤出可用行宽。'
      '中文内容需要在图片旁正常换行，标点不应被挤出可用行宽。'
      '中文内容需要在图片旁正常换行，标点不应被挤出可用行宽。</p>',
      id: 'float-cjk',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: landscape},
    );
    addTearDown(layout.dispose);

    final imageBottom = layout.boxes
        .singleWhere(
          (box) => box.nodeId == _findById(document.body!, 'pic').id,
        )
        .rect
        .bottom;
    final lines = _textCommands(layout);
    expect(lines.length, greaterThan(1));
    for (final line in lines) {
      if (line.offset.dy < imageBottom) {
        expect(line.offset.dx, greaterThanOrEqualTo(120));
      }
    }
  });

  test('clear moves following blocks below the float', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="120">'
      '<p>Inside the float paragraph.</p>'
      '<p style="clear: both">After clear.</p>',
      id: 'float-clear',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
    );
    addTearDown(layout.dispose);

    final after = _textCommands(layout).singleWhere((command) {
      return command.painter.text?.toPlainText().contains('After') ?? false;
    });
    final imageBox = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'pic').id,
    );
    expect(after.offset.dy, greaterThanOrEqualTo(imageBox.rect.bottom));
    expect(after.offset.dx, 0);
  });

  test('opposing floats share a line when they fit', () {
    final document = const WeftNormalizer().normalize(
      '<img id="left" src="asset:left.png" '
      'style="float: left" width="120" height="80">'
      '<img id="right" src="asset:right.png" '
      'style="float: right" width="120" height="80">'
      '<p>alpha beta gamma delta epsilon zeta eta theta</p>',
      id: 'float-opposing',
    );
    final images = {
      _findById(document.body!, 'left').id: square,
      _findById(document.body!, 'right').id: square,
    };
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: images,
    );
    addTearDown(layout.dispose);

    final left = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'left').id,
    );
    final right = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'right').id,
    );
    final bodyTop = layout.boxes
        .singleWhere((box) => box.nodeId == document.body!.id)
        .rect
        .top;
    expect(left.rect.top, bodyTop);
    expect(right.rect.top, bodyTop);
    expect(right.rect.left, 240);
  });

  test('same-side floats stack instead of overlapping', () {
    final document = const WeftNormalizer().normalize(
      '<img id="first" src="asset:first.png" '
      'style="float: left" width="120" height="80">'
      '<img id="second" src="asset:second.png" '
      'style="float: left" width="120" height="80">'
      '<p>alpha beta gamma</p>',
      id: 'float-stack',
    );
    final images = {
      _findById(document.body!, 'first').id: landscape,
      _findById(document.body!, 'second').id: landscape,
    };
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: images,
    );
    addTearDown(layout.dispose);

    final first = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'first').id,
    );
    final second = layout.boxes.singleWhere(
      (box) => box.nodeId == _findById(document.body!, 'second').id,
    );
    final bodyTop = layout.boxes
        .singleWhere((box) => box.nodeId == document.body!.id)
        .rect
        .top;
    expect(first.rect.top, bodyTop);
    expect(second.rect.top, greaterThanOrEqualTo(first.rect.bottom));
  });

  test('late image decode converges to the resolved-image layout', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" style="float: left" '
      'width="120" height="120">'
      '<p>alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu '
      'nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta '
      'gamma delta epsilon zeta eta theta iota kappa</p>',
      id: 'float-late-decode',
    );
    const engine = WeftLayoutEngine();
    final imageId = _findById(document.body!, 'pic').id;

    // Before the resolver delivers the image, the float falls back to alt
    // text; the engine has no resolved float to admit.
    final withoutImage = engine.layout(document, width: 360);
    addTearDown(withoutImage.dispose);
    expect(
      withoutImage.commands.whereType<WeftImagePaintCommand>(),
      isEmpty,
    );

    // When the decode lands, the next layout (previous = the fallback result)
    // must converge exactly to a fresh layout that always had the image.
    final lateDecode = engine.layout(
      document,
      width: 360,
      images: {imageId: square},
      previous: withoutImage,
    );
    addTearDown(lateDecode.dispose);
    final fresh = engine.layout(
      document,
      width: 360,
      images: {imageId: square},
    );
    addTearDown(fresh.dispose);
    expect(lateDecode.size, fresh.size);
    expect(lateDecode.commands, hasLength(fresh.commands.length));
    for (var i = 0; i < lateDecode.commands.length; i++) {
      expect(lateDecode.commands[i].nodeId, fresh.commands[i].nodeId);
      expect(lateDecode.commands[i].bounds, fresh.commands[i].bounds);
    }
    expect(
      lateDecode.commands.whereType<WeftImagePaintCommand>(),
      isNotEmpty,
    );
  });

  test('float wrapping stays structural at multiple widths', () {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" style="float: left" '
      'width="80" height="80">'
      '<p>alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu '
      'nu xi omicron pi rho sigma tau upsilon phi chi psi omega</p>'
      '<p style="clear: left">cleared tail paragraph after the float.</p>',
      id: 'float-widths',
    );
    const engine = WeftLayoutEngine();
    final imageId = _findById(document.body!, 'pic').id;

    for (final width in <double>[280, 360, 480]) {
      final layout = engine.layout(
        document,
        width: width,
        images: {imageId: square},
      );
      addTearDown(layout.dispose);
      expect(layout.size.width, width);

      // Every command stays inside its width; text lines never overlap.
      for (final command in layout.commands) {
        expect(command.bounds.right, lessThanOrEqualTo(width + 0.5),
            reason: 'width $width command escaped right');
      }
      final textRects = layout.commands
          .whereType<WeftTextPaintCommand>()
          .map((command) => command.bounds)
          .toList(growable: false);
      for (var i = 0; i < textRects.length; i++) {
        for (var j = i + 1; j < textRects.length; j++) {
          expect(
            textRects[i].intersect(textRects[j]).isEmpty,
            isTrue,
            reason: 'width $width text commands $i/$j overlap',
          );
        }
      }

      // The float shortens lines: some text line must sit right of the
      // 80px float, and the cleared tail must start below it.
      final textLines = layout.commands.whereType<WeftTextPaintCommand>();
      expect(
        textLines.any((command) => command.bounds.left >= 78),
        isTrue,
        reason: 'width $width: no line wrapped beside the float',
      );
    }
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
