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
- 可访问性语义（ADR 0024/0026/0028/0030）：单表面文本/链接/图片/选区、标题与表头 header、列表标记、list/table 嵌套角色、链接 tap、选区 copy、稳定节点 id 与屏外 showOnScreen。
- 渐进式布局虚拟化（ADR 0025）：WeftView 只物化可见顶层块，估算后缀 extent，复杂文档/选区/Semantics 回退 full。
- 锚点导航（ADR 0027/0029）：`scrollToAnchor` 同步 focus 定位，`scrollToAnchorAsync` 逐帧测量深链前缀并保持当前内容；无效/取消安全返回 false。
- 懒布局异步分帧与同快照复用（ADR 0031）：非锚点深跳/深 seed 每帧至多新测 32 个顶层块并逐帧收敛，消除冷跳底部单帧全量测量；同快照 relayout 跳过节点 diff、复用跨帧样式缓存与文本索引实例。
- 选择交互（ADR 0019）：长按选词/拖拽扩展/把手微调/复制按钮/tap 放 caret。
- 图片/Float 与表格的浏览器几何基线（Chrome 参考固化在 conformance/reference/）。
- 移动端原生构建（ADR 0035）：`weft_quickjs` 声明为 ffiPlugin；Android 模块用 CMake 就地编出 `libweft_quickjs.so`（16 KB 页对齐、只导出 `weft_*`），iOS pod 把垫片静态编进 app image 并用 ObjC 锚点防止 dead-strip；加载器按平台分派，显式路径可覆盖。

请继续下一个切片，优先级如下：
1. iOS 构建与真机验证（**暂缓**，2026-10-28：暂无 macOS 环境）：拿到 macOS/Xcode 后按 `docs/device-matrix.md` 的 iOS 清单执行；在此之前 iOS 不得宣称可用，若本次发布不含 iOS 产物，需在发布说明中写明。
2. 懒布局进阶：基于块 metrics 的窗口直物化（O(log N) 随机定位），设计约束见 ADR 0031 的后续小节（负 margin/溢出破坏 top 单调性、body chrome 重算、后缀 extent 增量缓存）；以及超高顶层块/表内行/图片解码资源虚拟化。
3. 语义增强：按产品需要补 headingLevel、语言/RTL 或 live region；保持 ADR 0024 的单表面所有权。
4. 增量布局扩展：继续缩小 O(块数) diff/样式解析，探索行级复用；保持 ADR 0023/0025 的全量等价门禁。

硬性约束：
- 不做完整浏览器；不执行不可信脚本；不把 HTML 节点映射为独立 Widget。
- 不支持的内容必须生成 SupportReport 并显式回退。
- 图片资源只能由宿主 WeftImageResolver 提供；引擎不得隐式发起网络请求。
- 每次修改必须运行 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart run tool/verify.dart` 和 `packages/weft_engine/tool/golden_pixel_test.dart`。
- 新增能力必须附带单元测试；影响布局时必须评估黄金基线与 conformance/reference/ 下的浏览器几何基线。
- 改动 `packages/weft_quickjs/native/`、`android/` 或 `ios/` 后必须跑 `packages/weft_quickjs/tool/build_native.sh` 重编桌面库并执行 `dart test`（weft_quickjs）；平台工程的编译参数必须与桌面脚本保持一致（ADR 0035）。
- 重要技术取舍写入 docs/adr/（下一个编号为 0036）。

先阅读 README.md、docs/architecture.md、docs/supported-subset.md 和 docs/handoff.md，再选择第一个任务并给出计划。

开发工作流提示（ADR 0014）：用 `tool/check.sh` 做本地门禁；新增几何案例走 `--emit-reference` 接入通用门禁，零测试代码；调布局用 `tool/dump_layout.sh --diff` 直接看偏差表；表格改动落在 `table_layout.part.dart`、行内/Float 改动落在 `inline_flow.part.dart`，两边可并行。
```

## 当前仓库状态

- 分支：`main`
- 最新提交：见 `git log`（本节只保证指南有效，不追踪哈希）
- Flutter：3.35.5 stable；Dart：3.9.2
- 常规测试 453 项（weft_engine 243、weft_document 77、weft 59、weft_quickjs 28、weft_capabilities 15、weft_runtime_fake 12、weft_runtime_contract 9、weft_runtime_api 2，另有 weft_lab 1 + weft_fallback 7）、像素黄金 3 项 + 选区高亮 1 项、性能门禁 14 场景（7 布局 + 3 绘制 + 4 命中）；`dart analyze` 无问题，公开 API 文档覆盖零缺口。开发计划阶段 0–5 已完成（阶段 5 见 ADR 0034），阶段 5 之后补了移动端原生构建（ADR 0035）。
- GitHub Actions 使用 Windows 执行像素黄金门禁。

已实现至 ADR 0035。ADR 0017–0033：分块渲染与命中裁剪（ADR 0017/0020）、行内图片（ADR 0018）、选择 chrome（ADR 0019）、块级盒模型（ADR 0021）、表格列轨道（ADR 0022）、流式顶层前缀复用（ADR 0023）、单表面 Semantics（ADR 0024/0026/0028/0030）、渐进式布局虚拟化（ADR 0025）、同步/异步锚点导航（ADR 0027/0029）、懒布局异步分帧与同快照复用（ADR 0031）、阶段 0–3 验收证据与重定界（ADR 0032）和受限 JS 运行时（QuickJS FFI + 能力网关 + 恢复去重 + 自定义标签，ADR 0033）。ADR 0034（阶段 5）：快照 JSON 线格式（format+version 门禁）与 21 个规范化一致性向量、种子化模糊测试（CI 快跑 + tool/fuzz.dart 长跑，修复诊断上限绕过与 toString 崩溃两个真实问题）、能力策略 8 子集矩阵、example/weft_fallback WebView 回退示例、发布手册与回滚演练测试、API 文档门禁、真机矩阵计划。ADR 0035：QuickJS 移动平台构建——ffiPlugin 声明、Android CMake 就地编译（16 KB 对齐）、iOS 静态链接与 dead-strip 锚点、按平台分派的加载器。

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
  weft_quickjs/         vendor QuickJS 源码、C 垫片与 dart:ffi 后端
    android/            Gradle 模块 + CMake，就地编出 libweft_quickjs.so
    ios/                podspec + ObjC 锚点，把垫片静态编进 app image
  weft_capabilities/    能力策略与内置命名空间
  weft_runtime_fake/    脚本化 FakeRuntime 后端
  weft_runtime_contract/  后端中立 JsSession 契约套件
example/weft_lab/       开发实验室、阶段 4 演示与图片资源
example/weft_fallback/  WebView 回退示例（requiresWebView → 宿主 WebView）
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
- Semantics（ADR 0024/0026）：RenderWeftSurface 手动组装阅读顺序文本、链接、图片和选区节点；标题子树带 header flag，链接语义 tap 与选区 copy 走独立回调入口，WeftView pointer/剪贴板职责不变。节点 key 对齐 NodeId，流式更新保留身份；屏外节点可 showOnScreen，选区仅暴露 value/selected/rect/copy，不伪装 text field。
- 布局虚拟化（ADR 0025）：`layoutViewport` 在原块流中连续测量精确前缀，只物化 viewport+250px 窗口；未测后缀按同类块中位数估算 extent。隐藏块释放 commands/painter，previous/current 继续单 owner 转移；跳到估算底部用 correctBy 跟随。顶层块内及 body 直属的已解析图片 Float 都以块级排除区 checkpoint 跨离屏复用；非图片/inline 祖先 Float、非空 selection（含首帧）、Semantics、未解析图片/loose inline 回退或粘滞 full。full 退出会递增 generation 并清除陈旧校正，初始 ScrollController offset 会 seed 首帧物化窗口。
- 懒布局异步分帧与同快照复用（ADR 0031）：视口末端距已测前缀超过一屏或首帧 seed 深于 overscan 时，每帧至多新测 32 个顶层块，post-frame 续帧按 `_needsLazyRelayout` 收敛，`_lazyGeneration` 取消；同快照 relayout 跳过节点 diff 与样式表比对，元素级样式缓存随增量缓存跨帧存活（宽度/缩放/图片不参与计算样式），文本索引实例直接复用。300 块冷跳底部从 124.8ms 单帧降为 10 帧 × 中位 5.8ms。
- 测试：规范化、布局、margin、盒模型、图片、浮动、表格（17 项）、选择（15 项，含 10 万字符随机选区与流式重映射）、CJK、长文档、公开层、像素基线、两个浏览器几何基线，以及语料结构断言（无丢失/无重叠/无越界）与敌意输入诊断扫描（ADR 0032）。
- 移动端原生构建（ADR 0035）：`weft_quickjs` 的 `flutter.plugin.platforms` 声明 android/ios 为 ffiPlugin，包本身不依赖 Flutter；Android 由 `android/src/main/cpp/CMakeLists.txt` 就地编译 vendor 源码（`-fvisibility=hidden`、16 KB 页对齐、`compileSdk 36`/NDK 27），iOS 由 podspec 编进 app image，`WEFT_EXPORT` 的 `used` 属性 + ObjC 锚点防止 `-dead_strip` 丢掉 `dlsym` 目标；`librarySourceFor()` 按平台分派（显式路径 > iOS process() > Android 按名打开 > 桌面文件搜索）。APK 已实测含三 ABI 的 `libweft_quickjs.so` 且恰好导出 10 个 `weft_*`；真机（Huawei JNY-AL10 / Android 10）跑通加载、JSON/字符串求值与内存/墙钟两类预算中断。

## 明确未实现

- 基于块 metrics 的窗口直物化与精确 O(1)/O(log N) 随机跳转（设计约束见 ADR 0031 后续小节），以及超高顶层块/表内行/图片解码资源虚拟化；锚点异步测量仍需顺序测量目标前缀。
- 非图片 Float 与表格局部 Float 的 checkpoint；增量布局的后缀平移与行级复用；行内原子的 margin 参与行框与 top/bottom 对齐。
- CJK 像素基线（跨引擎像素验收已按 ADR 0032 重定界为结构几何门禁；真机帧计时仍以 weft_lab 为准）。
- 表格：嵌套表格（触发回退）、浏览器级 auto 列宽分配精度、`col` 的 min/max 语义。
- Semantics 的 headingLevel、跨行跨列语义索引、CSS 列表样式/起始序号、可编辑 selection/caret 动作、RTL/语言属性、live region 与语义虚拟化。
- 受限 JS 的既有边界：bridge 风暴上限按单轮计数、`weft.net` 仅 GET、自定义标签不支持行内混排与 Float 环绕、JSON 编组把 undefined 折叠为 null（ADR 0033 后续小节）。
- 移动端验收证据：Android 已完成构建、打包与真机执行（Huawei JNY-AL10 / Android 10，加载/求值/内存与墙钟预算共 6 项冒烟全过）；iOS 构建与运行（需 macOS + Xcode + CocoaPods）**暂缓**——podspec 与锚点只经过代码审查，未执行过 `pod install`（ADR 0035）。

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

# QuickJS 原生库（首次克隆或改动 native/ 后执行；缺失时 FFI 测试跳过并给出本命令）
packages/weft_quickjs/tool/build_native.sh

# 移动端原生库：Android 需 SDK 36 + NDK 27，宿主工程需先生成 android/ 平台目录
flutter build apk --debug --target-platform android-arm64
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libweft_quickjs

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

开发计划阶段 0–5 已完成。以下为既有技术路线的延续候选（阶段 5 的验收边界外）。

### A. iOS 构建验证（暂缓，等待 macOS 环境）

目标：在 macOS + Xcode 上完成首次 `pod install` 与构建，确认 `weft_*` 符号未被剥离，并在 iOS 真机/模拟器跑通 runtime 示例；结果写入 `docs/device-matrix.md`。

状态：2026-10-28 决定暂缓——手头没有 macOS 设备。Android 已真机验证，桌面与 CI 路径不受影响；恢复时按 device-matrix §2.2 的清单逐条执行。未验证前不得对外宣称 iOS 可用，发布说明中要写明缺席。

注意：若符号缺失，先查 `-ObjC` 是否被宿主 Podfile 覆盖，再考虑把 vendor 源码移进 `ios/`（CocoaPods 文件模式不支持 `..`，当前用绝对路径绕过）。

### B. 懒布局进阶

目标：基于块 metrics 的窗口直物化（真正的 O(log N) 随机定位），让更多文档形态受益。

注意：异步分帧与同快照复用已由 ADR 0031 交付（深跳/深 seed 每帧 ≤ 32 块、同快照跳过 diff/样式解析/文本索引重建）；窗口直物化的三个前置问题（负 margin/溢出破坏 top 单调性、body chrome 重算、后缀 extent 增量缓存）记录在 ADR 0031 的后续小节。先画像再动手；继续保留 canonical full 与结构计数门禁。

### C. 语义增强

目标：按产品需求补 headingLevel、table/list 角色、CSS 列表序号、语言/RTL、live region 或更细选区动作。

注意：继续使用 describeSemanticsConfiguration/assembleSemanticsNode 的单表面模型；table/list role 需要真正嵌套容器节点并满足 Flutter 的严格父子校验，不要用扁平节点伪装。不要把静态文档伪装成 text field，也不要让语义节点持有旧 TextPainter。lazy 路径在 assemble 前必须升级 full。

### D. 增量布局扩展

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
- 分帧续推的停机条件是 `_needsLazyRelayout()`（窗口被前缀覆盖即停），不是 `measuredPrefixLength == body.children.length`：窗口末端之外的最后若干块会一直保持估算，拿前缀长度对块数做循环条件会永不终止。
- 浏览器几何基线重新生成后必须人工审查 diff，不允许盲目覆盖。
- 阶段 4 的 QuickJS 需要 native 库：测试在库缺失时跳过并提示 `packages/weft_quickjs/tool/build_native.sh`；不要把跳过当验收，中断/内存证据以真实 QuickJS 测试为准。
- 能力调用风暴的上限按"单个事件循环轮次"计数（`_maxBridgeCallsPerTurn`），不是累计预算；跨轮的链式风暴由 `settle()` 的 256 轮兜底，两者都不能省。
- 自定义标签是属性驱动的叶子元素：内容在规范化时丢弃（有诊断），不要指望布局遍历其子树，也不要忘记 `WeftNormalizer.customTags` 与引擎 `tagRenderers` 两处要同步。
- 移动端编译参数要三处一致：`tool/build_native.sh`、`android/src/main/cpp/CMakeLists.txt`、`ios/weft_quickjs.podspec` 必须反映同一组宏（`CONFIG_VERSION`、`CONFIG_BIGNUM`、`-fno-strict-aliasing`）；只改一处会让同一脚本在不同平台行为分叉。
- 不要删除 iOS 的锚点类或 `WEFT_EXPORT` 的 `used` 属性：它们不是死代码，去掉后 `-dead_strip` 会连同 `dlsym` 目标一起丢弃，而桌面测试完全发现不了。
