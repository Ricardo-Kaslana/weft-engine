# ADR 0049：lazy 准入与估算前缀跨快照采用

- 状态：已接受
- 日期：2026-11-01

## 背景

ADR 0048 把 lazy 流式轮的索引降为后缀 only 后，剩余 O(document) 成分 = 准入走查 S（`_supportsLazyLayout` 每新快照全树访问 + 全元素样式解析进 styleCache，12–18%）+ 估算重建（`_prepareLazyState` 每新快照全量：逐子 styleFor、`_minimumPaintOffset` 递归下降、ctor 循环）。本切片实现 0047 决策 ①(b)：diff 已证不变的 raw 前缀沿用上一轮的**准入结论**与**逐子估算状态**，只验证/重建变化后缀。

实现前探索钉死的机制事实：

- `_LazyChild` 已携带全部逐子状态（element/style/ordinal/gap/marker/minimumPaintOffset + `isFloat`/`fixedHeight` 派生）——前缀子采用即免重解析、免下降。
- `_minimumPaintOffset` 的 `styleCache[element]!` 硬断言不按需解析，今日安全唯一靠准入走查全树预热。采用路径下前缀子**从构造上不再进入该函数**（只有 fresh 后缀子进入，其子树刚被后缀准入解析）——隐患消除而非绕过。
- prepare 循环的边界局部状态三值可零歧义恢复：`pendingMargin`（最后一个非浮动子的 bottom——table/img 走 `style.marginBottom` 直取，否则一次 `outerMarginBottom` 链走查）；`leading`（初始值 && 前 k 子全浮动，O(k) 读 isFloat）；`orderedItem`（前缀 decimal li 计数，O(k) 读 tag+style.listStyle，零解析）。
- 准入拒绝条件清单（display:none、非 img 浮动/无图 img/inline 祖先下浮动、无解码图、body 级非空白文本/pre、body 级 inline 子）逐条是子树内容的纯函数 + images 键——diff 已证前缀子树 `_sameNode` 相等 + 复用键（样式表签名/images/lineBreakRules/tagRenderers/宽度/缩放）相等 → 前缀 verdict 可沿用。
- **provisional allowLazy 规则**：准入需先有 diff → diff 先行（`allowLazy = wantsLazy` 试探）。verdict=false 且前缀非空时必须以 `allowLazy: false` 重跑——lazy 旧缓存的映射对 plain 轮不安全（`_adoptBlock` 的未物化守卫是 isLazy-only，平移克隆会静默零命令），plain 旧缓存则丢后缀平移；映射为空时重跑结果不变，跳过。
- 表格文档是 lazy 合格的（准入不拒绝 table）；使文档不合格的最小构造 = 非图片浮动 / body 级 NBSP 文本。

## 等价性前提

- 前缀子树 `_sameNode` 相等 + 复用键相等 → 前缀的准入结论与逐子估算状态（style/gap/marker/minimumPaintOffset）与全量重走逐位相同。
- 采用子的 element 重绑到新快照对象：map 键与新 id 一致（先序 id 前缀相等），任何 raw 结构漂移都会破坏 diff 扫描使采用缩短——`_lazyPrefixAdoption` 逐子校验 `node.id == child.element.id` 作纵深防御。
- 边界恢复三值是已存 style/element 的纯函数；`_LazyLayoutState` ctor（remainingExtent 种子、minimumAdvances 后缀环、段树）是完整 children 列表的纯函数，代码不变。
- 后缀 fresh 子的 styleCache 读由后缀准入预热（与全量走查的预热范围对后缀区域逐位一致）。

## 决策

### 1. 准入增量 + 重跑规则（layout_engine.dart）

决策块重排：`wantsLazy` 先行 → diff 以 `allowLazy: wantsLazy` 试探 → `_admitLazyLayout` 判 verdict → `!verdict && prefix 非空` 时以 `allowLazy: false` 重跑 diff。`_supportsLazyLayout` 的 visit 闭包提取为共享 `_visitLazyElement`/`_resolveLazyStyle`；`_admitLazyLayout` 在 `previousCache.isLazy && k > 0` 时沿用前缀 verdict、只对 raw 子 k.. 做空白/inline/递归检查，否则原样全量走查（预热兜底）。sameSnapshot 与 plain 路径逐字保留。

### 2. 估算前缀采用（lazy_layout.part.dart `_prepareLazyState`）

新可选参数 adoption：前缀段直接追加 `_lazyPrefixAdoption` 产出的克隆子（element 重绑、style/gap/marker/minimumPaintOffset 逐字沿用），不进 styleFor/`_isSelfCollapsing`/`_minimumPaintOffset`/outer-margin；边界恢复三值后，fresh 循环从 `nextOrdinal` 继续，逐字保留原逻辑。`visitedBlockCount` 计入采用子 + 后缀迭代；`estimatedBlockCount`、ctor 不变。

### 3. `debugEligibilityVisitCount` 语义

语义收窄为「本轮流象征问的元素」——采用轮只计后缀（画像与测试以此判别增量语义）；sameSnapshot 轮恒 0 的既有断言不变。

## 画像数据（Windows 开发机，同机 stash 前后对；桌面 Stopwatch 仅相对比较）

| 形态（e4bs 滚动会话，尾追加） | 0048 引擎（同机 stash） | 0049 后 | Δ |
|---|---|---|---|
| 300 | 2.01 ms | **1.57 ms** | −22% |
| 1000 | 6.02 ms | **3.88 ms** | −36% |
| 2000 | 12.76 ms | **6.94 ms** | **−46%** |

- 准入访问数（eligibility）后缀化验证：931→111、3031→306、6031→798（每轮只走后缀子树）。
- E4b fresh（顶部视口）形态窗口界住不变（eligibility 888/901 等）——与 0048 的形态结论一致。
- E1 lazy 形态 @300：tail-append 2.78 / tail-growth 1.96 / mid-edit 2.65 / head-insert 3.28 ms——head-insert（k=0 全量走查）语义不变。
- 家族累计：0047 的 fresh U(2000) 30.8–42.4ms → 0049 滚动轮 6.9ms（−77–84%）；真机 4× 投影滚动轮 ≈ 6.3/15.5/27.8ms@300/1000/2000——300 档首次进入 8ms 帧预算。
- 滚动轮剩余 = 已测前缀种子消费（O(前缀) append）+ diff + 后缀物化——①(c) 按数据另案。

## 测试

- 新增 `test/lazy_prefix_adoption_test.dart`（11 项）：滚动尾追加/窗口内中部编辑（增量 vs canonical 全等 + eligibility 相对断言钉增量语义）、前缀含表格（硬断言隐患形态）、body 级 li 跨缝 marker（orderedItem 恢复）、浮动 img 前缀（排除区几何）、跨边界 margin 折叠（pendingMargin 恢复）、不合格后缀回退全量 plain、viewport 轮不合格编辑经重跑保留 plain 后缀平移（reused == children−2）、head 插入 k=0 全量回退、plain→lazy 过渡全量走查、链式 3 轮滚动会话每轮采用 + 全等。
- 全包 317 → 328 零回归；向量与像素黄金零 diff。

## 备选与拒绝原因

- **`_minimumPaintOffset` 改 styleFor 按需解析**：会把硬断言隐患变成隐性 O(子树) 重解析；采用路径从构造上消除该依赖，保留断言作为回归哨兵。
- **前缀 styleCache 整体搬运**（把上一轮 styleCache 按 id 拷贝进新轮）：元素对象换新后按 id 键仍可命中，但会把整个文档的样式条目搬进新 map——与采用语义重复且掩盖真实消费面；按需 styleFor 兜底已覆盖种子断裂等边角。
- **种子消费/段树/样本的前缀采用**（append 循环 O(前缀)）：失效面横跨 samples/remainingExtent/段树，收益需先看本轮数据——①(c) 另案。
- **避免重跑的 plain 模式加固**（给 `_adoptBlock` 加未物化守卫、允许部分前缀）：两个门语义改动面大，重跑只在「viewport + 不合格文档」组合发生且 diff 本身近乎免费。

## 后果

- lazy 滚动会话的流式轮 = 后缀准入验证 + 后缀估算重建 + 前缀种子消费；0047 家族清单中准入走查与估算重建两项落地。
- 已知限制：body 级块间空白仍使 k 截断（采用与索引同限）；fresh 顶部视口形态收益受测量窗口界住；种子断裂（topFor 不匹配）时断裂点之后的前缀子退化为 fresh 重估（styleFor 按需解析，输出不变）。
- `debugEligibilityVisitCount` 语义收窄已记录；`_LazyPrefixAdoption`/`_admitLazyLayout`/`_visitLazyElement` 为引擎私有面，公开 API 不变。
