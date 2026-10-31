# ADR 0041：语义虚拟化——Semantics 直接在 lazy 布局上组装

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0025 的原设计：`assembleSemanticsNode` 首行同步把 lazy 布局升级为 canonical full 并按 document.id 粘滞。读屏一开启，懒布局的全部收益丢失——O(N) 全量重排在 assemble 帧同步发生、全部块常驻内存（真机 +10MB 的懒布局内存收益归零）、ADR 0037 的 settling 遮罩在语义开启时永不出现（深跳被 full 升级先行吞掉）。

探索确认 lazy 结果已具备直接组装语义的数据：`incrementalCache.blocks[i]` 与第 i 个顶层**元素**子级按位对应（含 `element`/`top`/`height`/`materialized`/`paintBounds`），`measuredPrefixLength` 是从 0 开始的连续前缀，`textIndex` 在 lazy 下也是全文档（未测块的**标签文本**可全文取得）；但 `commands`/`textRectsForNode` 只覆盖物化窗口（未物化返回空列表）。同时现状 off-screen 语义节点本就带 `isHidden`（辅助技术不朗读，只为节点身份稳定与 showOnScreen 存在），因此窗口外语义的形态变化不影响朗读行为。

本 ADR 修订 ADR 0025 的「assemble 前必须升级 full」契约，让读屏与虚拟化共存。布局、绘制、像素黄金不变。

## 决策

### 1. 分区语义模型

| 区域 | 语义输出 |
|---|---|
| 物化窗口块 | 精确片段，与 full 路径逐字相同（文本 run/链接/图片/容器角色/ARIA 语义） |
| 已测但未物化、且块带与视口 band（±2–3 屏）相交 | **粗粒度叶子**：key `block:<nodeId>`，label 为该块扁平化文本（来自全文档 textIndex，img 取 aria-label/alt），rect 为块保留几何（paintBounds，退化时 margin-box 带） |
| band 外已测块 | 不产出（assemble 成本有界于 O(窗口+band)） |
| 未测后缀 | 不产出；滚动测量后自然出现（与 Flutter ListView 的语义虚拟化同型） |

- `_ensureFullLayoutForQuery('semantics')` 删除；`selection`/`anchor`/`image`/`engine-fallback` 的 full 升级路径与粘滞语义全部保持不变。
- band 按当前视口像素计算（`viewportPixels - 2×viewportHeight` … `+ 3×viewportHeight`），懒布局下视口高度必非空，取不到时（防御）不产出粗叶子。
- aria-hidden 块不产出粗叶子；body 级 `aria-live` 继承到粗叶子的 `liveRegion`。
- 粗→精升级时节点 key 变化（`block:` → `text:`/`image:`），辅助技术重新聚焦该块；这是窗口推进的自然结果。
- 粗叶子不携带列表 marker、标题层级、链接 tap、容器角色——这些只在精确片段上存在；band 内块被重新物化后恢复。

### 2. 更新频率与成本

- 框架在每次 `performLayout` 后隐式 `markNeedsSemanticsUpdate`：lazy 跨窗滚动每帧新建布局实例 → 片段缓存（layout identity 键）每帧重建。重建范围有界：精确片段 O(物化窗口) + 粗叶子 O(band 内未物化块)，每块一次 textIndex 文本遍历（无布局查询）。窗口内的近距滚动不触发 relayout，语义树不变。
- full 路径（无 lazy 或已粘滞 full）行为与缓存逻辑不变；全部既有非 lazy 语义测试保持原样并通过。

### 3. 与既有机制的交叉

- **settling**：语义开启的冷深跳现在真正走 ADR 0037 的 settling——宿主遮罩与 `onLazySettlingChanged`/`isLazySettling` 正常上报（此前被 full 升级吞掉）。配置了 `lazySettlingBuilder` 的宿主在 TalkBack 开启时会看到遮罩，这是预期行为。
- **异步锚点**：semantics 不再置粘滞位，semantics-on 会话中 `scrollToAnchorAsync` 照常分帧测量（ADR 0029 中"Semantics 强制 full 使请求返回 null"的句子随本 ADR 修订）。
- **图片异步解码**：`'image'` 粘滞升级保持；语义开启的会话中该路径真正可达（此前几乎不可达）。
- **选区**：非空 selection 仍粘滞 full，selection 片段始终在 full 布局上组装，自洽。

## 备选与拒绝原因

- **维持 full 升级，另建"无绘制命令的语义专用 full 布局"**：布局产出命令与几何不可分，省掉命令等于新布局模式；且全量文本测量的 O(N) 首帧成本仍在，违背虚拟化目标。
- **只在物化窗口暴露语义（无粗叶子）**：块刚离开窗口（跨过 overscan）语义即消失，块带与视口边缘相交的块无法朗读，身份抖动比粗叶子更大；粗叶子用 O(1) 成本换窗口外身份稳定与 showOnScreen 目标。
- **对全部已测前缀发粗叶子（不限 band）**：已测前缀可达千块，每次跨窗滚动的 assemble 变为 O(prefix) 节点更新；band 截断后成本回到 O(窗口)。
- **为未测后缀按聚合 remainingExtent 发估算节点**：没有 per-block 估算 offset，位置只能是伪造；ADR 0037 的"不伪造未测量块"原则继续适用。
- **提供虚拟化开关 API**：行为默认启用，避免增加宿主必须理解的配置面；契约变化由 ADR 与 CHANGELOG 承载。

## 后果

- 读屏开启时懒布局存活：内存与首帧收益保留，语义开启的深跳出现 settling 遮罩（宿主可见的行为变化）。
- 新增测试 1 项（band 内未物化块的粗叶子 + showOnScreen），重写 5 项契约测试（lazy_layout_test 渲染级、weft_view_lazy_test 两项、weft_view_semantics_test 离屏滚动一项、weft_view_settling_test 一项）；总数 508 → 509（以 `tool/verify.dart` 输出为准）。
- 契约句同步修订：supported-subset（流式增量节、可访问性节）、architecture、api-contracts、testing-strategy、weft_view 的 `enableLazyLayout` 文档。
- 已知限制：粗叶子只播报块文本（无行内结构）；块带离开 band 后节点消失；同 id 流式更新会随快照重建片段；语义开启滚动的真机帧耗时未验证（无设备在线，记入 device-matrix 后续项）。
