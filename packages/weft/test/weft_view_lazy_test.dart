import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  testWidgets('visible-first lazy layout follows controller scrolling', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);

    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.enableLazyLayout, isTrue);
    expect(tester.getSize(find.byType(WeftView)), const Size(320, 400));
    expect(render.viewportHeight, 400);
    final probe = const WeftLayoutEngine().layoutViewport(
      controller.document!,
      width: 320,
      viewportStart: 0,
      viewportEnd: 650,
    );
    expect(probe.debugIsLazy, isTrue);
    probe.dispose();
    expect(render.debugFullLayoutRequired, isFalse,
        reason: render.debugFullLayoutReason);
    expect(render.debugViewportPixels, 0);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThan(120));
    final firstMaterialized = render.debugLayout!.debugMaterializedBlockCount;
    final firstNodes =
        render.debugLayout!.commands.map((command) => command.nodeId).toSet();
    expect(firstMaterialized, greaterThan(0));
    expect(scroll.position.maxScrollExtent, greaterThan(0));

    scroll.jumpTo(3000);
    await tester.pump();
    final scrolled = render.debugLayout!;
    expect(scrolled.debugIsLazy, isTrue);
    // ADR 0031: a deep jump measures at most a block budget per frame, so the
    // first frame may not cover the new window yet; the post-frame
    // continuation fills it over subsequent frames instead of stalling one
    // long frame.
    expect(scrolled.commands, isEmpty);
    for (var i = 0; i < 12 && render.debugLayout!.commands.isEmpty; i++) {
      await tester.pump();
    }
    final settled = render.debugLayout!;
    expect(settled.debugIsLazy, isTrue);
    expect(settled.commands, isNotEmpty);
    expect(
      settled.commands.map((command) => command.nodeId).toSet(),
      isNot(equals(firstNodes)),
    );
    // The converged extent matches a canonical full layout of the document.
    final canonical = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    addTearDown(canonical.dispose);
    expect(settled.size, canonical.size);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('formatted body stays lazy and reuses its window index', (
    tester,
  ) async {
    const paragraphs = 600;
    final controller = _formattedController(paragraphs);
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final first = render.debugLayout!;
    expect(controller.document!.body!.children.length, greaterThan(paragraphs));
    expect(first.debugIsLazy, isTrue);
    expect(render.debugFullLayoutRequired, isFalse);
    expect(first.incrementalCache!.childCount, paragraphs);
    expect(first.incrementalCache!.measuredPrefixLength, lessThan(paragraphs));
    expect(first.debugLaidOutBlockCount, lessThan(paragraphs));
    expect(first.commands, isNotEmpty);

    scroll.jumpTo(1200);
    await _settle(tester);
    final warm = render.debugLayout!;
    expect(warm.debugIsLazy, isTrue);
    expect(warm.commands, isNotEmpty);
    expect(warm.debugEligibilityVisitCount, 0);
    expect(warm.debugVisitedBlockCount, lessThan(120));
    expect(warm.debugEstimatedBlockCount, lessThan(120));
    expect(warm.incrementalCache!.childCount, paragraphs);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('formatting text ordinals do not keep budgeted frames alive', (
    tester,
  ) async {
    const paragraphs = 96;
    final controller = _formattedController(paragraphs);
    // A deep seed must stop after flow entries, not raw formatting nodes, end.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: WeftSurface(
            document: controller.document!,
            enableLazyLayout: true,
            viewportHeight: 400,
            initialViewportPixels: 1000000,
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
    expect(await _settle(tester), lessThan(16));
    final settled = render.debugLayout!;
    final cache = settled.incrementalCache!;
    expect(cache.childCount, paragraphs);
    expect(cache.measuredPrefixLength, paragraphs);
    expect(cache.measuredPrefixLength,
        lessThan(controller.document!.body!.children.length));
    expect(cache.viewportState!.measuredEnd, double.infinity);
    expect(cache.viewportState!.needsLayout(1000000, 1000650), isFalse);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      expect(render.debugLayout, same(settled));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('initial controller offset seeds the first lazy window', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController(initialScrollOffset: 800);
    await _pump(tester, controller, scroll);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugViewportPixels, 800);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    final fresh = const WeftLayoutEngine().layoutViewport(
      controller.document!,
      width: 320,
      viewportStart: 550,
      viewportEnd: 1450,
    );
    addTearDown(fresh.dispose);
    expect(render.debugLayout!.commands, hasLength(fresh.commands.length));
    for (var i = 0; i < fresh.commands.length; i++) {
      expect(render.debugLayout!.commands[i].nodeId, fresh.commands[i].nodeId);
      expect(render.debugLayout!.commands[i].bounds, fresh.commands[i].bounds);
    }
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('selection present before first pump forces full layout', (
    tester,
  ) async {
    final controller = _controller(80);
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entries = probe.textIndex!.entries;
    controller.updateSelection(
      TextSelectionRange(
        anchor: TextAnchor(entries.first.nodeId, 0),
        extent: TextAnchor(entries.last.nodeId, 1),
      ),
    );
    probe.dispose();
    await _pump(tester, controller, null);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugFullLayoutRequired, isTrue);
    expect(render.debugFullLayoutReason, 'selection');
    expect(render.debugLayout!.debugIsLazy, isFalse);
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('height-only blocks do not relayout for a one-pixel scroll', (
    tester,
  ) async {
    final html = StringBuffer();
    for (var i = 0; i < 40; i++) {
      html.write('<div style="height: 24px"></div>');
    }
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          html.toString(),
          id: 'lazy-height-only-view',
        ),
      );
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final before = render.debugLayout!;
    expect(before.debugIsLazy, isTrue);
    scroll.jumpTo(1);
    await tester.pump();
    expect(identical(render.debugLayout, before), isTrue);
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('constraint changes keep the lazy window canonical', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    scroll.jumpTo(600);
    await tester.pump();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 260,
            height: 320,
            child: WeftView(
              controller: controller,
              scrollController: scroll,
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.viewportHeight, 320);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    final fresh = const WeftLayoutEngine().layoutViewport(
      controller.document!,
      width: 260,
      viewportStart: 350,
      viewportEnd: 1170,
    );
    addTearDown(fresh.dispose);
    expect(render.debugLayout!.commands, hasLength(fresh.commands.length));
    for (var i = 0; i < fresh.commands.length; i++) {
      expect(render.debugLayout!.commands[i].nodeId, fresh.commands[i].nodeId);
      expect(render.debugLayout!.commands[i].bounds, fresh.commands[i].bounds);
    }
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('scrollToAnchor keeps lazy and honors alignment and clamp', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final state = viewKey.currentState!;
    expect(render.debugLayout!.debugIsLazy, isTrue);

    expect(
      state.scrollToAnchor(const TextAnchor(999999, 0)),
      isFalse,
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(scroll.offset, 0);

    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.firstWhere(
      (candidate) => candidate.text.startsWith('Paragraph 100 '),
    );
    final targetRect = probe.textRectsForNode(entry.nodeId, 2, 3).first;
    final lastEntry = probe.textIndex!.entries.last;
    final lastRect = probe.textRectsForNode(lastEntry.nodeId, 0, 1).first;
    probe.dispose();

    expect(
      state.scrollToAnchor(TextAnchor(entry.nodeId, 2), alignment: 0.5),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugFullLayoutReason, isNull);
    final position = scroll.position;
    final expected = (targetRect.top -
            0.5 * (position.viewportDimension - targetRect.height))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    expect(scroll.offset, closeTo(expected, 0.01));

    expect(
      state.scrollToAnchor(TextAnchor(lastEntry.nodeId, 0), alignment: 1),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    final expectedLast =
        (lastRect.top - (position.viewportDimension - lastRect.height))
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    expect(scroll.offset, closeTo(expectedLast, 0.01));
    expect(lastRect.top, greaterThan(0));

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('scrollToAnchorAsync maps formatted ordinals without blanking', (
    tester,
  ) async {
    final controller = _formattedController(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final body = controller.document!.body!;
    final paragraph = body.children.whereType<WeftElement>().elementAt(100);
    expect(body.children.indexOf(paragraph), greaterThan(120));
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.firstWhere(
      (candidate) => candidate.text.startsWith('Paragraph 100 '),
    );
    final targetRect = probe.textRectsForNode(entry.nodeId, 2, 3).first;
    probe.dispose();

    final future = viewKey.currentState!.scrollToAnchorAsync(
      TextAnchor(entry.nodeId, 2),
      alignment: 0.5,
      maxNewBlocks: 4,
    );
    bool? result;
    var completed = false;
    future.then((value) {
      result = value;
      completed = true;
    });
    await tester.pump();
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.commands, isNotEmpty);
    expect(scroll.offset, 0);
    expect(completed, isFalse);
    for (var frame = 0; frame < 80 && !completed; frame++) {
      await tester.pump();
      expect(render.debugLayout!.commands, isNotEmpty);
    }
    expect(completed, isTrue);
    expect(result, isTrue);
    await _settle(tester);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugFullLayoutReason, isNull);
    final position = scroll.position;
    final expected = (targetRect.top -
            0.5 * (position.viewportDimension - targetRect.height))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    expect(scroll.offset, closeTo(expected, 0.01));
    expect(render.debugLayout!.textRectsForNode(entry.nodeId, 2, 3).first,
        targetRect);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('scrollToNode targets the first text inside an element', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final paragraph = (controller.document!.body!.children[80] as WeftElement);
    expect(
      viewKey.currentState!.scrollToNode(paragraph.id),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('scrollToNodeAsync targets a formatted element across frames', (
    tester,
  ) async {
    final controller = _formattedController(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final body = controller.document!.body!;
    final paragraph = body.children.whereType<WeftElement>().elementAt(90);
    expect(body.children.indexOf(paragraph), greaterThan(120));

    final future = viewKey.currentState!.scrollToNodeAsync(
      paragraph.id,
      maxNewBlocks: 4,
    );
    bool? result;
    var completed = false;
    future.then((value) {
      result = value;
      completed = true;
    });
    for (var frame = 0; frame < 80 && !completed; frame++) {
      await tester.pump();
    }
    expect(completed, isTrue);
    expect(result, isTrue);
    await tester.pump();
    await tester.pump();
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(scroll.offset, greaterThan(0));

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  for (final cancellation in [
    'new navigation',
    'document replacement',
    'unmount',
  ]) {
    testWidgets('async focus is cancelled by $cancellation', (tester) async {
      final controller = _formattedController(120);
      final scroll = ScrollController();
      final viewKey = GlobalKey<WeftViewState>();
      await _pump(tester, controller, scroll, viewKey: viewKey);
      final render = tester.renderObject<RenderWeftSurface>(
        find.byType(WeftSurface),
      );
      final entries = render.debugLayout!.textIndex!.entries;
      final far = entries.firstWhere(
        (entry) => entry.text.startsWith('Paragraph 110 '),
      );
      bool? result;
      viewKey.currentState!
          .scrollToAnchorAsync(TextAnchor(far.nodeId, 0), maxNewBlocks: 1)
          .then((value) => result = value);
      await tester.pump();
      expect(result, isNull);
      expect(scroll.offset, 0);

      if (cancellation == 'new navigation') {
        final nearer = entries.firstWhere(
          (entry) => entry.text.startsWith('Paragraph 60 '),
        );
        bool? replacementResult;
        viewKey.currentState!
            .scrollToAnchorAsync(TextAnchor(nearer.nodeId, 0), maxNewBlocks: 4)
            .then((value) => replacementResult = value);
        await _settle(tester);
        expect(replacementResult, isTrue);
        expect(scroll.offset, greaterThan(0));
        expect(render.debugLayout!.debugIsLazy, isTrue);
      } else if (cancellation == 'document replacement') {
        final document = controller.document!;
        controller.loadDocument(
          const WeftNormalizer().normalize(
            '<body>\n<p>Replacement</p>\n</body>',
            id: document.id,
            revision: document.revision + 1,
          ),
        );
        await _settle(tester);
        expect(scroll.offset, 0);
        expect(render.document, same(controller.document));
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
        await _settle(tester);
      }
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
      scroll.dispose();
      controller.dispose();
    }, semanticsEnabled: false);
  }

  testWidgets('scrollToAnchor uses the internal controller when none injected',
      (
    tester,
  ) async {
    final controller = _controller(120);
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, null, viewKey: viewKey);
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.firstWhere(
      (candidate) => candidate.text.startsWith('Paragraph 80 '),
    );
    final rect = probe.textRectsForNode(entry.nodeId, 0, 1).first;
    probe.dispose();

    expect(
      viewKey.currentState!.scrollToAnchor(TextAnchor(entry.nodeId, 0)),
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(
      position.pixels,
      closeTo(
        rect.top.clamp(position.minScrollExtent, position.maxScrollExtent),
        0.01,
      ),
    );
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('pending anchor scroll is discarded when the view unmounts', (
    tester,
  ) async {
    final controller = _controller(80);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.last;
    probe.dispose();
    expect(
      viewKey.currentState!.scrollToAnchor(TextAnchor(entry.nodeId, 0)),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('lazyOverscan controls the materialized window', (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    await _pump(tester, controller, scroll, lazyOverscan: 0);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final fresh = const WeftLayoutEngine().layoutViewport(
      controller.document!,
      width: 320,
      viewportStart: 0,
      viewportEnd: 400,
    );
    addTearDown(fresh.dispose);
    expect(render.debugLayout!.commands, hasLength(fresh.commands.length));
    for (var i = 0; i < fresh.commands.length; i++) {
      expect(render.debugLayout!.commands[i].nodeId, fresh.commands[i].nodeId);
    }
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('enableLazyLayout false keeps the canonical full layout', (
    tester,
  ) async {
    final controller = _controller(80);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 400,
            child: WeftView(
              controller: controller,
              enableLazyLayout: false,
            ),
          ),
        ),
      ),
    );

    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugLayout!.debugLaidOutBlockCount, 80);
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('expanded selection cancels async focus and stays full', (
    tester,
  ) async {
    final controller = _formattedController(80);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entries = probe.textIndex!.entries;
    final first = entries.firstWhere(
      (entry) => entry.text.startsWith('Paragraph 0 '),
    );
    final third = entries.firstWhere(
      (entry) => entry.text.startsWith('Paragraph 2 '),
    );
    final far = entries.firstWhere(
      (entry) => entry.text.startsWith('Paragraph 70 '),
    );
    final selection = TextSelectionRange(
      anchor: TextAnchor(first.nodeId, 0),
      extent: TextAnchor(third.nodeId, 3),
    );
    final selectedText = probe.selectionText(selection);
    final canonicalSize = probe.size;
    probe.dispose();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    bool? navigationResult;
    viewKey.currentState!
        .scrollToAnchorAsync(TextAnchor(far.nodeId, 0), maxNewBlocks: 1)
        .then((value) => navigationResult = value);
    await tester.pump();
    expect(navigationResult, isNull);

    controller.updateSelection(selection);
    await _settle(tester);
    expect(navigationResult, isFalse);
    expect(scroll.offset, 0);
    expect(render.debugFullLayoutRequired, isTrue);
    expect(render.debugFullLayoutReason, 'selection');
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugLayout!.size, canonicalSize);
    expect(render.selectionText(selection), selectedText);
    expect(render.debugPendingLazyCorrection, 0);

    controller.updateSelection(null);
    await tester.pump();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await _settle(tester);
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugFullLayoutRequired, isTrue);
    expect(render.debugFullLayoutReason, 'selection');
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('jumping to the estimated bottom follows extent corrections', (
    tester,
  ) async {
    final controller = _controllerWithTallTail();
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    final initialMax = scroll.position.maxScrollExtent;
    expect(initialMax, greaterThan(0));

    scroll.jumpTo(initialMax);
    await tester.pump();
    await tester.pump();
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(scroll.position.maxScrollExtent, greaterThan(initialMax));
    expect(
      scroll.offset,
      closeTo(scroll.position.maxScrollExtent, 1),
    );
    await _settle(tester);
    final cache = render.debugLayout!.incrementalCache!;
    expect(cache.measuredPrefixLength, cache.childCount);
    expect(render.debugViewportPixels, scroll.offset);
    expect(render.debugPendingLazyCorrection, 0);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('fully measured round trips keep extent and corrections stable', (
    tester,
  ) async {
    final controller = _controllerWithTallTail(formatted: true);
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final canonical = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    addTearDown(canonical.dispose);
    for (var pass = 0; pass < 20; pass++) {
      final cache = render.debugLayout!.incrementalCache!;
      if (cache.measuredPrefixLength == cache.childCount) break;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await _settle(tester);
    }
    final measured = render.debugLayout!;
    expect(measured.debugIsLazy, isTrue);
    expect(measured.incrementalCache!.measuredPrefixLength,
        measured.incrementalCache!.childCount);
    expect(
        measured.incrementalCache!.viewportState!.measuredEnd, double.infinity);
    expect(measured.size, canonical.size);
    expect(render.debugLazyCorrectionCount, greaterThan(0));
    final height = measured.size.height;
    final maxExtent = scroll.position.maxScrollExtent;
    final correctionCount = render.debugLazyCorrectionCount;

    for (final fraction in [0.0, 0.5, 1.0, 0.25, 1.0, 0.0, 1.0]) {
      final target = maxExtent * fraction;
      scroll.jumpTo(target);
      await _settle(tester);
      final revisited = render.debugLayout!;
      expect(revisited.debugIsLazy, isTrue);
      expect(revisited.commands, isNotEmpty);
      expect(revisited.size.height, height);
      expect(scroll.position.maxScrollExtent, maxExtent);
      expect(scroll.offset, closeTo(target, 0.01));
      expect(render.debugFollowLazyBottom, isFalse);
      expect(render.debugPendingLazyCorrection, 0);
      expect(render.debugLazyCorrectionCount, correctionCount);
      expect(revisited.debugEligibilityVisitCount, 0);
      expect(revisited.debugEstimatedBlockCount, 0);
      expect(revisited.debugVisitedBlockCount, lessThan(120));
    }
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('Semantics at the estimated bottom cancels lazy correction', (
    tester,
  ) async {
    final controller = _controllerWithTallTail();
    final scroll = ScrollController();
    await _pump(tester, controller, scroll);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugFollowLazyBottom, isTrue);

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugFollowLazyBottom, isFalse);
    expect(render.debugPendingLazyCorrection, 0);
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));

    semantics.dispose();
    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('streaming tail updates preserve the lazy layout path', (
    tester,
  ) async {
    final controller = _controller(120);
    await _pump(tester, controller, null);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);

    final html = StringBuffer();
    for (var i = 0; i < 121; i++) {
      html.write('<p>${_paragraphLabel(i)}</p>');
    }
    controller.loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'lazy-view'),
    );
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThan(121));
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('image request discovery is cached without suppressing retries', (
    tester,
  ) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p><img src="memory://first" alt="First"></p>',
          id: 'lazy-image-requests',
        ),
      );
    final requests = <WeftImageRequest>[];
    var fail = true;
    await _pump(tester, controller, null, imageResolver: (request) {
      requests.add(request);
      if (fail) throw StateError('Image is not available yet');
      return null;
    });
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(requests, isNotEmpty);
    final first = requests.first;
    for (final shouldFail in [false, true, false]) {
      fail = shouldFail;
      final before = requests.length;
      render.markNeedsLayout();
      await tester.pump();
      expect(requests.length, greaterThan(before));
      expect(requests.last, same(first));
    }
    render.imageResolver = (request) {
      requests.add(request);
      return null;
    };
    final beforeResolverChange = requests.length;
    await tester.pump();
    expect(requests.length, greaterThan(beforeResolverChange));
    expect(requests.last, same(first));

    // Matching id/revision is not enough: a new snapshot rebuilds discovery.
    final document = controller.document!;
    controller.loadDocument(
      const WeftNormalizer().normalize(
        '<p><img src="memory://second" alt="Second"></p>',
        id: document.id,
        revision: document.revision,
      ),
    );
    await tester.pump();
    expect(requests.last, isNot(same(first)));
    expect(requests.last.src, 'memory://second');
    expect(requests.last.alt, 'Second');

    controller.loadDocument(
      const WeftNormalizer().normalize(
        '<p>No image</p>',
        id: document.id,
        revision: document.revision,
      ),
    );
    final beforeRemoval = requests.length;
    await tester.pump();
    render.markNeedsLayout();
    await tester.pump();
    expect(requests, hasLength(beforeRemoval));
    expect(tester.takeException(), isNull);
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('global Float input conservatively uses the full layout', (
    tester,
  ) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p>Before</p><img src="asset:float.png" style="float:left">'
          '<p>Wrapping text</p>',
          id: 'lazy-float',
        ),
      );
    await _pump(tester, controller, null);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugFullLayoutRequired, isTrue);
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('enabling Semantics upgrades lazy layout to the full document', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller(80);
    await _pump(tester, controller, null);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(find.semantics.byLabel(_paragraphLabel(79)), findsOneWidget);
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugLayout!.debugLaidOutBlockCount, 80);

    controller.dispose();
    semantics.dispose();
  });
}

Future<void> _pump(
  WidgetTester tester,
  WeftController controller,
  ScrollController? scroll, {
  GlobalKey<WeftViewState>? viewKey,
  double lazyOverscan = 250,
  WeftImageResolver? imageResolver,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 400,
          child: WeftView(
            key: viewKey,
            controller: controller,
            scrollController: scroll,
            lazyOverscan: lazyOverscan,
            imageResolver: imageResolver,
          ),
        ),
      ),
    ),
  );
}

Future<int> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

WeftController _formattedController(int paragraphs) {
  final html = StringBuffer('<body>\n');
  for (var i = 0; i < paragraphs; i++) {
    html.writeln('  <p>${_paragraphLabel(i)}</p>');
  }
  html.write('</body>');
  return WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'lazy-formatted'),
    );
}

WeftController _controller(int paragraphs) {
  final html = StringBuffer();
  for (var i = 0; i < paragraphs; i++) {
    html.write('<p>${_paragraphLabel(i)}</p>');
  }
  return WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'lazy-view'),
    );
}

WeftController _controllerWithTallTail({bool formatted = false}) {
  final html = StringBuffer();
  for (var i = 0; i < 10; i++) {
    html.write('<p>Short $i</p>');
    if (formatted) html.write('\n  ');
  }
  for (var i = 10; i < 120; i++) {
    html.write('<p>${'Long paragraph body text ' * 40} $i</p>');
    if (formatted) html.write('\n  ');
  }
  return WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'lazy-tall-tail'),
    );
}

String _paragraphLabel(int index) {
  return 'Paragraph $index lazy viewport body text.';
}
