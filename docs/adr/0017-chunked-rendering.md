# ADR 0017：按 body 顶层子节点分块的 Picture 缓存与视口裁剪

- 状态：已接受
- 日期：2026-10-25

## 背景

`RenderWeftSurface.paint` 每帧全量遍历 `WeftLayoutResult.commands` 重绘所有命令，并且每次 paint 都重新调用 `getBoxesForSelection` 计算选区矩形。表面自身 `size` 是整篇文档的高度（`WeftView` 由外部 `SingleChildScrollView` 提供滚动），长文档滚动时绝大多数绘制工作花在视口之外的内容上，选区矩形也在每次 paint 中重复求解。

分块不能放进布局引擎：布局的输出契约是单一扁平命令列表，表格与浮动布局依赖在列表内插入、移位命令；按块分组是渲染层的关注点，布局引擎不应感知。

## 决策

### 分块数据模型（`layout_result.dart`）

- `WeftPaintCommand` 增加抽象 getter `bounds`：rect 命令返回自身矩形；text 命令返回 `offset` 与 `painter.width/height` 构成的矩形；image 命令返回 `destination`。bounds 必须完全包含命令能画出的每个像素。
- 新增 `WeftChunk`（命令组 + bounds 并集 + key）与静态构建器 `WeftChunk.partition({required document, required commands})`。
- 块粒度 = body 直接子元素：遍历 body 子树建立 nodeId → 顶层子节点序号映射（文本节点一并覆盖）。`nodeId == body.id` 的命令（body 背景/边框/直属文本）与任何映射不到的命令归入 **chrome 组**（`WeftChunk.chromeKey`），始终绘制、永不裁剪；无命令的块（空元素、`display: none`）跳过。
- 分区不依赖命令连续性，仅按 nodeId 分组；debug 断言验证非 chrome 块实际占据命令列表的连续区间。chrome 组不参与该断言——body 的直属散落文本会落在子元素区间之间，chrome 组天然可能不连续，但它始终整体绘制，输出不受影响。
- 渲染顺序 = chrome 组在最前 + 其余块按顶层序号升序，与扁平命令列表的实际顺序一致。

### 绘制与缓存（`weft_surface.dart`）

- `RenderWeftSurface` 持有 `Map<chunkKey, ui.Picture>`，paint 时惰性录制（`PictureRecorder`，命令以 `origin = Offset.zero` 记录为局部坐标）。失效时机：`_invalidateLayout`、dispose，以及绘制时发现布局实例已更换（父级 relayout 可能不经过 `_invalidateLayout` 就替换布局）。所有 Picture 正确 dispose。**选区变化绝不重建 Picture**，选区高亮仍在 Picture 之外单独绘制。
- paint 结构：`save → clipRect(offset & size) → 解析可见矩形（此刻画布仍在父坐标）→ translate(offset) → 按 chunk 顺序 drawPicture 与可见区域相交的块 → 选区矩形（局部坐标，逐矩形与可见区域求交）→ restore`。
- `@visibleForTesting void debugPaintChunks(ui.Canvas canvas, {ui.Rect? visible})` 承载"分组 + 惰性录制 + 裁剪 + drawPicture"核心逻辑，生产 paint 与基准工具共用；`visible` 为 null 时绘制全部块。
- 选区矩形缓存：键为（布局实例 + 选区值），布局或选区任一变化即重算一次；绘制时逐矩形与可见区域求交。

### 可见矩形策略（三层，保守优先）

1. `canvas.getLocalClipBounds()`：非合成宿主（常见滚动视图路径）在此画布上直接 clipRect，边界精确；仅当结果未完全覆盖自身 bounds 时才有裁剪信息。
2. `RenderAbstractViewport.maybeOf(this)` 找到视口，把视口自身 bounds 经其 paint transform 映射到表面局部坐标。`getOffsetToReveal` 无法承担此职责——它的结果描述"滚动到某偏移后内容的位置"，与当前滚动量无关；而视口的 paint transform 已烘焙当前滚动偏移。映射结果外扩 `defaultCacheExtent`（250px）再与自身 bounds 求交，保证无自身裁剪的视口也过近似。
3. 兜底返回自身 bounds，绘制全部。

裁剪是纯优化：任何一层失效都退化为与全量绘制完全一致的输出，绝不少画。块是否可跳过由 `chunk.bounds.overlaps(visible)` 决定，bounds 是命令 bounds 的严格并集，不存在"bounds 不相交却画出可见像素"的命令类型。

## 理由

- 顶层子节点是视口虚拟化的天然单元：滚动一次只跨过少数块；TextPainter 与图片等重资源挂在命令上不动，每个块只录制一次。
- chrome 组兜底保证未知 nodeId 的命令永不丢绘；分区只读文档树与命令 nodeId，不需要布局引擎提供任何新信息。
- 像素等价由测试固化：同一布局分别直绘全部命令与经 `debugPaintChunks` 绘制，`toImage` 逐字节相同。黄金基线因此原样通过，无需调整字体或容差。

## 后果

- article300（360px 宽，300 段）在参考机上的 paint 中位数：直绘全部命令（改前路径）约 1.9 ms，分块全可见约 1.0 ms，800px 高窗口约 0.1 ms 以下。新增三个 paint 场景进入基准工具与 perf gate（均为 500 ms 下限门禁）。
- 新增 8 项测试：分区连续性与 bounds 覆盖、chrome 组、空块/隐藏块跳过、像素等价、滚动裁剪（含重建/重绘计数）、缓存复用与选区缓存、布局失效重建、dispose 释放。
- 限制：视口若以 `clipBehavior: none` 运行且滚动越界超过外扩余量，视口外内容理论上可能被裁掉；当前宿主均为硬裁剪滚动视图，不受影响。块是失效的最小单位，局部文档更新仍会整块重录（增量失效留待后续）。
- 后续工作：引擎内部视口替换 `SingleChildScrollView`，以及按块失效（文档 diff 后只重建受影响块）。
