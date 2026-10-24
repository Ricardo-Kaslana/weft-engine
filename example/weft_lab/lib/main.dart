import 'package:flutter/material.dart';
import 'package:weft/weft.dart';

const _article = '''
<style>
  .lead { color: #57606a; font-size: 18px; }
  .note { background-color: #fff8c5; padding: 12px; }
</style>
<h1>Weft 内容引擎</h1>
<p class="lead">
  阶段 1A 已支持受控 HTML 子集、基础 CSS 层叠和 Block/Inline 静态渲染。
</p>
<h2>当前能力</h2>
<ul>
  <li>标题、段落、强调、链接、列表、引用和预格式化文本</li>
  <li>类型、类、ID、后代与子代选择器</li>
  <li>单渲染表面、可见文本绘制和可配置支持度回退</li>
</ul>
<blockquote>
  <p>内容正确性优先于新增能力，复杂内容必须显式回退。</p>
</blockquote>
<h2>示例代码</h2>
<pre><code>final snapshot = normalizer.normalize(html, id: 'demo');</code></pre>
<p class="note">
  Float、表格、跨段选择与真实 JavaScript 执行仍属于后续里程碑。
</p>
''';

void main() {
  runApp(const WeftLabApp());
}

class WeftLabApp extends StatelessWidget {
  const WeftLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weft Lab',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0969DA),
      ),
      home: const WeftLabPage(),
    );
  }
}

class WeftLabPage extends StatefulWidget {
  const WeftLabPage({super.key});

  @override
  State<WeftLabPage> createState() => _WeftLabPageState();
}

class _WeftLabPageState extends State<WeftLabPage> {
  late final WeftController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WeftController()
      ..loadDocument(
        const WeftNormalizer().normalize(
          _article,
          id: 'lab-article',
          revision: 1,
        ),
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weft Lab')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
            child: Text(
              '阶段 1A · 基础静态渲染',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: WeftView(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }
}
