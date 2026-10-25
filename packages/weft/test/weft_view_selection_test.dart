import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long press selects the word and dragging extends it',
      (tester) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p>alpha bravo</p><p>charlie delta</p>',
          id: 'selection-gestures',
        ),
      );
    final viewKey = GlobalKey<WeftViewState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 320,
          child: WeftView(key: viewKey, controller: controller),
        ),
      ),
    );

    // Reference geometry: "alpha" in the first paragraph, the second
    // paragraph's single line as the drag target.
    final layout = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    addTearDown(layout.dispose);
    final index = layout.textIndex!;
    final firstNode = index.entries[0].nodeId;
    final secondNode = index.entries[1].nodeId;
    final origin = tester.getTopLeft(find.byType(WeftSurface));
    final pressPoint = layout.textRectsForNode(firstNode, 0, 5).first.center;
    final dragTarget = layout.textRectsForNode(secondNode, 0, 13).first.center;

    final gesture = await tester.startGesture(origin + pressPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(controller.selection, isNotNull);
    expect(controller.selection!.anchor, TextAnchor(firstNode, 0));
    expect(controller.selection!.extent, TextAnchor(firstNode, 5));
    expect(viewKey.currentState!.selectionText(), 'alpha');

    await gesture.moveBy(dragTarget - pressPoint);
    await tester.pump();
    expect(
      controller.selection!.anchor,
      TextAnchor(firstNode, 0),
      reason: 'the anchor stays at the long-pressed word start',
    );
    expect(controller.selection!.extent.nodeId, secondNode);
    expect(viewKey.currentState!.selectionText(), startsWith('alpha bravo\n'));

    await gesture.up();
    await tester.pump();

    // Tapping away from any text clears the selection. The point is taken
    // from the actual surface box because the probe layout used for anchors
    // can wrap differently than the width the view ends up laying out at.
    final surfaceSize = tester.getSize(find.byType(WeftSurface));
    await tester.tapAt(
      origin + Offset(surfaceSize.width - 1, surfaceSize.height - 1),
    );
    await tester.pump();
    expect(controller.selection, isNull);
    controller.dispose();
  });

  testWidgets('tap on a link follows it and keeps the selection',
      (tester) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          // A second paragraph gives the selection chrome room below the
          // line, so the copy button's fallback placement does not cover the
          // tapped link itself.
          '<p><a href="https://example.com/help">Help</a> center</p>'
          '<p>More body text follows the link.</p>',
          id: 'selection-link',
        ),
      );
    WeftLinkRegion? tapped;
    final viewKey = GlobalKey<WeftViewState>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 320,
          child: WeftView(
            key: viewKey,
            controller: controller,
            onLinkTap: (link) => tapped = link,
          ),
        ),
      ),
    );

    final layout = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    addTearDown(layout.dispose);
    final helpNode = layout.textIndex!.entries.first.nodeId;
    final origin = tester.getTopLeft(find.byType(WeftSurface));
    final linkPoint = layout.textRectsForNode(helpNode, 0, 4).first.center;

    // Long press the link text first: the created selection must survive a
    // later quick tap because long press owns selection changes.
    final gesture = await tester.startGesture(origin + linkPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final selection = controller.selection;
    expect(selection, isNotNull);
    expect(viewKey.currentState!.selectionText(), 'Help');

    await tester.tapAt(origin + linkPoint);
    await tester.pump();
    expect(tapped?.href, 'https://example.com/help');
    expect(
      controller.selection,
      selection,
      reason: 'link taps leave the selection untouched',
    );

    // Tapping away from the link clears the selection (see the surface-size
    // note in the previous test).
    final surfaceSize = tester.getSize(find.byType(WeftSurface));
    await tester.tapAt(
      origin + Offset(surfaceSize.width - 1, surfaceSize.height - 1),
    );
    await tester.pump();
    expect(controller.selection, isNull);
    controller.dispose();
  });
}
