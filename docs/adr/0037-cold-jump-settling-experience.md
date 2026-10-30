# ADR 0037：冷深跳留白的宿主 settling 遮罩

- 状态：已接受；Android JNY-AL10 profile 已验收（device-matrix §4.8）
- 日期：2026-10-31

## 背景

深像素跳转（初始深偏移、滚动条拖拽、直接 `jumpTo`）落在未测量区域时，ADR 0031/0036 的窗口化懒布局会释放旧窗口，并按每帧 32 块从文档起点推进 frontier。frontier 到达目标前，视口没有任何绘制命令，出现约 31 帧空白（device-matrix §4.4）。异步锚点 `scrollToNodeAsync` 已经通过“保持当前视口 + focus 目标块”避免空白（ADR 0029），但普通像素跳转无法复用：单窗口状态与命令所有权一起转移（ADR 0036），保留旧窗口需要双窗口状态与命令复制，和现有所有权模型冲突。

本 ADR 只解决“空白期看起来像坏页”的体验问题，不加速测量，也不改变布局预算、overscan 或渲染后端。

## 决策

1. **宿主拥有遮罩，引擎不画占位。** `WeftView` 新增 `lazySettlingBuilder`，在视口上方渲染宿主提供的静态占位（骨架、品牌加载态等），用 `IgnorePointer` 包住，不影响滚动与点击。未配置 builder 时保持原有“渐进填充/空白”行为，树结构与黄金基线不变。
2. **引擎提供可靠的 settling 信号。** `RenderWeftSurface` 新增只读 `isLazySettling` 与 `onLazySettlingChanged`；`WeftView` 转发为 `onLazySettlingChanged` 并提供 `WeftViewState.isLazySettling`。回调只在 post-frame 触发，相同值去重；不额外调度帧。
3. **判定只覆盖真正的分帧测量。** 在 `performLayout` 末尾，满足 `useLazy && current.debugIsLazy && measureBudget != null && _needsLazyRelayout()` 时置 true。近 frontier 的同步滚动、已测量窗口、异步锚点测量不会触发；底部跟随在窗口物化前保持 true。
4. **生命周期收敛。** `_exitLazyMode()` 统一复位（选择/Semantics full 升级、禁用 lazy、视口高度失效、文档 id 变化、锚点测量等）；`dispose()` 先清回调再复位；`detach()` 静默复位；晚期安装回调且当前 settling 时补报一次 true。`WeftView` 在文档替换/控制器切换时以 post-frame false 收尾，新的 settling 会取消过期的 false。
5. **不改布局。** `_lazyMeasureBudget`、overscan、`layoutViewport`、`_layoutLazyChildren`、continuation 时序与后端选择全部保持原样；遮罩不伪造任何未测量块的绘制命令或位置。
6. **示例接入。** `example/weft_live` 传入静态主题色骨架，并新增“跳到文末”直接跳转入口。该示例的正文包在单个 `.content` 顶层块中，懒布局无法在块内切窗，因此示例测试注入 300 个顶层段落来验证 wiring；异步章节导航仍走 `scrollToNodeAsync`，全程不显示骨架。

## 备选与拒绝原因

- **引擎保留旧窗口直到目标测量完成**：需要双窗口布局与命令复制，会破坏 ADR 0036 的单所有者转移，内存与一致性成本高；当前没有产品需求支撑。
- **引擎绘制骨架/占位命令**：违反“不为未测量后缀伪造命令”的既有约束（ADR 0025/0029），且主题、内容策略和无障碍应由宿主决定。
- **同步测完再返回**：重新引入 100ms+ 单帧停顿（ADR 0031 的原始问题）。
- **自动滚动/淡入淡出/默认 spinner**：改变导航语义或强加视觉策略；宿主可在 builder 内自行动画，引擎不内置。

## 限制

- settling 信号是 post-frame 的，跳转后的第一个空白帧仍可能被看到；遮罩从下一帧开始覆盖，**不宣称零空白**。
- 遮罩只掩盖等待，不缩短 31 帧左右的收敛时间；strict 60fps 与后端切换不在本 ADR 范围内。
- 分帧 pass 可能只覆盖部分视口，遮罩会持续覆盖到窗口完成；宿主可返回半透明骨架以保留部分内容。
- 回调是 transition-based：卸载后不再触发，宿主必须把 unmount 视为 settled；文档替换等复位路径会以 false 收尾。
- 宿主骨架自身若有动画/Timer/大量 Widget，帧成本由宿主负责；示例使用静态骨架。

## 验证

- `packages/weft/test/weft_view_settling_test.dart` 覆盖深跳/深种子出现与消失、无 builder 的回调、近 frontier 与异步锚点不触发、底部跟随、文档替换、选择 full 升级、禁用 lazy、Semantics、无额外帧调度。
- `packages/weft_engine/test/lazy_layout_test.dart` 覆盖 surface 级回调序列、近 frontier 同步路径、lazy 退出与文档替换复位、同 id 流式更新。
- `example/weft_live/test/widget_test.dart` 覆盖直接跳底的骨架与异步章节导航的抑制。
- 全量 format/analyze/doc coverage/verify/像素黄金保持通过；未配置 builder 时树与黄金不变。
- Android JNY-AL10 profile 验证遮罩时序、异步/近 frontier 抑制、lazy 收敛与冷跳帧预算，证据与结论写入 `docs/device-matrix.md` §4.8。

## 引用

- ADR 0025：渐进式布局虚拟化
- ADR 0029：异步锚点测量保持当前内容
- ADR 0031：懒布局分帧与同快照复用
- ADR 0036：已测窗口直物化与命令所有权
- device-matrix §4.4：冷跳空白与四项设备标准
