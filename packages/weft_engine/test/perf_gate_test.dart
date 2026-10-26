// Loose CI performance gate against order-of-magnitude layout and paint
// regressions.
//
// The caps are NOT precise budgets: each cap is 10x the median measured on
// the reference machine (Windows, see docs/testing-strategy.md), rounded up
// to the next 100 ms with a 500 ms floor. A single run after one warm-up
// must stay under the cap; that catches 10x-class regressions while
// tolerating CI jitter and slower machines. Re-measure with
// tool/layout_benchmark_test.dart when touching the layout engine, and keep
// the scenario builders here in sync with that tool so the caps stay
// meaningful.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show BoxConstraints;
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

// Measured medians on the reference machine (2026-10, Windows dev box):
// article300 ~52-56 ms, table48 ~26-28 ms, floatWrap ~6-9 ms,
// selection300 ~0.7-0.9 ms. Medians below 50 ms use the 500 ms floor.
// The hit scenarios (ADR 0020) resolve a single point in the microsecond
// range, so their gates sit at the floor and only catch catastrophic
// regressions; the real comparison lives in docs/testing-strategy.md.
const int _article300CapMs = 600; // 10x ~55 ms, rounded up to a hundred.
const int _appendArticle300CapMs = 500; // 10x ~37 ms: floor cap.
const int _lazyArticle300CapMs = 500; // Median < 50 ms: floor cap.
const int _table48CapMs = 500; // Median < 50 ms: floor cap.
const int _floatWrapCapMs = 500; // Median < 50 ms: floor cap.
const int _selection300CapMs = 500; // Median < 50 ms: floor cap.
const int _paintDirectCapMs = 500; // Median < 50 ms: floor cap.
const int _paintFullCapMs = 500; // Median < 50 ms: floor cap.
const int _paintWindowCapMs = 500; // Median < 50 ms: floor cap.
const int _hitCapMs = 500; // Median in µs range: floor cap.

const double _viewportWidth = 360;
const double _paintWindowHeight = 800;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('perf gate: article300 layout under $_article300CapMs ms', () {
    final document = _normalize(_articleHtml(), 'gate-article');
    _runUnderCap(_article300CapMs, 'article300', () {
      const WeftLayoutEngine()
          .layout(document, width: _viewportWidth)
          .dispose();
    });
  });

  test('perf gate: appendArticle300Full under $_appendArticle300CapMs ms', () {
    final document = _normalize(
      '${_articleHtml()}${_articleParagraphHtml(300)}',
      'gate-article',
    );
    _runUnderCap(_appendArticle300CapMs, 'appendArticle300Full', () {
      const WeftLayoutEngine()
          .layout(document, width: _viewportWidth)
          .dispose();
    });
  });

  test(
      'perf gate: appendArticle300Incremental under $_appendArticle300CapMs ms',
      () {
    final first = _normalize(_articleHtml(), 'gate-article');
    final appended = _normalize(
      '${_articleHtml()}${_articleParagraphHtml(300)}',
      'gate-article',
    );
    final previous = List<WeftLayoutResult>.generate(
      2,
      (_) => const WeftLayoutEngine().layout(first, width: _viewportWidth),
    );
    addTearDown(() {
      for (final layout in previous) {
        layout.dispose();
      }
    });
    var run = 0;
    _runUnderCap(_appendArticle300CapMs, 'appendArticle300Incremental', () {
      final old = previous[run++];
      final current = const WeftLayoutEngine().layout(
        appended,
        width: _viewportWidth,
        previous: old,
      );
      old.dispose();
      current.dispose();
    });
  });

  test('perf gate: lazyArticle300FirstViewport under $_lazyArticle300CapMs ms',
      () {
    final document = _normalize(_articleHtml(), 'gate-article');
    _runUnderCap(_lazyArticle300CapMs, 'lazyArticle300FirstViewport', () {
      final surface = RenderWeftSurface(
        document: document,
        enableLazyLayout: true,
        viewportHeight: _paintWindowHeight,
      );
      surface.layout(const BoxConstraints.tightFor(width: _viewportWidth));
      surface.dispose();
    });
  });

  test('perf gate: table48 layout under $_table48CapMs ms', () {
    final document = _normalize(_tableHtml(), 'gate-table');
    _runUnderCap(_table48CapMs, 'table48', () {
      const WeftLayoutEngine()
          .layout(document, width: _viewportWidth)
          .dispose();
    });
  });

  test('perf gate: floatWrap layout under $_floatWrapCapMs ms', () async {
    final image = await _createImage(120, 96, const Color(0xFF3366CC));
    addTearDown(image.dispose);
    final document = _normalize(_floatHtml(), 'gate-float');
    final images = _imagesFor(document, image);
    _runUnderCap(_floatWrapCapMs, 'floatWrap', () {
      const WeftLayoutEngine()
          .layout(document, width: _viewportWidth, images: images)
          .dispose();
    });
  });

  test('perf gate: selection300 rects under $_selection300CapMs ms', () {
    final document = _normalize(_articleHtml(), 'gate-selection');
    final layout = const WeftLayoutEngine().layout(
      document,
      width: _viewportWidth,
    );
    addTearDown(layout.dispose);
    final selection = _crossParagraphSelection(layout);
    // Sanity check before the timed runs: the range must cover real text,
    // otherwise the gate would pass on an empty scenario.
    expect(layout.selectionRects(selection), isNotEmpty);
    _runUnderCap(_selection300CapMs, 'selection300', () {
      layout.selectionRects(selection);
    });
  });

  test('perf gate: paintArticle300Direct under $_paintDirectCapMs ms', () {
    final document = _normalize(_articleHtml(), 'gate-paint-direct');
    final layout = const WeftLayoutEngine().layout(
      document,
      width: _viewportWidth,
    );
    addTearDown(layout.dispose);
    _runUnderCap(_paintDirectCapMs, 'paintArticle300Direct', () {
      _recordPaintCanvas((canvas) {
        for (final command in layout.commands) {
          command.paint(canvas, Offset.zero);
        }
      });
    });
  });

  test('perf gate: paintArticle300Full under $_paintFullCapMs ms', () {
    final document = _normalize(_articleHtml(), 'gate-paint-full');
    final surface = RenderWeftSurface(
      document: document,
      textScaler: TextScaler.noScaling,
    );
    surface.layout(const BoxConstraints.tightFor(width: _viewportWidth));
    addTearDown(surface.dispose);
    final fullWindow = Offset.zero & surface.size;
    _runUnderCap(_paintFullCapMs, 'paintArticle300Full', () {
      _recordPaintCanvas((canvas) {
        surface.debugPaintChunks(canvas, visible: fullWindow);
      });
    });
  });

  test('perf gate: paintArticle300Window under $_paintWindowCapMs ms', () {
    final document = _normalize(_articleHtml(), 'gate-paint-window');
    final surface = RenderWeftSurface(
      document: document,
      textScaler: TextScaler.noScaling,
    );
    surface.layout(const BoxConstraints.tightFor(width: _viewportWidth));
    addTearDown(surface.dispose);
    final scrolledWindow = Rect.fromLTWH(
      0,
      math.max(0, (surface.size.height - _paintWindowHeight) / 2),
      _viewportWidth,
      math.min(_paintWindowHeight, surface.size.height),
    );
    _runUnderCap(_paintWindowCapMs, 'paintArticle300Window', () {
      _recordPaintCanvas((canvas) {
        surface.debugPaintChunks(canvas, visible: scrolledWindow);
      });
    });
  });

  test('perf gate: hitAnchorTop under $_hitCapMs ms', () {
    final (layout, top, _, _, _) = _hitScenario('gate-hit-top');
    addTearDown(layout.dispose);
    _runUnderCap(_hitCapMs, 'hitAnchorTop', () {
      layout.anchorAt(top);
    });
  });

  test('perf gate: hitAnchorMiddle under $_hitCapMs ms', () {
    final (layout, _, middle, _, _) = _hitScenario('gate-hit-middle');
    addTearDown(layout.dispose);
    _runUnderCap(_hitCapMs, 'hitAnchorMiddle', () {
      layout.anchorAt(middle);
    });
  });

  test('perf gate: hitAnchorBottom under $_hitCapMs ms', () {
    final (layout, _, _, bottom, _) = _hitScenario('gate-hit-bottom');
    addTearDown(layout.dispose);
    _runUnderCap(_hitCapMs, 'hitAnchorBottom', () {
      layout.anchorAt(bottom);
    });
  });

  test('perf gate: hitLinkArticle under $_hitCapMs ms', () {
    final (layout, _, _, _, link) = _hitScenario('gate-hit-link');
    addTearDown(layout.dispose);
    _runUnderCap(_hitCapMs, 'hitLinkArticle', () {
      layout.linkAt(link);
    });
  });
}

/// One attached article layout plus the known hit points for the hit gates,
/// mirroring the hit scenarios in tool/layout_benchmark_test.dart. Every
/// point is asserted to resolve a real hit before it is timed.
(WeftLayoutResult, Offset, Offset, Offset, Offset) _hitScenario(String id) {
  final document = _normalize(_articleHtml(), id);
  final layout = const WeftLayoutEngine().layout(
    document,
    width: _viewportWidth,
  );
  layout.attachDocument(document);
  Offset glyphPoint(WeftTextEntry entry) {
    return layout.textRectsForNode(entry.nodeId, 0, 1).first.center;
  }

  final entries = layout.textIndex!.entries;
  final top = glyphPoint(entries.first);
  final middle = glyphPoint(entries[entries.length ~/ 2]);
  final bottom = glyphPoint(entries.last);
  final link = layout.links[layout.links.length ~/ 2].rects.first.center;
  expect(layout.anchorAt(top), isNotNull);
  expect(layout.anchorAt(middle), isNotNull);
  expect(layout.anchorAt(bottom), isNotNull);
  expect(layout.linkAt(link), isNotNull);
  return (layout, top, middle, bottom, link);
}

/// Records painting commands onto a throwaway canvas and releases the
/// picture, matching the recording work a real frame performs for the paint.
void _recordPaintCanvas(void Function(ui.Canvas canvas) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  recorder.endRecording().dispose();
}

/// Runs [body] once as a warm-up, then times a single run and asserts it
/// stays under [capMs]. The generous cap keeps this stable on slower CI
/// machines while still catching order-of-magnitude regressions.
void _runUnderCap(int capMs, String name, void Function() body) {
  body();
  final watch = Stopwatch()..start();
  body();
  watch.stop();
  final elapsed = watch.elapsedMilliseconds;
  // ignore: avoid_print
  print('$name: $elapsed ms (cap $capMs ms)');
  expect(
    elapsed,
    lessThan(capMs),
    reason: '$name took $elapsed ms, cap is $capMs ms. If the engine '
        'genuinely got slower, profile it; if the scenario changed, '
        're-derive the cap from a fresh tool/layout_benchmark_test.dart '
        'median (10x, rounded up to 100 ms, floor 500 ms).',
  );
}

WeftDocumentSnapshot _normalize(String html, String id) {
  final document = const WeftNormalizer().normalize(html, id: id);
  if (!document.supportReport.canRender) {
    throw StateError(
      'Gate document "$id" is not renderable: '
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
