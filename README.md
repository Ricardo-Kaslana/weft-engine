# Weft Engine

Weft 是一个面向 Flutter 的轻量级、受控型 HTML/CSS 渲染引擎项目，目标场景是 CMS 文章、商品描述、帮助文档和 AI 流式内容。它以内容呈现和轻交互为主，不试图成为完整浏览器。

## 当前状态

当前为 **阶段 2（进行中）：图片资源与 Float 文字环绕**，可用于受控内容子集的实验和内部验证，尚不是稳定版本。

已实现：

- 受控 HTML 解析、标签白名单、属性清洗、支持度诊断和显式回退。
- 标签、类、ID、后代和子代选择器，以及基础层叠、内联样式和常用文本/盒模型属性。
- 标题、段落、强调、链接、列表、引用、代码块、分隔线和强制换行。
- Block/Inline 布局、空白折叠、相邻与父子 margin 折叠、列表标记和可缩放文本绘制。
- 与 CSS 半行距一致的文本行高分配，固定字体下块级几何与 Chromium 误差小于 0.5px。
- 块级 `width`/`min-width`/`max-width`、`box-sizing` 和基础实线边框绘制。
- 链接按行生成命中矩形，跨行链接可点击，并通过 `WeftView.onLinkTap` 交给宿主处理。
- 图片由宿主 `WeftImageResolver` 按需提供，支持宽高属性、固有比例、最大宽度约束和异步解码失效。
- 图片 `float: left/right`、逐行文字环绕、`clear`、同侧堆叠和对侧并排；浮动内容计入文档滚动高度。
- 图片资源不可用时回退为 `alt` 文本，不发起隐式网络请求。
- 单一 `RenderObject` 渲染表面、可滚动公开视图和真实文本/背景/图片绘制指令。
- 中英文内容、窄宽度换行及 300 段长文档的布局烟测。
- 六类代表性内容语料，以及 Chrome/Edge 诊断参考截图生成器。
- Apache 2.0 Roboto/Roboto Mono 固定字体、两个 Flutter 像素黄金基线和 Windows CI 门禁。
- Dart Pub workspace、73 项常规自动测试、2 项像素测试和 GitHub Actions CI。

尚未实现：

- 表格、行内图片基线混排和 CJK 禁则。
- CJK 像素字体与跨引擎像素预算达标。
- 跨段落选择、复制菜单和可访问性语义。
- 分块 Picture 缓存、视口虚拟化和内部滚动容器。
- QuickJS 原生库、FFI 绑定和真实脚本执行。
- 状态、事件、网络能力包的具体实现。

`example/weft_lab` 已展示真实可滚动的静态文章，但仍不用于验收完整 HTML/CSS 兼容性。当前限制与后续顺序见 `docs/supported-subset.md` 和 `docs/development-plan.md`。

## 仓库结构

```text
packages/
  weft/                 Flutter 公开 API 与文档控制器
  weft_document/        纯 Dart 文档、支持度和逻辑文本模型
  weft_engine/          Flutter 布局、渲染与交互层
  weft_runtime_api/     Runtime、桥接和能力扩展抽象
  weft_quickjs/         QuickJS 原生适配边界
  weft_capabilities/    内置能力标识与装载策略
example/weft_lab/       开发、示例和图片资源实验室
conformance/            语料、固定字体、Flutter 基线和浏览器参考输入
docs/                   架构、规范、计划和管理文档
tool/verify.dart        全包测试入口
tool/browser_references.mjs  Chrome/Edge 诊断截图生成器
tool/compare_goldens.py     跨引擎像素差异报告
.github/workflows/      持续集成
```

引擎包不依赖 QuickJS 或具体能力实现；宿主应用按需组合后端和能力包。

## 环境要求

- Dart SDK 3.5 或更高，低于 4.0。
- Flutter SDK 3.22 或更高，建议使用 stable。
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

`tool/verify.dart` 分别使用 `dart test` 和 `flutter test` 执行纯 Dart 包与 Flutter 包测试。

固定字体的 Flutter 像素基线需要在 Windows 环境单独验证：

```bash
cd packages/weft_engine
flutter test tool/golden_pixel_test.dart --timeout 120s
```

CI 使用 Windows + Flutter 3.35.5 执行同一命令。

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

当前仓库未生成平台原生目录。安装 Flutter 后，在 `example/weft_lab` 中补齐所需平台：

```bash
flutter create --platforms=android,ios --project-name weft_lab .
flutter run
```

平台生成步骤不会实现 QuickJS；Runtime 的原生接入将在对应里程碑单独交付。

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
