import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

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
}
