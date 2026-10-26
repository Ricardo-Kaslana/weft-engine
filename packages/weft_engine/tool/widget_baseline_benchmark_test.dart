// First parse-and-layout comparison: the Weft engine against a functionally
// equivalent "one Widget per block" pipeline built straight on package:html.
// Phase 1/3 acceptance (development-plan.md) compares the two on article300.
//
//   cd packages/weft_engine
//   flutter test tool/widget_baseline_benchmark_test.dart --no-pub
//
// Each scenario runs once as a warm-up, then five timed runs; the report
// prints the median. These are local reference numbers, not CI gates: the
// widget side includes a full frame (build + layout + paint) because that is
// the cheapest point where a widget pipeline has finished laying out, while
// the engine side records its commands onto a throwaway canvas so both sides
// end with painted output ready for display.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const double _viewportWidth = 360;
const int _sampleCount = 10;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('benchmark: engine vs tags-to-Widgets first parse and layout',
      (tester) async {
    final html = _articleHtml(300);

    Future<double> engineMs() async {
      final watch = Stopwatch()..start();
      final document =
          const WeftNormalizer().normalize(html, id: 'bench-engine');
      final layout = const WeftLayoutEngine().layout(
        document,
        width: _viewportWidth,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      for (final command in layout.commands) {
        command.paint(canvas, ui.Offset.zero);
      }
      recorder.endRecording().dispose();
      watch.stop();
      layout.dispose();
      return watch.elapsedMicroseconds / 1000.0;
    }

    Future<double> widgetsMs() async {
      final watch = Stopwatch()..start();
      final dom = html_parser.parseFragment(html);
      final widgets = _blocksToWidgets(dom.nodes);
      final key = UniqueKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: SizedBox(
              width: _viewportWidth,
              child: Column(
                key: key,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widgets,
              ),
            ),
          ),
        ),
      );
      watch.stop();
      return watch.elapsedMicroseconds / 1000.0;
    }

    double median(List<double> samples) {
      final sorted = samples.toList()..sort();
      return sorted[sorted.length ~/ 2];
    }

    await engineMs();
    await widgetsMs();
    await engineMs();
    await widgetsMs();
    // Interleave the two sides so machine drift cancels out, then report the
    // minimum (least-noise estimator) alongside the median.
    final engineSamples = <double>[];
    final widgetSamples = <double>[];
    for (var i = 0; i < _sampleCount; i++) {
      engineSamples.add(await engineMs());
      widgetSamples.add(await widgetsMs());
    }
    final engineMedian = median(engineSamples);
    final widgetMedian = median(widgetSamples);
    final reduction = 1 - engineMedian / widgetMedian;
    final minReduction =
        1 - engineSamples.reduce(math.min) / widgetSamples.reduce(math.min);
    // ignore: avoid_print
    print(
      'engine (normalize + layout + record): median '
      '${engineMedian.toStringAsFixed(1)}ms  '
      'samples ${engineSamples.map((v) => v.toStringAsFixed(1)).join(', ')}',
    );
    // ignore: avoid_print
    print(
      'tags-to-Widgets (package:html + first frame): median '
      '${widgetMedian.toStringAsFixed(1)}ms  '
      'samples ${widgetSamples.map((v) => v.toStringAsFixed(1)).join(', ')}',
    );
    // ignore: avoid_print
    print(
      'engine is ${(100 * reduction).toStringAsFixed(0)}% faster (median) / '
      '${(100 * minReduction).toStringAsFixed(0)}% faster (min) than the '
      'equivalent Widget pipeline (phase target: at least 40%); '
      'engine min ${engineSamples.reduce(math.min).toStringAsFixed(1)}ms, '
      'widget min ${widgetSamples.reduce(math.min).toStringAsFixed(1)}ms',
    );
  });
}

/// Collapses whitespace the way a content pipeline would before handing text
/// to Widgets, so both sides measure the same rendered content.
String _collapse(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Builds one widget per top-level block with the same user-visible styling
/// Weft produces: heading sizes and weights, bold/italic emphasis, styled
/// links, list markers, and collapsed whitespace. A functionally equivalent
/// "tags to Widgets" pipeline cannot stay with plain Text(node.text); these
/// spans are the minimum required for the same rendered outcome.
List<Widget> _blocksToWidgets(List<html_dom.Node> nodes) {
  final widgets = <Widget>[];
  for (final node in nodes) {
    if (node is html_dom.Text) {
      final text = _collapse(node.text);
      if (text.isNotEmpty) widgets.add(Text(text, style: _bodyStyle));
      continue;
    }
    if (node is! html_dom.Element) continue;
    switch (node.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
        final text = _collapse(node.text);
        if (text.isNotEmpty) {
          widgets.add(
            Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                height: 1.5,
              ),
            ),
          );
        }
      case 'ul':
      case 'ol':
        var index = 0;
        for (final child in node.children) {
          if (child.localName != 'li') continue;
          index += 1;
          final marker = node.localName == 'ol' ? '$index. ' : '• ';
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(marker, style: _bodyStyle),
                  Expanded(child: _inlineToText(child, _bodyStyle)),
                ],
              ),
            ),
          );
        }
      default:
        final inner = _collapse(node.text);
        if (inner.isEmpty) continue;
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _inlineToText(node, _bodyStyle),
          ),
        );
    }
  }
  return widgets;
}

const _bodyStyle = TextStyle(fontSize: 16, height: 1.5);
const _linkStyle = TextStyle(
  fontSize: 16,
  height: 1.5,
  color: Color(0xFF1A73E8),
  decoration: TextDecoration.underline,
);

Widget _inlineToText(html_dom.Element element, TextStyle style) {
  return Text.rich(
    TextSpan(
      children: _inlineSpans(element, style),
      style: style,
    ),
  );
}

List<InlineSpan> _inlineSpans(html_dom.Element element, TextStyle style) {
  final spans = <InlineSpan>[];
  for (final child in element.nodes) {
    if (child is html_dom.Text) {
      final text = _collapse(child.text);
      if (text.isEmpty) continue;
      spans.add(TextSpan(text: text, style: style));
      continue;
    }
    if (child is! html_dom.Element) continue;
    switch (child.localName) {
      case 'strong':
      case 'b':
        spans.addAll(
          _inlineSpans(child, style.copyWith(fontWeight: FontWeight.bold)),
        );
      case 'em':
      case 'i':
        spans.addAll(
          _inlineSpans(child, style.copyWith(fontStyle: FontStyle.italic)),
        );
      case 'a':
        spans.addAll(_inlineSpans(child, _linkStyle));
      default:
        spans.addAll(_inlineSpans(child, style));
    }
  }
  return spans;
}

String _articleHtml(int count) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    if (i % 10 == 0) {
      buffer.write('<h3>章节 ${i ~/ 10}:中英混排与布局性能基准</h3>');
    }
    buffer.write(
      '<p>第 $i 段。Weft engine lays out mixed English and 中文内容 at a '
      'fixed 360px viewport, exercising line breaking, <em>强调文本 $i</em> '
      'and <a href="https://example.com/a$i">inline links 第 $i 段</a> so the '
      'paragraph wraps onto several lines deterministically.</p>',
    );
  }
  return buffer.toString();
}
