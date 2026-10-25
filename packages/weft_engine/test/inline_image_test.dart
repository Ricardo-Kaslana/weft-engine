import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image landscape;
  late ui.Image tall;
  late ui.Image square;

  setUpAll(() async {
    landscape = await _createImage(200, 100, const Color(0xFF3366CC));
    tall = await _createImage(60, 120, const Color(0xFFCC6633));
    square = await _createImage(40, 40, const Color(0xFF228822));
  });

  tearDownAll(() {
    landscape.dispose();
    tall.dispose();
    square.dispose();
  });

  group('inline image geometry', () {
    test('inline image paints as an atom on the text baseline', () {
      final result = _layout(
        '<p>before <img id="pic" src="asset:pic.png" '
        'style="display: inline" width="60" height="20"> after</p>',
        namedImages: {'pic': landscape},
      );

      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(60, 20));

      // The atom bottom sits on the first line's alphabetic baseline.
      final text = result.commands.whereType<WeftTextPaintCommand>().single;
      final baseline = text.painter.computeLineMetrics().first.baseline;
      expect(image.destination.bottom, closeTo(baseline + text.offset.dy, 0.5));
    });

    test('atom takes part in line breaking and wraps as a unit', () {
      final result = _layout(
        '<p style="width: 120px">alpha '
        '<img id="pic" src="asset:pic.png" '
        'style="display: inline" width="90" height="20">'
        ' beta</p>',
        namedImages: {'pic': landscape},
      );

      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      final text = result.commands.whereType<WeftTextPaintCommand>().single;
      final metrics = text.painter.computeLineMetrics();
      // The atom does not fit after "alpha" (line 2), and "beta" does not fit
      // beside it either (line 3).
      expect(metrics.length, 3);
      expect(
        image.destination.top,
        closeTo(metrics[1].baseline - 20 + text.offset.dy, 0.5),
      );
      expect(
        image.destination.top,
        greaterThan(metrics[0].baseline - metrics[0].ascent + text.offset.dy),
      );
    });

    test('a tall atom grows the line box', () {
      final withAtom = _layout(
        '<p><img id="tall" src="asset:tall.png" '
        'style="display: inline" width="60" height="120"></p>',
        namedImages: {'tall': tall},
      );
      final textOnly = _layout('<p>text</p>');

      final image = withAtom.commands.whereType<WeftImagePaintCommand>().single;
      expect(withAtom.size.height, greaterThan(120));
      expect(
        withAtom.size.height,
        greaterThan(textOnly.size.height + 100),
      );
      expect(image.destination.height, 120);
    });

    test('vertical-align middle centers the atom box on the line', () {
      final baseline = _layout(
        '<p>Ag <img id="mid" src="asset:pic.png" '
        'style="display: inline" width="40" height="20"></p>',
        namedImages: {'mid': landscape},
      );
      final middle = _layout(
        '<p>Ag <img id="mid" src="asset:pic.png" '
        'style="display: inline; vertical-align: middle" '
        'width="40" height="20"></p>',
        namedImages: {'mid': landscape},
      );

      final baselineImage =
          baseline.commands.whereType<WeftImagePaintCommand>().single;
      final middleImage =
          middle.commands.whereType<WeftImagePaintCommand>().single;
      // Baseline alignment puts the box bottom on the alphabetic baseline;
      // middle alignment raises the bottom and lowers the top so the box
      // straddles the baseline.
      expect(middleImage.destination.top,
          greaterThan(baselineImage.destination.top));
      expect(middleImage.destination.bottom,
          greaterThan(baselineImage.destination.bottom));

      final text = middle.commands.whereType<WeftTextPaintCommand>().single;
      final baselineY =
          text.painter.computeLineMetrics().first.baseline + text.offset.dy;
      expect(middleImage.destination.top, lessThan(baselineY));
      expect(middleImage.destination.bottom, greaterThan(baselineY));
    });

    test('placeholder does not scale with textScaler', () {
      final scaled = _layout(
        '<p>before <img id="pic" src="asset:pic.png" '
        'style="display: inline" width="60" height="20"> after</p>',
        namedImages: {'pic': landscape},
        textScaler: const TextScaler.linear(2),
      );

      final image = scaled.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(60, 20));
      final text = scaled.commands.whereType<WeftTextPaintCommand>().single;
      final baseline = text.painter.computeLineMetrics().first.baseline;
      expect(image.destination.bottom, closeTo(baseline + text.offset.dy, 0.5));
    });
  });

  group('inline image beside floats', () {
    test('float-shortened lines wrap the atom and kinsoku still holds', () {
      final document = const WeftNormalizer().normalize(
        '<img id="float" src="asset:tall.png" '
        'style="float: left" width="120" height="240">'
        '<p><img id="atom" src="asset:pic.png" '
        'style="display: inline" width="60" height="20">'
        '一整段中文内容，标点。不应出现在行首。逗号，也不应出现在行首。'
        '重复一遍内容让换行足够多。一整段中文内容，标点。不应出现在行首。</p>',
        id: 'inline-float-kinsoku',
      );
      final result = const WeftLayoutEngine().layout(
        document,
        width: 400,
        images: {
          _nodeId(document, 'float'): tall,
          _nodeId(document, 'atom'): landscape,
        },
      );
      addTearDown(result.dispose);

      final floatBottom = result.boxes
          .singleWhere((box) => box.nodeId == _nodeId(document, 'float'))
          .rect
          .bottom;
      final lines = _textLines(result);
      expect(lines.length, greaterThan(2));
      for (final line in lines) {
        final plain = line.painter.text?.toPlainText() ?? '';
        if (plain.isEmpty) continue;
        expect(
          _lineStartProhibited(plain),
          isFalse,
          reason: 'line starts with prohibited punctuation: $plain',
        );
      }
      // The atom wraps beside the float, never overlapping the exclusion.
      final atom = result.commands
          .whereType<WeftImagePaintCommand>()
          .singleWhere(
              (command) => command.nodeId == _nodeId(document, 'atom'));
      expect(atom.destination.width, 60);
      if (atom.destination.top < floatBottom) {
        expect(atom.destination.left, greaterThanOrEqualTo(120));
      }
    });
  });

  group('inline image sizing', () {
    test('width and height attributes size the atom', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" '
        'style="display: inline" width="80" height="40"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(80, 40));
    });

    test('CSS px width keeps the intrinsic ratio', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" '
        'style="display: inline; width: 100px"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(100, 50));
    });

    test('CSS percentage width resolves against the containing block', () {
      final result = _layout(
        '<div style="padding: 10px">'
        '<img id="pic" src="asset:pic.png" '
        'style="display: inline; width: 50%">'
        '</div>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      // Content width is 400 - 20; 50% of it is 190, and the height follows
      // the intrinsic ratio.
      expect(image.destination.size, const Size(190, 95));
    });

    test('CSS px height derives the width from the ratio', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" '
        'style="display: inline; height: 40px"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(80, 40));
    });

    test('percentage height resolves as auto', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" '
        'style="display: inline; height: 50%"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(200, 100));
    });

    test('max-width clamps and rescales through the ratio', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" '
        'style="display: inline; width: 800px; max-width: 100px"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(image.destination.size, const Size(100, 50));
    });

    test('border-box sizing reserves padding without stretching the image', () {
      final result = _layout(
        '<p><img id="pic" src="asset:pic.png" style="display: inline; '
        'box-sizing: border-box; width: 120px; height: 60px; '
        'padding: 10px"></p>',
        namedImages: {'pic': landscape},
      );
      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      // The image content keeps the 120x60 attribute box inset by padding;
      // the reserved line box stays 120x60.
      expect(image.destination.size, const Size(100, 40));
      expect(image.destination.left, greaterThanOrEqualTo(10));
    });
  });

  group('inline image selection and links', () {
    test('unresolved inline image keeps its alt text path', () {
      final result = _layout(
        '<p>Before <img src="asset:missing.png" alt="Alt text" '
        'style="display: inline"> after</p>',
      );
      expect(result.commands.whereType<WeftImagePaintCommand>(), isEmpty);
      expect(
        _textLines(result).single.painter.text?.toPlainText(),
        'Before Alt text after',
      );
    });

    test('link ranges break at the atom but keep hit rects for the text', () {
      final result = _layout(
        '<p><a href="https://example.com/pic">before '
        '<img id="pic" src="asset:pic.png" '
        'style="display: inline" width="60" height="20">'
        ' after</a></p>',
        namedImages: {'pic': landscape},
      );

      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      expect(result.links.map((link) => link.href),
          everyElement('https://example.com/pic'));
      expect(result.links, hasLength(2));
      for (final link in result.links) {
        expect(link.text.contains('\uFFFC'), isFalse);
        for (final rect in link.rects) {
          // Link rects cover text runs only, never the atom box.
          expect(
            rect.left >= image.destination.right ||
                rect.right <= image.destination.left,
            isTrue,
          );
          expect(result.linkAt(rect.center), isNotNull);
        }
      }
    });

    test('selection copy text skips the atom', () {
      final document = const WeftNormalizer().normalize(
        '<p>before <img id="pic" src="asset:pic.png" '
        'style="display: inline" width="60" height="20"> after</p>',
        id: 'inline-selection',
      );
      final result = const WeftLayoutEngine().layout(
        document,
        width: 400,
        images: {_nodeId(document, 'pic'): landscape},
      );
      addTearDown(result.dispose);

      final index = result.textIndex!;
      expect(index.text.contains('\uFFFC'), isFalse);
      expect(index.text, 'before  after');

      final selection = TextSelectionRange(
        anchor: TextAnchor(index.entries[0].nodeId, 0),
        extent: TextAnchor(
          index.entries[1].nodeId,
          index.entries[1].text.length,
        ),
      );
      final copy = result.selectionText(selection)!;
      expect(copy.contains('\uFFFC'), isFalse);
      expect(copy, 'before  after');
    });

    test('anchoring on the atom never resolves to the image node', () {
      final document = const WeftNormalizer().normalize(
        '<p>before <img id="pic" src="asset:pic.png" '
        'style="display: inline" width="120" height="60"> after</p>',
        id: 'inline-anchor',
      );
      final result = const WeftLayoutEngine().layout(
        document,
        width: 400,
        images: {_nodeId(document, 'pic'): landscape},
      );
      addTearDown(result.dispose);

      final image = result.commands.whereType<WeftImagePaintCommand>().single;
      final point = image.destination.center;
      final anchor = result.anchorAt(point);
      if (anchor != null) {
        // The point may fall back onto a neighbouring text seam, but it must
        // never anchor inside the replaced element.
        expect(
          anchor.nodeId,
          isNot(_nodeId(document, 'pic')),
        );
      }
      final word = result.wordSelectionAt(point);
      if (word != null) {
        final copy = result.selectionText(word) ?? '';
        expect(copy.contains('\uFFFC'), isFalse);
      }
    });
  });

  test('unstyled images join the line and display: block opts back out', () {
    final document = const WeftNormalizer().normalize(
      '<p>text</p>'
      '<img id="pic" src="asset:pic.png" width="60" height="20">',
      id: 'block-default',
    );
    final result = const WeftLayoutEngine().layout(
      document,
      width: 400,
      images: {_nodeId(document, 'pic'): landscape},
    );
    addTearDown(result.dispose);

    // The UA stylesheet renders replaced content inline, so the unstyled
    // image becomes an atom in an anonymous line box below the paragraph.
    // The atom still registers its border box as the element's layout box,
    // matching what getBoundingClientRect reports for inline replaced
    // content. An image taller than the strut ascent paints at the same top
    // edge a block box would.
    expect(
      result.boxes.where((box) => box.nodeId == _nodeId(document, 'pic')),
      hasLength(1),
    );
    final image = result.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination, const Rect.fromLTWH(0, 56, 60, 20));

    final blockDocument = const WeftNormalizer().normalize(
      '<p>text</p>'
      '<img id="block" src="asset:pic.png" '
      'style="display: block" width="60" height="20">',
      id: 'block-opt-out',
    );
    final blockResult = const WeftLayoutEngine().layout(
      blockDocument,
      width: 400,
      images: {_nodeId(blockDocument, 'block'): landscape},
    );
    addTearDown(blockResult.dispose);

    expect(
      blockResult.boxes
          .where((box) => box.nodeId == _nodeId(blockDocument, 'block')),
      hasLength(1),
    );
    final blockImage =
        blockResult.commands.whereType<WeftImagePaintCommand>().single;
    expect(blockImage.destination, const Rect.fromLTWH(0, 56, 60, 20));
  });
}

WeftLayoutResult _layout(
  String html, {
  Map<String, ui.Image> namedImages = const {},
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final document = const WeftNormalizer().normalize(html, id: 'inline-image');
  final images = <int, ui.Image>{
    for (final entry in namedImages.entries)
      _nodeId(document, entry.key): entry.value,
  };
  final result = const WeftLayoutEngine().layout(
    document,
    width: 400,
    textScaler: textScaler,
    images: images,
  );
  addTearDown(result.dispose);
  return result;
}

int _nodeId(WeftDocumentSnapshot document, String id) {
  final body = document.body!;
  WeftElement? find(WeftNode node) {
    if (node is! WeftElement) return null;
    if (node.idAttribute == id) return node;
    for (final child in node.children) {
      final match = find(child);
      if (match != null) return match;
    }
    return null;
  }

  final element = find(body);
  if (element == null) {
    throw StateError('Element with id "$id" was not found.');
  }
  return element.id;
}

List<WeftTextPaintCommand> _textLines(WeftLayoutResult result) {
  return result.commands
      .whereType<WeftTextPaintCommand>()
      .where(
        (command) => (command.painter.text?.toPlainText() ?? '').isNotEmpty,
      )
      .toList();
}

bool _lineStartProhibited(String text) {
  const prohibited = <int>{
    0x3002,
    0x3001,
    0xFF0C,
    0xFF0E,
    0xFF1A,
    0xFF1B,
    0xFF1F,
    0xFF01,
    0xFF09,
    0x3009,
    0x300B,
    0x300D,
    0x300F,
    0x3011,
    0x3015,
    0x2026,
    0x2014,
    0x30FB,
    0x309B,
    0x309C,
    0x005D,
  };
  for (final code in text.codeUnits) {
    if (code == 0x20 || code == 0x09) continue;
    return prohibited.contains(code);
  }
  return false;
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
