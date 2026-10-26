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
| 图片 | `img` | 部分实现 | `src/alt/width/height`、块级替换盒、左右 Float、`clear` 和宿主资源解析；img 默认 `display: inline`，以原子参与基线混排，`display: block` 退回块级替换盒（ADR 0018） |
| 表格 | `table/thead/tbody/tfoot/tr/th/td/caption`、`colgroup/col` | 部分实现 | 槽位网格、`colspan/rowspan`、隐式行、caption、separate/collapse 边框与 `vertical-align`；`colgroup/col` 声明列轨道（px 固定列、百分比列、span，ADR 0022）；嵌套表格触发回退 |
| 单元格跨距 | `colspan/rowspan` | 已实现 | 1..1000 清洗、跨列跨行、悬空 rowspan 生成隐式行 |
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
| 盒模型 | `margin(-side)`、`padding(-side)` | 已实现非负 padding、可负 margin 和相邻/父子/空块折叠；水平 `margin: auto` 在显式宽度块上分配剩余空间（垂直 auto 按 0，图片 auto margin 按 0，ADR 0021） |
| 显示 | `display: block/inline/list-item/none` | 已实现 |
| 列表 | `list-style-type: disc/decimal/none` | 已实现 |
| 宽度 | `width/min-width/max-width/box-sizing` | 部分实现：块级与图片 px/em/rem，百分比宽相对包含块 content 宽（ADR 0018/0021）；min/max-width 百分比与 auto margin（图片）不支持 |
| 高度 | `height`（图片/块级） | 部分实现：图片 CSS px 高度按比例推导宽；块级显式高度生效（overflow 不裁剪，ADR 0021）；height 百分比一律按 auto |
| 边框 | `border`、`border-top/right/bottom/left` | 部分实现：块级 solid，无圆角/虚线/独立宽高与颜色属性 |
| 缩进与字距 | `text-indent/letter-spacing` | 阶段 1 后续 |
| 定位 | `position/float/clear` | 部分实现：仅图片 Float，支持左右、clear 和跨段落行框缩短 |
| 表格 | `border-collapse/border-spacing`、单元格 `vertical-align` | 已实现：separate（默认 2px 间距，含表缘）、collapse（中心线共享边，取最宽者）、top/middle/bottom 对齐（baseline 归并为 middle） |
| 行内对齐 | 图片 `vertical-align: baseline/middle` | 部分实现：仅行内图片原子消费（默认 baseline）；top/bottom/长度/百分比退化为 baseline，表格单元格语义不受影响 |
| Flexbox | 不进入当前布局 | 后续候选 |
| transform、filter、动画 | 不进入引擎 | 不支持 |

`display: inline-block` 当前不按浏览器行为实现，会在样式值层面被忽略。浏览器不接受或不认识的属性值不会扩大引擎能力。

## 文本与 CJK

当前能力：

- 跨文本节点空白折叠，保留 `<pre>` 的换行和空格。
- 窄宽度自动换行、对齐、文本缩放和基础中文逐字换行。
- CJK 禁则（ADR 0016）：默认表禁止 21 个行首字符（。、，！？）」』等）与 7 个行尾字符（（「『【等）出现在断行边界；逐行分行路径显式执行禁则（`WeftLineBreakRules` 可配置/可关闭），整段路径经 ICU 对照零违规。
- 逻辑文本在布局前后保持一致，选区解析与手势锚点（ADR 0013/0015/0019）均基于该模型。

尚未实现：

- 合法的拉丁词、数字和连字符边界优化。
- 字素簇级别的选择安全。
- 竖排、复杂 BiDi 和完整东亚排版规则（悬挂标点等）。

## 选择与交互

当前能力（ADR 0013/0015/0019）：

- 长按选词、长按拖拽扩展选区；拖拽落点不在文字上时保留上一次端点（安全丢弃，不钳制）。
- 点击文本放置 caret（折叠选区，surface 在 canvas 上绘制 2px 竖条）；点击空白清除选区；链接命中优先于 caret。
- 选择把手（小圆点 + 短柄）：可拖拽移动选区的起点/终点，触控目标 44×44，贴边平移、贴底收缩，绝不遮挡被选中的行。
- 复制按钮：白底圆角浮层，默认置于选区上方（无余地时放下方），tap 写入系统剪贴板并**保留选区**，标签由 `copyButtonLabel` 配置（默认 '复制'）。
- `WeftView.onSelectionChanged(WeftSelectionInfo?)` 向宿主上报选区文本（折叠时 text 为 null）；宿主也可经 `WeftViewState.selectionText()` 读取。

边界与限制：

- 引擎不写剪贴板；复制动作由 weft 视图层执行，策略归宿主。
- 把手与复制按钮是 `WeftView` 的 overlay；单独使用 `WeftSurface` 时只有 caret，`selectionControlsGeometry()` 仍可查询供宿主自组 chrome。
- overlay 位置滞后真实布局一帧（post-frame 同步补齐）；极短文档中复制按钮可能与文本重叠。
- 无选择工具条（全选/分享等菜单项）、无 chrome 动画；字素簇边界和辅助技术调整选区动作未处理。

## 可访问性语义

当前能力（ADR 0024）：

- `RenderWeftSurface` 手动暴露阅读顺序文本、链接、图片和非折叠选区；普通文本不与子链接重复朗读，链接支持宿主 Semantics tap，已解析图片使用 alt，空 alt 作为装饰跳过。
- 选区提供 value/selected/rect，复制仍使用现有按钮；同 document.id 的流式追加保留未变 SemanticsNode.id，屏外内容保留并支持 showOnScreen 滚动。
- 宿主可用 `ExcludeSemantics` 排除表面；`WeftSurface.onSemanticsLinkTap` 默认回退到 `onLinkTap`，WeftView 自动接入同一宿主回调。

边界与限制：尚无 heading/table/list 角色导航、可编辑 setSelection/copy/caret 动作、逐文本节点 selected state、RTL/语言属性、live region 或语义虚拟化。已解析图片位于链接内时不额外提供 tap，与当前 pointer 命中能力一致。

## 流式增量布局

当前能力（ADR 0023）：

- 同一 document 的连续快照可复用无 Float 的 body 顶层公共前缀块及其 TextPainter；完整尾部追加与最后一个顶层块持续增长都只重排变化后缀。
- 复用仍经过原块流的 margin collapse、列表计数和 cursor 计算；普通块、表格和块级图片以整个顶层块为单位，连续多轮快照可持续命中。
- 几何与命令实例完全未变的前缀 chunk 保留 ui.Picture；同 id/src 的已解析图片跨快照保留。文本索引每轮重建，命中索引随新快照更新。

边界与限制：样式表、宽度、textScaler、换行规则或图片输入变化会全量回退；旧结果含 Float、body 直属 loose inline/text、空块折叠或未解析图片时不作为复用来源。尚不支持 Float checkpoint、后缀平移、行级复用和布局级视口虚拟化。

## 当前明确限制

- 链接点击交给 `WeftView.onLinkTap`，引擎不会自行打开浏览器或执行导航。
- 图片必须由宿主 `WeftImageResolver` 提供 `ImageProvider`；引擎不进行隐式网络请求。未解析或加载失败时显示 `alt` 文本。
- 图片默认 `display: inline`（与浏览器 UA 样式表一致），以原子（U+FFFC 占位符）参与行内混排；显式 `display: block` 退回块级替换盒。行内原子忽略自身 `margin`，padding/border 只预留空间不绘制；`vertical-align` 只支持 baseline/middle。
- 图片百分比宽度相对包含块 content 宽解析；CSS `height`（px）显式给出时宽度按比例推导；height 百分比按 auto 处理。
- Float 仅支持作为块级容器直接子元素的 `img`；行内元素内部的嵌套浮动图片当前不参与布局。
- 浮动图片自身的 `margin`、`padding` 和边框参与排除区；`clear` 作用于后续块级元素。
- 宽度和边框只作用到块级盒；行内边框、百分比宽度、`auto` margin、CSS 高度和圆角尚未实现。
- 边框只支持 `solid` 简写；`dashed/dotted/double` 等当前按无边框处理。
- `WeftView` 依赖外部滚动，布局和绘制命令覆盖完整文档。
- 固定字体下块级几何与 Chromium 误差小于 0.5px；`float_image` 案例的全部块/图片几何实测误差 ≤ 0.16px，逐行词盒由浏览器几何基线测试覆盖，但跨引擎像素差异仍高于 1% advisory 预算，主要来自字形抗锯齿。
- 1:1 图片绘制目标在绘制时对齐整像素（浏览器同款行为）；缩放绘制仍按 FilterQuality.medium 重采样。
- CJK 尚无固定可分发的像素字体，中文只有结构测试，没有像素基线。
- 表格列宽为两遍自动布局（min/max-content + 比例分配）：固定字体下单元格边界与 Chromium 偏差约 ≤ 1px，自由分配场景可差数像素；`colgroup/col` 列宽属性不生效，嵌套表格触发 `requiresWebView`。详见 ADR 0012。

## Float 的 MVP 边界

当前已支持图片的左右浮动、逐行可用行框、`clear`、同侧堆叠、对侧并排、跨段落环绕和文档滚动高度。

尚未支持任意元素的 Float、浮动与表格/行内格式化上下文的交互、`clear` 的 margin 合并细节。Float 的定位与排除区在 `layout_engine.dart` 的 `_FloatContext` 中维护，后续表格和 Flexbox 必须复用同一套行框可用区查询，不得另建绕过机制。行内图片以原子参与浮动旁的逐行排版（见 ADR 0018）。

## 不支持输入处理

未知标签按策略选择 drop、unwrap 或 error。非关键 CSS 可丢弃并警告；Canvas、WebGL、需要完整 DOM 的交互、表格和未接入资源策略的图片必须在有能力渲染前设置 `requiresWebView`。任何策略都不得无诊断地静默改变内容语义。
