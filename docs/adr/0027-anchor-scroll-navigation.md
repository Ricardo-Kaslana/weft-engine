# ADR 0027：逻辑文本锚点滚动导航

- 状态：已接受
- 日期：2026-10-27

## 背景

宿主可以操作 `WeftView.scrollController` 的像素偏移，但无法按 `TextAnchor` 定位目录、脚注或外部深链。懒布局又只有可见块命令，无法直接用局部几何代表完整文档。锚点导航需要精确、可预测，同时保持无效锚点的安全丢弃语义；首版曾直接升级 full，随后改为一次性 focus 布局以保留 lazy。

## 决策

### Anchor 几何查询

- `RenderWeftSurface.textRectForAnchor(TextAnchor)` 返回锚点单字符范围的 document-local 矩形。
- 查询前先用完整 `WeftTextIndex.entryByNode` 校验 node 与 offset；未知节点、越界或节点末尾不触发布局、返回 null，遵循 ADR 0013 的安全丢弃。
- 懒布局下使用一次性 focus 布局：`layoutViewport(focusNodeId)` 计算目标 body 顶层 ordinal，强制精确测量目标之前的连续前缀并物化目标块，同时保留当前窗口命令；目标之后继续估算。
- focus 结果仍为 lazy，不设置 `_fullLayoutRequired`；若引擎准入失败或目标仍无矩形，才回退 `_ensureFullLayoutForQuery(reason)`。使用现有 `textRectsForNode(nodeId, offset, offset+1)` 与矩形并集，不新增第二套文本测量。

### ViewState 滚动

- `WeftViewState.scrollToAnchor(TextAnchor, {alignment})` 返回 bool：true 表示锚点已解析且滚动请求已排队；0 顶部、1 底部，非法 alignment 在 debug assert，release 返回 false。
- 同步升级 full 后 RenderObject.size 与 `maxScrollExtent` 要到下一帧更新，因此在 post-frame 读取 `viewportDimension`/滚动范围，按
  `rect.top - alignment * max(0, viewportDimension - rect.height)`
  计算并 clamp 后 `jumpTo`。显式 `scheduleFrame()`，保证连续定位在布局已稳定时也会执行。
- 请求带 generation，并校验 mounted、document id/revision；卸载、controller 切换或新请求会丢弃旧回调。
- 注入 controller 与内部 controller 共用同一实现；`jumpTo` 触发现有滚动 listener 更新 Surface 物化窗口。API 不改变 pointer、selection、Semantics 或 chrome。

## 理由

- focus 布局只扩展必要的精确前缀，避免为单次深链永久关闭 lazy；随机跳转本身仍可能需要顺序测量前缀，因此不宣称 O(1)。
- 通过 RenderObject 查询保证 textScaler、宽度、图片和真实布局输入一致，不在 View 层另跑 probe 布局。
- 返回 bool 与现有同步查询风格一致；无效锚点不产生异步异常或隐式升级。

## 后果

- 新增 1 项 engine anchor focus 查询测试与 3 项 WeftView 导航测试；weft_engine 常规测试 219 项、weft 34 项。
- 锚点导航不改变绘制、选区、Semantics 或几何基线。
- 限制：首次深链仍可能需要测量目标之前的全部块，目标块在下一帧窗口重排时可能再次物化；节点末尾无字符几何时返回 false；尚不支持动画滚动、水平定位或基于块 metrics 的 O(1) 随机访问。复杂文档仍升级 full。
