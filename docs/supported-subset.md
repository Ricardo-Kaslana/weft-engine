# HTML/CSS 子集状态

本文同时记录目标子集与当前实现状态。已建立固定字体 Flutter 像素门禁和 Chromium 诊断参考，但跨引擎像素预算尚未达标，不能据此宣称完整浏览器兼容。

状态说明：

- **已实现**：有代码路径和自动测试。
- **部分实现**：主路径可用，但缺少浏览器完整行为。
- **阶段 1 后续**：尚未实现，暂按未知元素或回退处理。
- **阶段 2/4**：按里程碑实现。
- **不支持**：由宿主通过回退或专用组件处理。

## HTML

| 类别 | 元素 | 状态 | 当前行为 |
|---|---|---|---|
| 文档与分组 | `html/body/div/span` | 已实现 | 受控树、块/行内叠放 |
| 标题与段落 | `h1-h6/p/br/hr` | 已实现 | 默认字号、字重、间距、换行和分隔线 |
| 基础文本 | `strong/b/em/i/u/s/small` | 已实现 | 粗体、斜体、装饰和相对字号 |
| 上下标 | `sub/sup` | 部分实现 | 缩小字号，尚未做基线位移 |
| 引用 | `blockquote` | 已实现 | 左右缩进和块级间距 |
| 代码 | `pre/code` | 部分实现 | 等宽字体、背景和预格式化换行；无横向滚动 |
| 列表 | `ul/ol/li` | 部分实现 | disc、decimal、none 和无障碍外的独立标记 |
| 描述列表 | `dl/dt/dd` | 部分实现 | 块级显示，无专用样式 |
| 链接 | `a` | 已实现 | URL 清洗、视觉样式、跨行命中矩形和宿主回调；导航由宿主决定 |
| 图片 | `img` | 阶段 2 | 当前触发显式回退 |
| 表格 | `table/thead/tbody/tfoot/tr/th/td/caption` | 阶段 2 | 当前触发显式回退 |
| 单元格跨距 | `colspan/rowspan` | 阶段 2 | 随表格实现 |
| 脚本 | 可信 `ScriptUnit` | 阶段 4 | 当前任何 `script` 都要求回退 |
| Canvas、WebGL、iframe、对象嵌入 | 不进入引擎 | 不支持 | 触发 `requiresWebView` |
| 表单、富文本编辑 | 不进入引擎 | 不支持 | 触发 `requiresWebView` |

未知非关键标签会 unwrap 并产生警告。可能丢失语义或交互的元素会要求回退，不会静默按已完整渲染处理。

## CSS 选择器与层叠

| 能力 | 状态 | 备注 |
|---|---|---|
| 标签、`.class`、`#id` | 已实现 | 支持复合选择器 |
| 后代、子代、逗号选择器 | 已实现 | 模型含结构化匹配测试 |
| 内联样式和 `<style>` | 已实现 | csslib 仅用于语法解析 |
| 继承、特异性和源码顺序 | 已实现 | 内联样式最后覆盖 |
| `margin`/`padding` 简写 | 已实现 | 展开为长属性参与层叠 |
| 属性选择器 | 阶段 1 后续 | 当前规则被忽略并警告 |
| 伪类、伪元素 | 不支持 | 当前规则被忽略并警告 |
| 媒体查询、at-rule | 不支持 | 当前被忽略并警告 |
| `!important` | 不支持 | 当前声明被丢弃并警告 |
| Shadow DOM、级联层 | 不支持 | 不在受控内容范围 |

## CSS 属性

| 类别 | 当前属性 | 状态 |
|---|---|---|
| 字体 | `font-family/size/style/weight` | 部分实现：family 只识别通用族和首个名称 |
| 行高 | `line-height` | 已实现：普通数字、百分比和 px；按 CSS 半行距分配 |
| 文本 | `color/text-align/text-decoration/white-space` | 已实现基础值 |
| 背景 | `background-color` | 已实现块背景和行内文本背景 |
| 盒模型 | `margin(-side)`、`padding(-side)` | 已实现非负 padding、可负 margin 和相邻/父子/空块折叠 |
| 显示 | `display: block/inline/list-item/none` | 已实现 |
| 列表 | `list-style-type: disc/decimal/none` | 已实现 |
| 宽度 | `width/min-width/max-width/box-sizing` | 部分实现：块级 px/em/rem，不含百分比和 auto margin |
| 高度 | `height/min-height/max-height` | 阶段 1 后续 |
| 边框 | `border`、`border-top/right/bottom/left` | 部分实现：块级 solid，无圆角/虚线/独立宽高与颜色属性 |
| 缩进与字距 | `text-indent/letter-spacing` | 阶段 1 后续 |
| 定位 | `position/float/clear` | 阶段 2 |
| 表格 | table display、`vertical-align`、`border-collapse` | 阶段 2 |
| Flexbox | 不进入当前布局 | 后续候选 |
| transform、filter、动画 | 不进入引擎 | 不支持 |

`display: inline-block` 当前不按浏览器行为实现，会在样式值层面被忽略。浏览器不接受或不认识的属性值不会扩大引擎能力。

## 文本与 CJK

当前能力：

- 跨文本节点空白折叠，保留 `<pre>` 的换行和空格。
- 窄宽度自动换行、对齐、文本缩放和基础中文逐字换行。
- 逻辑文本在布局前后保持一致，为后续选择索引提供来源。

尚未实现：

- 行首/行尾禁则和可配置中文标点表。
- 合法的拉丁词、数字和连字符边界优化。
- 字素簇级别的选择安全（选择本身尚未实现）。
- 竖排、复杂 BiDi 和完整东亚排版规则。

## 当前明确限制

- 链接点击交给 `WeftView.onLinkTap`，引擎不会自行打开浏览器或执行导航。
- 宽度和边框只作用到块级盒；行内边框、百分比宽度、`auto` margin、CSS 高度和圆角尚未实现。
- 边框只支持 `solid` 简写；`dashed/dotted/double` 等当前按无边框处理。
- `WeftView` 依赖外部滚动，布局和绘制命令覆盖完整文档。
- 固定字体下块级几何与 Chromium 误差小于 0.5px，但跨引擎像素差异仍高于 1% advisory 预算，主要来自字形抗锯齿。
- CJK 尚无固定可分发的像素字体，中文只有结构测试，没有像素基线。
- 图片和表格走回退；不要在阶段 1B 声称支持内容型页面的全部常见元素。

## Float 的 MVP 边界

后续必须支持图片导致的跨段落文字环绕。首版重点支持 `img` 和受限 inline-block 的左右浮动、Clear、父级高度和后续行框缩短。任意元素、复杂嵌套浮动不与完整 CSS 2.1 兼容承诺绑定。

## 不支持输入处理

未知标签按策略选择 drop、unwrap 或 error。非关键 CSS 可丢弃并警告；Canvas、WebGL、需要完整 DOM 的交互、图片和表格必须在有能力渲染前设置 `requiresWebView`。任何策略都不得无诊断地静默改变内容语义。
