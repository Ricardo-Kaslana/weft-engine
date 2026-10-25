# Weft 交接说明

本文用于把当前项目交给另一个 Agent（Codex、其它 IDE Agent 或人工团队）继续开发。先读“交接提示词”，再按需阅读后面的状态与约束。

## 交接提示词（可直接粘贴）

```text
你接手 Weft：一个面向 Flutter 的受控 HTML/CSS 渲染引擎，用于 CMS 文章、商品描述、帮助文档和 AI 流式内容，目标是替代这些场景下的 WebView。

当前代码已经实现并可测试：
- 受控 HTML 规范化、标签/属性白名单、结构化 CSS 选择器与层叠。
- Block/Inline 布局、空白折叠、CSS 2.1 margin 折叠、半行距、块级宽度/box-sizing/solid 边框。
- 链接跨行命中、宿主图片解析、块级图片、左右 Float、clear 和跨段落文字环绕。
- 表格：table 系标签、colspan/rowspan（含隐式行）、caption、separate/collapse 边框、border-spacing 和 vertical-align。
- 逻辑文本索引与选区解析：跨段锚点→视觉矩形与复制文本，表面绘制选择高亮。
- 图片/Float 与表格的浏览器几何基线（Chrome 参考固化在 conformance/reference/）。

请继续下一个切片，优先级如下：
1. 分块渲染：按块缓存 ui.Picture、视口外裁剪与选择矩形按块索引（性能门禁已在 docs/testing-strategy.md，改前留底、改后对比中位数）。
2. 选择把手/工具条与 caret：拖拽把手微调选区、宿主复制菜单（WeftView.selectionText() 已就绪）。
3. 行内图片基线混排或 CSS 高度/百分比宽度。

硬性约束：
- 不做完整浏览器；不执行不可信脚本；不把 HTML 节点映射为独立 Widget。
- 不支持的内容必须生成 SupportReport 并显式回退。
- 图片资源只能由宿主 WeftImageResolver 提供；引擎不得隐式发起网络请求。
- 每次修改必须运行 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart run tool/verify.dart` 和 `packages/weft_engine/tool/golden_pixel_test.dart`。
- 新增能力必须附带单元测试；影响布局时必须评估黄金基线与 conformance/reference/ 下的浏览器几何基线。
- 重要技术取舍写入 docs/adr/（下一个编号为 0017）。

先阅读 README.md、docs/architecture.md、docs/supported-subset.md 和 docs/handoff.md，再选择第一个任务并给出计划。

开发工作流提示（ADR 0014）：用 `tool/check.sh` 做本地门禁；新增几何案例走 `--emit-reference` 接入通用门禁，零测试代码；调布局用 `tool/dump_layout.sh --diff` 直接看偏差表；表格改动落在 `table_layout.part.dart`、行内/Float 改动落在 `inline_flow.part.dart`，两边可并行。
```

## 当前仓库状态

- 分支：`main`
- 最新提交：见 `git log`（本节只保证指南有效，不追踪哈希）
- Flutter：3.35.5 stable；Dart：3.9.2
- 常规测试 104+ 项、像素黄金 3 项 + 选区高亮 1 项、性能门禁 4 场景；`dart analyze` 无问题。
- GitHub Actions 使用 Windows 执行像素黄金门禁。

已实现到 ADR 0016：选择手势（长按选词/拖拽扩展/点击清除/`WeftView.selectionText()`）、CJK 禁则（`WeftLineBreakRules`，逐行路径显式、整段路径 ICU 对照零违规）、性能门禁（四场景基准 + 10 倍宽 CI 上限，见 docs/testing-strategy.md）。

## 包结构

```text
packages/
  weft/                 公开 API：WeftController、WeftView
  weft_document/        纯 Dart 文档模型、规范化、样式表、支持度报告
  weft_engine/          布局、绘制、图片、Float、表格、命中测试、选择、渲染表面
    lib/src/layout_engine.dart     引擎骨架、块流、图片（公共入口 layout()）
    lib/src/table_layout.part.dart 表格：槽位网格、列宽、折叠边框（extension）
    lib/src/inline_flow.part.dart  Float 排除区、行内累积器、数据类
  weft_runtime_api/     JS Runtime 与能力桥抽象
  weft_quickjs/         QuickJS 原生适配边界（尚无原生执行）
  weft_capabilities/    能力策略与内置命名空间
example/weft_lab/       开发实验室与浮动图片示例
conformance/            语料、固定字体、图片资产、Flutter 基线、浏览器几何参考
tool/                   check 门禁、dump 诊断、资产生成、浏览器参考、跨引擎报告
docs/adr/               架构决策记录
```

## 已实现能力

- 规范化：标签白名单（含 table 系）、属性清洗（含 colspan/rowspan 1..1000）、URL 与图片源策略、节点/深度/输入限制、诊断与显式回退；嵌套表格触发 requiresWebView。
- CSS：标签/类/ID/复合/后代/子代/逗号选择器，特异性与源码顺序，内联样式，margin/padding 简写，宽度约束，`float`、`clear`、`border-collapse`、`border-spacing`、`vertical-align`。
- 布局：标题、段落、强调、列表、引用、代码块、分隔线、`<br>`；margin 折叠；CSS 半行距；块级宽度/box-sizing/solid 边框。
- 表格（ADR 0012）：槽位网格、colspan/rowspan、隐式行、caption、两遍 min/max 列宽、行槽拉伸、separate/collapse 边框（中心线模型，最宽者胜）、单元格复用块级布局。
- 图片：宿主解析、异步解码失效、块级替换盒、固有比例、alt 回退；1:1 绘制像素对齐。
- Float：图片左右浮动、逐行行框避让、clear、同侧堆叠、对侧并排、文档滚动高度。
- 链接：跨行命中矩形、宿主 `onLinkTap`；单元格内链接同样可点。
- 选择（ADR 0013）：逻辑文本索引（块边界/`<br>` 换行、空白裁剪）、`selectionRects`/`selectionText`、表面半透明高亮；锚点无法映射时安全清除。
- 测试：规范化、布局、margin、盒模型、图片、浮动、表格（17 项）、选择（13 项）、CJK、长文档、公开层、像素基线和两个浏览器几何基线。

## 明确未实现

- 选择手势（点击/拖拽定位锚点）、复制菜单、命中语义、可访问性语义。
- CJK 禁则：标点行首/行尾约束、CJK 像素基线。
- 内部滚动、分块 Picture 缓存、视口虚拟化与性能门禁。
- 表格：嵌套表格（触发回退）、`colgroup/col`、浏览器级列宽分配精度。
- 行内图片基线混排、CSS 高度/百分比宽度、`auto` margin。
- QuickJS 原生执行、状态/事件/网络能力包。

## 关键约束

1. 内容呈现优先，不追求完整 W3C/WHATWG 兼容。
2. 只执行可信脚本；JS 不接触布局或渲染树。
3. 布局、选择、资源加载和 Runtime 保持分层；引擎不得知道 QuickJS。
4. 修改布局必须检查 `conformance/reference/` 基线和跨引擎差异。
5. 像素差异报告中字形抗锯齿属预期，不允许为通过测试直接放宽阈值。
6. 图片资源安全由宿主解析器负责，引擎只接受已解码 `ui.Image`。

## 验证命令

```bash
# 一键门禁 = format + analyze + verify + golden；--fast 跳过像素门禁
tool/check.sh

# 逐项运行
flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart
cd packages/weft_engine && flutter test tool/golden_pixel_test.dart --timeout 60s

# 浏览器诊断参考（本机 Chrome/Edge + Node 22）
node tool/browser_references.mjs

# 布局诊断：打印盒子/行/逻辑文本；--diff 输出逐元素 Weft-vs-Chrome 偏差表
tool/dump_layout.sh conformance/cases/table_basic.html --diff
tool/dump_layout.sh conformance/cases/float_image.html --runs

# 重新生成几何参考并直写 conformance/reference/（提交前人工审查 diff）
node tool/browser_references.mjs --case <id> --emit-reference

# 跨引擎像素报告（需要 Pillow）
python tool/compare_goldens.py --report-only

# 重新生成确定性图片资产（改动 conformance/assets 时）
python tool/generate_assets.py
```

## 建议的下一步

### A. 选择手势与复制

目标：点击放置锚点、拖拽扩展选区、长按选词、复制到剪贴板。

注意：命中测试可经 `WeftTextPaintCommand.runs` 与 `TextPainter.getPositionForOffset` 反查 `(NodeId, offset)`；锚点跨内容更新安全清除的语义已在 ADR 0013 定死，不得改为越界钳制。

### B. CJK 禁则

目标：行首/行尾标点约束、可配置标点表、CJK 结构测试扩展。

注意：换行走逐行分行路径（有浮动时）与整段路径（无浮动时），两处都要应用禁则；`conformance/cases/cjk_wrap.html` 已有结构语料。

### C. 性能与分块渲染

目标：长文档布局耗时基线、`ui.Picture` 分块缓存、视口外裁剪。

注意：当前是全量布局 + 单一命令列表；引入分块前先建立性能门禁数字，避免无基线优化。文本选择矩形依赖全量命令列表，分块后需要按块索引。

## 常见误区

- 不要把 `img` 映射为 Flutter `Image` Widget；保持单一渲染表面。
- 不要在规范化器里清洗不可信脚本；它只处理受控子集。
- 不要恢复已销毁的 Runtime 或自动重放副作用。
- 不要绕过 `_FloatContext` 直接计算行框；表格单元格用独立 `_FloatContext`（近似 BFC），不要让浮动外溢单元格。
- 不要为跨引擎像素通过而修改测试字体、通道容差或遮挡真实差异。
- 不要在折叠边框模型外给单元格再画自身边框（半边框已折算为合成 padding）。
- 浏览器几何基线重新生成后必须人工审查 diff，不允许盲目覆盖。
