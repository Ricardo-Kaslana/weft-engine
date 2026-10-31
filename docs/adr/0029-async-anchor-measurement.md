# ADR 0029：锚点导航的异步分帧测量

- 状态：已接受
- 日期：2026-10-27

## 背景

ADR 0027 的 focus 锚点能在一次同步布局中精确测到目标块，但数百段文档的深链仍可能在一帧内测量全部前缀。用户要求加入异步分帧；首版只用于锚点导航，不改变普通滚动与底部跳转，也不在目标位置显示估算内容。

## 决策

### 引擎预算

- `layoutViewport(maxNewBlocks:)` 限制单次 pass 新递归布局的顶层块数。达到预算后，即使 focus 尚未到达也改用现有 `_estimateHeight` 估算剩余；目标块一旦在本 pass 内测得，继续按 focus ordinal 强制物化。
- 每个 pass 仍从 body 起点复用 previous metrics/commands，不引入可恢复的 `_layoutChildren` 会话，也不伪造块位置。
- `measuredPrefixLength` 只连续增长；调用方据此判断目标是否已测到。

### Surface 异步测量

- `RenderWeftSurface.measureAnchorAsync` 先做与同步查询相同的完整 textIndex 校验和已物化快查。
- 需要分帧时，每个 post-frame 执行一次带 focus + budget 的 `layoutViewport`，替换并 dispose previous、markNeedsLayout，然后等待 `endOfFrame` 进入下一 pass。当前滚动 offset 和窗口命令保持不变，因此测量期间用户仍看到原内容，没有空白目标页。
- 达到目标 prefixed ordinal 且矩形可解析时完成；无进展、文档 id/revision 变化、selection 强制 full、下一次请求或 dispose 都会使旧请求返回 null。（ADR 0041 修订：Semantics 不再强制 full，语义开启会话中异步测量照常分帧。）
- 引擎 full fallback 仍设置粘滞 full；普通复杂文档不分帧。

### ViewState API

- 新增 `Future<bool> scrollToAnchorAsync(TextAnchor, {alignment, maxNewBlocks=32})`；同步 `scrollToAnchor` 保留。
- Future 完成后在下一帧内部/注入 controller 上按既有 alignment 公式 clamp 并 jumpTo；取消、卸载或文档变化返回 false。
- 测量期间不滚到估算位置，不改变 selection、Semantics、chrome 或 pointer 行为。

## 理由

- 每帧新增块数有确定上界，避免一次深链造成长帧；不实现跨帧 checkpoint，降低状态恢复风险。
- 等待测量完成后再跳转，避免先滚到估算位置再漂移；代价是深链要等待多个帧。
- 复用现有 focus/previous/command 所有权和滚动 formula，不新增第二套布局或滚动实现。

## 后果

- 新增 1 项 engine budget 测试与 1 项 WeftView 跨帧测试；weft_engine 常规测试 221 项、weft 36 项。
- 普通 lazy、同步 focus、selection/Semantics 与像素基线不变。
- 限制：每 pass 开销仍包含已测前缀的复用扫描；没有进度回调/取消 token API；目标靠后时总耗时仍与目标深度成正比；滚动到底部等非锚点路径不分帧。后续可加进度通知或基于块索引的精确随机访问。
