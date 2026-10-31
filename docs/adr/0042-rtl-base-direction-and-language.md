# ADR 0042：RTL 基础方向与语言属性

- 状态：已接受
- 日期：2026-10-31

## 背景

`dir`/`lang` 此前不在属性白名单，规范化器静默丢弃；布局 4 处 TextPainter 硬编码 `TextDirection.ltr` 与 `locale: Locale('zh')`，语义叶子的 textDirection 固定 ltr，caret 取字形盒左缘，列表 marker 只会放在内容盒左侧。本切片让块级基础方向生效（属性 + CSS `direction`），并把 `lang` 接到 TextPainter 的 locale 上。**行内双向重排（BiDi）交给 SkParagraph 的标准实现，引擎不做额外规则。**

探索确认的关键事实：几何框架方向中性（等宽 painter + 平移 + textAlign，行槽/排除区复用无碍）；`textAlign.start` 是既有默认且 start/end 随 painter 方向解析；`getBoxesForSelection`/`getPositionForOffset` 方向无关；conformance 中无任何 dir/lang 输入（零向量/黄金回归压力）；属性选择器 `[dir=rtl]` 被样式表解析器丢弃（supported-subset §"属性选择器=阶段 1 后续"），走 resolver 内建分支是唯一低成本路径。

## 决策

### 1. 方向来源与优先级

- 规范化器全局保留 `dir`（`rtl`/`ltr`/`auto`，大小写不敏感；其他值丢弃并产出 `html.dir.invalid` 警告）与 `lang`（任意值 1024 截断保留，title 模式）。
- 样式层 `WeftComputedStyle` 新增继承字段 `direction`（Flutter `TextDirection`）与 `lang`。元素 `dir` 属性在 `WeftStyleResolver.resolve` 开头应用（先于 tag 默认，使列表缩进镜像可读到方向）；CSS `direction: ltr|rtl` 声明经层叠后覆盖属性映射（`auto` 不是合法 CSS 值）。
- `dir=auto` 用 first-strong 检测：扫描元素子树的文本，首个强方向字符判定（希伯来/阿拉伯及其呈现形式主区间 0590–08FF、FB1D–FDFF、FE70–FEFC → rtl；拉丁/希腊/西里尔/亚美尼亚/格鲁吉亚/CJK/谚文 → ltr；中性字符跳过；无强字符继承父方向）。这是裁剪过的主区间实现，不追求完整 Unicode BiDi 类表。

### 2. 布局行为

- 整段路径：TextPainter `textDirection` 取块方向。RTL 时 `layout(minWidth: width, maxWidth: width)` 展开到内容宽——实测 `TextWidthBasis.parent` 下 painter 会收缩到文本自然宽，不展开则 start 对齐没有可推的空间；LTR 保持 `layout(maxWidth)` 原样（零回归）。
- 逐行路径（Float 环绕）：probe 与行 painter 同方向；`_lineBreakEnd` 的行尾探测按方向取视觉远端（LTR 右缘 / RTL 左缘 0），断行推进与行数保持正确。
- 列表：UA 缩进镜像——浏览器默认是 `padding-inline-start`，RTL 时落到右侧（`paddingRight = 40` 替代 `paddingLeft`）；marker 绘制位置镜像到内容盒右缘外 8px，marker 字形保持 LTR 绘制（数字/圆点方向中性）。
- caret：`caretRectForAnchor` 改为贴锚点字形盒的行内首侧——RTL 取盒右缘，LTR 取盒左缘（从 run 所属 painter 的 textDirection 判定）。
- 选区把手 chrome、auto margin 过约束解析、盒级逻辑属性（物理 padding/margin 语义）不镜像。

### 3. lang → locale

- `lang` 经 BCP-47 简单解析（主语言 + 可选 script/region 子标签）传入 TextPainter `locale`，影响断行与字体回退。**缺省保持 `Locale('zh')`**——ADR 0016 的 CJK 禁则与全部既有布局在该默认下验收，改变默认等于隐性回归。
- lang 在块级生效（computed style 继承），不做逐 run 语言切换；自定义标签 painter 保持 ltr（renderer 域，后续可扩）。

### 4. 语义

- 语义叶子 `textDirection` 从块自己的文本绘制命令 painter 读取（marker 命令无 runs，不参与），visit 沿树传递；full 与 lazy 路径一致。粗粒度叶子（ADR 0041）无命令可用，保持 ltr。

## 备选与拒绝原因

- **属性选择器 `[dir=rtl]` + UA 样式表**：选择器解析器不支持属性选择器（整条规则丢弃并警告），扩展 `WeftSelectorPart` 超出本切片；resolver 内建分支等价且便宜。
- **RTL 时镜像 marker 数字字形**：数字与圆点在 RTL 列表中的视觉形态与 LTR 相同（Chrome 参考一致），只需位置镜像。
- **`dir=auto` 完整 BiDi 类表**：主区间已覆盖现实内容的 99%；完整表属 over-engineering，诊断不了的场景继承父方向是安全兜底。
- **改默认 locale 为 `Locale('und')`/系统 locale**：CJK 禁则（ADR 0016）与像素基线都在 zh 默认下验收；改变默认会使全部既有几何漂移。
- **盒级逻辑属性（margin/padding-inline 等）**：受控子集没有逻辑属性语法，物理语义不变；仅列表 UA 默认因浏览器的 padding-inline-start 语义而镜像。

## 后果

- 新增测试：规范化器 2 项、RTL 布局 7 项（对齐/auto/嵌套覆盖/locale/列表镜像/浮排断行/caret 边缘）、语义方向 1 项、Chrome 几何对比 1 项（`conformance/cases/rtl_paragraph.html` + `conformance/reference/rtl_paragraph.geometry.json`，10 个元素的方向边缘 ±2px 对齐 Chrome）；向量 21 → 22（新增 `synthetic_dir_and_lang`，既有 21 个零 diff）。总数 509 → 523（weft_document 80→84、weft_engine 269→279；以 `tool/verify.dart` 输出为准）。
- `rtl_paragraph` 在 manifest 中不开启泛化几何对比（`geometry: true`）：Chrome 对 RTL 列表的盒级几何（ol/li 的 getBoundingClientRect 受 UA `padding-inline-start` 影响的落位）与我们的镜像 padding 模型在盒左缘有未解释的偏差，而用户可见的文本对齐边缘完全一致；方向行为的强制门禁由专项测试的文本边缘对比承担，盒级差异记录在案。
- `dir`/`lang` 进入白名单：使用它们的文档规范化输出变化（此前被丢弃），布局相应改变；无 dir/lang 的文档行为逐字节不变（缺省 ltr + zh locale）。
- 已知限制：行内双向重排依赖 SkParagraph（不额外做中性字符行缘解析）；RTL 整段 painter 展开到内容宽后 bounds 覆盖全宽；粗语义叶子的 textDirection 恒为 ltr；`dir=auto` 无强字符时继承；CSS `direction` 覆盖 `dir` 属性时列表 UA 缩进不重新镜像（作者可用显式 padding 修正）。
- 真机 TalkBack 对 RTL 播报的验收不在本切片（无设备在线）。
