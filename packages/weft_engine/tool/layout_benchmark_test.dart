// Layout performance benchmark driver. `dart run` cannot execute Flutter
// packages directly, so this runs through the test harness:
//
//   cd packages/weft_engine
//   flutter test tool/layout_benchmark_test.dart --no-pub
//
// Each scenario runs once as a warm-up, then five timed runs; the report
// prints the median and the nearest-rank P95 (over five samples that is
// the worst run). These are local, human-reference numbers: the CI gate
// lives in test/perf_gate_test.dart and documents its caps separately.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const double _viewportWidth = 360;
const int _sampleCount = 5;
const double _paintWindowHeight = 800;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('layout benchmark: median of 5 runs after 1 warm-up', () async {
    final floatImage = await _createImage(120, 96, const Color(0xFF3366CC));
    addTearDown(floatImage.dispose);
    const engine = WeftLayoutEngine();

    final article = _normalize(_articleHtml(), 'bench-article');
    final appendedArticle = _normalize(
      '${_articleHtml()}${_articleParagraphHtml(300)}',
      'bench-article',
    );
    final appendPreviousLayouts = List<WeftLayoutResult>.generate(
      _sampleCount + 1,
      (_) => engine.layout(article, width: _viewportWidth),
    );
    addTearDown(() {
      for (final layout in appendPreviousLayouts) {
        layout.dispose();
      }
    });
    var appendRun = 0;
    final table = _normalize(_tableHtml(), 'bench-table');
    final floatDocument = _normalize(_floatHtml(), 'bench-float');
    final floatImages = _imagesFor(floatDocument, floatImage);

    // selection300 lays the article out once up front; the measured unit is
    // a selectionRects() call over a range spanning ten paragraphs.
    final selectionDocument = _normalize(_articleHtml(), 'bench-selection');
    final selectionLayout = engine.layout(
      selectionDocument,
      width: _viewportWidth,
    );
    addTearDown(selectionLayout.dispose);
    final selection = _crossParagraphSelection(selectionLayout);

    // paintArticle300Direct records every command onto a fresh canvas per
    // run: that is the pre-chunking full-paint path and stays as the baseline
    // reference for the chunked scenarios below.
    final paintLayout = engine.layout(article, width: _viewportWidth);
    addTearDown(paintLayout.dispose);

    // Hit scenarios resolve single points against the article layout. The
    // document is attached so the timed path is the chunk-culled hit
    // resolution (ADR 0020), and points are resolved up front through the
    // logical text index so the timed body is exactly one anchorAt/linkAt
    // call. Every scenario is asserted to hit real content before it is
    // timed.
    paintLayout.attachDocument(article);
    ui.Offset glyphPoint(WeftTextEntry entry) {
      return paintLayout.textRectsForNode(entry.nodeId, 0, 1).first.center;
    }

    final articleEntries = paintLayout.textIndex!.entries;
    final hitTopPoint = glyphPoint(articleEntries.first);
    final hitMiddlePoint =
        glyphPoint(articleEntries[articleEntries.length ~/ 2]);
    final hitBottomPoint = glyphPoint(articleEntries.last);
    final hitLink = paintLayout.links[paintLayout.links.length ~/ 2];
    final hitLinkPoint = hitLink.rects.first.center;
    expect(paintLayout.anchorAt(hitTopPoint), isNotNull);
    expect(paintLayout.anchorAt(hitMiddlePoint), isNotNull);
    expect(paintLayout.anchorAt(hitBottomPoint), isNotNull);
    expect(paintLayout.linkAt(hitLinkPoint), isNotNull);

    // The chunked scenarios drive a detached RenderWeftSurface through the
    // production paint path (partition, picture cache, culling). The warm-up
    // run builds the picture cache, so the timed runs measure steady-state
    // painting.
    final lazyProbe = RenderWeftSurface(
      document: article,
      enableLazyLayout: true,
      viewportHeight: _paintWindowHeight,
    );
    lazyProbe.layout(const BoxConstraints.tightFor(width: _viewportWidth));
    // ignore: invalid_use_of_visible_for_testing_member
    final lazyProbeLayout = lazyProbe.debugLayout!;
    // ignore: avoid_print
    print(
      'lazyFirstViewport structure: laidOut='
      '${lazyProbeLayout.debugLaidOutBlockCount} '
      'materialized=${lazyProbeLayout.debugMaterializedBlockCount} '
      'commands=${lazyProbeLayout.commands.length}',
    );
    lazyProbe.dispose();

    final paintSurface = RenderWeftSurface(
      document: article,
      textScaler: TextScaler.noScaling,
    );
    paintSurface.layout(const BoxConstraints.tightFor(width: _viewportWidth));
    addTearDown(paintSurface.dispose);
    final fullWindow = Offset.zero & paintSurface.size;
    final scrolledWindow = Rect.fromLTWH(
      0,
      math.max(0, (paintSurface.size.height - _paintWindowHeight) / 2),
      _viewportWidth,
      math.min(_paintWindowHeight, paintSurface.size.height),
    );

    final scenarios = <String, void Function()>{
      'article300': () {
        engine.layout(article, width: _viewportWidth).dispose();
      },
      'appendArticle300Full': () {
        engine.layout(appendedArticle, width: _viewportWidth).dispose();
      },
      'lazyArticle300FirstViewport': () {
        final surface = RenderWeftSurface(
          document: article,
          enableLazyLayout: true,
          viewportHeight: _paintWindowHeight,
        );
        surface.layout(const BoxConstraints.tightFor(width: _viewportWidth));
        surface.dispose();
      },
      'appendArticle300Incremental': () {
        final previous = appendPreviousLayouts[appendRun++];
        final current = engine.layout(
          appendedArticle,
          width: _viewportWidth,
          previous: previous,
        );
        previous.dispose();
        current.dispose();
      },
      'table48': () {
        engine.layout(table, width: _viewportWidth).dispose();
      },
      'floatWrap': () {
        engine
            .layout(
              floatDocument,
              width: _viewportWidth,
              images: floatImages,
            )
            .dispose();
      },
      'selection300': () {
        selectionLayout.selectionRects(selection);
      },
      'paintArticle300Direct': () {
        _recordCanvas((canvas) {
          for (final command in paintLayout.commands) {
            command.paint(canvas, Offset.zero);
          }
        });
      },
      'paintArticle300Full': () {
        _recordCanvas((canvas) {
          // This file only runs through `flutter test`, so reaching the
          // testing-only paint entry point is intended.
          // ignore: invalid_use_of_visible_for_testing_member
          paintSurface.debugPaintChunks(canvas, visible: fullWindow);
        });
      },
      'paintArticle300Window': () {
        _recordCanvas((canvas) {
          // ignore: invalid_use_of_visible_for_testing_member
          paintSurface.debugPaintChunks(canvas, visible: scrolledWindow);
        });
      },
      'hitAnchorTop': () {
        paintLayout.anchorAt(hitTopPoint);
      },
      'hitAnchorMiddle': () {
        paintLayout.anchorAt(hitMiddlePoint);
      },
      'hitAnchorBottom': () {
        paintLayout.anchorAt(hitBottomPoint);
      },
      'hitLinkArticle': () {
        paintLayout.linkAt(hitLinkPoint);
      },
    };

    final report = StringBuffer();
    for (final entry in scenarios.entries) {
      entry.value(); // Warm-up: JIT and allocator steady state.
      final samples = <double>[];
      for (var i = 0; i < _sampleCount; i++) {
        final watch = Stopwatch()..start();
        entry.value();
        watch.stop();
        samples.add(watch.elapsedMicroseconds / 1000.0);
      }
      samples.sort();
      final median = samples[samples.length ~/ 2];
      // Nearest-rank P95 over five samples is the maximum sample.
      final p95 = samples.last;
      // Single hit resolutions land in the microsecond range, where
      // millisecond precision would round every sample to zero.
      final inMicros = entry.key.startsWith('hit');
      final scale = inMicros ? 1000.0 : 1.0;
      final unit = inMicros ? 'µs' : 'ms';
      report.writeln(
        '${entry.key.padRight(12)} median ${(median * scale).toStringAsFixed(1)} $unit'
        '  p95 ${(p95 * scale).toStringAsFixed(1)} $unit'
        '  samples [${samples.map((value) => (value * scale).toStringAsFixed(1)).join(', ')}]',
      );
    }
    // ignore: avoid_print
    print(report);
  });
}

/// Records painting commands onto a throwaway canvas and releases the
/// picture, matching the recording work a real frame performs for the paint.
void _recordCanvas(void Function(ui.Canvas canvas) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  recorder.endRecording().dispose();
}

WeftDocumentSnapshot _normalize(String html, String id) {
  final document = const WeftNormalizer().normalize(html, id: id);
  if (!document.supportReport.canRender) {
    throw StateError(
      'Benchmark document "$id" is not renderable: '
      '${document.supportReport.issues.map((issue) => issue.code).join(', ')}',
    );
  }
  return document;
}

/// 300 blocks of mixed English/Chinese article content: a heading every ten
/// paragraphs, inline emphasis and links inside the paragraphs.
String _articleHtml() {
  final buffer = StringBuffer();
  for (var i = 0; i < 300; i++) {
    if (i % 10 == 0) {
      buffer.write(
        '<h3>章节 ${i ~/ 10}:中英混排与布局性能基准</h3>',
      );
    }
    buffer.write(_articleParagraphHtml(i));
  }
  return buffer.toString();
}

String _articleParagraphHtml(int i) {
  return '<p>第 $i 段。Weft engine lays out mixed English and 中文内容 at a '
      'fixed 360px viewport, exercising line breaking, <em>强调文本 $i</em> '
      'and <a href="https://example.com/a$i">inline links 第 $i 段</a> so the '
      'paragraph wraps onto several lines deterministically.</p>';
}

/// A 48-row, 6-column collapsed-border table with header cells, cell
/// padding, one rowspan=2 cell every seven rows and one colspan=2 cell
/// every five rows.
String _tableHtml() {
  const cellStyle = 'border: 1px solid #dddddd; padding: 4px';
  final buffer = StringBuffer('<table style="border-collapse: collapse">');
  buffer.write('<tr>');
  for (var c = 0; c < 6; c++) {
    buffer.write('<th style="$cellStyle">H$c</th>');
  }
  buffer.write('</tr>');
  for (var r = 0; r < 47; r++) {
    final spansDown = r % 7 == 3;
    final spannedAbove = r > 0 && (r - 1) % 7 == 3;
    buffer.write('<tr>');
    var col = 0;
    if (spansDown) {
      buffer.write('<td rowspan="2" style="$cellStyle">R$r 跨行</td>');
      col = 1;
    } else if (spannedAbove) {
      // Column 0 is occupied by the previous row's overhanging rowspan.
      col = 1;
    }
    if (r % 5 == 2) {
      buffer.write('<td colspan="2" style="$cellStyle">C$r 跨列</td>');
      col += 2;
    }
    while (col < 6) {
      buffer.write('<td style="$cellStyle">r${r}c$col 数据</td>');
      col++;
    }
    buffer.write('</tr>');
  }
  buffer.write('</table>');
  return buffer.toString();
}

/// Ten left-floated 120x96 images, each followed by a long CJK paragraph
/// whose lines wrap beside the float and then reclaim the full width.
String _floatHtml() {
  const cjkBody = 'Weft 引擎在浮动图片旁边逐行缩短行盒,中文文本连续排布时需要'
      '按字符断行并保持标点不被挤到行首,这段文本足够长以覆盖多次换行。';
  final buffer = StringBuffer();
  for (var i = 0; i < 10; i++) {
    buffer.write(
      '<img src="asset:bench-float.png" '
      'style="float: left" width="120" height="96">',
    );
    buffer.write('<p>第 $i 组。$cjkBody$cjkBody$cjkBody</p>');
  }
  return buffer.toString();
}

/// Selection from inside paragraph 100 to inside paragraph 110, addressed
/// through the logical text index so it is robust to inline splits.
TextSelectionRange _crossParagraphSelection(WeftLayoutResult layout) {
  final index = layout.textIndex!;
  TextAnchor anchorAfter(String marker) {
    final entry = index.entries.firstWhere(
      (candidate) => candidate.text.startsWith(marker),
    );
    return TextAnchor(entry.nodeId, 4);
  }

  return TextSelectionRange(
    anchor: anchorAfter('第 100 段'),
    extent: anchorAfter('第 110 段'),
  );
}

Map<int, ui.Image> _imagesFor(WeftDocumentSnapshot document, ui.Image image) {
  final images = <int, ui.Image>{};
  void visit(WeftNode node) {
    if (node is WeftElement) {
      if (node.tag == 'img') images[node.id] = image;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  final body = document.body;
  if (body != null) visit(body);
  return images;
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
