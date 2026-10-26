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
    expect(scrolled.debugMaterializedBlockCount, greaterThan(0));
    expect(scrolled.commands, isNotEmpty);
    expect(
      scrolled.commands.map((command) => command.nodeId).toSet(),
      isNot(equals(firstNodes)),
    );

    scroll.dispose();
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

  testWidgets('scrollToAnchorAsync measures across frames without blanking', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.firstWhere(
      (candidate) => candidate.text.startsWith('Paragraph 100 '),
    );
    probe.dispose();

    final future = viewKey.currentState!.scrollToAnchorAsync(
      TextAnchor(entry.nodeId, 0),
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
    for (var frame = 0; frame < 80 && !completed; frame++) {
      await tester.pump();
    }
    expect(completed, isTrue);
    expect(result, isTrue);
    await tester.pump();
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(scroll.offset, greaterThan(0));

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

  testWidgets('scrollToNodeAsync targets an element across frames', (
    tester,
  ) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final viewKey = GlobalKey<WeftViewState>();
    await _pump(tester, controller, scroll, viewKey: viewKey);
    final paragraph = controller.document!.body!.children[90] as WeftElement;

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

  testWidgets('expanded selection upgrades lazy layout and stays full', (
    tester,
  ) async {
    final controller = _controller(80);
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entries = probe.textIndex!.entries;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entries[0].nodeId, 0),
      extent: TextAnchor(entries[2].nodeId, 3),
    );
    probe.dispose();
    await _pump(tester, controller, null);
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugLayout!.debugIsLazy, isTrue);

    controller.updateSelection(selection);
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(render.debugLayout!.commands, isNotEmpty);

    controller.updateSelection(null);
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isFalse);
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
          ),
        ),
      ),
    ),
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

WeftController _controllerWithTallTail() {
  final html = StringBuffer();
  for (var i = 0; i < 10; i++) {
    html.write('<p>Short $i</p>');
  }
  for (var i = 10; i < 120; i++) {
    html.write('<p>${'Long paragraph body text ' * 40} $i</p>');
  }
  return WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'lazy-tall-tail'),
    );
}

String _paragraphLabel(int index) {
  return 'Paragraph $index lazy viewport body text.';
}
