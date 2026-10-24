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
