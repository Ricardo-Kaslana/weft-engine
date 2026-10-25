import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_lab/main.dart';

void main() {
  testWidgets('lab renders the stage 2 article surface', (tester) async {
    await tester.pumpWidget(const WeftLabApp());

    expect(find.text('Weft Lab'), findsOneWidget);
    expect(find.text('阶段 2 · 图片与文字环绕'), findsOneWidget);
    expect(find.byType(WeftView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
