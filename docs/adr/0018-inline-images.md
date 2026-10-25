# ADR 0018：行内图片基线混排与图片 CSS 宽高

- 状态：已接受
- 日期：2026-10-25

## 背景

此前已解析的 `<img>` 在 `_layoutChildren` 中无条件走块级替换盒或浮动路径；`display: inline` 被忽略，行内元素（`<a>`/`<b>` 等）内嵌的已解析图片被静默丢弃（只有未解析图片的 alt 文本参与行内排版）。同时 `_imageMetrics` 忽略 CSS `height`，`style_resolver` 的 `_length` 不解析 `%`，`width: 50%` 被当作 null 丢弃。选择模型（ADR 0013/0015）要求图片不贡献逻辑文本，行内图片也必须遵守。

## 决策

### 原子 run

- 行内图片是 `_InlineRun` 的原子变体：`text` 固定为单个 U+FFFC（OBJECT REPLACEMENT CHARACTER）并标记 `isAtom`，携带已解码 `ui.Image`、占位盒宽/盒高与图片内容宽/高。纯文本缓冲、link 范围、禁则调整与逐行切分的游标机制全部复用，无需为图片引入第二条数据通路。
- 游标语义：原子占 1 个 UTF-16 code unit。`runSpecs` 对原子只推进游标、不发出 `WeftTextPainterRun`，因此 `anchorAt`/`wordSelectionAt` 无法把原子解析为文本锚点，选区/复制永远跳过图片。`_linkRanges` 中原子不带 href，链接范围在原子处自然断开。
- 禁则无需特判：U+FFFC 不在任何行首/行尾禁则表内，含原子行按既有规则正常断行（有测试确认）。

### Placeholder 绘制

- 原子 run 在 span 树中生成自定义 `_ImagePlaceholderSpan extends PlaceholderSpan`。Flutter 的 `PlaceholderSpan` 是抽象类，框架唯一的实现 `WidgetSpan` 在 widgets 库中，会拖入无关依赖，故引擎自带最小实现（build/visitChildren/getSpanForPosition/codeUnitAt/compareTo）。
- 两条行内路径都要设置占位尺寸：整段路径（`buildLayout`）在 `layout()` 前对整段 painter 调用 `setPlaceholderDimensions`；逐行路径（`buildLines`）对探测 painter 与每个行 painter 分别设置其覆盖范围内原子的尺寸（范围内没有原子则不设）。占位宽度 = 盒宽、高度 = 盒高；`painter.inlinePlaceholderBoxes` 按顺序与原子 zip，得到图片的绘制位置，生成 `WeftImagePaintCommand`（图片画在内容矩形上，即占位盒按 border+padding 内缩后的区域）。
- 对齐：`PlaceholderAlignment.baseline` 默认，`baselineOffset` = 盒高（盒子底边落在 alphabetic 基线上）；`vertical-align: middle` 时用 `PlaceholderAlignment.middle`，`baselineOffset` = 盒高/2；基线统一 `TextBaseline.alphabetic`。占位符推送 `decoration: none` 的样式，避免链接下划线画进图片区域。
- 占位尺寸是逻辑像素，不随 `textScaler` 缩放（引擎 `addPlaceholder` 的 scale 由 span build 决定，本实现传 1），与浏览器"图片不随文字缩放"一致；行高仍随基线位置正确计算。

### 分发

- `img` 标签默认 `display: inline`（`applyTagDefaults`，与浏览器 UA 样式表一致）：无作者样式的图片以原子加入周围行框；`display: block` 显式退回块级替换盒。语料中的图片全部带 float 或块级样式，几何基线不受影响。
- `_layoutChildren` 中已解析 img：`float != none` → 浮动路径（不变）；`display == inline` → `inline.addImageAtom(...)`（不 flushInline）；其余 → 块级路径（不变）。
- `collectElement` 内嵌于行内元素的已解析非浮动 img 同样生成原子；未解析 img 仍走 alt 文本路径，嵌套浮动 img 保持"不参与布局"的现状。
- 配套修复：`_isInlineEmpty` 与 `_isSelfCollapsing` 把 img 视为非空（替换内容恒有高度）。此前 img 自身（无子节点）会被递归判定为"行内空"，导致只含图片的段落被当作自垮塌块整体跳过、图片不可见。

### vertical-align

- `WeftVerticalAlign` 服务表格单元格（ADR 0012，`baseline` 归并为 `middle`），且表格布局对其穷举 switch；为不改动表格语义与该文件，新增 `WeftInlineVerticalAlign { baseline, middle }` 供行内原子消费。CSS `vertical-align: baseline|middle` 参与层叠后写入两个模型；其他取值（top/bottom/长度/百分比）对原子退化为 baseline（CSS 中替换内容的默认值）。

### 尺寸

- `_imageMetrics` 新增：CSS `height` px 显式高度（width 为 auto 时按比例推导宽度，min/max-width 钳制下宽度变化时高度随比例同步缩放，保持比例不失真）；`WeftComputedStyle.widthPercent/heightPercent`（`style_resolver` 解析以 `%` 结尾的 width/height）。百分比宽相对包含块的 content 宽解析（在减去图片自身 margin 之前）；height 百分比因文档流中父高不定按 auto 处理；box-sizing 沿用既有语义。既有分支（width/height 属性、CSS px 宽、固有比例、min/max 钳制）行为逐字节保持。
- 固有测量路径（表格列宽测量）以无穷宽构造行内累积器，百分比按 auto 回退到固有尺寸（与 CSS 循环百分比的处理一致）；带 `height` 无宽的图片在该近似测量中仍按固有宽度计（既有近似的自然边界）。

### 逻辑文本索引

- 图片不贡献文本，原子只存在于行内 painter 文本中，逻辑索引与复制文本永远不含 U+FFFC。`WeftTextIndex` 按解析后的 display 断块界：默认 inline 的行内图片不打断前后文本（`<p>a<img>b</p>` 复制为 "ab"），`display: block` 的图片仍作为块界（复制为 "a\nb"），二者均与视觉一致。

## 与浏览器的已知偏差

1. 行内原子的 `margin` 不参与行框推挤；padding/border 计入占位盒宽高（文本环绕按盒计），但只有图片内容被绘制。
2. `vertical-align` 只支持 baseline/middle；top/bottom/长度/百分比退化为 baseline。
3. `<a>` 内的原子断开链接范围：链接矩形只覆盖原子两侧的文本，图片本身不是可点击区域。
4. 点落在原子上时，`layout_result` 的接缝回退会把它锚定到相邻文本 run 的接缝偏移；原子自身永远不产生文本锚点（与块级图片"点不上文本"的效果等价，但不是返回 null）。
5. 表格列宽测量对"只有 CSS height、宽度 auto"的图片仍按固有宽度近似，未复用比例推导。

## 后果

- 行内图片不再静默丢失；`<p>text <a href><img></a> text</p>` 等 CMS 常见结构参与断行、基线混排与行高增长。
- `conformance/` 像素黄金与 `float_image`/`table_basic` 几何基线零影响（语料中没有行内图片、没有 CSS height/百分比宽度）。
- 后续扩展点：原子 run 可携带 href 使图片本身可点击；margin 参与行框、top/bottom 对齐、`vertical-align` 长度值可在 `WeftInlineVerticalAlign` 与 `_imageMetrics` 上渐进补齐。
