# Weft 交接说明

本文用于把当前项目交给另一个 Agent（Codex、其它 IDE Agent 或人工团队）继续开发。先读“交接提示词”，再按需阅读后面的状态与约束。

## 交接提示词（可直接粘贴）

```text
你接手 Weft：一个面向 Flutter 的受控 HTML/CSS 渲染引擎，用于 CMS 文章、商品描述、帮助文档和 AI 流式内容，目标是替代这些场景下的 WebView。

当前代码已经实现并可测试：
- 受控 HTML 规范化、标签/属性白名单、结构化 CSS 选择器与层叠。
- Block/Inline 布局、空白折叠、CSS 2.1 margin 折叠、半行距、块级宽度/box-sizing/solid 边框。
- 链接跨行命中、宿主图片解析、块级图片、左右 Float、clear 和跨段落文字环绕。

请继续下一个切片，优先级如下：
1. 图片与 Float 的浏览器黄金几何基线：用 Chrome 生成固定字体参考，比较 Weft 块/行几何。
2. 表格（table/tr/td、colspan/rowspan、基础边框）或 CJK 禁则处理。
3. 长文档稳定跨段选择、复制和性能门禁。

硬性约束：
- 不做完整浏览器；不执行不可信脚本；不把 HTML 节点映射为独立 Widget。
- 不支持的内容必须生成 SupportReport 并显式回退。
- 图片资源只能由宿主 WeftImageResolver 提供；引擎不得隐式发起网络请求。
- 每次修改必须运行 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart run tool/verify.dart` 和 `packages/weft_engine/tool/golden_pixel_test.dart`。
- 新增能力必须附带单元测试；影响布局时必须评估黄金基线。
- 重要技术取舍写入 docs/adr/。

先阅读 README.md、docs/architecture.md、docs/supported-subset.md 和 docs/handoff.md，再选择第一个任务并给出计划。
```

## 当前仓库状态

- 分支：`main`
- 最新提交：`60ac3f7 feat: add image resources and float text wrapping`
- Flutter：3.35.5 stable；Dart：3.9.2
- 常规测试：73 项；固定字体像素基线：2 项；`dart analyze` 无问题。
- GitHub Actions 使用 Windows 执行像素黄金门禁。

## 包结构

```text
packages/
  weft/                 公开 API：WeftController、WeftView
  weft_document/        纯 Dart 文档模型、规范化、样式表、支持度报告
  weft_engine/          布局、绘制、图片、Float、命中测试、渲染表面
  weft_runtime_api/     JS Runtime 与能力桥抽象
  weft_quickjs/         QuickJS 原生适配边界（尚无原生执行）
  weft_capabilities/    能力策略与内置命名空间
example/weft_lab/       开发实验室与浮动图片示例
conformance/            语料、固定字体、Flutter 基线、浏览器参考工具
tool/                   全量测试、浏览器参考、跨引擎差异报告
docs/adr/               架构决策记录
```

## 已实现能力

- 规范化：标签白名单、属性清洗、URL 与图片源策略、节点/深度/输入限制、诊断与显式回退。
- CSS：标签/类/ID/复合/后代/子代/逗号选择器，特异性与源码顺序，内联样式，margin/padding 简写，宽度约束，`float` 和 `clear`。
- 布局：标题、段落、强调、列表、引用、代码块、分隔线、`<br>`；相邻/父子/空块 margin 折叠；CSS 半行距。
- 链接：跨行命中矩形、宿主 `onLinkTap`。
- 图片：宿主解析、异步解码失效、块级替换盒、固有比例、alt 回退。
- Float：图片左右浮动、逐行行框避让、clear、同侧堆叠、对侧并排、文档滚动高度。
- 测试：规范化、布局、margin、盒模型、图片、浮动、CJK、长文档、公开层和像素基线。

## 明确未实现

- 表格：`table/tr/td`、`colspan/rowspan`、边框合并。
- CJK 禁则：标点行首/行尾约束、CJK 像素基线。
- 跨段落文本选择、复制、命中语义、内部滚动与分块缓存。
- 图片/浮动的浏览器像素几何基线。
- QuickJS 原生执行、状态/事件/网络能力包。
- Flexbox、任意元素 Float、BFC、完整增量失效。

## 关键约束

1. 内容呈现优先，不追求完整 W3C/WHATWG 兼容。
2. 只执行可信脚本；JS 不接触布局或渲染树。
3. 布局、选择、资源加载和 Runtime 保持分层；引擎不得知道 QuickJS。
4. 修改布局必须检查 `conformance` 基线和跨引擎差异。
5. 像素差异报告中字形抗锯齿属预期，不允许为通过测试直接放宽阈值。
6. 图片资源安全由宿主解析器负责，引擎只接受已解码 `ui.Image`。

## 验证命令

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart

# 固定字体像素门禁
cd packages/weft_engine
flutter test tool/golden_pixel_test.dart --timeout 60s

# 浏览器诊断参考（本机 Chrome/Edge + Node 22）
node tool/browser_references.mjs

# 跨引擎像素报告（需要 Pillow）
python tool/compare_goldens.py --report-only
```

## 建议的下一步

### A. 图片/Float 黄金几何基线

目标：给 `pixel_basic`/`box_model` 之外增加一个带图片和浮动的案例，并固定字体、视口和资源。

交付：
- `conformance/cases/float_image.html`
- 浏览器参考截图和 Weft 几何测试
- 行框避让、clear、图片晚加载的差异报告

### B. 表格

目标：支持 `table/thead/tbody/tr/td`、`colspan/rowspan` 和基础边框。

注意：表格宽度需要 min/max-content 两遍测量；建议先只实现简单单元格和边框，不做嵌套表格与复杂单元格。

### C. 长文档选择与性能

目标：稳定跨段选择、复制、随机选区压力测试和性能基线。

注意：当前仍是全量布局；不要在引入 Fragment/文本索引前堆叠更多复杂定位能力。

## 常见误区

- 不要把 `img` 映射为 Flutter `Image` Widget；保持单一渲染表面。
- 不要在规范化器里清洗不可信脚本；它只处理受控子集。
- 不要恢复已销毁的 Runtime 或自动重放副作用。
- 不要绕过 `_FloatContext` 直接计算行框。
- 不要为了跨引擎像素通过而修改测试字体、通道容差或遮挡真实差异。
