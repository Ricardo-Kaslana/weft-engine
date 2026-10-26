# ADR 0028：表头语义与列表标记朗读

- 状态：已接受
- 日期：2026-10-27

## 背景

ADR 0026 已为 h1..h6 提供 header flag 与选区 copy，但表格 `<th>` 仍被读成普通文本，列表项没有编号或项目符号提示。Flutter 3.35.5 的 list/table SemanticsRole 主要影响 Web，要求严格嵌套节点；当前扁平语义树无法直接使用，因此先增加跨平台可用的朗读信息。

## 决策

### 表头

- 语义片段增加独立 `isHeader`。h1..h6 和 th 子树都传播该标记；`th` 不伪造 headingLevel。
- assemble 使用片段的 isHeader 设置 `SemanticsConfiguration.isHeader`，不再仅从 headingLevel 推断。
- 相邻文本 merge 要求 isHeader 与 headingLevel 相同，避免表头、标题和普通段落错误合并。

### 列表标记

- 遍历 ul/ol 的直接 li 时生成一次性朗读前缀：无序 `• `，有序 `${index+1}. `；嵌套列表独立计数，不使用非 li 节点编号。
- li 子树中第一个实际生成的非空文本、链接或图片 alt fragment 获得前缀，随后清除；空装饰图片不会消耗前缀。
- marker 只写入 `_WeftSemanticFragment.label`，不进入 `WeftTextIndex`、selectionText、复制值、布局或绘制。
- 不创建独立 marker SemanticsNode，不改变现有节点 key、阅读顺序和流式身份。
- 不设置 SemanticsRole.list/table；严格嵌套角色留给后续专门设计。

## 理由

- header flag 和朗读标记在 Android/iOS/Web 都有明确收益，且不需要提高 Flutter 最低版本或重构节点层级。
- marker 放到首个语义片段可避免额外节点和重复朗读，也保证复制文本保持纯内容。
- table/list role 当前原生桥接消费有限，且 caption/thead/空 cell 等边界需要完整的嵌套语义模型，不应与轻量朗读增强混合交付。

## 后果

- 新增 1 项 engine 语义测试与 1 项 WeftView 语义测试；weft_engine 常规测试 220 项、weft 35 项。
- 现有标题、链接、图片、选区 copy、流式节点身份与 ExcludeSemantics 测试通过；像素与几何不变。
- 限制：有序列表编号从 1 开始，不读取 CSS 起始序号/样式；列表标记没有原生 list/listItem 角色；表格没有 table/row/cell 角色或行列导航；多层链接拆分时 marker 只出现在第一个可朗读片段。
