# ADR 0021：块级盒模型补齐——显式高度、百分比宽度与水平 auto margin

- 状态：已接受
- 日期：2026-10-25

## 背景

ADR 0009 把块级盒宽解析集中在布局层，但明确留下三个缺口：`height`、百分比宽度和 auto margin 均未实现。块级高度恒为内容驱动，`width: 50%` 被解析器当作 null 丢弃（仅 ADR 0018 的图片消费 `widthPercent`），`margin-left/right: auto` 经 `_length` 解析失败后静默归零。CMS 内容（分隔占位、居中卡片、等高区块）需要这三项基础能力。

字段层面无需新增解析：ADR 0018 已为 `WeftComputedStyle` 引入 `height/widthPercent/heightPercent` 和 `_percentage` 解析。解析器保证 `width` 与 `widthPercent` 互斥（`width: 50%` 时 `_length` 返回 null、`_percentage` 返回 50），块级可直接复用。

## 决策

### 显式 height

- `height` 非 auto（px/em/rem）时，块级边框盒高 = box-sizing 换算后的显式高：`content-box` 加上垂直 padding 与 border，`border-box` 直接使用声明值，与 ADR 0009 的宽度换算完全对称。
- **溢出照绘（与浏览器的偏差）**：内容超出显式高度时既不裁剪也不撑开盒子，文字绘制命令照常越过盒子底边。引擎没有 overflow 裁剪路径，文档注释与本 ADR 明确记录该行为。
- **百分比 height 按 auto**：文档流中父高不定，无法解析百分比；与 ADR 0018 对图片 height 百分比的决定一致。`heightPercent` 不参与块级布局，也不阻止 margin 穿透。
- **margin 折叠交互**（CSS 2.1 §8.3.1）：
  - `_isSelfCollapsing` 对 `height` 非 auto 的块返回 false——collapse-through 要求 height:auto。空块 + 显式高度产生真实盒高。
  - `outerMarginBottom` 在链上遇到显式高度的盒子即停止（末子元素的下 margin 不再穿出）；`outerMarginTop` 不受影响（CSS 顶边父子折叠没有 height 条件）。
  - 显式高度块与相邻兄弟的 margin 折叠仍按普通块参与。
- `hr`/`table` 的既有排除保持；`hr` 的固定 1px 内容高同样可被显式 height 覆盖。

### 百分比宽度

- `widthPercent != null` 时 `boxWidth = 包含块 content 宽 × percent/100`，再按 box-sizing 换算，然后走既有 min/max-width 钳制与可用宽 clamp 链。`width` 与 `widthPercent` 同时存在时后者胜（解析器实际保证只有一个非空）。
- 百分比相对**包含块 content 宽**（pre-margin），不是减去自身 margin 后的可用宽——CSS 百分比相对包含块、margin 在百分比之外。`layoutBlock` 把 pre-margin 宽度作为新参数 `containingWidth` 传入 `_resolveBoxWidth`；表格网格对该函数的调用点在显式 `width` 分支内，不传该参数，百分比按 auto 保持原状。
- 循环百分比（无穷宽测量）按 auto 处理，与 ADR 0018 图片固有测量的先例一致。
- `min-width`/`max-width` 的百分比值**不做**（仍只解析长度）。

### 水平 auto margin

- `WeftComputedStyle` 新增 `marginLeftAuto/marginRightAuto`（bool，默认 false）。解析层：`margin` 简写展开与单边声明均认 `auto`；命中时数值 margin 置 0 并置位 flag，层叠语义与既有 margin 一致（每条长手属性只有胜出声明参与）。
- **垂直 auto margin 按 0**：解析层直接置 0 并注释说明，不引入 flag 字段——块级文档流没有可分配的垂直空间。
- **生效点在 `layoutBlock`**：算出 boxWidth 后，若任一水平 flag 置位，`slack = 包含块宽 − boxWidth − 非自动水平 margin 之和`（auto 侧数值已为 0，直接用解析值求和即可）；slack < 0 时 auto 按 0，双边 auto 各得 slack/2，单边 auto 得全部。`boxX` 改用分配后的有效左边距。由于既有宽度解析把 boxWidth 钳制在减 margin 后的可用宽内，slack 经证明恒 ≥ 0，负值分支按规范保留为防御。
- auto 宽度块填满行宽、slack 恒为 0，auto margin 自然无效，无需按宽度是否 auto 分支。
- **仅块级自身盒生效**：`outerMarginTop/Bottom` 与折叠链中 auto 按 0 参与（数值 margin 已为 0）。img（块级替换盒与浮动路径直接读数值 margin）、表格（`table_layout` 自行定位）的 auto margin 按 0——记录为与浏览器的偏差，维持 ADR 0018 现状。表格单元格经 `_cellLayoutStyle` 合成样式构造，flag 缺省 false，不受影响。

## 后果

- 三个特性只触及 `layoutBlock/_resolveBoxWidth` 与样式解析/计算样式；`WeftTextIndex`、表格与浮动布局消费的 `layoutBlock` 结果结构不变。
- `conformance/` 三项像素黄金与 `float_image`/`table_basic` 几何基线零影响（语料无块级 height/百分比宽/auto margin），全部原样通过。
- 新增 `box_model_expansion_test.dart` 覆盖：height 的 px/em/rem、两种 box-sizing、溢出照绘、阻止自垮塌、与折叠链交互；百分比宽的包含块基准、margin 并存、min/max 钳制、嵌套复合；auto margin 的双边/单边/负 margin 补偿/auto 宽无效/与 text-align 无关；hr/table/img 不受影响；浮动旁显式高度块。
- 已知边界：溢出照绘不裁剪；百分比 height 与百分比 min/max-width 未支持；img 与表格的 auto margin 按 0；显式高度块内溢出内容的末子 margin 视觉上消失在盒底之外（不影响后续块位置）。
- 后续扩展点：`overflow` 裁剪、百分比 min/max-width、替换内容与表格的 auto margin 可在 `WeftComputedStyle` flag 与各自布局路径上渐进补齐。
