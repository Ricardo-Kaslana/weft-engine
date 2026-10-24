import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lays out headings and paragraphs into paint commands', () {
    final document = const WeftNormalizer().normalize(
      '<h1>Heading</h1><p>Plain <strong>bold</strong> text.</p>',
      id: 'basic',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(layout.dispose);

    expect(layout.size.width, 360);
    expect(layout.size.height, greaterThan(48));
    expect(layout.boxes, isNotEmpty);
    final textCommands =
        layout.commands.whereType<WeftTextPaintCommand>().toList();
    expect(textCommands, isNotEmpty);
    expect(textCommands.first.painter.text?.toPlainText(), 'Heading');
    expect(
      _firstSpan(textCommands.first).style?.fontSize,
      greaterThan(20),
    );
    expect(
      layout.commands.map((command) => command.nodeId).toSet().length,
      greaterThan(1),
    );
  });

  test('cascades class rules and preserves inline link styling', () {
    final document = const WeftNormalizer().normalize('''
      <style>
        p { color: rgb(17, 34, 51); font-size: 20px; }
        .accent { font-weight: 700; }
      </style>
      <p class="accent">Hello <a href="https://example.com">link</a></p>
    ''', id: 'cascade');
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final paragraph = layout.commands
        .whereType<WeftTextPaintCommand>()
        .singleWhere((command) {
      return command.painter.text?.toPlainText().startsWith('Hello') ?? false;
    });
    final span = paragraph.painter.text! as TextSpan;
    final spans = span.children!.whereType<TextSpan>().toList();

    expect(spans.first.style?.color, const Color(0xFF112233));
    expect(spans.first.style?.fontSize, 20);
    expect(spans.first.style?.fontWeight, FontWeight.w700);
    expect(spans.first.style?.decoration, isNot(TextDecoration.underline));
    expect(spans.last.style?.color, const Color(0xFF0969DA));
    expect(spans.last.style?.decoration, TextDecoration.underline);
  });

  test('collapses HTML whitespace without joining words', () {
    final document = const WeftNormalizer().normalize(
      '<p>  Hello\n  <strong> bold </strong>   world  </p>',
      id: 'whitespace',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final textCommands =
        layout.commands.whereType<WeftTextPaintCommand>().toList();
    expect(textCommands.single.painter.text?.toPlainText(), 'Hello bold world');
  });

  test('supports forced line breaks and preformatted content', () {
    final document = const WeftNormalizer().normalize(
      '<p>one<br>two</p><pre>alpha\n  beta</pre>',
      id: 'breaks',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final texts = layout.commands
        .whereType<WeftTextPaintCommand>()
        .map((command) => command.painter.text?.toPlainText())
        .toList();
    expect(texts, contains('one\ntwo'));
    expect(texts, contains('alpha\n  beta'));
  });

  test('paints list markers separately from selectable text', () {
    final document = const WeftNormalizer().normalize(
      '<ol><li>First</li><li>Second</li></ol>',
      id: 'list',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final texts = layout.commands
        .whereType<WeftTextPaintCommand>()
        .map((command) => command.painter.text?.toPlainText())
        .toList();
    expect(texts, containsAll(<String>['1.', 'First', '2.', 'Second']));
  });

  test('collapses adjacent block margins instead of summing them', () {
    final document = const WeftNormalizer().normalize(
      '<p style="margin: 0 0 30px 0">First</p>'
      '<p style="margin: 10px 0 0 0">Second</p>',
      id: 'margins',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final commands = layout.commands
        .whereType<WeftTextPaintCommand>()
        .where((command) => command.painter.text?.toPlainText() != '')
        .toList();
    final first = commands[0];
    final second = commands[1];
    expect(
      second.offset.dy - first.offset.dy,
      closeTo(first.painter.height + 30, 0.01),
    );
  });

  test('hidden content does not produce boxes or paint commands', () {
    final document = const WeftNormalizer().normalize(
      '<p style="display: none">Hidden</p><p>Visible</p>',
      id: 'display-none',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 240);
    addTearDown(layout.dispose);

    final texts = layout.commands
        .whereType<WeftTextPaintCommand>()
        .map((command) => command.painter.text?.toPlainText())
        .toList();
    expect(texts, isNot(contains('Hidden')));
    expect(texts, contains('Visible'));
  });
}

TextSpan _firstSpan(WeftTextPaintCommand command) {
  final root = command.painter.text! as TextSpan;
  return root.children!.whereType<TextSpan>().first;
}
