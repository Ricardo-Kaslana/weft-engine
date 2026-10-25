import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  WeftController articleController() {
    final buffer = StringBuffer();
    for (var i = 0; i < 40; i++) {
      buffer.write('<p>Paragraph $i scroll passthrough test body text.</p>');
    }
    return WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(buffer.toString(), id: 'view-scroll'),
      );
  }

  Future<void> pumpView(
    WidgetTester tester,
    WeftController controller,
    ScrollController? scrollController,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 400,
          child: WeftView(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
      ),
    );
  }

  testWidgets('an injected scrollController drives the internal scrolling',
      (tester) async {
    final controller = articleController();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pumpView(tester, controller, scroll);

    expect(scroll.hasClients, isTrue);
    expect(scroll.position.maxScrollExtent, greaterThan(0));

    scroll.jumpTo(120);
    await tester.pump();
    expect(scroll.offset, 120);
    // The content actually moved: the surface top is now above the viewport.
    expect(tester.getTopLeft(find.byType(WeftSurface)).dy, lessThan(0));
    controller.dispose();
  });

  testWidgets('dragging the content scrolls without an injected controller',
      (tester) async {
    final controller = articleController();
    await pumpView(tester, controller, null);

    expect(find.byType(Scrollable), findsOneWidget);
    // Drag the view, not the surface: the surface is laid out at the full
    // document height, so its center sits far below the visible viewport.
    await tester.drag(find.byType(WeftView), const Offset(0, -200));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(
          find.byType(Scrollable),
        )
        .position;
    expect(position.pixels, greaterThan(0));
    controller.dispose();
  });

  testWidgets('the internal scroll view never joins the primary scroll group',
      (tester) async {
    final controller = articleController();
    final primary = ScrollController();
    addTearDown(primary.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PrimaryScrollController(
          controller: primary,
          child: SizedBox(
            width: 320,
            height: 400,
            child: WeftView(controller: controller),
          ),
        ),
      ),
    );

    // primary: false keeps the view's scroll view off the ambient
    // PrimaryScrollController even though no explicit controller is given.
    expect(primary.hasClients, isFalse);
    expect(find.byType(Scrollable), findsOneWidget);
    controller.dispose();
  });
}
