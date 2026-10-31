# ADR 0024：单一渲染表面的 Semantics 树

- 状态：已接受
- 日期：2026-10-26

## 背景

Weft 的文本、链接、图片与选区全部绘制在一个 canvas 上，Flutter 无法像普通 Widget 树一样自动推导辅助技术语义。`MergeSemantics` 只能合并 RenderObject 子树，不能发现单表面内部结构，因此需要由 `RenderWeftSurface` 显式提供阅读顺序、矩形和动作。

## 决策

### 从文档与布局派生语义片段

- 根 RenderObject 是 `isSemanticBoundary` 且 `explicitChildNodes=true`，不设置根 label/value。子节点按文档阅读顺序设置 `OrdinalSortKey`，不按 Float 绘制顺序或可见 chunk 排序。
- 文本使用 `WeftTextIndex` 与 `textRectsForNode`，相邻普通文本或同一链接下的文本合并；逻辑块边界、换行和图片断开片段。块全文不与链接子节点重复暴露。
- 链接复用 `WeftLinkRegion`，设置 `isLink`；语义 tap 直接调用当前 region 的宿主回调，不模拟跨行联合矩形中心点击。无回调时不注册 tap action。
- 已解析图片使用当前 document 的 alt 与 `WeftImagePaintCommand.destination`，设置 `isImage`；空 alt 跳过，U+FFFC 不进入 label。未解析图片 alt 作为文本暴露，不重复生成图片节点。
- 非折叠选区生成独立 `value + isSelected + rect` 节点，清除、折叠或锚点失效时移除。首版不伪装 text field，不注册 setSelection 或光标动作；后续 ADR 0026 在宿主提供回调时增加语义 copy action。
- 所有 rect 使用 surface-local 坐标，必须有限、非空并与完整 surface bounds 求交。语义不随绘制视口裁剪，屏外节点仍可供无障碍焦点和滚动使用。

### 节点身份、缓存与滚动

- 内容派生片段按 layout identity 缓存，assemble 不创建 TextPainter，也不持有旧布局或 Picture。新布局重建派生数据，但保留可匹配的 SemanticsNode。
- key 由内容类型、首个 nodeId 和节点内起始偏移组成，选区使用独立 key。同一 document.id 的流式追加保留未变节点 id；document.id 改变时清空缓存。
- 每次 assemble 创建新的 children list 与 cache map。`clearSemantics` 清引用；Flutter 3.35.5 的 SemanticsNode 不调用 dispose。
- 子节点通过 `SemanticsNode(showOnScreen: ...)` 调用 RenderObject 现有 `showOnScreen`，闭包按 key 查询当前节点并安全处理删除/detach。`parentPaintClipRect` 只设置 `isHidden`，不删除屏外内容。
- selection 与链接 callback 变化显式触发 semantics update；布局、图片和尺寸变化沿用 RenderObject 的布局失效链路。

### 链接回调职责

- `WeftSurface.onSemanticsLinkTap` 是独立语义入口，standalone 默认回退到 `onLinkTap`；同时提供时分别服务辅助技术与 pointer。
- `WeftView` 只把 `widget.onLinkTap` 接到语义入口，不启用内部 surface 的 pointer detector。外层 GestureDetector 继续统一处理链接、caret 和选区，避免一次指针点击双重回调。
- 引擎不自行导航，不写剪贴板。宿主可用现有 `ExcludeSemantics` 排除整个表面，无需另加通用 label 开关。

## 理由

- 文档树和逻辑文本索引提供正确阅读顺序，绘制命令提供实际几何；二者结合即可建立有用语义，无需提前引入通用 Fragment/盒树。
- 扁平文本/链接/图片片段避免块全文与子节点重复朗读，也避免把静态文档误建模为可编辑文本框。
- 节点 key 与 ADR 0023 的稳定 NodeId 对齐，使流式追加不必重置辅助技术焦点身份；派生语义缓存与 Picture/TextPainter 所有权保持独立。

## 后果

- 新增 8 项 engine semantics widget 测试与 2 项 WeftView 测试，覆盖文本不重复、链接 action、图片/alt、选区更新、连续快照 id、pre 换行、ExcludeSemantics 和屏外 showOnScreen。weft_engine 常规测试增至 205 项，weft 增至 18 项。
- 现有 pointer 链接、caret、选择拖拽、复制按钮和滚动行为不变；像素与几何基线不需要调整。
- 首版限制（ADR 0042 修订：RTL 方向已随块方向透传到叶子 textDirection）：不提供 table/list 角色与导航、逐文本节点 selected state、可编辑 selection/caret action、RTL/语言/朗读属性、live region 或语义虚拟化。标题 header 与选区 copy 由 ADR 0026 增补。已解析图片位于链接内时不额外宣称 tap，与当前 pointer 命中能力一致。
