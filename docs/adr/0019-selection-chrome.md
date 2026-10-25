# ADR 0019：选择把手、复制按钮与 caret

- 状态：已接受
- 日期：2026-10-25

## 背景

ADR 0015 交付了长按选词、拖拽扩展与点击清除，但折叠选区（caret）、选择把手和复制菜单仍是空白：用户看不到插入位置，也没有移动选区端点或复制内容的入口。同时 ADR 0017 刚完成分块渲染，选区高亮在 Picture 之外单独绘制——任何新加入的选区 chrome 都必须遵守"选区变化不重建 Picture"的约束。本切片补齐 caret 绘制、把手拖拽、复制按钮与选区变化回调。

## 决策

### 分层：caret 进 surface，把手/复制按钮是 weft 层 overlay

- **caret 在 `RenderWeftSurface.paint` 内绘制**（canvas，选区高亮同层之后）：折叠选区时画 2px 竖条（`WeftLayoutResult.caretRectForAnchor`），受 `showCaret` 参数控制。caret 矩形带独立 memo（与选区矩形缓存同键模式），绘制发生在分块 Picture 之后，**绝不进入分块 Picture**——否则折叠/展开切换会重建 Picture，破坏 ADR 0017 的缓存计数断言。
- **把手与复制按钮是 WeftView 的 overlay 组件**（chrome，非内容节点）：`WeftView` 用 `Stack` 叠在 surface 上，位置来自渲染对象新公开的 `selectionControlsGeometry()`（surface-local 坐标，Stack 与 surface 同原点，随滚动内容自然移动，无需视口裁剪）。理由：把手需要拖拽手势（内层 GestureDetector 的 pan 在手势仲裁中胜过外层可滚动组件的垂直拖拽），复制按钮需要 tap——canvas 自绘无法干净接入手势仲裁。两者的 GestureDetector 均为 opaque，pointer 命中触控目标时在竞技场中先于 surface 的 tap/长按识别器，"命中把手/按钮各自处理"因此成立。
- `WeftSurface` 单独使用（不经 WeftView）时：caret 照画（参数控制），把手/复制按钮不出现；`selectionControlsGeometry()` 仍可查询，供宿主自组 chrome。此边界写在 surface 的文档注释里。

### 几何查询（`RenderWeftSurface.selectionControlsGeometry`）

- 返回 `WeftSelectionControlsGeometry`：start/end 把手的"锚点 + 触控矩形"与复制按钮建议位置；无选区、折叠选区或几何不可用时返回 null。折叠选区只有 caret、没有把手（把手语义是"展开选区的两个端点"）。
- 锚点取逻辑序选区矩形的经典端点：起点 = 第一个矩形左下角、终点 = 最后一个矩形右下角。推导完全建立在 ADR 0017 已有的选区矩形缓存之上（复用 `_selectionRectsFor`），不重复求解文本几何。
- 把手触控目标为 44×44（`kWeftSelectionHandleTouchExtent`），起点向左伸出、终点向右伸出（两侧不重叠，各留出拖拽延伸方向的抓取空间）。夹紧规则：**水平方向平移**（贴边时保持完整宽度且包含锚点），**垂直方向收缩**（锚点在选中行的底边，向上平移会把抓取区压到被选中的行上——把手绝不遮挡自己所属的行）。
- 复制按钮（`kWeftCopyButtonSize` 72×32）默认在选区上方（底边距选区上缘 8px）；越出顶部时放下方，且让开把手触控带的底缘；底部再无余地时按 surface 底边夹紧（极短文档中接受与文本重叠，浮层语义不变）。

### caret 矩形（`WeftLayoutResult.caretRectForAnchor`）

- 经 `textRectsForNode(anchor.nodeId, offset, offset + 1)` 取首个矩形构造：左边缘 x、矩形顶/底为高，固定 2px 宽（`WeftLayoutResult.caretWidth`）。未命中（节点不存在或偏移在节点末尾之后）返回 null，延续 ADR 0013 的安全丢弃语义，不做钳制。`text_index.dart` 不动。

### 交互语义（对 ADR 0015 tap 语义的演进）

- **tap**：命中把手/复制按钮 → 各自处理（opaque 内层组件获胜）；命中链接 → `onLinkTap`（现状不变）；命中文本 → **放置 caret**（`anchorAt` 得锚，写入 `TextSelectionRange.collapsed`）；未命中任何文本 → 清除选区。这取代 0015 的"tap 一律清除"——折叠选区从手势不可达变为 caret 的一等公民。
- **长按选词、长按拖拽扩展**：不变（仍走 `wordSelectionAt`/`anchorAt`，落点不在文字上时保留上一个 extent）。
- **把手拖拽**：pointer down 落在触控目标内后，pan 更新经 `anchorAt` 映射——起点把手更新 anchor、终点把手更新 extent；未命中文本时保持上一次值（ADR 0013 安全丢弃）。拖拽期间 overlay 几何**冻结在拖拽起始位置**：被拖拽的盒子不能在 pointer 下方移动（pan 的 local 坐标相对按下时的盒子），选区在拖拽中折叠时也不能把正在使用的 widget 从树上摘掉；选区高亮本身照常跟随 pointer。拖拽结束后按 settled 选区重新查询。
- **复制按钮**：tap → `Clipboard.setData(ClipboardData(text: selectionText))`，**选区保留**（opaque detector 挡住 surface tap，天然不清除）。剪贴板策略在 weft 层（引擎不碰剪贴板的既有约束不变）。`copyButtonLabel` 默认 '复制'。
- **回调**：`WeftView.onSelectionChanged(WeftSelectionInfo?)`，`WeftSelectionInfo { text, isCollapsed }`（折叠时 text 为 null）。内部手势路径经统一入口 `_setSelection` 在事件处理器内同步回调；宿主直接改 controller 的外部路径在 build 中检出差异后 post-frame 回调——build 期间从不同步回调。

### 参数与默认值

- `WeftSurface` 与 `WeftView` 均新增：`showSelectionHandles`（true）、`showCaret`（true）、`showCopyButton`（true）、`copyButtonLabel`（'复制'）。surface 的 show* 传到渲染对象（set 时 `markNeedsPaint`；showCaret 影响绘制，另两者门控几何查询）。WeftView 级参数既控制 overlay 组件的构建，也转发给 surface。
- 视觉常量全部 const：把手/caret 主色 `Color(0xFF1A73E8)`（`kWeftSelectionColor`，引擎与 weft 层共用）；复制按钮白底圆角细边框深色文字；把手为小圆点 + 短柄（CustomPaint），不引入主题依赖、不做 Material 动画。

### 一帧延迟

- overlay 位置在每次 controller notify 的 build 里从渲染对象查询，而渲染对象在同帧 build 之后才 relayout/吸收新 selection，因此查询结果滞后一帧。一个 post-frame 同步（检出渲染对象与 controller 的 selection 不一致后 `setState` 重建一次）保证事件处理器建立的选区在下一帧出现把手；拖拽由冻结几何兜底，不受延迟影响。

## 后果

- 折叠选区可见（caret）、可复制路径完整（选中 → 复制 → 选区保留），tap 语义与浏览器一致（点文本放 caret、点空白清除）。
- chunked_rendering 的计数断言不受影响：caret/选区高亮都在 Picture 之外，`debugRebuiltChunkCount` 只随布局变化增长。
- 已知边界：极短文档（单行、无滚动余量）中复制按钮可能与文本重叠；把手触控目标在贴左边缘时向右平移，极短首词选区的两个目标可能局部重叠（Stack 顺序让终点把手获胜）；字素簇边界仍按 ADR 0015 留待后续。
- 测试：engine 侧 7 项（caret 命中/未命中、锚点位置、下方回退、null 分支、show 标志门控、触控目标夹紧且不遮被选行）；weft 侧 7 项 widget 测试（把手/按钮出现、拖拽扩展与离文字保持、tap 放 caret、复制写剪贴板且选区保留、onSelectionChanged、两个 show 标志）。现有 weft_view_selection_test 的"点空白清除"落点改取实际 surface 尺寸（此前按 320 宽 probe 推导的落点在 800 宽实际布局下会落到 surface 之外），链接用例补了第二段正文给 chrome 让位。
