# ADR 0040：ARIA 基础——role 映射、aria-hidden/label 与 aria-atomic 整组播报

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0039 交付了 `headingLevel`、显式 `aria-live` 与有序列表序号，并明确把 `aria-atomic`、`role="status"` 和完整 ARIA role 映射列为后续。当时规范化器只保留 `aria-live` 一个 aria 属性，其余 aria-*（含 `aria-label`）在标准标签上被静默丢弃；而引擎的自定义标签路径已经在读 `aria-label`（`WeftTagLayout` 的标签回退链），形成"引擎在读、规范化器在丢"的接缝错位——只有自定义标签上的 `aria-label` 能存活。

本 ADR 补上 ARIA 的基础子集：`role`（保守映射）、`aria-hidden`、`aria-atomic` 与标准标签上的 `aria-label`。不改变布局、绘制、懒布局预算或 Runtime；像素黄金不变。

## 决策

### 1. role 映射（保守子集）

Flutter 3.35.5 的 `_DebugSemanticsRoleChecks` 对语义 role 有严格校验，映射表按"能否保证通过校验"取舍：

| HTML role | 语义行为 |
|---|---|
| `button` | 叶子片段携带 `isButton` flag 并向下游传播；无 tap action（引擎不执行脚本，激活行为归宿主） |
| `link`（非 `<a>`） | `isLink` flag，无 tap（无 href 契约） |
| `img` | 子树折叠为单个 `isImage` 叶子，名称取 `aria-label`，否则取扁平化文本 |
| `heading` | `isHeader` + `headingLevel`（非 h1..h6 标签按 ARIA 默认 2） |
| `dialog` / `alertdialog` | `SemanticsRole.dialog`/`alertDialog` 容器（Flutter 校验为 `_noCheckRequired`） |
| `alert` / `status` | **不映射 role 本身**，改为隐式 `aria-live`（assertive/polite 在 Flutter 布尔模型下等价）+ 隐式 `aria-atomic=true`；显式 `aria-live="off"` 仍然胜出 |
| `presentation` / `none` | 抑制元素自身派生语义：img 跳过；h1..h6/th 抑制 header/headingLevel；ul/ol 丢弃 list/listItem 容器与 marker；table 丢弃 table/row/cell 容器；`<a>` 抑制 link flag/tap。内容照常朗读 |
| 其余（landmark、tab/menu/radio 族、tooltip 等） | 丢弃并产出 `aria.role.unsupported`（info）诊断 |

- 显式 role 覆盖隐式语义：`<a role="button">` 不再绑定 link region（无 link flag、无语义 tap）。
- landmark（main/navigation 等）被拒：Flutter 要求不嵌套于其他 landmark 且重复时必须有唯一 label，受控内容无法保证，debug 断言会炸。
- tab/tabBar/menu/radio 族被拒：需要 selected/checked 状态或 tap action 等不变量，引擎无法从静态内容满足。
- `tooltip`/`progressBar`/`comboBox` 等被拒：Flutter 对这些 role 的校验函数尚未实现（debug 下直接报错）。
- `role` 大小写不敏感；不支持或空值丢弃，不影响渲染。

### 2. aria-hidden

- 全局属性，仅 `true`（大小写不敏感）生效：该元素子树从语义树中整体移除，视觉与复制文本不受影响。
- `false`/`undefined` 是合法值但无语义，静默丢弃；其他值丢弃并产出 `aria.hidden.invalid` 警告。
- `body` 上的 `aria-hidden="true"` 同样生效（语义树为空）。

### 3. aria-label

- 全局属性，修剪后超过 1024 字符截断（该截断分支此前因白名单未放行而是死代码，现在生效）。
- **img**：`aria-label` 优先于 `alt`（ARIA 名称计算顺序）。
- **其他元素**（排除 html/body/table/tr/td/th/thead/tbody/tfoot/col/colgroup）：子树折叠为单个叶子片段，label 为 `aria-label`，矩形为子树文本 rect 与已解析图片 destination 的并集；`<a aria-label>` 保留 link flag 与语义 tap。无可见几何或名称为空时不产出片段。
- 结构性标签不折叠：折叠会破坏 table/row/cell 的严格父子校验。
- 自定义标签路径维持现状（renderer 的 `semanticsLabel` → 元素 `aria-label` → 标签名回退链不变）；custom tag 的属性白名单旁路本就放行 aria-*，其语义由 renderer 域决定。

### 4. aria-atomic 整组播报

- 在 live region 上下文内（显式 `aria-live=polite/assertive`，或 `role=alert`/`status` 隐式）且 `aria-atomic=true` 时，live 子树折叠为**单个** `liveRegion` 叶子，替代 C1 的逐叶子播报；这是对 ADR 0039 已记录限制（"可能逐叶子播报"）的修复。
- live 上下文之外的 `aria-atomic=true` 无效果（与 ARIA 语义一致，无诊断）。
- 结构性标签（table 族）上的 atomic 回退为逐叶子行为，原因同上。
- 折叠片段不带列表 marker 前缀；嵌套 `aria-live=off`/`aria-hidden` 内容随之被吞（折叠即整体）。

### 5. 合并与节点模型

- `_WeftSemanticFragment` 新增 `isButton`/`isLinkFlag`；`canMerge` 要求两者相等，相邻同格式文本不因新 flag 误合并。
- 折叠片段的 key 命名空间为 `aria:<nodeId>`，与 text/link/image/tag 键隔离；globalStart/End 为 null，天然不参与文本合并。
- buildNode 叶子分支新增 `isButton` 输出，`isLink` 改为 `link != null || isLinkFlag`。

## 备选与拒绝原因

- **landmark role 直映射**：嵌套校验 + 唯一 label 要求与受控内容冲突；CMS 文章外层由宿主控制，宿主可以自加 landmark，引擎不越权。
- **`role=alert/status` 映射为 `SemanticsRole.alert/status`**：Flutter 明确拒绝"该 role + liveRegion flag"组合，而 live 播报正是这两个 role 的核心价值；隐式 aria-live + atomic 用既有机制达成同一播报效果且零校验风险。
- **aria-label 挂到容器节点的 label 上**：ADR 0030 确立容器不带 label 以满足严格 role 校验；给容器加 label 需要重新验证全部容器路径。折叠为带名叶子是等价的播报结果。
- **presentation 表格同步抑制后代 th 的 header flag**：需要贯穿递归的抑制标志且会误伤单元格内的真实标题；保留 header flag 是记录在案的小偏差，主要收益（去掉 table/row/cell 导航结构）已达成。
- **完整 ARIA 名称计算（aria-labelledby、aria-describedby）**：超出受控子集；`aria-label` 覆盖 CMS 场景的绝大多数命名需求。

## 后果

- 新增测试：规范化器 2 项（属性保留/校验 + aria-label 截断）、engine 语义 10 项、lazy→full 升级原因 1 项（补上 `'semantics'` reason 的既有覆盖空档）；总数 495 → 508（weft_engine 258→269、weft_document 78→80）。
- 21 个规范化一致性向量均不含 aria-*/role 输入，输出逐字节不变，无需重新生成。
- `role`/`aria-hidden`/`aria-atomic`/`aria-label` 进入全局属性白名单；使用这些属性的文档规范化输出会包含它们（此前被丢弃），语义树相应变化，布局/绘制/像素黄金不变。
- `role=button`/`link` 只播报角色不产生激活动作——宿主需要可激活控件时应使用链接或自定义标签的 tap 回调，引擎不伪造伪动作。
- presentation 表格后代 th 的 header flag 保留（记录在案的简化）；嵌套在折叠子树里的内容不进入语义树（含 aria-label、role=img、atomic 三类折叠）。
- 真机 TalkBack/Web 读屏的实际播报仍待按 device-matrix 清单抽查；本切片继续以 `SemanticsOwner` 层验证为准。
