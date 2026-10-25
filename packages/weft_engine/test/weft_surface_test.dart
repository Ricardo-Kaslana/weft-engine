import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

const _testPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGM0TjvDwMDAxAAG'
    'ABBNAWl85fWfAAAAAElFTkSuQmCC';

void main() {
  testWidgets('surface lays out normalized content in bounded constraints', (
    tester,
  ) async {
    final document = const WeftNormalizer().normalize(
      '<h1>Hello</h1><p>Body text for the render surface.</p>',
      id: 'surface',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: WeftSurface(document: document),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(WeftSurface)), const Size(320, 180));
  });

  testWidgets('surface reports taps inside rendered link boxes',
      (tester) async {
    final document = const WeftNormalizer().normalize(
      '<p>prefix <a href="https://example.com/target">target link</a> suffix</p>',
      id: 'link-tap',
    );
    final layout = const WeftLayoutEngine().layout(document, width: 200);
    addTearDown(layout.dispose);
    final link = layout.links.single;
    final localTarget = link.rects.first.center;
    WeftLinkRegion? tapped;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 240,
            child: WeftSurface(
              document: document,
              onLinkTap: (region) => tapped = region,
            ),
          ),
        ),
      ),
    );

    final origin = tester.getTopLeft(find.byType(WeftSurface));
    await tester.tapAt(origin + localTarget);
    await tester.pump();
    expect(tapped?.href, 'https://example.com/target');
    expect(tapped?.text, 'target link');

    tapped = null;
    await tester.tapAt(origin + const Offset(1, 1));
    await tester.pump();
    expect(tapped, isNull);
  });

  testWidgets('surface resolves images and relayouts after they decode', (
    tester,
  ) async {
    final document = const WeftNormalizer().normalize(
      '<img id="pic" src="memory://pic" width="40" height="20">',
      id: 'image-surface',
    );
    final provider = MemoryImage(base64Decode(_testPngBase64));
    final requests = <WeftImageRequest>[];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 240,
            height: 160,
            child: WeftSurface(
              document: document,
              imageResolver: (request) {
                requests.add(request);
                return request.src == 'memory://pic' ? provider : null;
              },
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(requests.single.src, 'memory://pic');
    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugResolvedImageCount, 1);
    final image =
        render.debugLayout!.commands.whereType<WeftImagePaintCommand>().single;
    expect(image.destination.size, const Size(40, 20));
  });

  testWidgets('a failing image resolver keeps alternative text', (
    tester,
  ) async {
    final document = const WeftNormalizer().normalize(
      '<p>Before <img src="https://example.com/broken.png" '
      'alt="Fallback image description"> after</p>',
      id: 'image-error',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 160,
          child: WeftSurface(
            document: document,
            imageResolver: (request) => throw StateError('blocked source'),
          ),
        ),
      ),
    );

    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    expect(render.debugResolvedImageCount, 0);
    expect(
      render.debugLayout!.commands
          .whereType<WeftTextPaintCommand>()
          .single
          .painter
          .text
          ?.toPlainText(),
      'Before Fallback image description after',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface accepts a replacement document without stale layout', (
    tester,
  ) async {
    final first = const WeftNormalizer().normalize(
      '<p>First</p>',
      id: 'first',
    );
    final second = const WeftNormalizer().normalize(
      '<h1>Second</h1><p>Updated</p>',
      id: 'second',
    );

    Widget wrap(WeftDocumentSnapshot document) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 280,
            height: 200,
            child: WeftSurface(document: document),
          ),
        ),
      );
    }

    await tester.pumpWidget(wrap(first));
    await tester.pumpWidget(wrap(second));

    expect(tester.getSize(find.byType(WeftSurface)), const Size(280, 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface paints selection highlights across paragraphs', (
    tester,
  ) async {
    final document = const WeftNormalizer().normalize(
      '<p>Alpha block</p><p>Beta block</p>',
      id: 'selectable',
    );
    // Resolve the logical anchors through a throwaway layout.
    final probe = const WeftLayoutEngine().layout(document, width: 280);
    final index = probe.textIndex!;
    final selection = TextSelectionRange(
      anchor: TextAnchor(index.entries[0].nodeId, 2),
      extent: TextAnchor(index.entries[1].nodeId, 4),
    );
    final rects = probe.selectionRects(selection);
    probe.dispose();
    expect(rects, isNotEmpty);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 280,
            height: 120,
            child: WeftSurface(document: document, selection: selection),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(WeftSurface),
      matchesGoldenFile('goldens/selection_highlight.png'),
    );
  });
}
