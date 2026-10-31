# ADR 0013：选择基于逻辑文本索引，锚点在内容变更后安全清除

- 状态：已接受
- 日期：2026-10-25

## 背景

阶段 3 要求稳定的跨段落选择、复制和命中语义。此前仓库只有 `TextAnchor`/`TextSelectionRange` 值类型和渲染表面的失效入口，没有把锚点映射为文本内容或视觉区域的模型。架构文档第 5 节规定：锚点使用 `(NodeId, localUtf16Offset)`，布局结果只负责把锚点映射为视觉区域，不能成为文本内容的唯一来源；无法映射时安全清除，禁止越界保留。

## 决策

### 逻辑文本索引（`WeftTextIndex`）

- 每次布局时从文档快照构建，随布局结果分发（`WeftLayoutResult.textIndex`），不跨快照缓存。（ADR 0044 修订：流式新快照按块 diff 前缀复用上一索引条目、只构建后缀，前置不满足即回退全量构建。）
- 每个文本节点产生一个条目，携带节点 painted 文本（`white-space: normal` 折叠空白，`pre` 保留原样）、节点 ID 和全局偏移。
- 换行语义与绘制一致：`<br>` 贡献一个换行，块边界贡献一个换行（跨嵌套块幂等），流首/断点后的空白不进入索引，流尾空白在构建后裁剪。
- 锚点无法定位（节点不存在或无 painted 文本）时，`order/between/textBetween` 返回空，选择被安全清除而不是钳制到错误位置。

### 绘制命令携带 run 映射（`WeftTextPainterRun`）

- `WeftTextPaintCommand.runs` 把 painter 文本区间映射回 `(nodeId, nodeStart..nodeEnd)`。同一节点跨行被拆成多个 painter 时，节点偏移保持稳定。
- `WeftLayoutResult.textRectsForNode` 和 `selectionRects` 用 `TextPainter.getBoxesForSelection` 计算矩形并平移到文档坐标。
- 布局结果新增 `selectionText`：从逻辑索引读取文本，供宿主实现复制；列表标记、图片和浮动排除区不产生逻辑文本。

### 绘制

- `RenderWeftSurface.paint` 在内容之上绘制半透明选择矩形（`selectionRects`），选区变化只触发重绘，不触发布局。

### 边界

- 手势定位锚点（点击/拖拽选择）尚未实现；本切片只交付锚点→矩形/文本的解析层与绘制层。
- 字素簇边界、双向文本和块级偏移语义留待手势切片处理。
- 表格单元格内的文本参与选择（按 reading order，单元格间以换行分隔）。

## 后果

- 选择解析不依赖 `TextPainter` 生命周期：矩形计算只在布局有效期内执行。
- 内容更新后旧锚点按节点 ID 查找失败即清除，符合“禁止越界保留”。
- 12 项单元测试覆盖索引语义、跨段复制、反向选择、未知节点和钳制；表面层以黄金图锁定选择高亮绘制。
