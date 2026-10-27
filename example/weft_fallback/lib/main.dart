import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:weft/weft.dart';

import 'fallback.dart';

/// Documents demonstrating each fallback decision path.
final class DemoDocument {
  const DemoDocument(this.label, this.html);

  final String label;
  final String html;
}

const demoDocuments = <DemoDocument>[
  DemoDocument('文章（Weft 渲染）', '''
<head><style>
  body { font-family: Roboto; }
  h1 { font-size: 22px; }
  .lead { color: #555; }
</style></head>
<body>
  <h1>受控内容示例</h1>
  <p class="lead">这段内容完全在 Weft 支持子集内，由原生布局渲染。</p>
  <ul><li>列表项一</li><li>列表项二</li></ul>
  <p>链接：<a href="https://example.com/weft">点按交给宿主处理</a>。</p>
</body>
'''),
  DemoDocument('嵌套表格（WebView 回退）', '''
<head><style>table { border-collapse: collapse; }</style></head>
<body>
  <h1>带嵌套表格的商品规格</h1>
  <table>
    <tr><td>外层
      <table><tr><td>内层单元格</td></tr></table>
    </td></tr>
  </table>
  <p>嵌套表格超出支持子集，SupportReport 会标记 requiresWebView。</p>
</body>
'''),
  DemoDocument('含脚本（WebView 回退）', '''
<body>
  <h1>第三方嵌入内容</h1>
  <script>document.write('hostile or interactive content');</script>
  <p>脚本不在受控子集内：要么走受限 Runtime 能力，要么整体回退。</p>
</body>
'''),
];

void main() {
  runApp(const WeftFallbackDemoApp());
}

final class WeftFallbackDemoApp extends StatelessWidget {
  const WeftFallbackDemoApp({super.key, this.home});

  /// Overrides the initial page; widget tests inject pages with
  /// placeholder WebView builders.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weft WebView 回退示例',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: home ?? const FallbackDemoPage(),
    );
  }
}

final class FallbackDemoPage extends StatefulWidget {
  const FallbackDemoPage({super.key, this.webViewBuilder});

  /// Overrides the platform WebView surface. The default builds
  /// [_DemoWebView] (webview_flutter); widget tests inject a placeholder so
  /// they never touch platform channels.
  final WebViewFallbackBuilder? webViewBuilder;

  @override
  State<FallbackDemoPage> createState() => _FallbackDemoPageState();
}

final class _FallbackDemoPageState extends State<FallbackDemoPage> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final document = demoDocuments[_index];
    const normalizer = WeftNormalizer();
    final snapshot = normalizer.normalize(document.html, id: 'demo-$_index');

    return Scaffold(
      appBar: AppBar(
        title: Text('Weft 回退示例：${document.label}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < demoDocuments.length; i++)
                ButtonSegment(value: i, label: Text('文档 ${i + 1}')),
            ],
            selected: {_index},
            onSelectionChanged: (selection) =>
                setState(() => _index = selection.first),
          ),
          _SupportReportBanner(report: snapshot.supportReport),
          Expanded(child: _buildSurface(document, snapshot)),
        ],
      ),
    );
  }

  Widget _buildSurface(
    DemoDocument document,
    WeftDocumentSnapshot snapshot,
  ) {
    final controller = WeftController()..loadDocument(snapshot);
    final injected = widget.webViewBuilder;
    final coordinator = WeftFallbackCoordinator(
      html: document.html,
      // Real WebView: webview_flutter is an example-only dependency — the
      // engine core stays free of it (architecture §8). Tests inject a
      // placeholder through the same hook.
      webViewBuilder:
          injected ?? (context, html, report) => _DemoWebView(html: html),
    );
    return WeftView(
      controller: controller,
      fallbackBuilder: coordinator.fallbackBuilder,
      onLinkTap: (link) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('宿主处理链接: ${link.href}')),
      ),
    );
  }
}

/// The host WebView surface. `loadHtmlString` feeds the **raw** markup to
/// the system WebView; Weft never executes scripts itself, so anything the
/// controlled subset cannot render is handed over whole.
final class _DemoWebView extends StatefulWidget {
  const _DemoWebView({required this.html});

  final String html;

  @override
  State<_DemoWebView> createState() => _DemoWebViewState();
}

final class _DemoWebViewState extends State<_DemoWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

final class _SupportReportBanner extends StatelessWidget {
  const _SupportReportBanner({required this.report});

  final SupportReport report;

  @override
  Widget build(BuildContext context) {
    final action = decideWeftFallback(report);
    final label = switch (action.action) {
      WeftFallbackAction.render => '决策：Weft 原生渲染',
      WeftFallbackAction.webView => '决策：requiresWebView → 交给宿主 WebView',
      WeftFallbackAction.errorCard => '决策：错误卡片',
    };
    final issues = report.issues.isEmpty
        ? '无诊断'
        : report.issues.map((issue) => issue.code).join(', ');
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text('$label\n诊断: $issues'),
    );
  }
}
