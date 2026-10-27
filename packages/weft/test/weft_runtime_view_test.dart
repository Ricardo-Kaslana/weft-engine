import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

void main() {
  testWidgets('a runtime failure keeps the last usable frame', (tester) async {
    const scriptId = 'fails-fast';
    // The failure is reported synchronously: real timers cannot fire inside
    // the fake-async widget zone.
    final backend = FakeRuntimeBackend(behaviors: {
      scriptId: (context) => context.timeoutFailure('deadline exceeded'),
    });
    final runtime = await WeftDocumentRuntime.open(
      backend: backend,
      documentId: 'doc-frame',
      policy: CapabilityPolicy(enabled: const <String>{}),
    );
    addTearDown(runtime.dispose);

    final document = const WeftNormalizer().normalize(
      '<h1>Stable heading</h1><p>Body text that must survive the failure.</p>',
      id: 'doc-frame',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 320,
          child: WeftSurface(document: document),
        ),
      ),
    );

    final render = tester.renderObject<RenderWeftSurface>(
      find.byType(WeftSurface),
    );
    String describeFrame() {
      final layout = render.debugLayout!;
      return layout.commands
          .map((command) => '${command.nodeId}:${command.bounds}')
          .join('|');
    }

    final frameBefore = describeFrame();
    expect(frameBefore, isNotEmpty);

    final result = await runtime.execute(
      const ScriptUnit(id: scriptId, source: ''),
      budget: const ExecutionBudget(timeout: Duration(milliseconds: 80)),
    );
    expect(result.isSuccess, isFalse);
    expect(result.failure?.kind, RuntimeFailureKind.timeout);

    // The frame after the failure is unchanged: the failed script never
    // reaches layout, and the surface repaints its last good content.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(describeFrame(), frameBefore);

    // And the host can still keep scrolling/repainting the same document.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(describeFrame(), frameBefore);
  });
}
