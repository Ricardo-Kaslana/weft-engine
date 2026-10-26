# ADR 0023：流式追加的顶层前缀布局复用

- 状态：已接受
- 日期：2026-10-26

## 背景

AI 流式内容通常由宿主逐 token 重新规范化完整 HTML 快照。此前 `RenderWeftSurface` 每次替换快照都会销毁旧布局和全部分块 Picture，即使 300 段文章只在末尾增加一段，也会重建全部 TextPainter。ADR 0017/0020 已按 body 顶层子节点组织绘制与命中，但布局层没有可复用片段。

## 决策

### 顶层前缀片段

- `WeftLayoutResult` 保存增量缓存：来源快照、全局布局输入，以及每个 body 顶层块的子树、原 left/top、height、commands/boxes/links。表格和块级图片同样以整个顶层块为单位。
- `WeftLayoutEngine.layout()` 接受可选 previous result。纯尾部追加与“最后一个顶层块持续增长”共用一条路径：递归比较规范化节点 ID、标签、文本、属性、inline style 和子节点顺序，取公共顶层前缀，从第一个变化块起重排。
- 复用嵌入现有 `_layoutChildren()`，不另建后缀布局算法。前缀仍依次参与样式解析、margin collapse、列表计数和 cursor 推进，只跳过递归测量与 TextPainter 创建；实际 left/top 与缓存不一致时立即停止复用。
- 复用记录重新绑定当前快照节点，因此连续多轮快照不会退化为隔一轮全量。首版只复用原坐标片段，不做后缀平移或行级复用。

### 缓存键与保守回退

- 全局键包括 document id、body 自身属性/样式、语义样式表、宽度、TextScaler、kinsoku 规则以及图片 nodeId/image identity/尺寸。任一变化即全量。
- 旧结果含 Float 时不作为复用来源，避免恢复不完整 `_FloatContext`；body 直属 loose inline/text、display:none、self-collapsing 或未解析图片使结果不可作为后续缓存来源。新增图片改变全局图片键，同样先回退。
- `WeftTextIndex` 每轮全量重建；新结果重新挂载新快照，使命中索引按需重建。选区/caret 几何缓存随布局失效。

### Painter、图片与 Picture 所有权

- 复用命令由新结果接管。旧结果记录已转出的命令并使其增量缓存失效，随后正常 dispose 只释放未复用后缀，避免双重 dispose 或释放新结果仍使用的 TextPainter。成功复用过的 previous 不得再作为另一轮复用来源。
- 同一 document id 的快照更新保留图片解析表，由既有 `_syncImages()` 按 nodeId/src 清理 stale 项；document id、resolver 或 image configuration 改变仍清空。
- Surface 在 document 更新后保留下一轮布局所需的 previous result。新布局分块时，仅当 chunk ordinal、bounds 和命令实例序列全部一致才保留原 Picture；chrome、变化尾部及任何不匹配块均 dispose 并重录。选区高亮和 caret 仍独立于 Picture。

## 理由

- 顶层块是当前分块绘制与块流算法的共同边界，能在不引入通用 Fragment 树的情况下覆盖 AI 文章的主要流式形态。
- 尾部变化不会反向改变无 Float 前缀的位置；仍在原块流中执行 margin 和 cursor 计算，比恢复一份不完整布局 checkpoint 更容易证明等价。
- 全局输入或 Float 状态无法证明等价时直接回退，优先保证正确性。首版不以支持所有编辑形态为目标。

## 后果

- 360px 宽 article300 尾部追加一段，Windows 开发机（1 次预热、5 次采样）：

| 场景 | 改前全量 | 改后同轮全量对照 | 增量路径 |
|---|---:|---:|---:|
| appendArticle300 | 37.3ms | 31.8ms | 6.7ms |

  同轮比较中位数约降低 79%（4.7 倍）；不同轮次受 JIT 与机器负载影响，保留全量对照避免只比较历史数字。基准新增 Full/Incremental 两个场景，CI 上限均按规则取 500ms 下限。

- 新增 normalizer 前缀 NodeId 契约、8 项增量布局/像素测试、1 项连续 Surface Picture 复用测试及 2 个性能场景；weft_engine 常规测试增至 197 项。增量与干净全量结果对 size、boxes、命令、runs、links、文本索引、选区、caret、逐点命中和像素等价。
- 限制：仍有 O(块数) 的快照 diff、样式解析、列表合并和文本索引重建；不支持 Float checkpoint、任意中部编辑的后缀平移、行级复用或布局虚拟化。这些留待后续画像驱动优化。
