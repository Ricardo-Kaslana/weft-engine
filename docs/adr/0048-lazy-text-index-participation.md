# ADR 0048：lazy 轮文本索引增量参与

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0047 把 lazy 流式轮分解为 U−F = 3.3–42ms（host）的家族工作，其中全量索引重建 T 占 38–63%（最大单项）：`_incrementalTextIndex` 的参与门要求 `previousCache.blocks.length == previousChildren`，而 lazy 缓存只持测量窗口，恒不满足 → 每轮全量 `WeftTextIndex.build`。本切片实现 0047 决策 ①(a)：放宽该门。

实现前探索钉死的机制事实（含两个**既有缺陷**）：

- **尾 trim/drop 还原洞（text_index.dart）**：`buildIncremental` 只在 `k == checkpointCount`（全前缀）时还原 `finish()` 裁掉/丢弃的流尾条目。若前文档以静默子（display:none/空块）结尾、最后 emitting 条目位于复用前缀**内部**，`take(boundary.entryCount)` 静默截断/缩短 → 条目、text、length 与 canonical 不符。该洞今日 plain 中部编辑即可触发（如 `<p>Alpha </p><div></div>` 编辑成 `<p>Alpha </p><div>Beta</div>`），0044 上线以来潜伏。
- **checkpoint 不播种**：增量产物不携带前缀 checkpoint（`checkpointCount == children − k`），下一轮 `checkpointCount != previousChildren` 门即拒绝 → 新快照轮全量/增量**交替**（0044 既有行为；链式测试只断言等价故未发现）。lazy 是连续新快照轮，不修复则收益减半。
- **k 计数自对齐**：`_incrementalTextIndex` 的 k 循环遍历 raw `body.children`、遇未映射子即停；lazy diff 的映射表只含元素 id（元素过滤列表构建），文本节点 id 永不入表 → body 级空白只损失复用（前缀更短或 k=0 回退），永不腐蚀。规范化器丢弃 body **前导**空白、保留块间空白（实测钉死）。
- **恢复状态纯度**：六个 checkpoint 字段（entryCount/nextGlobalStart/hardBreaks/blockBreakPending/lastEmittedBreak/atLeadingEdge）是前缀内容 + 样式表的纯函数；text_index 从不引用 images/textScaler/绝对位置；checkpoint 不含节点 id。

## 等价性前提

- 索引条目是（子树内容 + 样式表签名）的纯函数，与几何测量无关——diff 已证 raw 子前缀 `_sameNode` + body 壳相等 + 样式表签名 + images/lineBreakRules 相等（复用键），**测量窗口性无关**。
- `checkpointCount == previousChildren` 保证前 checkpoint 按 raw 子对齐；k 循环的 raw 迭代保证边界 checkpoint 与 raw 前缀一致。
- 尾 trim/drop 还原条件 = 「前文档流尾条目位于复用前缀内」：dropped 时 `boundary.entryCount == entries.length + 1`、trimmed 时 `== entries.length`（流尾条目是最后一个 pre-finish 条目；还原体与全前缀路径逐字相同——take 已取尽现存条目，追加/拼接即回原位）。
- 播种合法性：被播种的 checkpoint 描述 children 0..k−1 的 walk 状态，diff 已证该区间内容不变；后缀循环按 raw 子续记，产物 `checkpointCount == children` 恒成立。

## 决策

### 1. 参与门放宽（layout_engine.dart `_incrementalTextIndex`）

删除 `previousCache.blocks.length != previousChildren`（plain 缓存该条件由 diff 门隐含；lazy 缓存正是要放开的对象），保留 `previousIndex.checkpointCount != previousChildren` 与 `k >= 1`/`k <= checkpointCount`。头部插入（k=0）仍回退全量——条目平移属方向③另案。（ADR 0051 修订：该回退已解除——k=0 由 `_suffixIncrementalTextIndex` 经反向 diff 后缀映射驱动 `buildFromSuffix`；本函数与 k ≥ 1 门不变。）doc comment 重写为内容纯函数论证。

### 2. 尾 trim/drop 还原扩展到部分前缀（修洞 1）

还原条件从 `k == checkpointCount` 扩为 `k == checkpointCount || boundary.entryCount >= streamEndEntryCount`（`streamEndEntryCount = entries.length + (dropped ? 1 : 0)`）。这同时修复今日 plain 中部编辑的潜伏腐蚀。

### 3. 前缀 checkpoint 播种（修洞 2）

`adoptPrefix` 后、后缀循环前 `builder.checkpoints.addAll(previous._checkpoints.take(k))`——链式轮每轮参与，plain 与 lazy 同时受益（plain 连续两次中部编辑不再隔轮回退）。

### 4. `debugReusedEntryCount`（WeftTextIndex）

沿用 `checkpointCount` 的「宿主不直接消费」文档风格，记录增量构建采用的前缀条目数（全量 build 为 0）——测试钉参与、画像读数的判别器（播种后 `checkpointCount` 恒等于 children，不再可判别）。

## 画像数据（Windows 开发机；桌面 Stopwatch 仅相对比较）

画像工具新增 **E4b scrolled 形态**（`e4bs`）：种子与更新轮都用滚动到底部的视口——已测前缀 ≈ 全文档（reused 计数 87–91% 块），是滚动阅读中的真实流式形态；原 E4b（fresh 顶部视口）的 diff 前缀被测量窗口界住（k ≈ 窗口 ~20 块），索引仍近乎全量重走，形态本身测不出本切片收益。

| 形态（plain 文章，lazy 宿主，滚动到底部） | 0047 基线（同一 harness 同机） | 0048 后 | Δ |
|---|---|---|---|
| 尾追加 300 | 6.3 ms | **2.7 ms** | −57% |
| 尾追加 1000 | 14.7 ms | **7.1 ms** | −52% |
| 尾追加 2000 | 48.2 ms | **15.3 ms** | **−68%** |

（两轮 reused 计数逐块一致 273/908/1744——差异全部来自索引路径。）

- E4b fresh 形态：3.7/11.4/25.7 ms，与 0047 区间（3.3–5.5/11.5–14.6/30.8–42.4）一致——窗口界住前缀，符合形态预期，零回归。
- E1 lazy 形态（顶部视口）：tail-append 6.2 / tail-growth 3.3 / mid-edit 3.8 / head-insert 4.4 ms@300——head-insert（k=0 全量）逐字不动，其余在噪声内持平或略降。
- 滚动轮剩余成本 = 准入走查 S + 估算重建 + 已测前缀种子消费（O(前缀)，0047 残差同族）——①(b) 的目标。

## 测试

- `test/incremental_text_index_test.dart` 14 → 24 项：洞 1 三个回归（trimmed/dropped 条目在部分前缀内、还原点后另有后缀子）；lazy 矩阵（测量窗口内中部编辑、部分前缀参与、链式 3 轮每轮参与、块间空白 k=1 精确复用）；过渡（plain→lazy 参与、lazy→plain 回退全量）；lazy 头部插入仍全量（k=0 边界钉住）；plain 连续两次中部编辑第二轮仍参与（钉播种）。原「partially measured lazy previous falls back」更名为参与语义。
- 全包 307 → 317 零回归（`_expectLayoutEquals` 内嵌的索引全等断言全部通过）；向量与像素黄金零 diff。

## 备选与拒绝原因

- **只放宽门、不修两个洞**：洞 1 在部分前缀下腐蚀条目（今日 plain 即可触发）；洞 2 让链式轮隔轮回退，lazy 收益减半——两者都是本切片成立的前提。
- **filtered→raw 索引映射**（把元素过滤前缀换算回 raw 子位置以提高空白文档复用）：需要过滤/raw 双序列映射与额外守卫，收益仅限块间空白文档——复用损失保守接受，写入已知限制。
- **k=0 头部插入条目平移**：有界成本（= T），方向③另案。（ADR 0051 修订：已交付。）
- **用 `checkpointCount` 判别参与**：播种后恒等于 children，不可判别——新增 `debugReusedEntryCount`。

## 后果

- lazy 宿主滚动会话中的尾追加流式轮进入与 plain 同档：索引工作降为后缀 only；剩余 O(doc) 成分（准入 S、估算重建、前缀种子消费）属 ①(b)。
- plain 宿主链式轮不再全量/增量交替（0044 上线以来的隐性折损一并消除）。
- 已知限制：body 级块间空白把 k 截到空白处（复用损失、非正确性）；fresh 顶部视口形态的索引收益受测量窗口界住（真实收益随滚动深度增长）；`debugReusedEntryCount` 是公开 API 新增（调试用途，与既有 debug 家族一致）。
