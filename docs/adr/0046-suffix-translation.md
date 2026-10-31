# ADR 0046：流式快照的后缀平移复用

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0043 的形态阶梯把「头部插入 ≈0% 复用（weft_live 实际更新形态）、中部编辑 44–60%」列为方向③的能力缺口：块 diff 只做前向扫描（`_reusableLayoutBlocks`），第一个变化块之后的所有块每轮全部重测。本切片增加**反向扫描 + 后缀平移**：变化区之后内容未变的旧块按一个共享垂直增量 Δ 整体平移复用，不再重测。

实现前探索钉死的机制事实：

- 三种命令类型已有 `shift(offset)`（layout_result.dart），`paint(canvas, origin)` 是相加语义；`WeftLinkRegion.shift` 现成；boxes/tagRegions/floatExclusions 为 2 字段 const 值对象。
- 复用 walk 的状态推进（margin collapse、列表计数、cursor）是 styles 纯函数——后缀块的 Δ 由未变 styles 推导，逐块天然一致。
- lazy 与 plain 完全隔离：`allowLazy` 时跳过反向扫描，lazy 对 map 的消费是连续前缀种子；`_incrementalTextIndex` 的连续前缀计数不受后缀条目影响。
- 所有权链与现有复用同构：原件登记进 `reusedCommands` → `previous.transferCommands` 使 previous.dispose 跳过；新结果持平移克隆并在自身 dispose 释放 painter——每个 TextPainter 恰好 dispose 一次。

## 决策

### 1. 双向块 diff

`_reusableLayoutBlocks` 返回 `(prefix, suffix, ids)` 记录。前向扫描逐字保留；新增反向扫描（仅 `!allowLazy && !sameSnapshot`）：`oldIndex/newIndex` 从两侧末尾推进、止于 `prefix.length`（与前缀映射不相交、每个旧块至多映射一次），body 级 `li` 双向即停（有序列表 marker 是唯一跨块计数状态，编号烧在缓存命令里）。

### 2. 形状比较 + id 重映射（实现中的关键发现）

**节点 id 是先序位置编码**——中部节点数一变，后缀所有节点的 id 整体平移，`_sameNode` 的 id 相等检查使反向扫描永不命中（头部插入首测 0 复用）。修正：反向扫描用 `_sameNodeShape`（逐字段比较 tag/attributes/inlineStyle/文本/子树，忽略 id）并收集旧→新 id 映射；`_adoptBlock` 的平移克隆把命令、runs、boxes、links、tagRegions 的 nodeId 全部经映射重写，与 fresh 布局产出的 id（及 0044 文本索引的新 id）一致。命中、选择、语义、chunk 分组（nodeId→ordinal）全部消费新 id。

### 3. 平移克隆与 Δ 一致性

`_reuseTopLevelBlock` 前缀路径逐字保留；map miss 后查后缀 map：水平位置必须精确相等；首个后缀块记 `suffixDelta = top - block.top` 并执行 **Float 守卫**（`floats.maxBottom > min(top, block.top)` 即回退——前缀/中部的排除区不得触及平移区的新旧起点；后缀内部 Float 随块平移，相对几何自保持）；后续块 `delta != suffixDelta` 即 `reuseStopped`（高度/margin 发散则整段回退 fresh）。克隆输出：命令 `shift` + id 重映射、boxes/links/tagRegions/floatExclusions/paintBounds 平移、wrapper 记新 top——平移后的缓存继续供下一轮前缀复用（链式轮自洽）。

### 4. plain 路径 only

lazy 路径不参与（估算/段树/窗口状态是另一层失效面）；**plain Float 文档本就不播种 incrementalCache**（`(lazy || !floats.hasExclusions)`，ADR 0025），后缀平移对它们自然不生效——walk 时的 Float 守卫作为未来缓存来源的纵深防御保留。

## 画像数据（Windows 开发机，与 ADR 0043/0044 基线对比）

| 形态（plain 宿主） | 0043 基线（两轮） | 0046 后 | saving |
|---|---|---|---|
| 中部编辑 300 | 15.8–21.6 ms | **2.3 ms** | 44–60% → **93%** |
| 头部插入 300（weft_live 形态） | 31.1–40.9 ms | **2.4 ms** | ≈0% → **93%** |
| 中部编辑 1000 | 64.3–66.7 ms | **9.9 ms** | 44–60% → **93%** |
| 尾部追加 300/1000 | 3.5–6.8 / 9.7–16.2 ms | 3.3 / 10.1 ms | 不变 ✓ |
| 尾块增长 300/1000 | 3.1–4.6 / 8.7–12.4 ms | 2.9 / 8.6 ms | 不变 ✓ |
| lazy 宿主各形态 / float-plain | — | 不变 ✓ | 未触碰 |

后缀平移的每轮成本 = 前缀走查 + 变化区重排 + 后缀克隆（O(后缀命令数) 的轻量克隆，无 shaping）——中部编辑/头部插入与尾部追加同档。剩余 O(doc) 成分（走查样式解析、lazy 准入/估算、lazy 轮 textIndex 回退）属「样式与状态跨快照」家族，留待后续画像驱动。

## 测试

- 新增 `test/suffix_translation_test.dart`（9 项）：变长/变短中部编辑、删块、头部插入（各含 reused 计数结构断言 + 与 canonical 全等 + 光栅逐字节）、Float 文档不播种 plain 缓存（守卫纵深防御声明）、body 级 li 停扫等价、链式 A→中部编辑 B→尾部追加 C。
- 既有断言按新语义更新（复用变多是特性生效）：`incremental_text_index_test` 的中部编辑 3→7、头部插入测试更名并断言 4 复用 + 全量索引重建；`incremental_layout_test` 的结构变化插入 0→2。总数 542 → 551（以 `tool/verify.dart` 输出为准）。
- 画像工具 E1 的形态契约断言同步新语义（中部编辑 reused = children−1、头部插入 = children−1：置顶段文本逐轮变化不匹配）。

## 备选与拒绝原因

- **保留 `_sameNode` 的 id 检查**：后缀永不命中（先序 id 平移），机制退化为无用——形状比较 + id 重映射是能力成立的前提。
- **跨结果共享命令对象加渲染期平移**（wrapper 命令或 chunk 局部原点）：污染每个命令消费方；克隆是 O(命令数) 轻量分配，语义干净。
- **lazy 路径后缀平移**：估算状态与段树的失效面未论证，收益需先看 plain 数据；留待「样式与状态跨快照」家族统一画像。
- **k=0 头部插入的 textIndex 条目平移**（新块条目前插、旧条目 globalStart 整体平移）：有界成本（~1.8ms@300），机制变体另案；本轮头部插入的索引仍全量重建。

## 后果

- 三种流式形态（尾追加/尾增长/中部编辑/头部插入）在 plain 宿主全部进入 91–95% saving 档；weft_live 的头部插入流式不再每轮全量。
- chunk Picture 对平移块重录（`_sameChunk` 按 bounds+identical 判）——收益来自跳过 shaping 而非录制，记录在案。
- 已知限制：plain Float 文档不参与；body 级 li 截断后缀扫描；`_shiftCommand` 的 id 映射 `!` 依赖「块命令 ⊆ 块子树」的结构不变量（形状比较遍历双子树全节点）。
