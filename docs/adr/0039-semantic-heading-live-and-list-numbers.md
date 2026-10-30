# ADR 0039：语义补全——headingLevel、live region 与有序列表序号

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0026 已经记录标题的 header flag，但因为最低 Flutter 版本的限制，暂缓了 `SemanticsConfiguration.headingLevel`；ADR 0030 也只补了 list/table 的嵌套角色，没有给有序列表真正的起始序号。C0（ADR 0038）把 Flutter 基线提升到 3.35.5 后，`headingLevel` 和 `SemanticsRole` 都可以直接使用，语义层不再需要为版本让步。

同时，规范化器此前没有保留 `aria-live`，标题、表格与列表之外的动态内容无法告诉辅助技术“这块内容会更新”。`ol start` 与 `li value` 也被属性白名单丢弃，视觉标记和语义 marker 只能从 1 开始。

本 ADR 只补这三类语义与内容保真能力，不改变布局窗口、绘制、懒布局预算或 Runtime。

## 决策

### 1. 标题层级

- `h1..h6` 的文本、链接、强调和图片 alt 片段继续继承原有的 `headingLevel` 与 `isHeader`；assemble 时对 `headingLevel > 0` 的片段设置 `SemanticsConfiguration.headingLevel`。
- 保留 `isHeader` 作为跨平台兼容标志：不支持 headingLevel 的桥接仍能读出 header；`<th>` 仍只设 header flag，不获得标题层级。
- 不为标题额外创建容器节点，标题与行内子节点仍按阅读顺序合并/拆分。

### 2. live region

- 规范化器全局保留 `aria-live`，只接受 `off`、`polite`、`assertive`（大小写不敏感）；其他值丢弃并产出 `aria.live.invalid` 警告。
- 语义遍历维护三态继承：`polite/assertive` 置为 live，`off` 显式关闭，缺省继承祖先；`body` 上的属性同样生效。
- 不在 live 子树内创建额外的语义容器。文本、链接、图片 alt 与自定义标签的叶子片段各自带 `liveRegion`；相邻片段必须 live 状态相同才合并。
- Flutter 只提供布尔 `liveRegion`，因此 `polite` 与 `assertive` 的播报优先级不保留；需要更细粒度时由宿主在语义层之外处理。
- 不实现 `aria-atomic`、`role="status"` 或完整 ARIA role 映射；也不在引擎内播放通知或维护临时消息队列。

### 3. 有序列表序号

- 规范化器保留 `ol[start]` 与 `li[value]` 的整数；无效值丢弃并分别产出 `list.start.invalid`、`list.value.invalid`。
- 布局的列表编号与语义 marker 编号使用同一 `start`/`value` 规则：`start` 缺省为 1，`li value` 重置当前项及后续项的计数；嵌套列表各自独立；`ul` 仍使用项目符号，`li value` 在 `ul` 内不参与编号，`list-style-type` 仍按既有行为决定 marker 形态。
- 列表计数只影响 marker（视觉与语义），不进入正文的逻辑文本、选区或复制文本；现有 `list-style-type` 行为不变。

## 备选与拒绝原因

- **为 live region 创建专用容器节点**：会引入额外的无标签节点，和 ADR 0030 的严格 role 父子校验叠加后更难验证；对常见的一段状态文本也没有收益。叶子 flag 更直接，且不改变现有阅读顺序。
- **保留 polite/assertive 差异**：Flutter API 只有布尔值；模拟差异需要自定义 action/hint，辅助技术不会按 live region 播报，反而制造伪语义。
- **用 `aria-atomic` 或完整 ARIA 角色推断 live 范围**：需要一套 ARIA 状态机，超出当前受控子集；先只支持显式的 `aria-live` 标记。
- **全量 CSS list counter / 任意 `list-style-type`**：当前布局只渲染 disc/decimal/none，完整 counter 语义不属于本切片；`start/value` 已覆盖 CMS 的常见起始序号需求。
- **只改视觉 marker，不改进程语义**：会让读屏朗读与视觉序号不一致，违反单一语义来源的约束；两者必须共用同一规则。

## 后果

- 新增测试：规范化器 1 项、布局 1 项、engine 语义 2 项；总数由 491 增至 495（以 `tool/verify.dart` 输出为准）。像素黄金不应变化；未使用新属性的文档树与语义树保持原样。
- 语义节点数量不因 live region 增加；同一段落内的连续文本仍按原有规则合并，只是多携带一个布尔标志。
- live region 的播报粒度由文档作者决定：一个 aria-live 子树包含多个叶子时，辅助技术可能分别播报这些叶子；宿主应把属性放在窄范围的状态容器上。
- 设备端 TalkBack/Web 的实际播报仍依赖平台桥接；本切片用 `SemanticsOwner` 验证 `headingLevel`、`liveRegion` 标志与 marker 编号，不宣称已完成真机读屏验收。
