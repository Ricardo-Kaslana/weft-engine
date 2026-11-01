# Weft Engine

[![ci](https://github.com/Ricardo-Kaslana/weft-engine/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/Ricardo-Kaslana/weft-engine/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Weft 是一个面向 Flutter 的轻量级、受控型 HTML/CSS 渲染引擎项目，目标场景是 CMS 文章、商品描述、帮助文档和 AI 流式内容。它以内容呈现和轻交互为主，不试图成为完整浏览器。

## 当前状态

开发计划 **阶段 0–5 已完成**（静态渲染、内容排版、长文档与性能、受限 JS 与能力扩展、回退硬化与发布），可用于受控内容子集的实验和内部验证，尚不是稳定版本。当前预发布：[v0.7.0-dev.2](https://github.com/Ricardo-Kaslana/weft-engine/releases/tag/v0.7.0-dev.2)。

已实现：

- Flutter 3.35.5 兼容基线（ADR 0038）：Flutter 依赖包与示例声明 `flutter: ">=3.35.5"`，纯 Dart 包保持 Dart 3.5；包版本统一为 0.7.0-dev.2。
- 受控 HTML 解析、标签白名单、属性清洗、支持度诊断和显式回退。
- 标签、类、ID、后代和子代选择器，以及基础层叠、内联样式和常用文本/盒模型属性。
- 标题、段落、强调、链接、列表、引用、代码块、分隔线和强制换行。
- Block/Inline 布局、空白折叠、相邻与父子 margin 折叠、列表标记和可缩放文本绘制。
- 与 CSS 半行距一致的文本行高分配，固定字体下块级几何与 Chromium 误差小于 0.5px。
- 块级 `width`/`min-width`/`max-width`（含百分比宽）、CSS `height`、水平 `auto` margin、`box-sizing` 和基础实线边框绘制（ADR 0021）。
- 链接按行生成命中矩形，跨行链接可点击，并通过 `WeftView.onLinkTap` 交给宿主处理。
- 图片由宿主 `WeftImageResolver` 按需提供，支持宽高属性、固有比例、CSS px/百分比宽度与显式高度、最大宽度约束和异步解码失效。
- 行内图片基线混排（ADR 0018）：img 默认 `display: inline`（与浏览器 UA 样式表一致），以原子占位符参与断行、`vertical-align: baseline/middle` 对齐与行高增长，`display: block` 退回块级替换盒；选区/复制跳过图片。
- 图片 `float: left/right`、逐行文字环绕、`clear`、同侧堆叠和对侧并排；浮动内容计入文档滚动高度。
- 图片资源不可用时回退为 `alt` 文本，不发起隐式网络请求。
- 表格：`table/thead/tbody/tfoot/tr/th/td/caption`、`colspan/rowspan`（含隐式行）、caption、separate/collapse 边框、`border-spacing` 与单元格 `vertical-align`；`colgroup/col` 列宽（px 固定列、百分比列、span，ADR 0022）；单元格复用块级布局，链接可点。
- 逻辑文本索引与选区解析（ADR 0013）：跨段锚点→视觉矩形和复制文本，`WeftSurface` 绘制选择高亮。
- 选择手势（ADR 0015/0019）：长按选词、拖拽扩展、点击文本放置 caret、点击空白清除，`WeftView.selectionText()` 导出选区文本；链接点击与选择共存。
- 选择 chrome（ADR 0019）：折叠选区绘制 caret；选择把手可拖拽移动选区端点；复制按钮写入剪贴板并保留选区（`copyButtonLabel` 可配）；`WeftView.onSelectionChanged` 向宿主上报选区文本；把手/复制按钮可用 `showSelectionHandles`/`showCopyButton` 关闭。
- CJK 禁则（ADR 0016）：可配置行首/行尾禁则表（默认覆盖常用中日标点），逐行分行路径显式执行禁则；整段路径经 ICU 对照零违规。
- 分块渲染（ADR 0017）：绘制命令按 body 顶层子节点分块缓存为 `ui.Picture`，绘制时按可见窗口裁剪、只重绘相交块；选区矩形独立缓存，选区变化不重建 Picture。
- 流式增量布局（ADR 0023/0044/0046）：同 id 追加复用未变顶层前缀与 TextPainter，未变前缀 Picture 跨快照保留；流式快照的文本索引按前缀复用条目（ADR 0044，lazy 部分窗口亦参与，ADR 0048），变化区之后的形状相同块平移复用——中部编辑与头部插入与尾部追加同为 91–95% saving 档（ADR 0046）；头部插入/头删除轮的索引条目经反向 diff 后缀映射平移重映射（ADR 0051）；lazy 滚动会话的流式轮沿用已证前缀的准入结论与逐子估算（ADR 0049），plain 复用块样式成对沿用（ADR 0050），复用轮与样式表规模脱钩。
- 可访问性语义（ADR 0024/0026/0028/0030/0039/0040/0042）：单表面文本、链接、图片与选区 Semantics，支持标题 headingLevel 与表头 header、有序列表 start/value 标记、`aria-live` live region、list/table 嵌套角色与 indexInParent、链接语义 tap、选区 copy 和屏外 showOnScreen；ARIA `role` 保守映射、`aria-hidden`/`aria-label`/`aria-atomic` 整组播报，叶子 textDirection 随块方向。
- ARIA 基础（ADR 0040）：规范化器保留 `role`/`aria-hidden`/`aria-atomic`/`aria-label`（修复自定义标签在读而标准标签被丢弃的错位）；`alert`/`status` 隐式化为 live+atomic 播报，`presentation` 抑制自身派生语义。
- RTL 与语言（ADR 0042）：`dir`（含 `auto` first-strong 检测）与 CSS `direction` 驱动块级基方向——RTL 起始对齐、Float 逐行断行、列表缩进/marker 镜像、caret 行内首侧；`lang` 转为 TextPainter locale（缺省 `zh` 不变）；`rtl_paragraph` Chrome 几何参考钉住方向边缘。
- 渐进式布局虚拟化（ADR 0025/0041）：WeftView 简单长文只物化可见块，首屏不创建全文 TextPainter；`lazyOverscan` 可调预取窗口，顶层块内及 body 直属图片 Float 通过排除区 checkpoint 参与 lazy，selection/复杂文档回退 full；Semantics 直接在 lazy 结果上组装窗口化语义（物化窗口精确、视口附近未物化块折叠为粗叶子、未测后缀滚动物化后出现），读屏开启不再丢失虚拟化收益。
- 懒布局异步分帧与同快照复用（ADR 0031）：深跳/深 seed 每帧至多新测 32 个顶层块并逐帧收敛，消除冷跳底部的单帧全量测量停顿；同快照滚动 relayout 跳过节点 diff、复用跨帧样式缓存与文本索引。
- 已测窗口直物化（ADR 0036）：按保守绘制区间索引定位窗口，缓存准入、块流元数据与后缀估算；支持 body 格式化空白，热态不再重扫全文，extent 校正后同步实际视口。JNY-AL10 profile 已验收（冷启动中位 635ms、滚动 p95 ≈26ms 且无 >50ms 帧、深跳最大 37ms、内存 +10MB）。
- 冷深跳 settling 遮罩（ADR 0037）：`WeftView.lazySettlingBuilder` 在分帧测量期间覆盖宿主视口，`onLazySettlingChanged` / `WeftViewState.isLazySettling` post-frame 报告起止；未配置时不改变原有渐进填充，引擎不绘制占位。`example/weft_live` 接入静态骨架，语义开启的冷深跳同样进入 settling（ADR 0041）。Android 验收见 `docs/device-matrix.md` §4.8。
- 阶段 0–3 验收证据（ADR 0032）：商品/帮助文档语料的无丢失/无重叠/无越界结构断言、敌意输入诊断扫描、10 万字符随机跨段选区与复制（代理对安全）、流式选区重映射/安全清除、滚动缓存预算稳定、晚解码 Float 等价，以及"标签→Widget"基线与滚动帧耗时两个基准工具。
- 锚点导航（ADR 0027/0029）：`scrollToAnchor` / `scrollToNode` 精确定位，异步版本逐帧测量深链前缀并保持当前内容；无效或取消请求安全返回 false。
- 性能门禁：布局/绘制/命中 14 场景基准工具与 10 倍宽上限的 CI 稳定门禁（见 docs/testing-strategy.md）；命中解析经分块索引裁剪（ADR 0020），`WeftView.scrollController` 可注入。
- 受限 JavaScript（ADR 0033）：vendor QuickJS 2024-01-13 + C 垫片 + `dart:ffi` 真实执行；墙钟/内存/栈/微任务四类预算原生强制，无限循环与内存炸弹在配置预算内中断且界面保留最后可用帧。
- 移动端原生构建（ADR 0035）：`weft_quickjs` 声明为 FFI 插件；Android 模块用 CMake 就地编译 vendor 源码为 `libweft_quickjs.so`（隐藏内部符号、16 KB 页对齐），iOS pod 把垫片编进 app image 并用 ObjC 锚点防止 dead-strip；加载器按平台分派，显式路径仍可覆盖。
- 单文档能力宿主：`weft.state/events/net` 模块经版本化能力桥暴露，未启用能力在 JS 中不可见；网络仅 GET、scheme/host 白名单、逐跳重定向校验与副作用审计。
- 会话恢复不自动重放网络副作用；网关按 `(sessionId, sequence)` 去重重投递命令，网络客户端跨恢复恰好调用一次。
- 自定义标签：`WeftNormalizer.customTags` 白名单 + 受信任 Dart `WeftTagRenderer`（rect/text ops、语义标签、`onTagTap`），由引擎钳制并转为常规绘制命令。
- 后端契约：`weft_runtime_contract` 契约套件同时覆盖 QuickJS FFI 与脚本化 FakeRuntime（`weft_runtime_fake`），替换后端不修改引擎核心。
- `float_image` 一致性案例：Chrome 生成的浏览器几何基线（块、图片、逐行词盒误差 ≤ 0.5px）与 Flutter 像素黄金双重门禁；图片按 1:1 对齐整像素绘制。
- 快照 JSON 线格式（ADR 0034）：`WeftDocumentJson` 确定性编码 + format/version 门禁，服务端可规范化一次、客户端直接解码消费；`conformance/normalization/` 下 22 个一致性向量逐字节约束服务端/客户端规范化一致性。
- 硬化与模糊测试（ADR 0034）：种子化 fuzz 覆盖规范化管线（CI 快跑 + `tool/fuzz.dart` 发布前长跑）；能力策略 8 子集矩阵；公开 API 文档门禁（`tool/doc_coverage.dart`）。
- WebView 回退示例（ADR 0034）：`example/weft_fallback` 演示 requiresWebView → 宿主 WebView 的决策与接入；发布手册 `docs/release-runbook.md` 固化版本锚点、发布清单与回滚演练；真机矩阵计划见 `docs/device-matrix.md`。
- `table_basic`/`table_cols` 一致性案例：表格浏览器几何基线（单元格 ≤ 1.5px、行/列结构精确断言），覆盖 collapse/separate、跨列跨行、caption 与 colgroup/col 列宽。
- 单一 `RenderObject` 渲染表面、可滚动公开视图和真实文本/背景/图片绘制指令。
- 中英文内容、窄宽度换行及 300 段长文档的布局烟测。
- 十二类代表性内容语料，以及 Chrome/Edge 诊断参考截图生成器。
- Apache 2.0 Roboto/Roboto Mono 固定字体、三个 Flutter 像素黄金基线（含图片/浮动案例）、确定性 PNG 图片资产和 Windows CI 门禁。
- Dart Pub workspace、全包自动测试（数量以 `tool/verify.dart` 输出为准）、3 项像素测试、浏览器几何基线测试、规范化一致性向量、模糊测试、API 文档门禁和 GitHub Actions CI。

尚未实现：

- CJK 像素基线（无可分发 CJK 像素字体，跨引擎像素验收已按 ADR 0032 重定界为结构几何门禁）。
- 表格的嵌套表格（触发回退）与浏览器级 auto 列宽分配精度。
- 选择工具条（完整菜单）与 chrome 动画打磨；ARIA 增强（landmark/tab/menu 族角色、`aria-level`/`aria-labelledby`）；行内双向重排的中性字符行缘解析与竖排（基础 RTL 块方向已由 ADR 0042 支持，行内 BiDi 委托 SkParagraph）。
- 未测区域的精确 O(1)/O(log N) 随机跳转，以及超高顶层块/表内行/图片解码资源虚拟化；冷跳仍分帧测量前缀，配置 `lazySettlingBuilder` 时由宿主遮罩覆盖，但仍不承诺零空白（ADR 0037）。
- 严格 60fps 的滚动预算：JNY-AL10 上 combined p95 ≈26ms，瓶颈在 raster；12+12 轮 Impeller/Skia A/B（device-matrix §4.7）未发现可复现的后端优势（SCROLL total p95 25.70 vs 24.49ms，p≈0.33），不建议旧 Mali 关闭 Impeller；冷跳分帧期间仍会有短暂空白，见 `docs/device-matrix.md` §4.4/§4.7。
- 真机证据：Android 已完成构建、打包与真机执行验证（Huawei JNY-AL10 / Android 10）；iOS 由 macOS CI 覆盖无签名构建、`weft_*` 符号检查与 iPhone 模拟器 runtime 冒烟（加载/求值/超时中断/恢复），物理设备仍未验证，见 `docs/device-matrix.md`。

`example/weft_lab` 展示真实可滚动的静态文章；`example/weft_live` 把实时图表、自动快照、投票、主题切换和深链接聚合到一张专题页里，并接入冷跳 settling 骨架与跳底控件。两者均不用于验收完整 HTML/CSS 兼容性。当前限制与后续顺序见 `docs/supported-subset.md` 和 `docs/development-plan.md`。

## 安装

8 个包已具备发布条件（每包 README/CHANGELOG/LICENSE、`repository`/`issue_tracker`/`topics`，包间依赖为版本约束），但**尚未发布到 pub.dev**。这带来一个过渡期约束：**包间依赖是版本约束，pub 只会去 pub.dev 找它们**，因此单独引用 `packages/weft` 会解析失败。

发布前的外部接入方式是把同级包也指向同一 ref：

```yaml
dependencies:
  weft:
    git:
      url: https://github.com/Ricardo-Kaslana/weft-engine
      ref: v0.7.0-dev.2
      path: packages/weft

dependency_overrides:
  weft_runtime_api:
    git: {url: https://github.com/Ricardo-Kaslana/weft-engine, ref: v0.7.0-dev.2, path: packages/weft_runtime_api}
  weft_document:
    git: {url: https://github.com/Ricardo-Kaslana/weft-engine, ref: v0.7.0-dev.2, path: packages/weft_document}
  # …weft_capabilities / weft_runtime_fake / weft_runtime_contract /
  #   weft_engine / weft_quickjs，共 7 个
```

`dart run tool/consumer_smoke.dart --keep` 会生成一份可直接参照的 `pubspec_overrides.yaml`。发布到 pub.dev 后只需一行：

```yaml
dependencies:
  weft: ^0.7.0-dev.2
```

发布前可用 dry-run 门禁自查（不会联网推送）：

```bash
dart run tool/pub_dry_run.dart
```

## 仓库结构

```text
packages/
  weft/                 Flutter 公开 API 与文档控制器
  weft_document/        纯 Dart 文档、支持度和逻辑文本模型
  weft_engine/          Flutter 布局、渲染与交互层
  weft_runtime_api/     Runtime、桥接和能力扩展抽象
  weft_quickjs/         QuickJS 源码、C 垫片与 dart:ffi 后端
    android/src/main/cpp/CMakeLists.txt  Android 原生构建（libweft_quickjs.so）
    ios/weft_quickjs.podspec             iOS 静态链接（编进 app image）
  weft_capabilities/    能力模块、装载策略与桥接网关
  weft_runtime_fake/    脚本化 FakeRuntime 后端
  weft_runtime_contract/  后端中立 JsSession 契约测试套件
example/weft_lab/       开发、示例和图片资源实验室
example/weft_live/      实时专题页演示（Web target、自定义标签、动态快照）
example/weft_fallback/  WebView 回退示例（requiresWebView 决策演示）
conformance/            语料、固定字体、Flutter 基线和浏览器参考输入
docs/                   架构、规范、计划和管理文档
tool/verify.dart        全包测试入口
tool/consumer_smoke.dart  仓库外 Git 消费者冒烟测试
tool/ios_smoke.dart       macOS 上的 iOS 无签名构建与 QuickJS 符号检查
tool/browser_references.mjs  Chrome/Edge 诊断截图生成器
tool/compare_goldens.py     跨引擎像素差异报告
.github/workflows/      持续集成
```

引擎包不依赖 QuickJS 或具体能力实现；宿主应用按需组合后端和能力包。

## 环境要求

- Dart SDK 3.5 或更高，低于 4.0（纯 Dart 包；Flutter 3.35.5 随带 Dart 3.9.2）。
- Flutter SDK 3.35.5 或更高，建议使用 stable（引擎与示例的编译下限，ADR 0038）。
- Android/iOS 真机验证需要对应平台工具链。
- Node.js 22 或更高仅用于可选的 Chrome/Edge 参考截图工具。
- Python 3.11 或更高与 Pillow 仅用于可选的跨引擎像素报告。

仓库使用 Dart Pub workspace，要求所有包在 workspace 根目录统一解析依赖。

## 初始化与验证

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart
```

一键本地门禁（覆盖 CI 的格式、分析、API 文档覆盖、全包测试和像素检查；`--fast` 跳过像素门禁）：

```bash
tool/check.sh
```

布局诊断（打印盒子/行/逻辑文本，`--diff` 对比 Chrome 几何参考）：

```bash
tool/dump_layout.sh conformance/cases/table_basic.html --diff
```

`tool/verify.dart` 分别使用 `dart test` 和 `flutter test` 执行纯 Dart 包与 Flutter 包测试。

固定字体的 Flutter 像素基线需要在 Windows 环境单独验证：

```bash
cd packages/weft_engine
flutter test tool/golden_pixel_test.dart --timeout 120s
```

## 持续集成

`.github/workflows/ci.yaml` 定义三个任务，均固定 Flutter 3.35.5：

- `verify`（Ubuntu）：解析依赖、构建 QuickJS 原生库、验证原生库可加载，然后执行格式、静态分析、API 文档覆盖、全部包测试和仓库外 Git 消费者冒烟测试。
- `golden`（Windows）：比较 3 个 Flutter 像素黄金基线。
- `ios`（macOS 15）：创建临时 iOS 宿主，执行 CocoaPods 集成和无签名 release 构建，并在 app bundle（Runner 或链接的 framework）中确认全部 10 个 `weft_*` 符号。

仓库已配置 GitHub 远端 `origin`（`Ricardo-Kaslana/weft-engine`）。工作流在 `main` push、Pull Request 和手动触发时运行，状态见顶部 CI 徽章与 Actions 页面。

## 图片资源

图片不会由引擎隐式加载。宿主通过 `WeftView.imageResolver` 提供 `ImageProvider`：

```dart
WeftView(
  controller: controller,
  imageResolver: (request) {
    if (request.src == 'asset:assets/cover.png') {
      return const AssetImage('assets/cover.png');
    }
    return null; // 显示 alt 文本
  },
)
```

解析器应执行 URL 白名单、认证、缓存和解码大小策略。`float: left/right` 与 `clear` 当前只对 `img` 生效。

## 运行实验室

`example/weft_lab` 未提交平台原生目录。安装 Flutter 后补齐所需平台：

```bash
flutter create --platforms=android,ios --project-name weft_lab .
flutter run
```

实验室演示使用 `weft_runtime_fake`。真实 QuickJS 的原生构建已由 `weft_quickjs` 提供（ADR 0035）：Android 由 CMake 就地编译，iOS 由 podspec 静态链接，由 macOS CI 执行无签名构建、符号检查与模拟器 runtime 冒烟（物理设备仍待验证），桌面端需先运行 `packages/weft_quickjs/tool/build_native.sh`。

## 运行实时专题页

`example/weft_live` 是一张由 Weft 渲染的实时专题页，包含每 2 秒更新的现场
指标与脉冲图、自动进入的直播记录、可投票/鼓掌的自定义标签、明暗主题、
频道筛选、站内锚点导航和可直接分享的深链接（如
`/?theme=dark&section=agenda`）。它已带 Web 平台目录：

```bash
cd example/weft_live
flutter run -d chrome
```

页面只使用受控 HTML/CSS 子集和受信任的 Dart 自定义标签，不使用 WebView、
DOM 或第三方脚本。详情见 `example/weft_live/README.md`。

## 文档导航

- [总体架构](docs/architecture.md)
- [模块与接口契约](docs/api-contracts.md)
- [目标 HTML/CSS 子集](docs/supported-subset.md)
- [内容规范化](docs/content-normalization.md)
- [开发里程碑](docs/development-plan.md)
- [测试与性能策略](docs/testing-strategy.md)
- [一致性语料与浏览器参考](conformance/README.md)
- [安全与资源限制](docs/security.md)
- [项目管理](docs/project-management.md)
- [交接说明与提示词](docs/handoff.md)
- [发布与回退](docs/release.md)
- [架构决策记录](docs/adr/)
- [贡献指南](CONTRIBUTING.md)

## 明确边界

不执行不可信第三方脚本，不提供完整 DOM、npm 生态、Canvas/WebGL、富文本编辑或现有 Web 应用的无损迁移。内容规范化不是安全清洗器；复杂或明确不支持的内容由宿主通过 `SupportReport` 和回退策略处理。

## 许可证

本项目采用 [MIT License](LICENSE)，版权归 Weft Engine contributors 所有。

第三方组件保留各自许可证：

- QuickJS：MIT，见 `packages/weft_quickjs/ios/Classes/native/quickjs/LICENSE`
- Roboto / Roboto Mono：Apache-2.0，见 `conformance/fonts/LICENSE-Roboto.txt`
