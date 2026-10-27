import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';

void main() {
  testWidgets('WeftView with onTagTap settles without a frame storm',
      (tester) async {
    final controller = WeftController()
      ..loadDocument(
        const WeftNormalizer(customTags: {'weft-badge'}).normalize(
          '<p>Intro</p><weft-badge label="New"></weft-badge><p>Outro</p>',
          id: 'tag-tap-doc',
        ),
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 360,
          height: 400,
          child: WeftView(
            controller: controller,
            tagRenderers: const {'weft-badge': _BadgeRenderer()},
            onTagTap: (region) {},
          ),
        ),
      ),
    );

    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'frame $frame still scheduled work; the surface lookup must '
            'resolve through the tap-detector proxy',
      );
    }
    expect(tester.takeException(), isNull);
  });
}

final class _BadgeRenderer implements WeftTagRenderer {
  const _BadgeRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    return const WeftTagLayout(
      height: 22,
      semanticsLabel: 'badge',
      ops: [
        WeftTagRectOp(
          rect: Rect.fromLTWH(0, 0, 80, 22),
          color: Color(0xFF0969DA),
        ),
      ],
    );
  }
}
