# ADR 0038：Flutter 3.35.5 兼容基线

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0030 使用 Flutter 的 `SemanticsRole.list/listItem/table/row/cell/columnHeader` 构建真正嵌套的列表与表格语义。该 API 由 Flutter 3.35.5 提供（ADR 0026 已记录同一事实）；`SemanticsConfiguration.headingLevel` 则自 Flutter 3.24 起可用。

所有 Flutter 依赖包和示例此前仍声明 `flutter: ">=3.22.0"`。在 Flutter 3.22–3.34 上，`pub` 可以解析依赖，但编译 `weft_engine` 时会因缺少 `SemanticsRole` 失败。也就是说，0.5/0.6 等包含 ADR 0030 的历史版本从未真正支持过 3.22；元数据与实际编译下限不一致。

C0 的目标不是改变运行时行为，而是把真实下限写入包元数据和发布文档，并让后续语义工作（headingLevel/live region）可以直接使用 3.35 API，不再受错误的下限约束。

## 决策

1. **统一 Flutter 下限。** `weft`、`weft_engine`、`weft_quickjs` 及三个示例声明 `flutter: ">=3.35.5"`；`weft_quickjs` 虽不直接导入 Flutter，但作为 ffiPlugin 参与宿主平台构建，跟随同一基线。
2. **纯 Dart 包不变。** `weft_document`、`weft_runtime_api`、`weft_capabilities`、`weft_runtime_fake`、`weft_runtime_contract` 继续保持 Dart `>=3.5.0` 且不引入 Flutter 依赖。
3. **统一版本。** 所有引擎包和示例按既有发布策略一起升到 `0.7.0-dev.1`；`CHANGELOG` 标明这是兼容性基线变更，运行时、布局、快照格式、bridge 协议和像素基线均不变。
4. **文档与 CI 对齐。** README、release-runbook、release.md、handoff 和 architecture 的 ADR 索引记录 3.35.5 基线；CI 继续固定 Flutter 3.35.5。
5. **不回退 `SemanticsRole`。** 保留 ADR 0030 的嵌套 list/table 角色；不为了虚假的 3.22 兼容性删除已交付的无障碍结构。

## 备选与拒绝原因

- **删除 `SemanticsRole`，恢复扁平语义以支持 3.22**：会回退 ADR 0030 的列表/表格父子角色，破坏 Web 与原生语义结构；拒绝。
- **条件导入或运行时探测**：缺少 API 是编译期问题，Dart 条件导入无法按 Flutter 版本切换；维护双包/双分支的成本远高于升级下限；拒绝。
- **继续声明 3.22**：宿主能通过依赖解析却在编译期失败，是最坏的失败形式；拒绝。
- **只把下限设为 3.24**：`headingLevel` 可用，但 `SemanticsRole` 仍不可用；拒绝。

## 后果

- Flutter 3.22–3.34 的宿主必须先升级 Flutter，不能通过回退到包含 ADR 0030 的 0.5/0.6 版本规避；这些版本在实际编译时同样要求 3.35.5。
- 0.7.0-dev.1 没有新增运行时测试；现有 491 项测试、3 项像素黄金与文档覆盖门禁保持不变。
- 后续语义切片（headingLevel、live region、有序列表起始序号）可以直接使用 Flutter 3.35 的语义 API，不再需要额外的版本门槛。
- 本次只修正元数据和发布基线，不改变任何渲染、选择、懒布局或 Runtime 行为。
