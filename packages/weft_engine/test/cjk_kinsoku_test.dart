import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ui.Image square;

  setUpAll(() async {
    square = await _createImage(120, 120, const Color(0xFF3366CC));
  });

  tearDownAll(() {
    square.dispose();
  });

  test('default tables cover the common CJK punctuation', () {
    const start = WeftLineBreakRules.defaultLineStart;
    const end = WeftLineBreakRules.defaultLineEnd;
    const startProhibited = [
      '。',
      '、',
      '，',
      '．',
      '：',
      '；',
      '？',
      '！',
      '）',
      '〉',
      '》',
      '」',
      '』',
      '】',
      '〕',
      '…',
      '—',
      '・',
      '゛',
      '゜',
      ']',
    ];
    const endProhibited = ['（', '〈', '《', '「', '『', '【', '〔'];
    for (final char in startProhibited) {
      expect(start.contains(char.codeUnitAt(0)), isTrue, reason: char);
    }
    for (final char in endProhibited) {
      expect(end.contains(char.codeUnitAt(0)), isTrue, reason: char);
    }
    expect(start.intersection(end), isEmpty);
    expect(WeftLineBreakRules.off.lineStartProhibited, isEmpty);
    expect(WeftLineBreakRules.off.lineEndProhibited, isEmpty);
  });

  test('kinsoku keeps prohibited punctuation off line edges beside a float',
      () {
    const paragraph = '中文排版需要遵守禁则，句号与逗号不能出现在行首。'
        '左括号（和书名号《不应留在行尾，右括号）与书名号》不应出现在行首。'
        '中文 ，中文里逗号前的空格同样不能把标点挤到下一行的开头。'
        '省略号…与破折号—也不能出现在行首。';
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="120">'
      '<p>$paragraph$paragraph$paragraph</p>',
      id: 'kinsoku-float',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
    );
    addTearDown(layout.dispose);

    final lines = _lineTexts(layout);
    expect(lines.length, greaterThan(3));
    for (final text in lines) {
      expect(
        WeftLineBreakRules.defaultLineStart.contains(text.codeUnitAt(0)),
        isFalse,
        reason: 'line starts with "${text.substring(0, 1)}"',
      );
      final visibleEnd = text.trimRight();
      expect(visibleEnd, isNotEmpty);
      expect(
        WeftLineBreakRules.defaultLineEnd.contains(
          visibleEnd.codeUnitAt(visibleEnd.length - 1),
        ),
        isFalse,
        reason:
            'line ends with "${visibleEnd.substring(visibleEnd.length - 1)}"',
      );
    }
    // No character is dropped; spaces may collapse at break points, so the
    // comparison ignores whitespace.
    expect(
      lines.join().replaceAll(RegExp(r'\s'), ''),
      (paragraph * 3).replaceAll(RegExp(r'\s'), ''),
    );
  });

  test('a line made entirely of prohibited characters still advances', () {
    const text = '。，、；：？！';
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="80">'
      '<p>${text * 40}</p>',
      id: 'kinsoku-extreme',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
    );
    addTearDown(layout.dispose);

    final lines = _lineTexts(layout);
    expect(lines, isNotEmpty);
    // The floor keeps one character per line, so the run advances without
    // looping and without losing a single code unit.
    expect(lines.join(), text * 40);
  });

  test('empty rule tables keep the legacy line breaking', () {
    const paragraph = '中文内容需要在图片旁正常换行，标点不应被挤出可用行宽。';
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="120">'
      '<p>${paragraph * 6}</p>',
      id: 'kinsoku-off',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
      lineBreakRules: WeftLineBreakRules.off,
    );
    addTearDown(layout.dispose);

    final lines = _lineTexts(layout);
    expect(lines.length, greaterThan(3));
    // With the tables off the engine performs no kinsoku adjustments; only
    // completion and text integrity are asserted here.
    expect(
      lines.join().replaceAll(RegExp(r'\s'), ''),
      (paragraph * 6).replaceAll(RegExp(r'\s'), ''),
    );
  });

  test('custom end-of-line table pulls breaks back to allowed characters', () {
    // Periodic text that ends on the only allowed closing character, so every
    // tail still contains one.
    const text = '中文内容中文内容中文内容中文内容中文内容中文内容中文内容'
        '中文内容中文内容中文内容中文内容中';
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="asset:pic.png" '
      'style="float: left" width="120" height="120">'
      '<p>$text</p>',
      id: 'kinsoku-custom',
    );
    final layout = const WeftLayoutEngine().layout(
      document,
      width: 360,
      images: {_findById(document.body!, 'pic').id: square},
      // Only 中 may close a line; every break retreats until it does.
      lineBreakRules: const WeftLineBreakRules(
        lineEndProhibited: <int>{0x6587, 0x5185, 0x5BB9}, // 文 内 容
      ),
    );
    addTearDown(layout.dispose);

    final lines = _lineTexts(layout);
    expect(lines.length, greaterThan(2));
    for (final line in lines) {
      expect(
        line.endsWith('中'),
        isTrue,
        reason: 'line "$line" ends with a prohibited character',
      );
    }
    expect(lines.join(), text);
  });

  test('whole-paragraph path comparison records the ICU baseline', () {
    const paragraph = '这是一段用于对照整段排版路径的中文文本，句号、逗号、顿号与括号（示例内容）'
        '都不应出现在行首，左括号（不应出现在行尾。'
        '整段路径由 TextPainter 与 ICU 直接分行，用于记录现状与逐行路径的差异。';
    final document = const WeftNormalizer().normalize(
      '<p>$paragraph$paragraph</p>',
      id: 'kinsoku-whole-path',
    );
    // No float: this exercises the single TextPainter path.
    final layout = const WeftLayoutEngine().layout(document, width: 360);
    addTearDown(layout.dispose);

    final commands = layout.commands
        .whereType<WeftTextPaintCommand>()
        .where(
          (command) => (command.painter.text?.toPlainText() ?? '').isNotEmpty,
        )
        .toList();
    expect(commands, hasLength(1));
    final painter = commands.single.painter;
    final text = painter.text!.toPlainText();
    expect(text.length, greaterThan(40));

    var start = 0;
    var lineCount = 0;
    var startViolations = 0;
    var endViolations = 0;
    while (start < text.length && lineCount < 500) {
      final boundary = painter.getLineBoundary(TextPosition(offset: start));
      if (boundary.end <= start) break;
      final line = text.substring(boundary.start, boundary.end);
      final visibleEnd = line.trimRight();
      if (visibleEnd.isNotEmpty) {
        if (WeftLineBreakRules.defaultLineStart.contains(line.codeUnitAt(0))) {
          startViolations++;
        }
        if (WeftLineBreakRules.defaultLineEnd.contains(
          visibleEnd.codeUnitAt(visibleEnd.length - 1),
        )) {
          endViolations++;
        }
      }
      lineCount++;
      start = boundary.end;
    }
    expect(lineCount, greaterThan(2));
    // Recorded ICU baseline: TextPainter already keeps prohibited characters
    // off line edges through the UAX #14 break classes, so the
    // whole-paragraph path needs no kinsoku fixup of its own.
    expect(startViolations, 0);
    expect(endViolations, 0);
  });
}

List<String> _lineTexts(WeftLayoutResult layout) {
  return layout.commands
      .whereType<WeftTextPaintCommand>()
      .where(
        (command) => (command.painter.text?.toPlainText() ?? '').isNotEmpty,
      )
      .map((command) => command.painter.text!.toPlainText())
      .toList();
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
