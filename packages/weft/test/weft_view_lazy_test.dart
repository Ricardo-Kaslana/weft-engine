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
  ScrollController? scroll,
) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 400,
          child: WeftView(
            controller: controller,
            scrollController: scroll,
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
