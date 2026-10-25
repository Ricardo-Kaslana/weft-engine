# ADR 0020：分块索引的精确命中裁剪与滚动控制器透传

- 状态：已接受
- 日期：2026-10-25

## 背景

ADR 0017 已把绘制命令按 body 顶层子节点分块，绘制时按可见窗口裁剪；但命中与选区解析仍遍历全量命令列表：`WeftLayoutResult._textHitAt`（`anchorAt`/`wordSelectionAt` 的底层）逐命令反向扫描全量命令，`linkAt` 遍历全量 links 并逐链接检查全部矩形。300 段文章（300+ 文本命令、300 个链接）下每次指针事件都是全量扫描，实测中位数：文档顶部命中 ~20 µs、中部 ~11 µs、底部 ~2 µs、链接 ~8 µs——成本随点击位置靠近文档顶部线性增长。

同时 `WeftView` 自身不含滚动视图，宿主无法注入 `ScrollController` 读取或驱动滚动偏移。

## 决策

### 命中索引（`layout_result.dart`）

- `WeftLayoutResult.attachDocument(WeftDocumentSnapshot)`：布局结果的构造契约保持不变（布局引擎不感知分块），由执行布局的一方把快照挂上来——生产路径是 `RenderWeftSurface.performLayout` 在布局完成后的一行转发。索引在首次命中查询时惰性构建；未挂载快照的裸布局结果走原有全量扫描，两者结果一致。
- 索引复用 `WeftChunk.partition` 的既有分组：nodeId → 顶层子节点序号的遍历提取为共享私有构建器，`partition` 的对外行为不变。索引形态为三部分——chunks 列表（partition 输出）、nodeId→chunk 映射（构建后即弃）、按固定高度（512px）纵向条带组织的 bounds 定位结构。
- 命令候选以**段（segment）**为单位：段是扁平命令列表中连续且属于同一 chunk 的命令区间，bounds 为段内命令 bounds 的并集。非 chrome chunk 各占一段；body 直属散落文本会把 chrome chunk 分成多段——各段 bounds 紧致，且段的位置忠实于扁平列表，这正是精确序的来源。
- `_textHitAt` 查询：取点所在条带，倒序遍历其中 bounds 含点的段（= 扁平倒序），段内命令保持原序倒序扫描，命中即返回。**裁剪是精确的，不是近似的**：命令 bounds ⊆ 段 bounds，因此"点不在任何段 bounds 内 ⇒ 不存在 bounds 含该点的命令 ⇒ 返回 null"是严格推理，不存在"裁剪后 miss 回退全量扫"的模糊语义；条带登记覆盖段的完整 y 范围，候选集不会漏；倒序段 + 段内倒序在一切文档形态下（含 chrome 散落文本穿插、负 margin 造成的跨块 bounds 重叠）都等价于全量逐命令倒序扫描，"后绘制者胜"的语义逐点保持。
- `linkAt` 查询：links 按 nodeId（锚点元素）经同一映射归属 chunk 并按 chunk 分桶；候选 = bounds 含点的 chunk 的链接桶 + 映射不到的链接（debug 断言后者为空——快照有 body 时锚点元素必在某个顶层子树内；release 中它们仍对每次查询参与候选，绝不静默丢弃）。命中者取 links 列表序最大者，即全量倒序扫描的返回值。精确性依据：链接矩形 ⊆ 其文本命令 bounds ⊆ chunk bounds。
- 边界语义：候选过滤使用闭区间含点判定。`ui.Rect.contains` 排除右/下边界，而文本命中检查接受 painter 右/下边缘上的点，候选过滤必须是后者的超集，最终裁决仍由原逐命令检查完成。

### 滚动透传（`weft_view.dart`）

- `WeftView` 增加 `ScrollController? scrollController` 参数，内嵌 `SingleChildScrollView(controller: …, primary: false)` 承载内容 Stack（含选择 chrome 覆盖层）。不改变 `primary: false` 语义：视图的滚动视图永不加入 `PrimaryScrollController`，宿主注入 controller 是为了读取或驱动偏移，而非接管滚动职责。覆盖层坐标仍是 surface-local，随文档一起滚动。

## 理由

- 段而非 chunk 作为扫描单位：chrome 的直属文本在扁平列表中穿插于子元素区间之间，若按 paint 顺序（chrome 最前）倒扫，在"chrome 文本与先行子元素 bounds 重叠"的病态输入下会颠倒"后绘制者胜"。按段扫描把这种分歧从设计上排除，并由等价测试固化（含负 margin 重叠用例）。
- 布局结果不持文档、由外部挂载：布局引擎的输出契约与构造调用点保持原样（该文件承载并行切片的未提交成果，不可改动），语义上"谁持有文档谁挂载"；未挂载时行为退化为等价的全量扫描，安全优先于性能。
- 条带网格 + 精确 bounds 过滤：条带只收缩搜索域、永不参与正确性判定；固定 512px 在数百段量级的文档上使每次查询的候选段为个位数。

## 后果

- article300（360px 宽）参考机实测中位数（1 次预热、5 次采样）：

| 场景 | 改前（全量扫描） | 改后（裁剪路径） |
|---|---|---|
| hitAnchorTop | 20.0 µs | 3.0 µs |
| hitAnchorMiddle | 11.0 µs | 2.0–3.0 µs |
| hitAnchorBottom | 2.0 µs | 3.0 µs |
| hitLinkArticle | 8.0 µs | ~1.0 µs |

  文档中部与顶部的命中提速约 4–7 倍，链接命中接近免费；底部命中从"本就近乎免费"变为位置无关的常数——命中成本不再随点击位置线性增长，最坏情况与最好情况一致。

- 基准工具与门禁新增 hitAnchorTop/hitAnchorMiddle/hitAnchorBottom/hitLinkArticle 四场景（构造逐字一致）；µs 级中位数的门禁按既有规则取 500ms 下限，只能拦截灾难性回归，精确对比以 `docs/testing-strategy.md` 的表格为准。
- 新增 5 项命中测试：多块 + 块内多文本命令语料上的 anchorAt/wordSelectionAt/linkAt 与全量扫描逐点对照（约 100+ 采样点，含块间隙与文档外空点）、chrome chunk 参与命中、chrome 文本跨块重叠保持扁平序、块边界上的点仍由命令检查裁决；另加 3 项 `WeftView` 滚动透传 widget 测试（注入 controller 读取/驱动偏移、无 controller 手势滚动、不加入 PrimaryScrollController）。
- 限制：直接构造 `WeftLayoutResult` 而未挂载快照的调用方仍走全量扫描（结果一致、仅慢）；索引按布局实例一次性构建，未来按块失效的局部更新需要重建或增量化；布局结果与渲染表面各自惰性调用一次 `partition`（首次命中 / 首次绘制），互不共享以避免命中索引与绘制缓存耦合，代价为每次布局一次 O(commands) 遍历。
- 后续工作：`textRectsForNode`/`selectionRects` 的锚点驱动路径仍遍历全量命令，若成为画像热点可复用段结构按节点归属裁剪。
