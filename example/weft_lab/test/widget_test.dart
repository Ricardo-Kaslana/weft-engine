import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_lab/main.dart';

void main() {
  testWidgets('lab renders the stage 4 article with runtime controls',
      (tester) async {
    await tester.pumpWidget(const WeftLabApp());
    await tester.pumpAndSettle();

    expect(find.text('Weft Lab'), findsOneWidget);
    expect(find.text('阶段 4 · 受限 JS 与能力扩展'), findsOneWidget);
    expect(find.byType(WeftView), findsOneWidget);
    expect(find.textContaining('运行脚本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
