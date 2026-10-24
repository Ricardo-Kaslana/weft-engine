import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('first child top margin collapses outside the parent box', () {
    final document = const WeftNormalizer().normalize(
      '<p style="margin: 20px 0 0 0">First</p>'
      '<p style="margin: 0">Second</p>',
      id: 'leading-collapse',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final body = layout.boxes.singleWhere(
      (box) => box.nodeId == document.body!.id,
    );
    expect(body.rect.top, 20);
    expect(body.rect.height, 48);
    expect(layout.size.height, 68);

    final paragraphs = _textCommands(layout);
    expect(paragraphs.first.offset.dy, 20);
    expect(paragraphs.last.offset.dy, 44);
  });

  test('top padding prevents parent-child margin collapsing', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="padding-top: 10px">'
      '<p style="margin-top: 20px">Inside</p></div>',
      id: 'padding-blocks-collapse',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final box = _boxFor(layout, document, 'box');
    expect(box.rect.top, 0);
    expect(box.rect.height, 54);
    expect(_textCommands(layout).single.offset.dy, 30);
    // The paragraph's trailing 16px margin escapes the box and the body, so it
    // extends the document extent without enlarging either border box.
    expect(layout.size.height, 54 + 16);
  });

  test('last child bottom margin collapses out of the parent box', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box"><p style="margin: 0 0 30px 0">Inside</p></div>'
      '<p id="after" style="margin: 0">After</p>',
      id: 'trailing-collapse',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final box = _boxFor(layout, document, 'box');
    expect(box.rect.height, 24);

    final after = _boxFor(layout, document, 'after');
    expect(after.rect.top, 54);
    expect(layout.size.height, 78);
  });

  test('a parent with bottom padding keeps the child margin inside', () {
    final document = const WeftNormalizer().normalize(
      '<div id="box" style="padding-bottom: 5px">'
      '<p style="margin: 0 0 30px 0">Inside</p></div>',
      id: 'padding-keeps-margin',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final box = _boxFor(layout, document, 'box');
    expect(box.rect.height, 24 + 30 + 5);
  });

  test('negative margins collapse as max positive plus min negative', () {
    final document = const WeftNormalizer().normalize(
      '<p style="margin: 0 0 30px 0">First</p>'
      '<p style="margin: -10px 0 0 0">Second</p>',
      id: 'negative-margin',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final paragraphs = _textCommands(layout);
    expect(
      paragraphs.last.offset.dy - paragraphs.first.offset.dy,
      closeTo(24 + 20, 0.01),
    );
    expect(layout.size.height, 24 + 20 + 24);
  });

  test('empty blocks collapse their own margins and add no height', () {
    final document = const WeftNormalizer().normalize(
      '<p style="margin: 0 0 20px 0">First</p>'
      '<div style="margin: 10px 0"></div>'
      '<p style="margin: 0">Second</p>',
      id: 'empty-block',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final paragraphs = _textCommands(layout);
    expect(paragraphs, hasLength(2));
    expect(
      paragraphs.last.offset.dy - paragraphs.first.offset.dy,
      closeTo(24 + 20, 0.01),
    );
    expect(layout.size.height, 24 + 20 + 24);
  });

  test('inline content between blocks prevents margin collapsing', () {
    final document = const WeftNormalizer().normalize(
      '<div><p style="margin: 0 0 20px 0">First</p>'
      'separator'
      '<p style="margin: 10px 0 0 0">Second</p></div>',
      id: 'inline-breaks-collapse',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    final paragraphs = _textCommands(layout);
    expect(
      paragraphs.last.offset.dy - paragraphs.first.offset.dy,
      closeTo(24 + 20 + 24 + 10, 0.01),
    );
  });

  test('nested wrappers propagate the first block margin to the body', () {
    final document = const WeftNormalizer().normalize(
      '<div><div><p style="margin: 25px 0 0 0">Nested</p></div></div>',
      id: 'nested-collapse',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 300);
    addTearDown(layout.dispose);

    expect(_textCommands(layout).single.offset.dy, 25);
    expect(layout.size.height, 25 + 24);
  });
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
