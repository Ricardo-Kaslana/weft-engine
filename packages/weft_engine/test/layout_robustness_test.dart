import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('specificity and inline styles override lower-priority rules', () {
    final document = const WeftNormalizer().normalize('''
      <style>
        p { color: red; }
        .note { color: green; }
        #target { color: blue; font-size: 22px; }
      </style>
      <p id="target" class="note" style="font-size: 24px">Text</p>
    ''', id: 'specificity');
    final layout = const WeftLayoutEngine().layout(document, width: 320);
    addTearDown(layout.dispose);

    final command = layout.commands.whereType<WeftTextPaintCommand>().single;
    final root = command.painter.text! as TextSpan;
    final run = root.children!.whereType<TextSpan>().single;

    expect(run.style?.color, const Color(0xFF0000FF));
    expect(run.style?.fontSize, 24);
  });

  test('wraps a paragraph across multiple lines at narrow widths', () {
    final document = const WeftNormalizer().normalize(
      '<p>This sentence contains enough words to wrap across several lines '
      'when the available layout width is small.</p>',
      id: 'wrap',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 120);
    addTearDown(layout.dispose);

    final command = layout.commands.whereType<WeftTextPaintCommand>().single;
    expect(command.painter.height,
        greaterThan(command.painter.preferredLineHeight * 1.5));
  });

  test('lays out CJK content without corrupting the logical text', () {
    const text = '中文排版需要正确处理标点、空格与连续文本的换行。'
        'Weft 会在当前阶段先保证内容完整与可读。';
    final document = const WeftNormalizer().normalize(
      '<p>$text</p>',
      id: 'cjk',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 180);
    addTearDown(layout.dispose);

    final command = layout.commands.whereType<WeftTextPaintCommand>().single;
    expect(command.painter.text?.toPlainText(), text);
    expect(layout.size.height, greaterThan(0));
  });

  test('lays out a long document without dropping block content', () {
    final source = List<String>.generate(
      300,
      (index) => '<p>Paragraph $index: '
          'a deterministic sentence used for long document layout smoke tests.'
          '</p>',
    ).join();
    final document = const WeftNormalizer().normalize(source, id: 'long');
    final layout = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(layout.dispose);

    final paragraphs =
        layout.commands.whereType<WeftTextPaintCommand>().where((command) {
      return command.painter.text?.toPlainText().startsWith('Paragraph ') ??
          false;
    }).toList();
    expect(paragraphs, hasLength(300));
    expect(layout.size.height, greaterThan(300 * 24));
  });
}
