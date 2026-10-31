# ADR 0043：增量布局画像与方向选择

- 状态：已接受
- 日期：2026-10-31

## 背景

handoff 的最高优先级指令是「先画像再选择 Float checkpoint、后缀平移、文本索引增量」。选择依据此前只有间接证据：ADR 0023 的流式追加 6.7ms（无成分分解）与其遗留成本清单（O(块数) 的快照 diff、样式解析、列表合并和文本索引重建；Float checkpoint、后缀平移、行级复用未实现）、ADR 0031 的滚动重排三分量分解（已被 styleCache/同快照复用消化）。本切片只画像不实现：引擎 `lib/src/` 零改动，产出可复现的画像工具、成分分解数据与方向决策。

## 画像方法

新工具 `packages/weft_engine/tool/incremental_profile_test.dart`（与 `tool/layout_benchmark_test.dart`、`tool/scroll_frame_benchmark_test.dart` 并列的第三个手动基准，不进 CI 门禁），三组实验：

- **E0 成分分解**（富文章 300/1000/2000 段）：冷全量 C(n)、同快照地板 F(n)（diff/样式缓存/textIndex 全部跳过，剩走查）、同内容新快照轮 U(n)（= diff + textIndex + 样式 + 走查）；textIndex（`WeftTextIndex.build` 公开直测）、样式解析全量遍历（同包直测 resolver，镜像 text_index 的走查形状）、diff（工具侧镜像引擎 `_sameNode` 的递归比较）各自直测。恒等式 U ≈ diff + T + S + F 的覆盖率随行打印，不当假设。
- **E1 流式形态**（300 与 1000 段，每轮新快照同 id，预热 3 轮后测 6 轮取中位）：尾部追加（plain `layout` 与 lazy `layoutViewport` 两种宿主）、尾块增长（AI 流式）、中部编辑、头部插入（weft_live 实际更新形态），另测最终文档冷全量对照。每轮打印 `debugReused/LaidOut/Estimated/EligibilityVisit` 计数与 incrementalCache 是否播种，并按形态契约断言复用计数（断言失败即数据无效）。
- **E3 Float 成本**：plain 宿主 Float 文档的缓存播种与流式轮、lazy 宿主图片 Float 流式轮、单浮图 + 长 CJK 段 {1k/2k/4k/8k 字} 对无浮对照的逐行路径标度。

测量纪律：桌面 Stopwatch 含 harness 成本，只做相对比较，不当真机帧耗时（handoff 红线）；采集两轮对照，毫秒级小项（<5ms）受噪声支配看比例与结构计数；复用键为 document.id + 样式表签名 + 宽度/缩放/图片/断行规则（layout_engine `_reusableLayoutBlocks`）。

## 数据（Windows 开发机，2026-10-31，两轮）

### E0：新快照流式轮的成分（ms，两轮区间）

| 规模 | 冷全量 | 地板 F | 新快照轮 U | textIndex T | 样式全量 S | diff 代理 | 每块 µs |
|---|---|---|---|---|---|---|---|
| 300（330 块） | 47.1–48.0 | 1.6–1.8 | 2.3–2.7 | 1.5–1.8 | 0.5–0.6 | 0.21–0.23 | 6.9–8.1 |
| 1000（1100 块） | 132.6–135.9 | 1.3–1.5 | 7.9–8.6 | 5.8–8.4 | 1.4–2.2 | 0.20–0.38 | 7.2–7.8 |
| 2000（2200 块） | 292.5–343.0 | 2.5 | 19.5–23.1 | 11.8–13.0 | 2.8–3.0 | 0.5–1.7 | 8.9–10.5 |

300 段量级单项 <3ms，噪声与分量同阶（U−T−S−F 出现负残差）；1000/2000 的比例稳定：**textIndex 占新快照轮 56–81%，diff ≤1.7ms 可忽略，样式单遍 0.5–3ms**。注意 T 内部还包含一次全量样式解析（text_index 直连 resolver、绕过布局的 styleCache），即流式每轮每元素选择器匹配至少两遍。

### E1：形态成本阶梯（每轮中位 ms，两轮区间；saving 对同规模冷全量）

| 形态 | 宿主 | 300 段 | 1000 段 | saving |
|---|---|---|---|---|
| 尾部追加（10 段/轮） | plain | 3.5–6.8 | 9.7–16.2 | 84–93% |
| 尾块增长（120 字/轮） | plain | 3.1–4.6 | 8.7–12.4 | 89–91% |
| 中部编辑（第 n/2 段） | plain | 15.8–21.6 | 64.3–66.7 | 44–60% |
| 头部插入（weft_live 形态） | plain | 31.1–40.9 | — | **≈0%（−4–+4%）** |
| 尾部追加 | lazy | 3.1–4.3 | 10.3–12.9 | 91–92% |

lazy 宿主流式轮的结构计数：`eligibility` ≈ 3× 元素数（每轮全树准入走查）、`estimated` ≈ 全部块数（估算后缀逐块重建）、`reused` 仅等于已测窗口（4–5 块）——O(doc) 三件套 = 准入 + 估算重建 + textIndex。

### E3：Float 成本

- plain 宿主 Float 文档 `incrementalCache` **不播种**（`_layoutDocument` 的 `(lazy || !floats.hasExclusions)` 条件，结构断言证实）→ 流式每轮冷全量，且首段浮图后**整篇**走逐行路径：328–430ms/轮（同规模无浮冷全量 43ms 的 8–10 倍）。
- lazy 宿主 + 图片 Float 流式轮 5.2–5.6ms/轮，与无浮 lazy（3.1–4.3ms）同量级——ADR 0036 的窗口物化 + 逐块排除区 checkpoint 已覆盖图片 Float 的流式复用。
- 逐行路径标度（单浮图 + 单段 CJK，对无浮对照）：1000 字 11.5ms vs 0.09ms；2000 字 53.4 vs 0.31；4000 字 171.3 vs 2.1；8000 字 **763.9 vs 1.2ms**。字数翻倍耗时 3.2–4.6 倍，**段内 O(n²) 确认**（probe 每行重塑全部剩余文本，inline_flow `_InlineAccumulator.buildLines`）；短段落的常数成本约 30×/段（Float 文章 330 段 ≈340ms vs 43ms）。

### 校准

E1 冷对照 article300 ≈ 43.6ms、尾部追加 plain 300 ≈ 6.8ms（第一轮）与 `tool/layout_benchmark_test.dart` 及 ADR 0023 的历史值吻合；画像数据与既有基准同源可信。

## 结论

1. **快照 diff 不是问题**：0.2–1.7ms（2200 块），ADR 0023 遗留清单中的「O(块数) diff」可以撤掉。
2. **样式解析单遍便宜**（0.5–3ms），但流式每轮发生 2–3 遍（textIndex 内部一遍、lazy 准入一遍、布局走查一遍），源于 textIndex 直连 resolver 与新快照清空 styleCache。
3. **textIndex 全量重建是流式轮最大纯开销**（56–81% of U），存在于所有形态与两种宿主。
4. **形态阶梯**：尾部追加/增长已优化充分（84–93% saving）；中部编辑损失一半（后缀重排）；头部插入零收益（每轮全量）——weft_live 的实际更新形态落在最差档。
5. **Float checkpoint（作为块复用使能）被数据降级**：lazy 宿主的图片 Float 流式已被 ADR 0036 覆盖；plain 宿主的 340ms 轮成本来自逐行路径本身（30× 常数 + O(n²)），不是复用缺失。逐行路径的增量化/行级复用才是 Float 家族的正主。
6. lazy 宿主流式轮的 O(doc) 固定成本 = 准入走查 + 估算后缀重建 + textIndex（12.9ms@1000），三者只有计数没有分时，属同一「跨快照复用」家族。

## 决策

**下一方向 = 文本索引增量（跨快照前缀复用）**。理由：数据上它是所有形态、两种宿主共有的最大单开销成分；机制上条目是快照的纯函数且节点 id 跨同内容快照稳定（`_sameNode` 的复用已依赖该事实），尾部追加可逐字复用前缀条目（含 globalStart 与已解析文本）、仅构建后缀，等价性论证是 ADR 0031「计算样式与逻辑文本是快照的纯函数」模板的直接延伸，守卫为增量索引与全量重建逐条目相等的结构测试。它同时消掉 textIndex 内部的前缀全量 resolve，并为后续两个方向垫底（行级复用与后缀平移落地后每轮仍要重建 textIndex）。

后续排序（数据依据见结论）：② 逐行路径增量化/行级复用（Float 家族，画像中绝对值最大：763.9ms 单段、340ms Float 文章轮）；③ 后缀平移（头部插入/中部编辑能力缺口，head-insert saving ≈0、mid-edit saving 44–60%）。Float checkpoint 不再作为独立方向立项。

## 备选与拒绝原因

- **引擎内加计时埋点再画像**：现有 debug 计数器 + 差分法已足够分解到方向决策所需的粒度；给 `lib/src/` 引入计时代码打破「引擎无计时」现状，且临时埋点的生命周期管理与 handoff 的 perf_probe 流程重复。
- **先做后缀平移**：收益形态（head-insert 每轮省 ~33ms@300）真实，但等价性成本最高——margin collapse、列表计数、cursor 都是顺序状态机（ADR 0023 明确「复用嵌入现有 `_layoutChildren()`，不另建后缀布局算法」），且其每轮成本仍含 textIndex 重建，应排在 ① 之后叠加。
- **先做 Float checkpoint**：被数据降级（结论 5）。
- **真机画像先行**：handoff 红线禁止把桌面 layoutViewport 画像当真机帧耗时；方向选择只需相对比例，真机 4× 换算与 FrameTiming 分列属 device-matrix §5 待办。
- **直接放宽懒准入/近似复用**：handoff 明令禁止把 ADR 0023/0025 的保守回退改成未验证的近似复用；本决策不触碰准入条件。

## 后果

- 新增第三个手动性能工具 `tool/incremental_profile_test.dart`（E0/E1/E3 三组实验，print 报告 + 形态契约断言），不在 CI 门禁内；运行方式与数据录入本 ADR。
- 引擎 `lib/src/` 零改动：523 项测试与像素黄金零回归（以 `tool/verify.dart` 输出为准）。
- 已知局限：E0@300 单项噪声与分量同阶（残差为负属预期）；diff 代理是工具侧镜像而非引擎内实测；准入/估算重建只有计数证据；单一开发机单字体环境（无 CJK 字体，CJK 数据走测试默认字体）。
- 真机待办不变：device-matrix §5 的语义开启滚动帧耗时等条目继续挂起；本 ADR 数据不改变任何运行时行为。
