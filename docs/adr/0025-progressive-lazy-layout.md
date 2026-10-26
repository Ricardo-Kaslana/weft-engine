# ADR 0025：渐进式布局级视口虚拟化

- 状态：已接受
- 日期：2026-10-27

## 背景

ADR 0017/0020 已按可见窗口裁剪绘制和命中，但每次文档更新仍会布局全部 body 顶层块并创建全部 TextPainter。AI 长文与 CMS 文章的首屏只需要少量可见块；同时，未测量后缀无法提供精确文档高度。本决策选择渐进契约：精确测量连续前缀，未测后缀估算滚动高度，首版只服务可证明安全的简单块流。

## 决策

### 入口与启用条件

- 公开 `WeftLayoutEngine.layout()` 保持 canonical 全量结果。新增 `layoutViewport()` 供 Surface 使用，传入 document 可见窗口；部分 lazy result 不会作为完整布局的 previous。
- `WeftView.enableLazyLayout` 默认 true，可显式关闭；standalone `WeftSurface` 默认 full。只有 WeftView 提供有界 viewportHeight 时才启用。
- 准入递归检查计算样式和图片输入。包含全局 Float、body 直属 loose inline/text、display:none、self-collapsing 或未解析图片的文档直接 full；表格作为单个顶层原子块，不做行级或表内虚拟化。

### 连续精确前缀与估算后缀

- 复用 `_layoutChildren()`、`layoutBlock()`、`layoutTable()` 和 ADR0023 顶层块复用，不复制简化排版器。已测块保存精确 left/top/height、paintBounds、commands/boxes/links；未变可见块可继续复用 TextPainter 和 Picture。
- 物化窗口 = 当前滚动 offset ± 250px overscan 与视口高度。屏幕外已测块释放 commands，仅保留 metrics；再次进入窗口时在原块流状态下重新布局，不做行级缓存或后缀平移。
- 只能连续推进 measuredPrefixLength。首个未测且位于窗口末端之后的块使用最近 16 个同类块高度中位数估算；margin、列表计数和 cursor 仍按原状态机推进。冷跳底部可同步顺序测量中间块，首版不承诺 O(1) 随机访问。
- 估算 extent 只代表未测区；全部块测完后收敛 canonical 高度。滚动条长度可能随测量校正，这是渐进契约的一部分。

### 滚动、校正与所有权

- WeftView 使用注入的 ScrollController 或自有内部 controller，通过 LayoutBuilder 获取 viewportHeight，并在滚动时更新 Surface 的 document pixels。仅当目标物化集合变化或需要推进前缀时触发布局。
- RenderSurface.size 继续表示估算/精确文档高度，SingleChildScrollView、selection chrome 和命中继续使用 document-local 坐标。跳到当前估算底部后，extent 增长通过 post-frame `ScrollPosition.correctBy(delta)` 跟随；用户离开底部即取消，不使用强制 jumpTo。
- current lazy result 是物化命令唯一 owner；previous 只转出仍可见的命令，淘汰命令随 previous.dispose 释放。未测后缀不生成假命令或假 TextPainter。
- 同 document.id 的尾部追加使用 ADR0023 子树 diff，保留变化前缀前 metrics 和未变可见资源；非尾部编辑、图片/尺寸/样式/scaler/kinsoku 变化回退 full。

### 交互回退

- 任意非空 selection（含 caret）需要完整几何时，Surface 立即升级 canonical full。`selectionText` 仍只依赖完整逻辑文本。
- Semantics assemble 遇到 lazy result 时先同步升级 full，再生成全部屏外节点；不暴露“仅可见块”语义，ADR0024 的 showOnScreen 契约保持不变。
- full 升级按 document.id 粘滞，selection 清除或 Semantics 关闭后不来回切换；新文档才重新评估。图片晚解码或身份变化同样升级 full。

## 理由

- 首屏收益来自不创建未测块 TextPainter，而估算只影响滚动条，不进入绘制、命中或语义几何，错误不会被当作内容呈现。
- 连续测量保持 margin collapse、列表序号和块坐标精确，避免从任意块恢复不可能完整的布局 checkpoint。
- 复用 ADR0023 的所有权和内容身份检查，不引入第三个 Painter owner；ADV 0024 则在需要时升级 full，优先保证无障碍和跨屏选择正确。

## 后果

- 360×800 视口、250px overscan、360px 宽 article300：

| 场景 | 同轮中位数 | 实际布局/物化块 |
|---|---:|---:|
| article300 Full | 43.6ms | 330 |
| lazyArticle300FirstViewport | 3.2ms | 6 / 6 |

  首屏约降低 93%。数据来自本机 1 次预热、5 次采样，真实设备会受字体和 JIT 影响；CI 仍使用宽松上限，结构计数测试断言首屏远小于全文档。

- 新增 engine lazy/结构/底部收敛测试与 7 项 WeftView lazy 测试；weft_engine 常规测试 210 项、weft 25 项。
- 限制：未测后缀高度和滚动条长度会校正；冷跳底部仍为 O(N) 顺序测量；一个超高顶层块、Float、未解析图片和屏外选择/Semantics 会回退或保持 full。尚无异步分帧测量、表格行虚拟化、图片解码虚拟化和精确随机跳转。
