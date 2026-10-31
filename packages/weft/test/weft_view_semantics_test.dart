import 'package:flutter/rendering.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  testWidgets('WeftView activates links through semantics once',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p><a href="https://example.com/help">Help</a> center</p>',
          id: 'semantic-link-view',
        ),
      );
    final tapped = <WeftLinkRegion>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: WeftView(
            controller: controller,
            onLinkTap: tapped.add,
          ),
        ),
      ),
    );

    final link = find.semantics.byLabel('Help');
    expect(link, findsOneWidget);
    tester.semantics.tap(link);
    expect(tapped, hasLength(1));
    expect(tapped.single.href, 'https://example.com/help');
    expect(controller.selection, isNull);

    controller.dispose();
    semantics.dispose();
  });

  testWidgets('WeftView exposes ordered list markers in semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<ol><li>First item</li><li>Second item</li></ol>',
          id: 'semantic-list-view',
        ),
      );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: WeftView(controller: controller),
        ),
      ),
    );

    final first = find.semantics.byLabel('1. First item');
    expect(first, findsOneWidget);
    expect(find.semantics.byLabel('2. Second item'), findsOneWidget);
    expect(first.evaluate().single.parent?.role, SemanticsRole.listItem);
    expect(
      first.evaluate().single.parent?.parent?.role,
      SemanticsRole.list,
    );
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('semantic copy uses the WeftView clipboard policy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p>alpha bravo</p><p>charlie delta</p>',
          id: 'semantic-copy-view',
        ),
      );
    final probe = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    final entry = probe.textIndex!.entries.first;
    final selection = TextSelectionRange(
      anchor: TextAnchor(entry.nodeId, 0),
      extent: TextAnchor(entry.nodeId, 5),
    );
    probe.dispose();
    controller.updateSelection(selection);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: WeftView(controller: controller),
        ),
      ),
    );

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

    final selected = find.semantics.byValue('alpha');
    expect(selected, findsOneWidget);
    expect(
      selected.evaluate().single,
      containsSemantics(hasCopyAction: true, isSelected: true),
    );
    tester.semantics.copy(selected);
    expect(clipboardText, 'alpha');
    expect(controller.selection, selection);

    controller.dispose();
    semantics.dispose();
  });

  testWidgets('windowed semantics keep offscreen content and scroll to it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final html = StringBuffer();
    for (var i = 0; i < 40; i++) {
      html.write('<p>Paragraph $i accessibility scroll body text.</p>');
    }
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          html.toString(),
          id: 'semantic-scroll-view',
        ),
      );
    final scroll = ScrollController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 400,
          child: WeftView(
            controller: controller,
            scrollController: scroll,
          ),
        ),
      ),
    );

    // ADR 0041: the unmeasured suffix has no semantics node yet, while the
    // measured window keeps offscreen content semantic.
    const farLabel = 'Paragraph 39 accessibility scroll body text.';
    const headLabel = 'Paragraph 0 accessibility scroll body text.';
    expect(find.semantics.byLabel(farLabel), findsNothing);
    expect(find.semantics.byLabel(headLabel), findsOneWidget);
    expect(scroll.offset, 0);

    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    // Paragraph 0 is measured but dematerialized; inside the coarse band it
    // stays reachable as a per-block leaf and showOnScreen scrolls to it.
    final target = find.semantics.byLabel(headLabel);
    expect(target, findsOneWidget);
    tester.semantics.showOnScreen(target);
    await tester.pumpAndSettle();

    expect(scroll.offset, lessThan(100));
    expect(
      find.semantics.byLabel(headLabel).evaluate().single,
      containsSemantics(isHidden: false),
    );

    scroll.dispose();
    controller.dispose();
    semantics.dispose();
  });
}
