# ADR 0050：plain 复用块的走查样式跨快照采用

- 状态：已接受
- 日期：2026-11-01

## 背景

ADR 0049 交付 ①(b) 后按数据降级了 ①(c)：滚动轮剩余 6.94ms@2000 中种子 append 池仅 ~1–1.7ms（由 append 的 estimate 排序 + 段树 bubble 推断）且机制最重（`_LazyLayoutState` 整体手术）——缓办留案。本切片实现 0047 预登记的**方向②**：diff 已证不变的顶层子，其样式从上一轮 styleCache 采用，免每轮重解析。

数据依据（ADR 0047 E4a/E4d）：已复用轮走查的全部解析量 = body + 顶层子（每轮 ~N+1 次 resolve，0.55–1.28ms@1000–2000 默认样式表）；resolver 单次成本随规则数陡增（8 条 7–10µs → 256 条 57–104µs）——大样式表下 1000 块轮的样式单项达 62–170ms。

实现前探索钉死的机制事实：

- **样式对象跨快照共享安全**：`lib/src` 无任何 `identical`/`==` 样式比较，`WeftComputedStyle` 无相等重载但无消费者比较实例；0049 的 `_LazyChild` 采用已在跨快照传样式对象。
- **walk 顺序**：`styleFor` 在每子循环顶部、四个 `_reuseTopLevelBlock` 调用点（float-img/block-img/table/泛块）之前，且 childStyle 在复用路径也被消费（margin/clear/marker）→ 种子化对复用与 fresh 路径同时生效。
- **前提闭合**：resolver 输入 = (element, parent, ancestors, stylesheet, customTags)，无宽度/缩放/图片参数；diff 门已证样式表签名 + `_sameNodeShell`（body 的 tag/attributes/inlineStyle 全覆盖 → bodyStyle 值等）+ tagRenderers 身份。body 级 text 杀死 plain 缓存 → plain 域 raw 子即元素。
- **映射形状**：prefix/suffix map 键 = 新子 id、值 `.element` = 旧元素（双向恒等验证）；prefix 连续正扫、suffix 连续尾部逆扫；`previousStyles[block.element] == null` 守卫——lazy 前缓存的 styleCache 缺前缀条目（采用轮的前缀样式在 `_LazyChild` 上）时自然断在首子，优雅退化。

## 等价性前提

- 前缀子树 `_sameNode` 相等、后缀子树 `_sameNodeShape` 相等 + 样式表签名 + body 壳 + tagRenderers 身份 → 被采用样式与 fresh 解析值等（不同实例、无身份消费者）。
- 采用后 walk 的消费面（display 检查、margin 折叠、marker、fresh 重排）全部读字段值——对象来源不影响输出。
- 子树级样式不需要：复用块不重测、其 inline 子树样式不被消费；编辑块 fresh 解析（不在映射内）。
- id 键控 styleCache 不可行：后缀先序 id 平移会让新元素错误命中旧条目——元素对象键控 + 成对种子化是唯一安全形状。

## 决策

### 1. 种子化（layout_engine.dart 决策块）

`reusedMaps` 终态后、`_LayoutContext` 构造前：`!sameSnapshot && previousCache != null` 时，前缀连续正扫（`block == null` 或 `previousStyles[block.element] == null` 即停）+ 后缀连续尾逆扫，把 `previousCache.styleCache[block.element]` 写入新 `styleCache[newChild]`。sameSnapshot 轮 styleCache 即前缓存 map，门控跳过。

### 2. `debugAdoptedStyleCount`（4 处管道）

仿 `debugReusedBlockCount`：context 字段 → result 构造 → ctor 默认参 → 字段 + doc。测试与画像以它钉参与量。

### 3. 不做 body 样式种子

bodyStyle 每轮仅 1 次 resolve，收益为零；种子化只覆盖顶层子（收益主体）。

## 画像数据（Windows 开发机，同机 A/B——仅门控种子化开关，其余逐字相同）

E4f（新实验）：mid-edit@300 流式轮、规则数变体：

| 样式表 | 种子关闭（基线） | 采用开启 | Δ |
|---|---|---|---|
| 8 条规则 | 2.61 ms | **1.91 ms** | −27% |
| 256 条规则 | 29.14 ms | **11.66 ms** | **−60%** |

- adoptedRange = 299..299 vs 0..0（A/B 干净——差异全部来自样式路径）。
- 256 条规则的剩余 11.7ms = diff（O(前缀子树递归)）+ 0046 后缀平移克隆（O(后缀命令数)）——样式单项已从主导降为次要。
- E1 plain 形态同机对照：mid-edit@300 1.96ms、head-insert@300 2.11ms、mid-edit@1000 6.37ms（本机历史最优档）；E0 的 U-round 恒等句已按 0050 修订（复用区样式零解析）。
- 真机 4× 投影：默认样式表 mid-edit@300 ≈ 7.8ms（预算内）；大样式表轮从 ~117ms 降至 ~47ms——复用轮与样式表规模脱钩是本切片的架构收益。

## 测试

- 新增 `test/plain_style_adoption_test.dart`（7 项）：中部编辑 count == children−1 + 全等（含 textIndex）、链式 2 轮 count 持续 + 全等、样式表变化 count 0 + 全量回退、256 条规则大样式表正确性、lazy 轮经 plain 前缓存种子化 + 全等、sameSnapshot 轮 count 0、表格/图片前缀经各自复用路径采用。
- 全包 328 → 335 零回归；向量与像素黄金零 diff。

## 备选与拒绝原因

- **①(c) 状态整体采用**：剩余池 ~1–1.7ms@2000（13–24%）而机制最重（截断语义 + 所有权 + samples/段树补丁）——0049 数据降级，留案。
- **id 键控 styleCache**：后缀 id 随中部平移会错误命中（0046 的核心发现），元素对象键控 + 成对种子化是安全形状。
- **子树级样式种子**：复用块不重测、子树样式不被消费——只有顶层子（walk 的 styleFor 漏斗）需要。
- **`continue` 替代前缀 `break`（null 样式时）**：lazy 前缓存缺全部前缀条目时，continue 每轮空扫 O(N) 个 map 查找；break 在首子即停，plain 前缓存（条目齐全）行为不变。

## 后果

- plain 复用轮的样式解析降为编辑区 fresh 子；流式轮成本与样式表规模脱钩（E4d 的放大效应被采用消除）。
- lazy 轮经 plain 前缓存过渡时同样受益；lazy→lazy 链式轮的前缀样式走 `_LazyChild` 采用（0049），种子化自然断在首子不重复工作。
- 已知限制：编辑区子仍 fresh 解析（内容已变，本应如此）；样式表变化轮全量回退（签名门）。
- `debugAdoptedStyleCount` 为公开调试面新增（与既有 debug 家族一致）。
