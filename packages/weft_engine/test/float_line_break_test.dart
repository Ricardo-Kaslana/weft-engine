import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

/// ADR 0045: the float per-line probe covers a window instead of the whole
/// remaining text. Line breaks must be unchanged in every observable way —
/// the pinned surfaces are the existing float geometry, pixel, kinsoku and
/// RTL tests; these tests pin the invariants on long paragraphs where the
/// window actually grows: complete coverage (only line-end spaces dropped),
/// per-line kinsoku, width monotonicity, determinism, and unbreakable words
/// that force the window to the paragraph end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = WeftLayoutEngine();

  test('long CJK paragraph beside a float keeps coverage and kinsoku',
      () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final text = _cjkFiller(4000);
    final (layout, _) = _layoutFloatParagraph(engine, image, text, 360);
    addTearDown(layout.dispose);
    final lines = _lineTexts(layout);
    expect(lines.length, greaterThan(60),
        reason: 'the paragraph must span far more lines than the probe seed');
    _expectCoverage('锚点。$text', lines);
    _expectKinsoku(lines);
  });

  test('line counts shrink monotonically as the width grows', () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final text = _cjkFiller(1200);
    var previousLines = -1;
    for (final width in const [200.0, 260.0, 320.0, 380.0, 440.0, 520.0]) {
      final (layout, doc) = _layoutFloatParagraph(engine, image, text, width);
      addTearDown(layout.dispose);
      final lines = _lineTexts(layout);
      _expectCoverage('锚点。$text', lines);
      _expectKinsoku(lines);
      if (previousLines >= 0) {
        expect(lines.length, lessThanOrEqualTo(previousLines),
            reason: 'width $width must not wrap into more lines');
      }
      previousLines = lines.length;
      expect(doc.body, isNotNull);
    }
  });

  test('an unbreakable word grows the window to the paragraph end', () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final word = 'x' * 300;
    final (layout, _) = _layoutFloatParagraph(engine, image, word, 360);
    addTearDown(layout.dispose);
    final lines = _lineTexts(layout);
    expect(lines.join(), '锚点。$word',
        reason: 'a word with no break opportunity must survive intact');
    final (relayout, _) = _layoutFloatParagraph(engine, image, word, 360);
    addTearDown(relayout.dispose);
    expect(_lineTexts(relayout), lines, reason: 'the probe must be causal');
  });

  test('spaces dropped at line ends keep every painted character', () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final text = '${_cjkFiller(2400)} tail space ';
    final (layout, _) = _layoutFloatParagraph(engine, image, text, 360);
    addTearDown(layout.dispose);
    final lines = _lineTexts(layout);
    _expectCoverage('锚点。$text', lines);
    // Spaces inside a line are painted; only line-end spaces vanish.
    final joined = lines.join();
    expect(joined.contains('浮动图片旁边'), isTrue);
    final fullText = '锚点。$text';
    final dropped = fullText.length - joined.length;
    expect(dropped, lessThanOrEqualTo(' '.allMatches(fullText).length));
  });

  test('mixed inline styles keep run coverage across windowed lines', () async {
    final image = await _createImage();
    addTearDown(image.dispose);
    final buffer = StringBuffer();
    for (var i = 0; i < 60; i++) {
      buffer.write('段落 $i <em>强调$i</em> and <a href="https://e.com/$i">'
          'links$i</a> mixed ${_cjkFiller(40)}');
    }
    final (layout, _) =
        _layoutFloatParagraph(engine, image, buffer.toString(), 360);
    addTearDown(layout.dispose);
    final commands = layout.commands.whereType<WeftTextPaintCommand>().toList();
    expect(commands.length, greaterThan(40));
    for (final command in commands) {
      final painted = command.painter.text!.toPlainText();
      var covered = 0;
      for (final run in command.runs) {
        expect(run.painterStart, covered,
            reason: 'runs must tile the painter text without gaps');
        covered = run.painterEnd;
      }
      expect(covered, painted.length);
    }
  });
}

List<String> _lineTexts(WeftLayoutResult layout) {
  return layout.commands
      .whereType<WeftTextPaintCommand>()
      .map((command) => command.painter.text!.toPlainText())
      .toList();
}

/// Lays out one floated image followed by one long paragraph and returns the
/// result plus the document, so tests can pin extra structure.
(WeftLayoutResult, WeftDocumentSnapshot) _layoutFloatParagraph(
  WeftLayoutEngine engine,
  ui.Image image,
  String text,
  double width,
) {
  final document = const WeftNormalizer().normalize(
    '<p><img src="asset:float-break.png" style="float:left" '
    'width="120" height="96">锚点。</p><p>$text</p>',
    id: 'float-line-break',
  );
  expect(document.supportReport.canRender, isTrue);
  final images = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      if (node.tag == 'img') images[node.id] = image;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  visit(document.body!);
  return (engine.layout(document, width: width, images: images), document);
}

/// Lines join into the paragraph text with only line-end spaces removed:
/// every joined character must appear in order in the plain text, and every
/// skipped plain-text character must be a dropped space.
void _expectCoverage(String plainText, List<String> lines) {
  final joined = lines.join();
  var cursor = 0;
  for (var i = 0; i < joined.length; i++) {
    while (cursor < plainText.length && plainText[cursor] != joined[i]) {
      expect(plainText[cursor], ' ',
          reason: 'only collapsible spaces may be dropped from the stream');
      cursor++;
    }
    expect(cursor < plainText.length, isTrue,
        reason: 'joined line text at $i is not covered by the paragraph');
    cursor++;
  }
}

void _expectKinsoku(List<String> lines) {
  final rules = const WeftLineBreakRules();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    expect(
      rules.lineEndProhibited.contains(line.codeUnitAt(line.length - 1)),
      isFalse,
      reason: 'line $i ends with a prohibited character: '
          '${line.substring(math.max(0, line.length - 4))}',
    );
    if (i > 0) {
      expect(
        rules.lineStartProhibited.contains(line.codeUnitAt(0)),
        isFalse,
        reason: 'line $i starts with a prohibited character: '
            '${line.substring(0, math.min(4, line.length))}',
      );
    }
  }
}

/// CJK filler long enough to wrap across many lines at 360px, with sparse
/// punctuation that exercises the kinsoku adjustment without hitting its
/// documented single-character fallback.
String _cjkFiller(int chars) {
  const unit = 'Weft 引擎在浮动图片旁边逐行缩短行盒，中文文本连续排布时按字符'
      '断行，标点不落在行首。';
  final buffer = StringBuffer();
  while (buffer.length < chars) {
    buffer.write(unit);
  }
  return buffer.toString().substring(0, chars);
}

Future<ui.Image> _createImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, 120, 96),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 96);
  picture.dispose();
  return image;
}
