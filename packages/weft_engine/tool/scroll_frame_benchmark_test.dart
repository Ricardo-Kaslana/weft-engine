// Host Stopwatch timings include harness costs, not device FrameTiming budgets.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const _viewportWidth = 360.0;
const _viewportHeight = 800.0;
const _blockBudget = 32;
const _roundTrips = 20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'scroll pump timing over 300 paragraphs (test harness)',
    (tester) async {
      final document = _document(300, newlineSeparated: false);
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
      final initialLayout = render.debugLayout!;
      // ignore: avoid_print
      print(
        'pump structure: elements='
        '${document.body!.children.whereType<WeftElement>().length} '
        'rawBodyChildren=${document.body!.children.length} '
        'width=${render.size.width} debugIsLazy=${initialLayout.debugIsLazy} '
        'laidOut=${initialLayout.debugLaidOutBlockCount} '
        'materialized=${initialLayout.debugMaterializedBlockCount}',
      );

      final frameTimes = <double>[];
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
      // ignore: avoid_print
      print(
        'pump mixed-cache harness samples=${frameTimes.length} (not FrameTiming) '
        'p50=${_percentile(sorted, 0.50).toStringAsFixed(3)}ms '
        'p95=${_percentile(sorted, 0.95).toStringAsFixed(3)}ms '
        'p99=${_percentile(sorted, 0.99).toStringAsFixed(3)}ms '
        'max=${sorted.last.toStringAsFixed(3)}ms',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    },
    semanticsEnabled: false,
  );

  for (final count in [300, 1000]) {
    for (final newlineSeparated in [false, true]) {
      final shape = newlineSeparated ? 'newline' : 'compact';
      test('layoutViewport same-snapshot $count plain p / $shape', () {
        _profileViewport(count, newlineSeparated: newlineSeparated);
      });
    }
  }
}

WeftDocumentSnapshot _document(int count, {required bool newlineSeparated}) {
  final paragraphs = <String>[
    for (var i = 0; i < count; i++)
      '<p>段落 $i。Weft engine lays out mixed English and 中文内容 at a '
          'fixed 360px viewport, exercising line breaking and deterministic '
          'wrapping for the scroll frame benchmark.</p>',
  ];
  final document = const WeftNormalizer().normalize(
    paragraphs.join(newlineSeparated ? '\n' : ''),
    id: 'scroll-profile-$count-${newlineSeparated ? 'newline' : 'compact'}',
  );
  expect(document.supportReport.canRender, isTrue);
  return document;
}

void _profileViewport(int count, {required bool newlineSeparated}) {
  const engine = WeftLayoutEngine();
  final document = _document(count, newlineSeparated: newlineSeparated);
  final body = document.body!;
  final elements = body.children.whereType<WeftElement>().toList();
  expect(elements, hasLength(count));
  expect(elements.every((element) => element.tag == 'p'), isTrue);
  final firstText = elements.first.children.whereType<WeftText>().first;
  final lastText = elements.last.children.whereType<WeftText>().last;
  final label = '$count/${newlineSeparated ? 'newline' : 'compact'}';
  WeftLayoutResult? current;
  addTearDown(() => current?.dispose());

  // ignore: avoid_print
  print(
    'engine $label elements=${elements.length} '
    'rawBodyChildren=${body.children.length} '
    'width=$_viewportWidth viewportHeight=$_viewportHeight budget=$_blockBudget '
    'sameSnapshot=true; cold=geometry discovery, warm=fully measured; '
    'layoutViewport Stopwatch only, not FrameTiming; VM/JIT not reset',
  );

  _PassSample pass(
    String phase,
    int number,
    double start, {
    NodeId? focusNodeId,
  }) {
    final previous = current;
    final watch = Stopwatch()..start();
    final next = engine.layoutViewport(
      document,
      width: _viewportWidth,
      viewportStart: start,
      viewportEnd: start + _viewportHeight,
      focusNodeId: focusNodeId,
      maxNewBlocks: _blockBudget,
      previous: previous,
    );
    watch.stop();
    current = next;
    previous?.dispose();
    final sample = _PassSample(
      watch.elapsedMicroseconds / 1000.0,
      next.debugLaidOutBlockCount,
      next.debugMaterializedBlockCount,
    );
    // ignore: avoid_print
    print(
      'engine $label $phase pass=$number start=${start.toStringAsFixed(1)} '
      'ms=${sample.ms.toStringAsFixed(3)} debugIsLazy=${next.debugIsLazy} '
      'laidOut=${sample.laidOut} materialized=${sample.materialized} '
      'visited=${next.debugVisitedBlockCount} estimated=${next.debugEstimatedBlockCount} '
      'eligibility=${next.debugEligibilityVisitCount} '
      'measuredPrefix=${next.incrementalCache?.measuredPrefixLength ?? 'none'}'
      '/${next.incrementalCache?.childCount ?? elements.length}',
    );
    if (next.debugIsLazy) {
      expect(next.debugLaidOutBlockCount, lessThanOrEqualTo(_blockBudget));
    }
    return sample;
  }

  bool fullyMeasured() =>
      !current!.debugIsLazy ||
      current!.incrementalCache!.measuredPrefixLength ==
          current!.incrementalCache!.childCount;

  final first = pass('cold-first-viewport', 1, 0);
  // Focus the last real node so an underestimated extent cannot stop discovery.
  final estimatedBottom = math.max(0.0, current!.size.height - _viewportHeight);
  final deepSamples = <_PassSample>[];
  for (var i = 0; i < body.children.length; i++) {
    final oldPrefix = current!.incrementalCache?.measuredPrefixLength ?? 0;
    deepSamples.add(
      pass('cold-deep-jump', i + 1, estimatedBottom, focusNodeId: lastText.id),
    );
    if (fullyMeasured()) break;
    expect(
      current!.incrementalCache?.measuredPrefixLength ?? 0,
      greaterThan(oldPrefix),
      reason: '$label deep jump must advance within the finite pass bound',
    );
  }
  expect(fullyMeasured(), isTrue, reason: '$label must finish discovery');
  expect(current!.textRectsForNode(lastText.id, 0, 1), isNotEmpty);
  final knownHeight = current!.size.height;
  final knownBottom = math.max(0.0, knownHeight - _viewportHeight);
  final deepMs = deepSamples.fold(0.0, (sum, sample) => sum + sample.ms);
  // ignore: avoid_print
  print(
    'engine $label cold-summary firstMs=${first.ms.toStringAsFixed(3)} '
    'deepPasses=${deepSamples.length} deepTotalMs=${deepMs.toStringAsFixed(3)} '
    'deepMaxMs=${deepSamples.map((sample) => sample.ms).reduce(math.max).toStringAsFixed(3)} '
    'fullyMeasured=true knownTop=0.0 knownBottom=${knownBottom.toStringAsFixed(1)} '
    'height=${knownHeight.toStringAsFixed(1)} debugIsLazy=${current!.debugIsLazy}',
  );

  final topSamples = <_PassSample>[];
  final bottomSamples = <_PassSample>[];
  for (var trip = 1; trip <= _roundTrips; trip++) {
    topSamples.add(pass('warm-top', trip, 0));
    expect(fullyMeasured(), isTrue);
    expect(current!.size.height, closeTo(knownHeight, 0.001));
    expect(current!.textRectsForNode(firstText.id, 0, 1), isNotEmpty);
    bottomSamples.add(pass('warm-bottom', trip, knownBottom));
    expect(fullyMeasured(), isTrue);
    expect(current!.size.height, closeTo(knownHeight, 0.001));
    expect(current!.textRectsForNode(lastText.id, 0, 1), isNotEmpty);
  }
  _printWarmSummary(label, 'top', topSamples);
  _printWarmSummary(label, 'bottom', bottomSamples);
  _printWarmSummary(label, 'combined', [...topSamples, ...bottomSamples]);
}

final class _PassSample {
  const _PassSample(this.ms, this.laidOut, this.materialized);

  final double ms;
  final int laidOut;
  final int materialized;
}

void _printWarmSummary(String label, String window, List<_PassSample> samples) {
  final times = samples.map((sample) => sample.ms).toList()..sort();
  final laidOut = samples.map((sample) => sample.laidOut).toList()..sort();
  final materialized = samples.map((sample) => sample.materialized).toList()
    ..sort();
  // ignore: avoid_print
  print(
    'engine $label warm-summary window=$window roundTrips=$_roundTrips '
    'samples=${samples.length} p50=${_percentile(times, 0.50).toStringAsFixed(3)}ms '
    'p95=${_percentile(times, 0.95).toStringAsFixed(3)}ms '
    'laidOutSum=${laidOut.fold(0, (sum, value) => sum + value)} '
    'laidOutRange=${laidOut.first}..${laidOut.last} '
    'materializedSum=${materialized.fold(0, (sum, value) => sum + value)} '
    'materializedRange=${materialized.first}..${materialized.last}',
  );
}

// Nearest-rank percentiles, with zero-based indexing.
double _percentile(List<double> sorted, double p) =>
    sorted[(p * sorted.length).ceil() - 1];
