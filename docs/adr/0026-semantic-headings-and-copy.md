# ADR 0026：标题 header 语义与选区复制动作

- 状态：已接受
- 日期：2026-10-27

> 版本基线后续更新：ADR 0038 已将最低 Flutter 提高到 3.35.5，并纠正了 3.22 元数据与实际 `SemanticsRole` 依赖不符的问题；本 ADR 中“最低支持 Flutter 3.22”的表述仅反映当时决策。

## 背景

ADR 0024 建立了单表面的阅读顺序语义，但标题没有 header 标记，辅助技术也无法直接复制当前选区。Flutter 3.35.5 新增了 `SemanticsRole.list/table` 与 `headingLevel`，但本包最低支持 Flutter 3.22；这些 role 在当前原生桥接中主要影响 Web，且 table/list 要求严格直接父子节点。本轮选择跨平台收益明确、不会破坏现有扁平语义树的增强。

## 决策

### 标题 header

- 语义片段记录 `headingLevel`（0 表示非标题）。`h1..h6` 的文本、链接、强调和图片 alt 片段继承层级；相邻文本只有 heading 层级相同才合并。
- assemble 时对标题片段设置 `isHeader=true`。Android/iOS 分别映射 heading trait / header flag，Web 也识别该 flag。
- 暂不设置 `headingLevel` 属性：当前最低 Flutter 版本不能保证该 API 可用。升级最低版本后可在同一片段上追加，不改变节点身份。
- 标题内被链接/换行拆成多个片段时各自带 header flag；这是扁平模型的可接受限制。

### 选区复制

- `WeftSurface`/RenderWeftSurface 增加独立的 `onSemanticsCopy(String text)` 回调。仅当当前存在非折叠选区且宿主提供回调时，选区语义节点注册 `SemanticsAction.copy`。
- 引擎仍不导入 Clipboard。`WeftView` 将语义 action 与复制按钮接到同一个文本复制方法，复制后保留选区；standalone Surface 不提供回调时继续保持无 copy action。
- 不设置 `textField`、`textSelection` 或 `setSelection`；Weft 仍是静态文档选区，不是可编辑文本字段。
- 独立选区节点继续位于根节点直接子级，不把 selected state 扩散到列表/表格叶子，避免重复朗读。

### 暂缓角色

- list/table/listItem/row/cell 需要真正嵌套的 SemanticsNode 层级；扁平 fragment 不能只加 role。该改造需要容器 fragment、父子 rect 坐标、局部分组 sortKey，并避开 Flutter debug 的严格父子 role 校验。
- `SemanticsRole` 在当前 Flutter Android/iOS 桥接中未被消费，原生端收益不明确；先交付 header/copy 等跨平台行为。
- 语言/RTL、live region 同样留到专门切片。

## 理由

- `isHeader` 与 `onCopy` 在 Android、iOS 和 Web 都有明确桥接，且不改变现有阅读顺序、链接动作或节点 key。
- copy 策略继续留在 weft 层，符合引擎不接触剪贴板的既有边界；回调模式与 `onSemanticsLinkTap` 一致。
- 不提前承诺 role 和 headingLevel，避免提高 Flutter 最低版本或引入跨平台不可见的能力声明。

## 后果

- 新增 2 项 engine 语义测试与 1 项 WeftView clipboard 测试；weft_engine 常规测试 218 项、weft 31 项。
- 现有文本/链接/图片/选区/流式节点身份测试保持不变；像素与几何基线不受影响。
- 限制：标题被内联元素拆分时会得到多个 header 节点；没有 headingLevel、list/table role、语言、live region 或可编辑 setSelection。辅助技术仍通过现有复制按钮与选区 copy action 两种入口复制文本。
