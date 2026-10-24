# ADR 0010：实现 CSS 兼容的 margin 折叠与半行距

- 状态：已接受
- 日期：2026-10-25

## 背景

像素对照发现两个独立问题：

1. 仅对相邻兄弟使用 `max()` 近似 margin 折叠，父级的首尾子元素 margin 被计入父级盒高，导致带背景或边框的容器盒子偏大、文档高度偏差。
2. Flutter `TextStyle.height` 默认按比例分配行高余量（proportional leading），而 CSS 使用上下均分的半行距（half-leading），使字形在行盒内向下偏移约 1–2px。

## 决策

### margin 折叠

布局前先计算块级元素的外边距，再放置边框盒：

- `outerMarginTop/outerMarginBottom` 沿首/末块级子元素链传播，遇到边框、padding、`hr` 或行内内容即停止。
- 折叠规则为“最大正值 + 最小负值”，相邻 margin 不相加。
- 父级无上/下边框和 padding 时，首/末子元素的 margin 折叠到父级外部，父级背景盒不覆盖该区域。
- 无边框、padding 和可见内容的块视为自折叠块，其上下 margin 合并并穿透，不产生盒高。
- 行内内容阻断相邻 margin 折叠；空文本节点和空白 inline 不阻断。

### 行高

`WeftComputedStyle.toTextStyle` 显式设置 `leadingDistribution: TextLeadingDistribution.even`，与 CSS 半行距一致。

## 后果

固定字体下 `body`、`h1` 和首个段落的浏览器几何完全一致（21.44 / 21.44 / 82.88），后续块累计偏差小于 0.2px。`box_model` 跨引擎差异从 1.064% 降至 0.920%，`pixel_basic` 从 7.260% 降至 5.973%。

已知边界：

- 首个/末个空块参与父级外边距链时按普通流内空间处理，父级背景盒可能比 CSS 多覆盖该空块 margin 区域，但后续内容绝对位置不变。
- 百分比 margin、`auto` margin、根元素特殊折叠规则和跨 Float/表格格式化上下文的折叠尚未实现。

新增布局能力时，必须复用 `outerMarginTop/outerMarginBottom` 和自折叠判定，禁止在子布局中再次累加已经折叠到父级外部的 margin。
