import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  test('loading a document resets the previous selection', () {
    final controller = WeftController();
    const selection = TextSelectionRange(
      anchor: TextAnchor(1, 0),
      extent: TextAnchor(2, 4),
    );
    controller.updateSelection(selection);

    controller.loadDocument(
      const WeftDocumentSnapshot(
        id: 'doc-2',
        revision: 2,
        normalizedHtml: '<p>Next</p>',
      ),
    );

    expect(controller.document?.id, 'doc-2');
    expect(controller.selection, isNull);
    controller.dispose();
  });

  testWidgets('WeftView forwards link taps to the host', (tester) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<p><a href="https://example.com/help">Help</a></p>',
          id: 'public-link',
        ),
      );
    final layout = const WeftLayoutEngine().layout(
      controller.document!,
      width: 320,
    );
    addTearDown(layout.dispose);
    WeftLinkRegion? tapped;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 320,
          child: WeftView(
            controller: controller,
            onLinkTap: (link) => tapped = link,
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(WeftSurface));
    await tester.tapAt(origin + layout.links.single.rects.first.center);
    await tester.pump();

    expect(tapped?.href, 'https://example.com/help');
    controller.dispose();
  });

  testWidgets('unsupported content invokes the explicit fallback',
      (tester) async {
    final controller = WeftController()
      ..loadDocument(
        WeftDocumentSnapshot(
          id: 'doc-fallback',
          revision: 1,
          normalizedHtml: '<canvas></canvas>',
          supportReport: SupportReport(const [
            SupportIssue(
              code: 'canvas.unsupported',
              message: 'Canvas is outside the supported subset.',
              requiresWebView: true,
            ),
          ]),
        ),
      );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WeftView(
          controller: controller,
          fallbackBuilder: (context, report) => const Text('fallback'),
        ),
      ),
    );

    expect(find.text('fallback'), findsOneWidget);
    controller.dispose();
  });
}
