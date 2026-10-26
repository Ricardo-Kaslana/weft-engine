# ADR 0031：懒布局的异步分帧测量与同快照复用准入

- 状态：已接受
- 日期：2026-10-27

## 背景

ADR 0025 的懒布局只连续推进 `measuredPrefixLength`，冷跳底部会在一帧内同步测量整个前缀；ADR 0029 只给锚点导航加了分帧。本机画像（360px 视口、800px 视口高、250px overscan，1 次预热 + 5 次采样取中位数）量化了两个成本：

- 冷跳估算底部：300 块文章单帧 124.8ms，1000 块 149.6ms——全部前缀块在同一帧内递归排版。
- 已测满前缀后的滚动重排：每帧 6ms（300 块）～10ms（1000 块），随块数线性增长。成本由三部分构成：`_reusableLayoutBlocks` 对每棵子树的递归 `_sameNode` 比较、`_supportsLazyLayout` 与块走查中逐元素重复的选择器匹配（无缓存）、`WeftTextIndex` 全量重建。

## 决策

### 非锚点路径的预算分帧

- `RenderWeftSurface` 新增 `_lazyMeasureBudget = 32`。两类情形下滚动驱动的 `layoutViewport` 传入该预算：首帧 lazy 布局且 seed 像素深于 overscan（`previous` 无可复用 lazy cache 而视口起点 > 0）；已测前缀末端距视口末端超过一屏（`end > last.top + last.height + viewportHeight`）。其余滚动保持原有的单次同步测量。
- 每个 pass 最多新测 32 个顶层块，超出部分按 ADR 0025 估算。pass 后由 post-frame 回调检查 `_needsLazyRelayout()`，仍需推进则 `markNeedsLayout` 并 `scheduleFrame`，逐帧收敛；`_lazyGeneration` 在 full 升级、换文档、模式退出与 dispose 时使回调失效。
- 停止条件与 `_needsLazyRelayout()` 一致：物化窗口覆盖后，窗口之外的尾部块保持估算，不追求"测完全部"。锚点异步测量（ADR 0029）继续携带自己的 focus 与预算，两个循环共用同一 pass 管线，互不干扰。
- 分帧期间目标区域在测到之前没有绘制命令（空白），随 frontier 逐帧填充；跳到估算底部时既有的 `_followLazyBottom` 与 `correctBy` 校正继续生效。这是渐进契约（估算 extent、估算滚动条长度）的自然延伸，与 Chrome `content-visibility` 的渐进布局行为一致。

### 同快照 O(1) 复用准入与跨帧缓存

- `identical(cache.document, document)` 时跳过递归节点 diff 与样式表签名比较：同一快照实例的树、属性与样式表就是同一对象，逐节点比较是纯冗余。流式更新（新快照实例）仍走完整 diff。
- `WeftIncrementalLayoutCache` 新增 `styleCache`（元素身份 → `WeftComputedStyle`）。计算样式只由快照决定（宽度、缩放、图片不参与），因此只要快照实例未变，样式缓存跨帧有效；宽度或 textScaler 变化仍可复用样式，仅重建几何。同一元素在单次布局内也只解析一次（`outerMarginTop/Bottom`、`_isSelfCollapsing`、`_isInlineEmpty` 的重复探测全部命中缓存）。
- 同快照的 relayout 直接复用 `previous.textIndex` 实例；逻辑文本索引只依赖快照内容，逐帧重建是纯浪费。

### 等价性论证

样式缓存与文本索引复用的正确性来自"计算样式与逻辑文本是快照的纯函数"：规范化快照不可变，元素的父链唯一确定，因此解析结果确定。块复用仍要求全局输入键（宽度、缩放、图片、断行规则）一致，几何结果与全量布局逐命令等价，由既有增量测试与新增的样式缓存等价测试守护。

## 后果

- 本机画像（1 次预热 + 5 次采样取中位数）：

| 场景 | 改前（单帧同步） | 改后（分帧） |
|---|---:|---:|
| 300 块冷跳估算底部 | 124.8ms 单帧 | 10 帧 × 中位 5.8ms（最差 6.3ms） |
| 1000 块冷跳估算底部 | 149.6ms 单帧 | 32 帧 × 中位 9.3ms（最差 17.6ms） |
| 复用走查（同快照换窗） | 3.5ms（300 块）/ 8.5ms（1000 块） | 0.6ms / 1.0ms |

- 新增 5 项引擎测试（同快照复用计数、样式缓存等价、深跳分帧收敛、深 seed 分帧收敛、近距滚动同步）并更新 2 项 WeftView 测试；weft_engine 常规测试 227 项、weft 39 项。
- 限制：滚动重排仍走查整个已测前缀（无缓存命中后约 1µs/块），窗口直物化（真正的 O(log N) 随机定位）留待后续；分帧期间深跳目标区短暂空白；逐帧预算为内部常量，未公开配置。

### 后续：窗口直物化（O(log N) 随机定位）的设计约束

同快照下块的 top/height 已持久保存，理论上可按窗口二分定位、直接物化命令而无需走查前缀。但直接落地有三个前置问题，本 ADR 不处理：

1. 负 margin 与显式 `height` 溢出使块盒与绘制区间失去单调性，简单按 top 二分会漏块；需要前缀最大绘制底边等保守索引。
2. body 自身的背景/边框命令不落在任何顶层块缓存内，其矩形随估算 extent 变化，需要单独的 chrome 缓存或按 extent 重算。
3. 估算后缀的每块逐一遍历仍随未测块数线性；要把整个 relayout 做成 O(log N + 窗口)，还需把后缀 extent 缓存为 frontier 状态的函数，并在 frontier 推进时增量更新。

## 参考

- 画像脚本与门禁测试：`packages/weft_engine/test/lazy_layout_test.dart`（预算分帧、同快照复用、样式缓存等价）。
- 前置：ADR 0023（顶层前缀复用与所有权）、ADR 0025（渐进式虚拟化与估算契约）、ADR 0027/0029（锚点 focus 与异步分帧）。
