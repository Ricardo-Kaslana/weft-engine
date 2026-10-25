import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/src/weft_selection_chrome.dart';
import 'package:weft/weft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const documentHtml =
      '<p>alpha bravo</p><p>charlie delta</p><p>echo foxtrot</p><p>golf hotel</p>';

  WeftController _controller() {
    return WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(documentHtml, id: 'selection-chrome'),
      );
  }

  Future<void> _pumpView(
    WidgetTester tester,
    WeftController controller, {
    GlobalKey<WeftViewState>? viewKey,
    ValueChanged<WeftSelectionInfo?>? onSelectionChanged,
    bool showSelectionHandles = true,
    bool showCopyButton = true,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 400,
          child: WeftView(
            key: viewKey,
            controller: controller,
            onSelectionChanged: onSelectionChanged,
            showSelectionHandles: showSelectionHandles,
            showCopyButton: showCopyButton,
          ),
        ),
      ),
    );
  }

  /// Long presses "alpha" and settles until the chrome overlays are built.
  /// The overlays appear one frame after the selection: the build that
  /// applies it queries the render object before its update lands, and the
  /// post-frame sync rebuilds with the settled frame.
  Future<TestGesture> _longPressAlpha(
    WidgetTester tester,
    WeftController controller,
    Offset origin,
    WeftLayoutResult probe,
  ) async {
    final firstNode = probe.textIndex!.entries.first.nodeId;
    final pressPoint = probe.textRectsForNode(firstNode, 0, 5).first.center;
    final gesture = await tester.startGesture(origin + pressPoint);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(controller.selection, isNotNull);
    expect(controller.selection!.extent, TextAnchor(firstNode, 5));
    return gesture;
  }

  testWidgets('long press shows drag handles and the copy button',
      (tester) async {
    final controller = _controller();
    await _pumpView(tester, controller);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    expect(find.byType(WeftSelectionHandle), findsNWidgets(2));
    expect(find.byType(WeftCopyButton), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    controller.dispose();
  });

  testWidgets('dragging the end handle extends the selection', (tester) async {
    final controller = _controller();
    final viewKey = GlobalKey<WeftViewState>();
    await _pumpView(tester, controller, viewKey: viewKey);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final entries = probe.textIndex!.entries;
    final firstNode = entries[0].nodeId;
    final secondNode = entries[1].nodeId;
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    await gesture.up();
    await tester.pump();

    final endHandle = find.byWidgetPredicate(
      (widget) => widget is WeftSelectionHandle && widget.isEnd,
    );
    final handleCenter = tester.getCenter(endHandle);
    final dragTarget =
        origin + probe.textRectsForNode(secondNode, 0, 13).first.center;
    final drag = await tester.startGesture(handleCenter);
    // The first move exceeds the pan slop to claim the gesture, the second
    // delivers the final position.
    await drag.moveBy(const Offset(0, 60));
    await tester.pump();
    await drag.moveBy(dragTarget - handleCenter - const Offset(0, 60));
    await tester.pump();
    expect(
      controller.selection!.anchor,
      TextAnchor(firstNode, 0),
      reason: 'the start handle endpoint stays at the word start',
    );
    expect(controller.selection!.extent.nodeId, secondNode);
    expect(
      viewKey.currentState!.selectionText(),
      startsWith('alpha bravo\n'),
    );

    // Dragging somewhere without text keeps the previous endpoint (ADR 0013
    // safe drop).
    await drag.moveBy(const Offset(0, 400));
    await tester.pump();
    expect(controller.selection!.extent.nodeId, secondNode);

    await drag.up();
    await tester.pump();
    controller.dispose();
  });

  testWidgets('tap on text places a collapsed caret without chrome',
      (tester) async {
    final controller = _controller();
    await _pumpView(tester, controller);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final firstNode = probe.textIndex!.entries.first.nodeId;
    final origin = tester.getTopLeft(find.byType(WeftSurface));
    final tapPoint = probe.textRectsForNode(firstNode, 2, 3).first.center;

    await tester.tapAt(origin + tapPoint);
    await tester.pump();

    final selection = controller.selection;
    expect(selection, isNotNull);
    expect(selection!.isCollapsed, isTrue);
    expect(selection.anchor.nodeId, firstNode);
    expect(find.byType(WeftSelectionHandle), findsNothing);
    expect(find.byType(WeftCopyButton), findsNothing);
    controller.dispose();
  });

  testWidgets('tap on the copy button copies the text and keeps the selection',
      (tester) async {
    final controller = _controller();
    await _pumpView(tester, controller);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    await gesture.up();
    await tester.pump();
    final selection = controller.selection;

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.tap(find.byType(WeftCopyButton));
    await tester.pump();

    expect(clipboardText, 'alpha');
    expect(
      controller.selection,
      selection,
      reason: 'copying must not clear the selection',
    );
    controller.dispose();
  });

  testWidgets('onSelectionChanged reports selected text and clears',
      (tester) async {
    final events = <WeftSelectionInfo?>[];
    final controller = _controller();
    await _pumpView(tester, controller, onSelectionChanged: events.add);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    await gesture.up();
    await tester.pump();
    expect(events.length, 1);
    expect(events.single!.text, 'alpha');
    expect(events.single!.isCollapsed, isFalse);

    // Tapping outside any text clears the selection and reports null.
    await tester.tapAt(origin + Offset(160, probe.size.height - 1));
    await tester.pump();
    expect(controller.selection, isNull);
    expect(events.length, 2);
    expect(events.last, isNull);
    controller.dispose();
  });

  testWidgets('showCopyButton: false hides only the copy button',
      (tester) async {
    final controller = _controller();
    await _pumpView(tester, controller, showCopyButton: false);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    await gesture.up();
    await tester.pump();
    expect(find.byType(WeftCopyButton), findsNothing);
    expect(find.byType(WeftSelectionHandle), findsNWidgets(2));
    controller.dispose();
  });

  testWidgets('showSelectionHandles: false hides only the drag handles',
      (tester) async {
    final controller = _controller();
    await _pumpView(tester, controller, showSelectionHandles: false);
    final probe =
        const WeftLayoutEngine().layout(controller.document!, width: 320);
    addTearDown(probe.dispose);
    final origin = tester.getTopLeft(find.byType(WeftSurface));

    final gesture = await _longPressAlpha(tester, controller, origin, probe);
    await gesture.up();
    await tester.pump();
    expect(find.byType(WeftSelectionHandle), findsNothing);
    expect(find.byType(WeftCopyButton), findsOneWidget);
    controller.dispose();
  });
}
