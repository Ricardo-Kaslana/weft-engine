import 'package:flutter/material.dart';
import 'package:weft/weft.dart';
import 'package:weft_runtime_fake/weft_runtime_fake.dart';

const _article = '''
<style>
  .lead { color: #57606a; font-size: 18px; }
  .note {
    background-color: #fff8c5;
    padding: 12px;
    border: 1px solid #d4a72c;
  }
</style>
<h1>Weft 内容引擎</h1>
<p class="lead">
  阶段 4 接入了受限 JavaScript：单文档 Context、状态/事件/网络能力、
  预算内中断与可恢复会话。
</p>
<p>
  <weft-badge label="QuickJS" data-color="#0969da"></weft-badge>
  <weft-badge label="能力白名单" data-color="#1a7f37"></weft-badge>
  <weft-badge label="预算中断" data-color="#bf3989"></weft-badge>
</p>
<img src="asset:assets/weft_flow.png" alt="Weft 排版示意图"
     width="200" style="float: right; margin: 0 0 14px 18px;">
<p>
  脚本运行在独立的安全域里，只能通过版本化能力桥调用宿主注册的
  状态、事件和网络模块；未启用的能力在 JS 里不可见。无限循环、
  内存炸弹与微任务风暴都在配置预算内被原生中断，界面保留最后一帧。
  自定义标签 <code>weft-badge</code> 由受信任的 Dart 渲染器绘制。
</p>
<h2 style="clear: both">当前能力</h2>
<ul>
  <li>标题、段落、强调、链接、列表、引用、表格与预格式化文本</li>
  <li>块级图片替换盒、左右浮动与 clear 环绕</li>
  <li>渐进式视口布局、稳定文本选区与单表面语义</li>
</ul>
<blockquote>
  <p>内容正确性优先于新增能力，复杂内容必须显式回退。</p>
</blockquote>
<p>查看 <a href="https://example.com/weft">Weft 项目文档</a> 了解后续里程碑。</p>
<p class="note">
  下方按钮驱动一个 FakeRuntime 会话：脚本通过能力桥累加文档状态并
  发出事件；网络能力仅在宿主提供客户端与白名单时启用。
</p>
''';

/// Example custom tag renderer: an attribute-driven pill badge.
///
/// This is the phase-4 extension pattern: the host allowlists `weft-badge`
/// in `WeftNormalizer.customTags`, registers this renderer on the engine, and
/// the engine paints the returned ops inside the element's content box.
class WeftBadgeTagRenderer implements WeftTagRenderer {
  const WeftBadgeTagRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final label = context.element.attribute('label') ?? 'badge';
    final color = WeftBadgeTagRenderer.parseColor(
            context.element.attribute('data-color')) ??
        const Color(0xFF57606A);
    const height = 22.0;
    return WeftTagLayout(
      height: height,
      semanticsLabel: '标签：$label',
      ops: [
        WeftTagRectOp(
          rect: Rect.fromLTWH(0, 0, context.contentWidth, height),
          color: color.withValues(alpha: 0.14),
        ),
        WeftTagTextOp(
          offset: const Offset(10, 3),
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          maxWidth: context.contentWidth - 20,
        ),
      ],
    );
  }

  static Color? parseColor(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
    if (match == null) return null;
    return Color(0xFF000000 | int.parse(match.group(1)!, radix: 16));
  }
}

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
  WeftDocumentRuntime? _runtime;
  final List<String> _eventLog = <String>[];
  int _count = 0;
  String _lastFailure = '无';

  @override
  void initState() {
    super.initState();
    _controller = WeftController()
      ..loadDocument(
        const WeftNormalizer(customTags: {'weft-badge'}).normalize(
          _article,
          id: 'lab-article',
          revision: 1,
        ),
      );
    _openRuntime();
  }

  Future<void> _openRuntime() async {
    // The lab runs the scripted FakeRuntime so the demo needs no native
    // library; swapping in QuickJsFfiBackend() is the only change required.
    final backend = FakeRuntimeBackend(behaviors: {
      'count-up': (context) async {
        final current = await context.bridge('weft.state', 'get', ['count']);
        final next = ((current as num?) ?? 0) + 1;
        await context.bridge('weft.state', 'set', ['count', next]);
        await context.bridge('weft.events', 'emit', [
          'count-changed',
          <String, JsValue>{'value': next}
        ]);
        return context.success(next);
      },
    });
    final runtime = await WeftDocumentRuntime.open(
      backend: backend,
      documentId: 'lab-runtime',
      policy: CapabilityPolicy(
        enabled: const {WeftCapabilityIds.state, WeftCapabilityIds.events},
      ),
      services: WeftRuntimeServices(
        onJsEvent: (name, payload) {
          if (!mounted) return;
          setState(() {
            _eventLog.insert(0, '$name $payload');
            if (_eventLog.length > 5) _eventLog.removeLast();
          });
        },
        onRuntimeFailure: (failure) {
          if (!mounted) return;
          setState(() => _lastFailure = '${failure.kind}: ${failure.message}');
        },
      ),
    );
    if (!mounted) {
      await runtime.dispose();
      return;
    }
    setState(() => _runtime = runtime);
  }

  Future<void> _runCountUp() async {
    final runtime = _runtime;
    if (runtime == null) return;
    final result = await runtime.execute(
      const ScriptUnit(id: 'count-up', source: ''),
    );
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) {
        _count = (result.value as num?)?.toInt() ?? _count;
      } else {
        _lastFailure = '${result.failure?.kind}: ${result.failure?.message}';
      }
    });
  }

  @override
  void dispose() {
    _runtime?.dispose();
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
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            child: Text(
              '阶段 4 · 受限 JS 与能力扩展',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _runtime == null ? null : _runCountUp,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('运行脚本（状态=$_count）'),
                ),
                Text('最近事件：${_eventLog.isEmpty ? '无' : _eventLog.first}'),
              ],
            ),
          ),
          if (_eventLog.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '事件日志：${_eventLog.skip(1).join(' | ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              '会话：${_runtime?.sessionId ?? '打开中'} · 最近失败：$_lastFailure',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: WeftView(
                controller: _controller,
                tagRenderers: const {'weft-badge': WeftBadgeTagRenderer()},
                onTagTap: (region) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('宿主收到标签：${region.tag}')),
                    );
                },
                imageResolver: (request) {
                  if (request.src == 'asset:assets/weft_flow.png') {
                    return const AssetImage('assets/weft_flow.png');
                  }
                  return null;
                },
                onLinkTap: (link) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text('宿主收到链接：${link.href}')),
                    );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
