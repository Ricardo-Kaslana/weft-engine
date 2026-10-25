import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

const _testPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGM0TjvDwMDAxAAG'
    'ABBNAWl85fWfAAAAAElFTkSuQmCC';

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

  testWidgets('WeftView forwards the image resolver', (tester) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          '<img src="memory://cover" width="40" height="20">',
          id: 'public-image',
        ),
      );
    final provider = MemoryImage(base64Decode(_testPngBase64));
    final requests = <WeftImageRequest>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 240,
          height: 180,
          child: WeftView(
            controller: controller,
            imageResolver: (request) {
              requests.add(request);
              return provider;
            },
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(requests.single.documentId, 'public-image');
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugResolvedImageCount, 1);
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
