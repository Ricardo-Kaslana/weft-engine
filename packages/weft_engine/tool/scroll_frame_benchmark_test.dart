// Scroll frame timing benchmark for the phase 3 acceptance
// (development-plan.md): reference scroll P95/P99 frame costs. Frame pump
// durations here include test-harness overhead, so treat these numbers as
// structured evidence on the host machine, not as reference-device results;
// weft_lab on hardware remains the authoritative device measurement.
//
//   cd packages/weft_engine
//   flutter test tool/scroll_frame_benchmark_test.dart --no-pub
//   flutter test --release tool/scroll_frame_benchmark_test.dart
//
// The session scrolls a 300-paragraph lazy document from top to bottom and
// back in viewport-sized steps, timing every pumped frame.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'scroll frame timing over a 300-paragraph lazy document',
    (tester) async {
      final buffer = StringBuffer();
      for (var i = 0; i < 300; i++) {
        buffer.write(
          '<p>段落 $i。Weft engine lays out mixed English and 中文内容 at a '
          'fixed 360px viewport, exercising line breaking and deterministic '
          'wrapping for the scroll frame benchmark.</p>',
        );
      }
      final document = const WeftNormalizer().normalize(
        buffer.toString(),
        id: 'scroll-frames',
      );
      final scroll = ScrollController();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            controller: scroll,
            child: WeftSurface(
              document: document,
              enableLazyLayout: true,
              viewportHeight: 800,
            ),
          ),
        ),
      );
      final render = tester.renderObject<RenderWeftSurface>(
        find.byType(WeftSurface),
      );
      scroll.addListener(() => render.setViewportPixels(scroll.offset));
      final maxExtent = scroll.position.maxScrollExtent;
      // ignore: invalid_use_of_visible_for_testing_member
      expect(render.debugLayout!.debugIsLazy, isTrue);

      final frameTimes = <double>[];
      // Downward in half-viewport steps, then back up, timing each frame.
      final offsets = <double>[
        for (var offset = 0.0; offset < maxExtent; offset += 400) offset,
        for (var offset = maxExtent; offset > 0; offset -= 400) offset,
      ];
      for (final offset in offsets) {
        final watch = Stopwatch()..start();
        scroll.jumpTo(offset);
        await tester.pump();
        watch.stop();
        frameTimes.add(watch.elapsedMicroseconds / 1000.0);
      }

      final sorted = frameTimes.toList()..sort();
      double percentile(double p) {
        final index = math.min(
          sorted.length - 1,
          (p * sorted.length).ceil(),
        );
        return sorted[index];
      }

      final median = percentile(0.5);
      final p95 = percentile(0.95);
      final p99 = percentile(0.99);
      // ignore: avoid_print
      print(
        'scroll frames measured: ${frameTimes.length}  '
        'median ${median.toStringAsFixed(1)}ms  '
        'p95 ${p95.toStringAsFixed(1)}ms  p99 ${p99.toStringAsFixed(1)}ms  '
        'max ${sorted.last.toStringAsFixed(1)}ms',
      );
      scroll.dispose();
    },
    semanticsEnabled: false,
  );
}
