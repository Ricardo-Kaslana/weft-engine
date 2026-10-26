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
- 分块渲染（ADR 0017）：按块缓存 ui.Picture、可见窗口裁剪、选区矩形与 caret 独立缓存；命中解析经分块索引裁剪（ADR 0020）。
- 行内图片基线混排（ADR 0018）：img 默认 inline 原子参与断行，CSS 宽高（含百分比宽）。
- 块级盒模型（ADR 0021）：显式 height（不裁剪溢出）、百分比宽度、水平 auto margin。
- 表格列轨道（ADR 0022）：colgroup/col 声明 px 固定列、百分比列与 span 轨道。
- 流式增量布局（ADR 0023）：复用无 Float 的顶层前缀块/TextPainter，尾部重排；未变 Picture 跨快照复用。
- 可访问性语义（ADR 0024）：单表面 Semantics 文本/链接/图片/选区、链接 tap、稳定节点 id 与屏外 showOnScreen。
- 渐进式布局虚拟化（ADR 0025）：WeftView 只物化可见顶层块，估算后缀 extent，复杂文档/选区/Semantics 回退 full。
- 选择交互（ADR 0019）：长按选词/拖拽扩展/把手微调/复制按钮/tap 放 caret。
- 图片/Float 与表格的浏览器几何基线（Chrome 参考固化在 conformance/reference/）。

请继续下一个切片，优先级如下：
1. 懒布局进阶：按画像加入异步分帧测量、Float checkpoint 与精确随机定位，减少冷跳底部的 O(N) 停顿。
2. 语义增强：按产品需要补 heading/table/list 角色、语言/RTL 或 live region；保持 ADR 0024 的单表面所有权。
3. 增量布局扩展：继续缩小 O(块数) diff/样式解析，探索行级复用；保持 ADR 0023/0025 的全量等价门禁。

硬性约束：
- 不做完整浏览器；不执行不可信脚本；不把 HTML 节点映射为独立 Widget。
- 不支持的内容必须生成 SupportReport 并显式回退。
- 图片资源只能由宿主 WeftImageResolver 提供；引擎不得隐式发起网络请求。
- 每次修改必须运行 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart run tool/verify.dart` 和 `packages/weft_engine/tool/golden_pixel_test.dart`。
- 新增能力必须附带单元测试；影响布局时必须评估黄金基线与 conformance/reference/ 下的浏览器几何基线。
- 重要技术取舍写入 docs/adr/（下一个编号为 0026）。

先阅读 README.md、docs/architecture.md、docs/supported-subset.md 和 docs/handoff.md，再选择第一个任务并给出计划。

开发工作流提示（ADR 0014）：用 `tool/check.sh` 做本地门禁；新增几何案例走 `--emit-reference` 接入通用门禁，零测试代码；调布局用 `tool/dump_layout.sh --diff` 直接看偏差表；表格改动落在 `table_layout.part.dart`、行内/Float 改动落在 `inline_flow.part.dart`，两边可并行。
```

## 当前仓库状态

- 分支：`main`
- 最新提交：见 `git log`（本节只保证指南有效，不追踪哈希）
- Flutter：3.35.5 stable；Dart：3.9.2
- 常规测试 250+ 项（weft_engine 210、weft 25）、像素黄金 3 项 + 选区高亮 1 项、性能门禁 14 场景（7 布局 + 3 绘制 + 4 命中）；`dart analyze` 无问题。
- GitHub Actions 使用 Windows 执行像素黄金门禁。

已实现到 ADR 0025：分块渲染与命中裁剪（ADR 0017/0020）、行内图片（ADR 0018）、选择 chrome（ADR 0019）、块级盒模型（ADR 0021）、表格列轨道（ADR 0022）、流式顶层前缀复用（ADR 0023，同轮 31.8ms→6.7ms）、单表面 Semantics（ADR 0024）和渐进式布局虚拟化（ADR 0025，article300 首屏 43.6ms→3.2ms、330 块→6 块）。

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
- 选择（ADR 0013/0015/0019）：逻辑文本索引（块边界/`<br>` 换行、空白裁剪）、`selectionRects`/`selectionText`、表面高亮；长按选词、拖拽扩展、把手微调端点、复制按钮（剪贴板策略在 weft 层）、tap 放 caret；`WeftView.onSelectionChanged`。
- 分块渲染（ADR 0017）：绘制命令按 body 顶层子节点分块缓存 `ui.Picture`，三层可见矩形策略（canvas clip → viewport transform → 全绘兜底）；选区矩形与 caret 独立 memo，选区变化不重建 Picture。
- 行内图片（ADR 0018）：img 默认 `display: inline`（UA 语义）以 U+FFFC 占位原子参与两条行内路径的断行，`vertical-align: baseline/middle`，占位符不随 textScaler 缩放；CSS height px 与百分比宽（相对包含块）。
- 块级盒模型（ADR 0021）：显式 `height`（box-sizing 换算，溢出不裁剪照绘，阻止自垮塌）；百分比 `width` 相对包含块 content 宽；水平 `margin: auto` 分配剩余空间（双边居中/单边全吃/负按 0）。
- 命中裁剪（ADR 0020）：`WeftLayoutResult.attachDocument` 后命中查询经分块索引（段 bounds 条带）裁剪，语义与全量倒扫逐点等价；`WeftView.scrollController` 可注入。
- 列轨道（ADR 0022）：`colgroup/col` 的 px 固定列（min=max=声明值）、百分比列（基数 = 表内容宽）、span 轨道与 colspan 平摊绕过固定列；带轨道 collapse 表采用 Chrome 盒语义。
- 流式增量（ADR 0023）：公共顶层前缀按规范化子树与全局输入键复用，在原块流中跳过递归排版并保留 TextPainter；连续快照重新绑定缓存节点。旧结果含 Float、全局输入变化等情况全量回退；文本索引仍全量重建，未变前缀 Picture 跨布局保留。
- Semantics（ADR 0024）：RenderWeftSurface 手动组装阅读顺序文本、链接、图片和选区节点；链接语义 tap 走独立回调入口，WeftView pointer 手势仍单 owner。节点 key 对齐 NodeId，流式更新保留身份；屏外节点可 showOnScreen，选区仅暴露 value/selected/rect，不伪装 text field。
- 布局虚拟化（ADR 0025）：`layoutViewport` 在原块流中连续测量精确前缀，只物化 viewport+250px 窗口；未测后缀按同类块中位数估算 extent。隐藏块释放 commands/painter，previous/current 继续单 owner 转移；跳到估算底部用 correctBy 跟随。非空 selection、Semantics、Float、未解析图片/loose inline 回退或粘滞 full。
- 测试：规范化、布局、margin、盒模型、图片、浮动、表格（17 项）、选择（13 项）、CJK、长文档、公开层、像素基线和两个浏览器几何基线。

## 明确未实现

- 懒布局的异步分帧测量、Float checkpoint、精确随机跳转，以及超高顶层块/表内行/图片解码资源虚拟化。
- 增量布局的 Float checkpoint、后缀平移与行级复用；行内原子的 margin 参与行框与 top/bottom 对齐。
- CJK 像素基线与跨引擎像素预算达标。
- 表格：嵌套表格（触发回退）、浏览器级 auto 列宽分配精度、`col` 的 min/max 语义。
- Semantics 的 heading/table/list 角色导航、可编辑 selection/copy/caret 动作、RTL/语言属性、live region 与语义虚拟化。
- QuickJS 原生执行、状态/事件/网络能力包。
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

### A. 懒布局进阶

目标：降低冷跳底部的同步测量停顿，并让更多文档形态受益。

注意：先画像；候选是异步分帧连续测量、Float/块流 checkpoint、精确块索引随机跳转，以及超高顶层块/表内行或图片资源虚拟化。继续保留 canonical full 与结构计数门禁。

### B. 语义增强

目标：按产品需求补 heading/table/list 角色、语言/RTL、live region 或更细选区动作。

注意：继续使用 describeSemanticsConfiguration/assembleSemanticsNode 的单表面模型；不要把静态文档伪装成 text field，也不要让语义节点持有旧 TextPainter。lazy 路径在 assemble 前必须升级 full。

### C. 增量布局扩展

目标：在保持全量等价的前提下减少剩余 O(块数) diff/样式解析，或支持含 Float 文档与更多编辑形态。

注意：先画像再选择 Float checkpoint、后缀平移、文本索引增量或更细粒度片段；不要把 ADR 0023/0025 的保守回退改成未验证的近似复用。

## 常见误区

- 不要把 `img` 映射为 Flutter `Image` Widget；保持单一渲染表面。
- 不要在规范化器里清洗不可信脚本；它只处理受控子集。
- 不要恢复已销毁的 Runtime 或自动重放副作用。
- 不要绕过 `_FloatContext` 直接计算行框；表格单元格用独立 `_FloatContext`（近似 BFC），不要让浮动外溢单元格。
- 不要为跨引擎像素通过而修改测试字体、通道容差或遮挡真实差异。
- 不要在折叠边框模型外给单元格再画自身边框（半边框已折算为合成 padding）。
- 不要把选区高亮、caret 或任何 chrome 画进分块 `ui.Picture`——它们必须随选区即时重绘，进 Picture 会破坏 ADR 0017 的缓存计数与失效语义。
- 不要让两个布局结果共同持有同一个 TextPainter；ADR 0023 会转移复用命令所有权并使 previous 的增量缓存失效，成功复用过的 previous 不得再次作为复用来源。
- 不要用 MergeSemantics 推导单画布内容，也不要同时暴露块全文和相同链接/图片子节点；语义数据必须跟随当前 document/layout，不能按可见 Picture 裁剪。
- 不要把未测后缀的估算高度当作精确块位置，也不要在 lazy 窗口外伪造命中、选择或 Semantics；需要完整几何时先升级 canonical full。
- 浏览器几何基线重新生成后必须人工审查 diff，不允许盲目覆盖。
