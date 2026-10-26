# ADR 0030：列表与表格的嵌套语义角色

- 状态：已接受
- 日期：2026-10-27

## 背景

ADR 0028 已提供列表标记和表头 header flag，但语义节点仍是扁平结构，没有 Flutter 的 list/listItem、table/row/cell 角色。Flutter 在 debug 下严格校验这些角色的直接父子关系，因此不能只给叶子节点加 role。

## 决策

### 片段 forest

- 语义叶子继续沿用现有文本/链接/图片/header/marker 字段与 key；额外记录其 list/table 容器路径。
- `ul/ol` 生成 `SemanticsRole.list`，直接 `li` 生成 `listItem`；嵌套列表逐层进入自己的 list/listItem。
- `table` 生成 `table`，`tr` 生成 `row`，`td` 生成 `cell`，`th` 生成 `columnHeader`；`thead/tbody/tfoot` 透明展开。
- `caption` 在 table 之前作为普通兄弟片段暴露，不进入 table 子树，避免破坏 table→row 直接父子规则。
- 空容器不会出现在 forest 中；列表 marker 仍只写首个朗读叶子，不增加重复节点。
- 容器 key 为 `role + NodeId`，跨流式快照保持稳定；容器不设置 label，避免与子内容重复朗读。

### 坐标与组装

- forest 的容器 rect 为子树 document-local union；转成 SemanticsNode 时子节点 rect 改为父级局部坐标。
- `showOnScreen` 和 `isHidden` 使用保存的 document-local 绝对 rect，不受嵌套局部坐标影响。
- assemble 递归构建节点；每层独立 OrdinalSortKey，复用现有 `_semanticsChildNodes` 缓存保持嵌套节点 id。
- 选区节点继续位于根级，不进入 list/table 子树；lazy 在 assemble 前仍升级 full。

## 理由

- 真正嵌套节点满足 Flutter debug 角色约束，并让 Web 语义正确表达列表与表格结构。
- `thead/tbody/tfoot` 透明和 caption 外置是满足严格父子关系的最小映射。
- 容器无 label、marker 叶子化的组合避免列表/表格被重复朗读。
- 继续使用 surface-local 几何与 selection/语义缓存，不触碰布局和绘制。

## 后果

- 新增 1 项 engine table-role 测试并在现有 list/table 测试中断言父子 role；weft_engine 222 项、weft 38 项。
- 原生 Android/iOS 对 role 的消费仍有限；header、marker 与单元格内容仍通过 label/flag 工作。
- 限制：不提供行列导航索引、表格 caption label、跨行列 span 语义或 live region；容器层级按 DOM 结构生成，与视觉布局顺序一致。
