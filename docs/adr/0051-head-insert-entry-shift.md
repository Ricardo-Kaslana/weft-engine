# ADR 0051：k=0 头部插入的索引条目平移

- 状态：已接受
- 日期：2026-11-01

## 背景

ADR 0046 备选清单预登记、ADR 0047 列为「样式与状态跨快照」家族第三方向的机制：头部插入轮的反向 diff 已证全部旧子 shape 相等（`suffix` map 覆盖 + `ids` 旧→新 nodeId 映射，布局侧 0046 平移克隆已复用），但文本索引仍全量重建，成本 = T = 1.8–2.5 / 7.3–8.3 / 15.3–16.2 ms@300/1000/2000（0047 E4b 直测）。本切片把旧索引条目采用过来：新头部块 fresh 走查前插、旧条目 globalStart 整体平移 + nodeId 经 `ids` 重映射。

实现前探索钉死的机制事实：

- **接缝定理（正确性核心）**：走查进入某子的状态由四个标志唯一决定其发射行为（`atLeadingEdge` 剥离、`blockBreakPending` 换行、`hardBreaks` 硬换行、`lastEmittedBreak` 恒 false）——emit 首次成功发射即重置全部标志（text_index.dart emit），`entries` 非空性与 `atLeadingEdge == false` 等价。故两构建在某接缝标志逐项相等时，其后 diff 已证内容相等的子的全部发射恰差一个常数平移 Δ = 新接缝 globalStart − 旧接缝 nextGlobalStart。
- **流首剥离分歧真实存在**：emit 在 `atLeadingEdge` 且 `hardBreaks == 0` 时剥首个可折叠空白串；normalizer 保留原始 `node.data`（仅 colgroup 丢纯空白）→ 旧流首条目（被剥离）与 canonical（头块之后、流中态、不剥离）文本不同。接缝比较恰好在 j=0 用伪初态（`atLeadingEdge = true`）对照头部走查后的状态（已发射 → false）→ 分歧被检测为不匹配，该子 fresh 走查；首发射消费全部分歧，其后接缝必匹配——典型头部插入只多走查 1 个后缀子。
- **回退即全量**：carried 子逐个「比较或走查」，走满 = 等价 `WeftTextIndex.build` 本身，回退无分歧。
- **后缀 map 仅 plain**：反向 diff 只在 `!allowLazy && !sameSnapshot` 构建（0046）→ lazy 轮天然无后缀，本机制 plain 限定，lazy 轮保持全量。
- **体级 text 子截断（探索发现）**：`_reusableLayoutBlocks` 的缓存门要求 `cache.blocks.length == 旧 body.children.length`（raw 子数）——旧 body 含任何体级 text 子（块间空白）时整个 diff 直接为空映射（前缀路径同样受此门）。故「部分采用」只在**新侧**插入体级空白时可达；`carried` 计数按新 body 尾部连续「WeftElement 且在 suffix map 内」的 raw 子数，与索引的 per-raw-child checkpoint 对齐。

## 等价性前提

- carried 子树 `_sameNodeShape` 相等 + 样式表签名 + body 壳 + tagRenderers 身份 → 子树发射内容与样式逐项相等；接缝标志相等 → 发射行为相等 → 旧条目 + Δ 与 canonical 逐条目相等（不同实例，条目无可变字段）。
- Δ 可为负（头删除/头部改写收缩）：首采用条目 shifted ≥ 头部走查末态（旧首条目 ≥ 旧接缝 nextGlobalStart + 接缝 breaks ≥ 该值）→ join 单调性与 canonical 一致。
- 尾 trim/drop 还原（0048 镜像）：采用区间恒达旧流尾，`接缝.entryCount < streamEndEntryCount` 时还原 `_trailingRemovedEntry`（平移+重映射后追加）/ `_trailingTrimmedTail`（拼回末条目）；新 `finish()` 在同一末子上重 trim，记录 canonical 簿记。区间为空时旧流尾属接缝前内容（已重走查或弃用），还原会重复 canonical 没有的文本。
- id 重映射结构不变量：采用区间全部是 diff 证明的元素子树，其文本节点全部被 `_sameNodeShape` 配对 → `shiftedIds[entry.nodeId]!` 安全（同 `_shiftCommand` 先例，assert 钉住）。
- 头部走查镜像 `visitBodyChildren`：body 非行内时先置 `blockBreakPending = true` 再走查——头部 checkpoint 才与 canonical 逐项一致，下一轮前缀采用（0048 adoptPrefix）恢复的状态不缺 body 级悬挂换行。

## 决策

### 1. `WeftTextIndex.buildFromSuffix`（text_index.dart，新静态方法）

`carriedTopLevelBlocks`（尾部连续 raw 子数）+ `shiftedIds`（0046 ids map）。头部子逐个走查后，carried 子逐个比较接缝（seamIndex < 0 用伪初态）：标志相等 → 采用（条目平移+重映射重建、dropped/trimmed 还原、checkpoint 平移重事实化、`reusedEntryCount` 计入）并止；不等 → fresh 走查该子继续。doc comment 载接缝定理与错位警告（仿 buildIncremental）。

### 2. `_suffixIncrementalTextIndex`（layout_engine.dart，新私有门）

调用链插在 `_incrementalTextIndex` 与 `WeftTextIndex.build` 之间：`?? _suffixIncrementalTextIndex(... suffixBlocks: reusedMaps.suffix, suffixIds: reusedMaps.ids) ?? build(...)`。门 = previousCache/previousIndex/checkpointCount == 旧 raw 子数 + `carried` 计数（0 或越界即回退）。mid-edit（前缀非空）被 `_incrementalTextIndex` 先命中，天然不进后缀路径——0048 计数器语义与既有 pin 全部不动。

### 3. `debugReusedEntryCount` 语义扩展

「前缀逐字采用（0048）或后缀平移重映射采用（0051）的条目数」；builder 字段 doc 与 getter doc 同步。无 result 级新计数器。

## 画像数据（Windows 开发机，同机 stash A/B——lib 改动前后，harness 逐字相同）

E1 head-insert plain 形态（两轮 after 取区间；entries 列 = `debugReusedEntryCount` 每轮读数）：

| base | 前（entries=0） | 后（entries=1500/5000） | Δ |
|---|---|---|---|
| 300 | 2.11 ms | **1.16–1.38 ms** | **−35…−45%** |
| 1000 | 7.82 ms | **3.02–3.09 ms** | **−60%** |

- 前@1000 = 7.82 与历史 T@1000（7.3–8.3）吻合——A/B 锚点有效；entries=0 → 1500/5000 证明差异全部来自索引路径。
- 未改路径的噪声带：mid-edit/tail-growth（代码未动）三轮中位数 @300 ±0.3ms、@1000 最大离散 ~2.7ms（mid-edit 前轮 7.24 为离群高值）——@1000 的 −60% 稳定复现（3.02/3.09），远超噪声。
- 轮形态对照：head-insert@300（1.16–1.38）已低于 mid-edit@300（1.85–2.18）——0047 记录的「head-insert 比 mid-edit 贵」反差消失；剩余 = 头部走查 + 接缝子走查 + O(条目) 重事实化 + 平移克隆。
- 真机 4× 投影：head-insert@300 ≈ 4.6–5.5ms（预算内）；@1000 ≈ 12–12.4ms。
- E4c 的 k=0 机会（有界 T）按本轮实测销账。

## 测试

- 新增 `test/suffix_entry_adoption_test.dart`（8 项）：典型头部插入（含列表/链接，counter > 0 + 全量布局等价验证 id 重映射）、display:none 头部块（Δ=0 全量采用、text 与前索引逐字同）、**前导空白首段**（剥离分歧走 fresh 回退，` 前导空白段落` 空格重现——本切片关键正确性测试）、头部末块 `<br>`（硬换行接缝）、头部末尾空块（悬挂换行接缝）、头部删除（负 Δ）、链式 2 轮、新侧体级空白截断（部分采用）。
- 既有 pin 更新：`incremental_text_index_test.dart` head-insert 测试更名 + `debugReusedEntryCount > 0`；lazy 头部插入 reason 更新（0051 已交付 plain 侧，lazy 无后缀 map 仍全量）。
- 全包 335 → 343 零回归；向量与像素黄金零 diff。

## 备选与拒绝原因

- **推广到 mid-edit（前缀非空）轮的后缀采用**：机制可组合（adoptPrefix + 中段走查 + 后缀采用），但改变 0048 计数器语义与 pin 面、收益（后缀走查消除）未测——留案，先测后缀走查份额再定。
- **流首条目文本重建（un-strip）**：需要按 id 查找新文档文本节点（无 id→node 索引，O(N) 走查）且只省一次子走查——接缝不匹配 fresh 走查更简单且回退即 canonical。
- **体级 text 子纳入采用**：checkpoint 按 raw 子计、text 子无元素证明、旧侧体级空白更被 0046 缓存门整体拒绝——无可达收益。
- **ids 缺失的运行时降级**：结构不变量（采用区 ⊆ 配对子树）已由 diff 构造保证，assert + `!` 同 `_shiftCommand` 先例；保守预检需 checkpoint 私有量跨库暴露，不值。
- **`atLeadingEdge` 不参与接缝比较**：它恰是流首剥离分歧的唯一信号，剔除即引入腐蚀。

## 后果

- k=0 头部插入（含头删除、头部改写）plain 轮的索引成本从 T（全量走查）降为头部走查 + ≤ 数个接缝子走查 + O(条目) 重事实化；E1 head-insert 与 mid-edit 的反差消失。
- 0047 家族清单全部销账：①(a) 0048、①(b) 0049、② 0050、③ 本切片；①(c) 按数据降级留案、行级缓存留案（E4e 上界）。
- 已知限制：lazy 轮无后缀 map 仍全量（0046 已留案的 lazy 平移同一前提）；旧 body 含体级 text 子时整个 diff 不可用（0046 既有门，非本切片引入）；接缝不匹配的子 fresh 走查使最坏情形 = 全量构建。
- `debugReusedEntryCount` 语义扩展为双向采用计数（公开调试面，与既有 debug 家族一致）。
