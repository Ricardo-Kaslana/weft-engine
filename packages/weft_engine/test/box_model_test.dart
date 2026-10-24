import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content-box width includes padding and borders', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="width: 200px; padding: 10px; '
      'border: 2px solid #ff0000; box-sizing: content-box">'
      '<p style="margin: 0">Text</p></div>',
      id: 'content-box',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 500);
    addTearDown(layout.dispose);

    final boxNode = _findById(document.body!, 'box');
    final box = layout.boxes.singleWhere((item) => item.nodeId == boxNode.id);
    expect(box.rect.width, 224);
    expect(box.rect.left, 0);

    final borders = layout.commands
        .whereType<WeftRectPaintCommand>()
        .where((command) => command.color == const Color(0xFFFF0000))
        .toList();
    expect(borders, hasLength(4));
    expect(borders.first.rect.width, 224);
    expect(borders.first.rect.height, 2);

    final text = layout.commands.whereType<WeftTextPaintCommand>().singleWhere(
        (command) => command.painter.text?.toPlainText() == 'Text');
    expect(text.offset.dx, 12);
  });

  test('border-box width is the final outer box width', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="width: 200px; padding: 10px; '
      'border: 2px solid #000000; box-sizing: border-box">Text</div>',
      id: 'border-box',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 500);
    addTearDown(layout.dispose);

    final boxNode = _findById(document.body!, 'box');
    final box = layout.boxes.singleWhere((item) => item.nodeId == boxNode.id);
    expect(box.rect.width, 200);

    final text = layout.commands.whereType<WeftTextPaintCommand>().singleWhere(
        (command) => command.painter.text?.toPlainText() == 'Text');
    expect(text.offset.dx, 12);
  });

  test('min and max width constrain explicit widths', () {
    final document = const WeftNormalizer().normalize(
      '<div id="max" style="width: 400px; max-width: 180px">A</div>'
      '<div id="min" style="width: 100px; min-width: 220px">B</div>',
      id: 'limits',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 500);
    addTearDown(layout.dispose);

    final maxBox = layout.boxes.singleWhere(
      (item) => item.nodeId == _findById(document.body!, 'max').id,
    );
    final minBox = layout.boxes.singleWhere(
      (item) => item.nodeId == _findById(document.body!, 'min').id,
    );
    expect(maxBox.rect.width, 180);
    expect(minBox.rect.width, 220);
  });

  test('border shorthand is expanded before per-side overrides', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="width: 200px; border: 2px solid green; '
      'border-top: 4px solid red">Text</div>',
      id: 'border-cascade',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 500);
    addTearDown(layout.dispose);

    final commands = layout.commands.whereType<WeftRectPaintCommand>().toList();
    final red = commands.where(
      (command) => command.color == const Color(0xFFFF0000),
    );
    final green = commands.where(
      (command) => command.color == const Color(0xFF008000),
    );

    expect(red, hasLength(1));
    expect(red.single.rect.height, 4);
    expect(green, hasLength(3));
    expect(green.every((command) => command.rect.height >= 2), isTrue);
  });

  test('unsupported border styles do not paint a border', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="border: 2px dashed red">Text</div>',
      id: 'dashed-border',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final redCommands = layout.commands
        .whereType<WeftRectPaintCommand>()
        .where((command) => command.color == const Color(0xFFFF0000));
    expect(redCommands, isEmpty);
  });
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
