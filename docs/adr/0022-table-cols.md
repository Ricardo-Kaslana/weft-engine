# ADR 0022：表格 colgroup/col 列轨道与列宽分配

- 状态：已接受
- 日期：2026-10-25

## 背景

ADR 0012 落地了表格的两遍 min/max 列宽与槽位网格，但 `colgroup/col` 被解包并告警，列宽声明不生效。商品规格表和参数对照表大量依赖 `col` 固定列宽来获得确定几何（这也是 `table_basic` 案例对第二张表固定列宽的原因）。本决策在 ADR 0012 的两遍测量之上叠加列轨道声明，不改动槽位网格与折叠边框模型。

## 决策

### 规范化

- `colgroup`、`col` 进入标签白名单；`col` 为 void 元素，不收子节点。
- 属性清洗：`colgroup` 允许 `span`，`col` 允许 `span`、`width`。`span` 与 `colspan` 同规则清洗到 1..1000（`table.span.invalid` / `table.span.clamped`）；`width` 只接受正数或正百分比，其余移除并报 `table.col.width.invalid`。
- 结构约束：`colgroup/col` 只在 `table` 内有意义。HTML5 解析器本就会把表外的声明丢弃（与浏览器一致），规范化器保留防御性守卫：表外的 `colgroup/col` 丢弃并报 `html.table.col.unplaced`，colgroup 的非 `col` 子元素丢弃并报 `html.table.colgroup.content.unplaced`——这样未来其他解析适配层即使不做 foster parenting，内容也不会静默消失。
- 位置容忍：CSS 只允许列声明出现在首个行之前，但引擎无论 `colgroup/col` 在 table 子元素中的先后都收集（对受控内容无害且实现简单；偏差记录在案）。
- colgroup 语义：没有 `col` 子元素时按自身 `span` 声明占位轨道；有 `col` 子元素时 `span` 被忽略（HTML 行为）。

### 列宽语义

- 轨道数 = max(所有 col/colgroup span 之和, 行槽位网格列数)；行里超出的单元格照常生成隐式 auto 列。
- col px 宽（CSS `width` px/em 或 `width` 属性）：该列 min=max=声明值（固定列），不参与比例分配。collapse 模型下声明值按边框中心线距离解释，分配时扣除两侧半边框记入内容宽。
- col 百分比宽（CSS `width: N%` 或 `width="N%"`）：相对解析后的表内容宽的期望值。分配顺序：先落固定列与百分比目标，auto 列用剩余预算走既有 min/max 三分支；最后把百分比列按比例伸缩到"表预算 − 固定列 − auto 列"的剩余空间——收缩应对固定列单独溢出预算的情形，拉伸保证没有 auto 列时指定表宽仍被填满。
- 无 width 的 col/colgroup：纯轨道占位，列保持 auto（不改变现有分配）。
- 跨列单元格：平摊需求先减去跨到的固定列已提供的宽，剩余只摊给跨到的非固定列（auto 与百分比列）；固定列不接收平摊。固定列已足够时单元格照常溢出（沿用现有行为）。
- 带列轨道且指定宽度的 collapse 表：列宽总和 = 指定宽度（外边框中心线之间的距离），表盒 = 列和 + 外侧半边框。这与 Chrome 一致（实测 `width: 200px`、2px/4px 外边框渲染 203px 盒宽）。无轨道表保持 ADR 0012 的整格语义（预算扣除全部边框），避免回归既有测试。
- 跨列单元格的盒宽改为按 `columnWidths`（中心线距离）切片求和。这修正了原实现在 collapse 模型下跨列时少算内部半边框的偏差：`table_basic` 的 colspan 单元格与 Chrome 的宽度差从约 1px 收敛到约 0.01px。

### 一致性门禁

- 新增 `table_cols` 案例：caption + 两组 colgroup（px 固定列、25% 列、`span=2` 占位）+ 数据行 + 一个 colspan 单元格；manifest 记 `geometry: true`（不加像素基线）。
- 案例刻意让多数列由 col px 固定、内容不触发压缩，使两引擎几何高度确定；保留一个 auto 列覆盖剩余宽分配路径。
- Chrome 参考生成后逐元素 diff 审查：全部单元格 left/width 偏差 ≤ 0.02px；表盒与 caption 宽度差 −1.00px（Chrome 盒为 361，超出视口宽 1px；Weft 把表盒钳制在视口内，单元格几何不受影响）。

## 与浏览器的已知偏差

1. 百分比列的基数取解析后的表内容宽，浏览器内部算法在收缩/挤压场景更复杂；案例设计避开了这些退化场景，自由场景可差数像素。
2. 表外 `colgroup/col` 依赖 HTML5 解析器丢弃；规范化器的防御性诊断在 package:html 路径下不可达（解析器先行处理）。
3. 无列轨道的指定宽度 collapse 表仍保持 ADR 0012 的整格语义，与 Chrome 可差外侧半边框的宽度。
4. 列声明本身不产生盒子（无 `data-geo` 标注），col 背景等列样式不在支持子集内。

## 后果

- 受控内容可以用 `colgroup/col` 固定列宽，几何与 Chrome 对齐到亚像素；`table_cols` 案例接入通用几何门禁，零测试代码。
- 带列轨道的表格分配路径新增"固定列 → 百分比目标 → auto 列"的顺序约束；后续列宽精度工作（如浏览器级 auto 分配）必须复用同一轨道收集入口 `_collectColumnTracks`，不得绕过 `layoutTable`。
- 规范化白名单、`browser_compat.css`（col 在 Chrome 有 UA 默认，无需补充声明）与既有 17 项表格测试全部保持原样。
