# 模块与接口契约

本文区分“已建立代码契约”和“规划中接口”。公开 API 在稳定版前仍可通过 ADR 调整。

## 已建立：文档模型

```dart
const WeftDocumentSnapshot({
  required String id,
  required int revision,
  required String normalizedHtml,
  SupportReport supportReport,
  WeftElement? body,
  WeftStyleSheet styleSheet,
});
```

快照代表一次规范化结果。`revision` 是缓存和失效判断的一部分；节点树、内联样式和 CSS 规则都保持不可变。`body` 为受控元素根，文本节点使用独立 `NodeId` 和原始文本，布局不得修改该树。

`WeftElement` 提供标签、白名单属性、解析后的内联声明和子节点；`WeftText` 提供原始文本。外部 HTML DOM 和 csslib AST 不进入该模型。

`SupportReport` 提供：

- `hasErrors`：是否存在错误级诊断。
- `requiresWebView`：是否命中明确回退能力。
- `canRender`：当前是否允许进入引擎。

`TextAnchor(nodeId, offset)` 是逻辑文本锚点；`TextSelectionRange` 保存 anchor 和 extent，不假设视觉方向，也不直接持有 RenderObject。

## 已建立：公开控制与回退

`WeftController`：

- `loadDocument(snapshot)`：替换快照并清空旧选区。
- `updateSelection(range)`：只更新逻辑选择。
- `clear()`：清除文档和选择。

`WeftView` 监听控制器。支持内容进入垂直滚动容器和 `WeftSurface`；不支持内容必须调用 `fallbackBuilder`，未提供时抛出明确 Flutter 错误。

`WeftView.onLinkTap` 接收命中的 `WeftLinkRegion`，负责把经过清洗的链接交还宿主；pointer 与 Semantics tap 都走这一回调，各由单一入口触发。引擎不自行打开 URL、启动外部应用或执行导航。独立使用 `WeftSurface` 时，`onSemanticsLinkTap` 默认回退到 `onLinkTap`；同时提供两个回调时分别服务辅助技术与 pointer。

`WeftView.imageResolver` / `WeftSurface.imageResolver` 接收受控图片请求：

```dart
final class WeftImageRequest {
  final String documentId;
  final int nodeId;
  final String src;
  final String alt;
}

typedef WeftImageResolver =
    ImageProvider<Object>? Function(WeftImageRequest request);
```

解析器返回 `null` 时布局显示 `alt`；返回的 `ImageProvider` 由渲染表面监听解码并触发失效。宿主必须在解析器中执行自己的 URL 白名单、认证、缓存和大小策略，引擎不自动请求网络。

`WeftView` 使用内部 `SingleChildScrollView`，`scrollController` 可注入读取/驱动偏移；`primary:false` 保持不变。`enableLazyLayout` 默认 true：简单文档只物化可见块并允许估算滚动高度，复杂文档及 selection/Semantics 会升级为完整布局。standalone `WeftSurface` 默认完整布局。

## 已建立：规范化与样式

`WeftNormalizer.normalize(html, id, revision)` 输出 `WeftDocumentSnapshot`，并接受可配置的输入、样式、节点、深度和诊断数量限制。

- 允许标签、类、ID、后代、子代和逗号选择器。
- 支持的属性、简写和层叠规则见 `supported-subset.md`。
- `img` 的 `src` 过滤 `javascript:`、`vbscript:` 和 `data:`；`width/height` 必须是正整数，否则丢弃并诊断。
- 脚本、Canvas、表格等复杂内容生成 `requiresWebView` 诊断，当前不静默移除后继续宣称完整渲染。
- 规范化器不是不可信内容安全清洗器。

`WeftStyleSheetParser` 输出 `WeftStyleRule` 和 `WeftSelector`；选择器可针对不可变元素和祖先链执行匹配，并提供结构化特异性。`!important`、at-rule 和伪类当前被丢弃并产生警告。

## 已建立：布局与绘制

```dart
final layout = const WeftLayoutEngine().layout(
  snapshot,
  width: availableWidth,
  textScaler: MediaQuery.textScalerOf(context),
  images: decodedImagesByNodeId,
);
```

`images` 只接受已解码的 `ui.Image`，布局不执行 I/O。解码、监听和释放由 `RenderWeftSurface` 管理；公开调用方也可直接使用布局引擎做无图或注入图测试。

`WeftLayoutResult` 包含内容尺寸、布局盒、有序绘制命令和链接命中区域：

- `WeftRectPaintCommand`：块背景和分隔线。
- `WeftTextPaintCommand`：文本布局与绝对偏移。
- `WeftImagePaintCommand`：已解码图片与目标矩形。
- `WeftLayoutBox`：块级与图片替换盒的 `NodeId` 和边框盒矩形，已包含内容宽度、padding、border 和 `box-sizing` 的结果。
- `WeftLinkRegion`：链接元素 ID、经过清洗的 `href`、显示文本和每行一个的矩形。
- `WeftLayoutResult.linkAt(position)`：返回该位置最上层的链接命中，未命中返回 null。

布局结果拥有 `TextPainter`，调用方必须 `dispose()`。`RenderWeftSurface` 在重新布局和销毁时负责释放旧结果，缓存当前链接区域供点击测试使用，并管理图片 `ImageInfo` 的监听与释放。

布局直接执行 Block/Inline/Table 流，没有通用 Fragment 行盒树；ADR 0023 可复用 body 顶层前缀块，ADR 0025 在 WeftView 内部渐进测量可见窗口，ADR 0024 从文档与布局结果派生 Semantics。Float 只覆盖图片，使用共享排除区和逐行文本布局；链接命中覆盖字形行盒，不包含行间空白。

## 已建立：Runtime

```dart
abstract interface class JsRuntimeBackend {
  Future<JsSession> open(RuntimeConfig config, BridgeDispatcher bridge);
}

abstract interface class JsSession {
  String get id;
  Future<JsResult> execute(ScriptUnit script, ExecutionBudget budget);
  Future<void> send(EventEnvelope event);
  Future<void> dispose();
}
```

`RuntimeConfig` 固定文档 ID、JS 堆、栈和已启用能力集合。`ExecutionBudget` 限制单次执行时间和微任务批次。所有桥接参数使用可序列化值，禁止传递任意 Dart 对象。

`JsResult` 以 `RuntimeFailure` 表示超时、内存、栈、脚本、桥接和销毁错误，不允许把超限静默当成普通脚本返回值。

## 已建立：能力扩展

```dart
abstract interface class CapabilityModule {
  CapabilityDescriptor get descriptor;
  Future<JsValue> invoke(BridgeCall call);
}
```

`CapabilityDescriptor` 包含命名空间、API 版本和方法集合。`CapabilityPolicy` 是不可变装载策略，自定义命名空间与内置能力使用同一机制。

内置命名空间预留为 `weft.state`、`weft.events` 和 `weft.net`；当前只有标识和策略，没有具体实现。

## 已建立：QuickJS 边界

`QuickJsRuntimeBackend` 将 `open` 委托给 `QuickJsNativeAdapter`。该适配器是 FFI 实现的接缝，使核心契约测试可以使用 FakeRuntime/NativeAdapter。

这层委托不表示 QuickJS 已可用。原生库、线程约束、中断和内存限制必须另行实现并验收。

## 规划中：扩展与资源接口

以下接口只在对应里程碑进入代码：

- `TagRenderer`：自定义标签的布局、绘制、命中和语义。
- `LayoutAlgorithm`：按约束生成 Fragment，未来支持 Flexbox。
- `TextShaper`：替换当前直接使用的 `TextPainter` 测量与整形。
- `ResourceProvider`：统一的受控资源加载、取消、缓存和释放；当前只有图片的 `WeftImageResolver`。

这些接口的草案和设计约束记录在架构文档，不以未经验证的占位类提前冻结。现有 `WeftLayoutResult` 只是阶段 1A 的绘制产物，不承诺作为最终扩展契约。
