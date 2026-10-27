import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_fallback/fallback.dart';
import 'package:weft_fallback/main.dart';

SupportReport _report(List<SupportIssue> issues) => SupportReport(issues);

void main() {
  group('decideWeftFallback', () {
    test('renderable content stays on the native path', () {
      final plan = decideWeftFallback(const SupportReport.empty());
      expect(plan.action, WeftFallbackAction.render);
      expect(plan.html, isNull);
    });

    test('requiresWebView hands the raw markup to the host engine', () {
      final plan = decideWeftFallback(_report(const [
        SupportIssue(
          code: 'html.table.nested',
          message: 'nested table',
          requiresWebView: true,
        ),
      ]));
      expect(plan.action, WeftFallbackAction.webView);
    });

    test('errors without a webview requirement show the issue card', () {
      final plan = decideWeftFallback(_report(const [
        SupportIssue(
          code: 'html.parse.failed',
          message: 'could not parse',
          severity: SupportSeverity.error,
        ),
      ]));
      expect(plan.action, WeftFallbackAction.errorCard);
    });
  });

  group('WeftFallbackCoordinator', () {
    testWidgets('fallbackBuilder routes requiresWebView to the host webview',
        (tester) async {
      final coordinator = WeftFallbackCoordinator(
        html: '<body><p>raw</p></body>',
        webViewBuilder: (context, html, report) => Text('webview:$html'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => coordinator.fallbackBuilder(
                context,
                _report(const [
                  SupportIssue(
                    code: 'x',
                    message: 'y',
                    requiresWebView: true,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      expect(find.text('webview:<body><p>raw</p></body>'), findsOneWidget);
    });

    testWidgets('fallbackBuilder shows the diagnostic card otherwise',
        (tester) async {
      final coordinator = WeftFallbackCoordinator(
        html: '',
        webViewBuilder: (context, html, report) => const SizedBox(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => coordinator.fallbackBuilder(
                context,
                _report(const [
                  SupportIssue(
                    code: 'html.parse.failed',
                    message: 'boom',
                    severity: SupportSeverity.error,
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      expect(find.text('html.parse.failed'), findsOneWidget);
      expect(find.textContaining('无法渲染'), findsOneWidget);
    });
  });

  group('fallback demo app', () {
    testWidgets('renderable document uses WeftView without fallback',
        (tester) async {
      await tester.pumpWidget(const WeftFallbackDemoApp());
      await tester.pump();
      await tester.pump();

      expect(find.byType(WeftView), findsOneWidget);
      expect(find.textContaining('决策：Weft 原生渲染'), findsOneWidget);
    });

    testWidgets('nested-table document switches the decision banner',
        (tester) async {
      await tester.pumpWidget(
        const WeftFallbackDemoApp(
          home: FallbackDemoPage(webViewBuilder: _placeholderWebView),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('文档 2'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('requiresWebView'), findsOneWidget);
      expect(find.byType(PlaceholderWebView), findsOneWidget);
    });
  });
}

/// Test stand-in for the platform WebView surface: records the raw markup
/// size without touching platform channels.
final class PlaceholderWebView extends StatelessWidget {
  const PlaceholderWebView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) =>
      Text('placeholder-webview:${html.length}');
}

Widget _placeholderWebView(
  BuildContext context,
  String html,
  SupportReport report,
) =>
    PlaceholderWebView(html: html);
