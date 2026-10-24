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
