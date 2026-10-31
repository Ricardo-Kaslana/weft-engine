import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

const _overlayKey = ValueKey<String>('settling-overlay');

void main() {
  testWidgets(
      'deep jump shows the host overlay until the target window settles',
      (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final state = viewKey.currentState!;
    expect(render.isLazySettling, isFalse);
    expect(state.isLazySettling, isFalse);
    expect(find.byKey(_overlayKey), findsNothing);

    scroll.jumpTo(15000);
    await tester.pump();
    expect(render.isLazySettling, isTrue);
    expect(state.isLazySettling, isTrue);
    expect(values, [true]);
    expect(render.debugLayout!.commands, isEmpty);
    expect(find.byKey(_overlayKey), findsNothing);
    await tester.pump();
    expect(find.byKey(_overlayKey), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(_overlayKey),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );

    await _settle(tester);
    expect(render.isLazySettling, isFalse);
    expect(state.isLazySettling, isFalse);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values, [true, false]);
    expect(render.debugLayout!.commands, isNotEmpty);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('settling signal works without an overlay builder',
      (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final state = viewKey.currentState!;
    scroll.jumpTo(15000);
    await tester.pump();
    expect(render.isLazySettling, isTrue);
    expect(state.isLazySettling, isTrue);
    expect(values, [true]);
    expect(find.byKey(_overlayKey), findsNothing);

    await _settle(tester);
    expect(state.isLazySettling, isFalse);
    expect(values, [true, false]);
    expect(find.byKey(_overlayKey), findsNothing);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('initial deep offset seeds settling and clears it',
      (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController(initialScrollOffset: 15000);
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final state = viewKey.currentState!;
    expect(render.debugLayout!.debugLaidOutBlockCount, lessThanOrEqualTo(32));
    expect(render.isLazySettling, isTrue);
    expect(values, [true]);
    await tester.pump();
    expect(find.byKey(_overlayKey), findsOneWidget);

    await _settle(tester);
    expect(render.isLazySettling, isFalse);
    expect(state.isLazySettling, isFalse);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values, [true, false]);
    expect(render.debugLayout!.commands, isNotEmpty);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('near-frontier scroll never enters settling', (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    scroll.jumpTo(200);
    await tester.pump();
    await tester.pump();
    expect(render.isLazySettling, isFalse);
    expect(viewKey.currentState!.isLazySettling, isFalse);
    expect(values, isEmpty);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(render.debugLayout!.commands, isNotEmpty);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('async anchor measurement keeps content and never shows overlay',
      (tester) async {
    final controller = _formattedController(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.firstWhere(
      (candidate) => candidate.text.startsWith('Paragraph 100 '),
    );
    probe.dispose();

    var completed = false;
    bool? result;
    viewKey.currentState!
        .scrollToAnchorAsync(
      TextAnchor(entry.nodeId, 2),
      alignment: 0.5,
      maxNewBlocks: 4,
    )
        .then((value) {
      result = value;
      completed = true;
    });
    await tester.pump();
    expect(values, isEmpty);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(render.debugLayout!.commands, isNotEmpty);
    for (var frame = 0; frame < 80 && !completed; frame++) {
      await tester.pump();
      expect(values, isEmpty);
      expect(find.byKey(_overlayKey), findsNothing);
    }
    expect(completed, isTrue);
    expect(result, isTrue);
    expect(values, isEmpty);

    await _settle(tester);
    expect(find.byKey(_overlayKey), findsNothing);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('bottom-follow jump keeps the overlay until the tail settles',
      (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(render.isLazySettling, isTrue);
    expect(values, [true]);
    await tester.pump();
    expect(find.byKey(_overlayKey), findsOneWidget);

    await _settle(tester);
    expect(render.isLazySettling, isFalse);
    expect(values, [true, false]);
    expect(render.debugPendingLazyCorrection, 0);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(scroll.offset, greaterThan(0));

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('document replacement clears settling and reports false',
      (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final state = viewKey.currentState!;
    scroll.jumpTo(15000);
    await tester.pump();
    await tester.pump();
    expect(state.isLazySettling, isTrue);
    expect(find.byKey(_overlayKey), findsOneWidget);
    expect(values, [true]);

    controller.loadDocument(
      const WeftNormalizer().normalize(
        '<p>replacement</p>',
        id: 'settling-replacement',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(state.isLazySettling, isFalse);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values.last, isFalse);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('selection full upgrade cancels settling', (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    scroll.jumpTo(15000);
    await tester.pump();
    await tester.pump();
    expect(render.isLazySettling, isTrue);
    expect(find.byKey(_overlayKey), findsOneWidget);

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
    await tester.pump();
    await tester.pump();
    expect(render.isLazySettling, isFalse);
    expect(render.debugFullLayoutRequired, isTrue);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values.last, isFalse);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('disabled lazy layout never shows the overlay', (tester) async {
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
      enableLazyLayout: false,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    scroll.jumpTo(15000);
    await tester.pump();
    await tester.pump();
    expect(render.debugLayout!.debugIsLazy, isFalse);
    expect(viewKey.currentState!.isLazySettling, isFalse);
    expect(values, isEmpty);
    expect(find.byKey(_overlayKey), findsNothing);

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);

  testWidgets('Semantics keeps lazy deep jumps settling with the overlay',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = _controller(120);
    final scroll = ScrollController();
    final values = <bool>[];
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(
      tester,
      controller,
      scroll,
      viewKey: viewKey,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    final state = viewKey.currentState!;
    // ADR 0041: semantics no longer upgrades to a full layout, so a deep
    // jump with a screen reader active settles through the host overlay.
    scroll.jumpTo(15000);
    await tester.pump();
    expect(render.debugFullLayoutRequired, isFalse);
    expect(render.debugLayout!.debugIsLazy, isTrue);
    expect(render.isLazySettling, isTrue);
    expect(state.isLazySettling, isTrue);
    expect(values, [true]);
    await tester.pump();
    expect(find.byKey(_overlayKey), findsOneWidget);

    await _settle(tester);
    expect(render.isLazySettling, isFalse);
    expect(state.isLazySettling, isFalse);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values, [true, false]);

    scroll.dispose();
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('settled view with an overlay builder schedules no extra frames',
      (tester) async {
    final controller = _controller(3);
    final scroll = ScrollController();
    final values = <bool>[];
    await _pumpView(
      tester,
      controller,
      scroll,
      settlingBuilder: _overlay,
      onSettling: values.add,
    );
    await _settle(tester);
    expect(find.byKey(_overlayKey), findsNothing);
    expect(values, isEmpty);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }

    scroll.dispose();
    controller.dispose();
  }, semanticsEnabled: false);
}

Future<void> _pumpView(
  WidgetTester tester,
  WeftController controller,
  ScrollController? scroll, {
  GlobalKey<WeftViewState>? viewKey,
  WeftLazySettlingBuilder? settlingBuilder,
  ValueChanged<bool>? onSettling,
  bool enableLazyLayout = true,
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
            enableLazyLayout: enableLazyLayout,
            lazySettlingBuilder: settlingBuilder,
            onLazySettlingChanged: onSettling,
          ),
        ),
      ),
    ),
  );
}

Widget _overlay(BuildContext context) {
  return const ColoredBox(
    key: _overlayKey,
    color: Color(0xFFEEEEEE),
  );
}

Future<int> _settle(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}

WeftController _controller(int paragraphs) {
  final html = StringBuffer();
  for (var i = 0; i < paragraphs; i++) {
    html.write('<p>${_paragraphLabel(i)}</p>');
  }
  return WeftController()
    ..loadDocument(
      const WeftNormalizer().normalize(html.toString(), id: 'settling-view'),
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
      const WeftNormalizer().normalize(
        html.toString(),
        id: 'settling-formatted',
      ),
    );
}

String _paragraphLabel(int index) {
  return 'Paragraph $index with enough words to wrap across lines in the '
      'test viewport and keep the document long enough for deep jumps.';
}
