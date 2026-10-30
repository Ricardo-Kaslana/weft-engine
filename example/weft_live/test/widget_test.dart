import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_live/main.dart';

void main() {
  testWidgets('live demo shell and document react to host controls',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const WeftLiveApp(enableLiveUpdates: false));
    await tester.pump();

    expect(find.byType(WeftView), findsOneWidget);
    expect(find.text('CHANNEL'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('filter-qa')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey<String>('filter-qa')));
    await tester.pump();

    var view = tester.widget<WeftView>(find.byType(WeftView));
    var html = view.controller.document!.normalizedHtml;
    expect(html, contains('当前筛选：问答'));
    expect(html, contains('观众提问：动态刷新会打断阅读吗'));
    expect(html, isNot(contains('主舞台：内容开始自己呼吸')));

    await tester.tap(find.byKey(const ValueKey<String>('live-toggle')));
    await tester.pump();

    view = tester.widget<WeftView>(find.byType(WeftView));
    html = view.controller.document!.normalizedHtml;
    expect(html, contains('直播已暂停'));
    expect(find.byTooltip('继续直播'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('theme-toggle')));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final darkHtml = tester
        .widget<WeftView>(find.byType(WeftView))
        .controller
        .document!
        .normalizedHtml;
    expect(darkHtml, contains('data-accent="#ff6b4a"'));

    await tester.tap(find.byKey(const ValueKey<String>('about')));
    await tester.pumpAndSettle();
    expect(find.text('关于 Weft Live'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('poll and clap custom tags drive the host state', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 6000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const WeftLiveApp(enableLiveUpdates: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final root = tester
        .binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
    final vote = _findLabeledNode(root, '投票选项');
    expect(vote, isNotNull);
    await tester.tapAt(_globalCenter(vote!, root));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    var html = tester
        .widget<WeftView>(find.byType(WeftView))
        .controller
        .document!
        .normalizedHtml;
    expect(html, contains('已记录你的选择'));

    final currentRoot = tester
        .binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
    final clap = _findLabeledNode(currentRoot, '为现场鼓掌');
    expect(clap, isNotNull);
    await tester.tapAt(_globalCenter(clap!, currentRoot));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    html = tester
        .widget<WeftView>(find.byType(WeftView))
        .controller
        .document!
        .normalizedHtml;
    expect(html, contains('1,285'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('live updates rebuild the snapshot on the host clock',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const WeftLiveApp());
    await tester.pump();
    expect(find.text('LIVE  10:42:06'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('LIVE  10:42:08'), findsOneWidget);
    final html = tester
        .widget<WeftView>(find.byType(WeftView))
        .controller
        .document!
        .normalizedHtml;
    expect(html, contains('10:42:08'));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

SemanticsNode? _findLabeledNode(SemanticsNode node, String prefix) {
  final label = node.getSemanticsData().label;
  if (label.startsWith(prefix)) return node;
  SemanticsNode? found;
  node.visitChildren((child) {
    found ??= _findLabeledNode(child, prefix);
    return found == null;
  });
  return found;
}

Offset _globalCenter(SemanticsNode node, SemanticsNode root) {
  var transform = Matrix4.identity();
  SemanticsNode? current = node;
  while (current != null && current != root) {
    final parentTransform = current.transform;
    if (parentTransform != null) {
      transform = parentTransform.multiplied(transform);
    }
    current = current.parent;
  }
  return MatrixUtils.transformPoint(transform, node.rect.center);
}
