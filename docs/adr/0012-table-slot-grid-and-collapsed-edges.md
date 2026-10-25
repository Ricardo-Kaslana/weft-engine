# ADR 0012：表格使用槽位网格与中心线折叠边框模型

- 状态：已接受
- 日期：2026-10-25

## 背景

商品描述、帮助文档和 CMS 文章大量使用简单表格（规格表、价格表、参数对照）。此前 `table` 属于回退标签，宿主必须为任何含表格的内容启用 WebView。目标子集要求支持 `table/thead/tbody/tfoot/tr/th/td/caption`、`colspan/rowspan` 和基础边框，同时保持“不做完整浏览器”的边界。

## 决策

### 规范化与样式

- `table` 系标签进入白名单；`colspan/rowspan` 按 HTML 上限（1..1000）清洗，非法值移除并报告 `table.span.invalid`。
- 嵌套表格触发 `html.table.nested` 并要求 `requiresWebView`，子树被丢弃而不是静默展平。
- 裸文本和未知块在 HTML5 解析器（package:html）的 foster parenting 下会移到表外，与浏览器一致；规范化器保留防御性诊断以覆盖未来其他解析适配层。
- 新增 CSS：`border-collapse`（separate/collapse，默认 separate）、`border-spacing`（默认 2px，即浏览器 UA 值）、`vertical-align`（top/middle/bottom；baseline 归并为 middle）。
- `td/th` 默认 `vertical-align: middle`、`th` 加粗居中；table 不带默认外边距（与浏览器一致）。

### 网格与跨距

- `layoutTable` 从 `tr`（直接或经 thead/tbody/tfoot）收集单元格，用占用槽位算法放置 `colspan/rowspan`，悬空的 rowspan 生成隐式行。
- 表格盒不参与自垮塌（`_isSelfCollapsing` 排除 table），外边距链也不会穿入单元格（`outerMarginTop/Bottom` 在 table 处截断）。
- 单元格以强制 border-box 宽度复用 `layoutBlock`：单元格内容获得与普通块一致的行内布局、链接命中、margin 折叠和列表支持；每个单元格使用独立的 `_FloatContext`（单元格近似 BFC，浮动不外溢）。

### 宽度算法（两遍）

- 第一遍测量：行内内容用 `TextPainter.minIntrinsicWidth/maxIntrinsicWidth` 精确测量；块子元素用递归近似测量。列内建 min/max，跨列单元格按现有列宽比例分配差额。
- 第二遍分配：表宽为 shrink-to-fit（`min(max(minSum, available), maxSum)`）或解析后的 CSS 宽度；预算 = 表宽 − 全部边框 − 间距（separate 模式间距含表缘两侧）；富余按列 max-content 权重比例分配，不足时按 min 等比压缩。

### 边框模型

- separate（默认）：每格绘制自身实线边框；`border-spacing` 同时作用于格间与表缘。
- collapse：边框居中于网格线。边宽取相邻单元格（及表框）的最大值，平手时靠左/靠上者优先（CSS 2.1 §17.6.2 的简化，因引擎只支持 solid）。单元格盒从边框中心线延伸到中心线，半边宽以合成 padding 的形式内缩内容、背景铺到中心线之下，与浏览器一致。
- 单元格盒、背景与边框在内容短于行槽时拉伸到整行（浏览器行为），`vertical-align` 只移动内容。

### 单元格平移

- 单元格先在原点布局（行高未知），记录命令/盒/链接区间，行高确定后按 (dx, dy) 平移。区间使用捕获的起止下标，避免共享数组上的重叠平移。

## 与浏览器的已知偏差

1. 列宽分配按 max-content 权重比例，浏览器算法更复杂；固定字体下 `table_basic` 一致性案例的列边界与 Chromium 偏差 ≤ 1px，自由分配场景（无固定列宽且需要压缩/扩张）可差数像素。
2. 块子元素的 min/max 测量是近似（行内精确、块递归估算），极端嵌套下会传导上述列宽偏差。
3. `vertical-align: baseline` 按居中处理；行高不足时的跨行高度差额全部计入最后一行（浏览器按比例分布到各行）。
4. 表格自身不与相邻浮动交互（表宽仍取包含块全宽）；`colgroup/col` 被解包并警告，列宽属性不生效。
5. 表格内部的内容不参与全局文本选择（选择模型尚未实现）。

## 后果

- 含简单表格的受控内容不再需要 WebView 回退；`table_basic` 一致性案例提供浏览器几何基线（单元格 ≤ 1.5px、结构关系精确断言）。
- 后续 Flexbox、完整 BFC 等格式化上下文如需与表格交互，必须复用同一套网格与行槽查询，不得绕过 `layoutTable`。
