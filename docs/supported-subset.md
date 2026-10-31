# HTML/CSS 子集状态

本文同时记录目标子集与当前实现状态。已建立固定字体 Flutter 像素门禁和 Chromium 诊断参考，但跨引擎像素预算尚未达标，不能据此宣称完整浏览器兼容。

状态说明：

- **已实现**：有代码路径和自动测试。
- **部分实现**：主路径可用，但缺少浏览器完整行为。
- **阶段 1 后续**：尚未实现，暂按未知元素或回退处理。
- **部分实现（阶段 4）**：主路径已交付并验收（ADR 0033），边界见各行说明。
- **不支持**：由宿主通过回退或专用组件处理。

## HTML

| 类别 | 元素 | 状态 | 当前行为 |
|---|---|---|---|
| 文档与分组 | `html/body/div/span` | 已实现 | 受控树、块/行内叠放；全局属性含 `dir`（rtl/ltr/auto）与 `lang`（ADR 0042） |
| 标题与段落 | `h1-h6/p/br/hr` | 已实现 | 默认字号、字重、间距、换行和分隔线 |
| 基础文本 | `strong/b/em/i/u/s/small` | 已实现 | 粗体、斜体、装饰和相对字号 |
| 上下标 | `sub/sup` | 部分实现 | 缩小字号，尚未做基线位移 |
| 引用 | `blockquote` | 已实现 | 左右缩进和块级间距 |
| 代码 | `pre/code` | 部分实现 | 等宽字体、背景和预格式化换行；无横向滚动 |
| 列表 | `ul/ol/li` | 部分实现 | disc、decimal、none 和无障碍外的独立标记；有序列表支持 `ol start` 与 `li value` |
| 描述列表 | `dl/dt/dd` | 部分实现 | 块级显示，无专用样式 |
| 链接 | `a` | 已实现 | URL 清洗、视觉样式、跨行命中矩形和宿主回调；导航由宿主决定 |
| 图片 | `img` | 部分实现 | `src/alt/width/height`、块级替换盒、左右 Float、`clear` 和宿主资源解析；img 默认 `display: inline`，以原子参与基线混排，`display: block` 退回块级替换盒（ADR 0018） |
| 表格 | `table/thead/tbody/tfoot/tr/th/td/caption`、`colgroup/col` | 部分实现 | 槽位网格、`colspan/rowspan`、隐式行、caption、separate/collapse 边框与 `vertical-align`；`colgroup/col` 声明列轨道（px 固定列、百分比列、span，ADR 0022）；嵌套表格触发回退 |
| 单元格跨距 | `colspan/rowspan` | 已实现 | 1..1000 清洗、跨列跨行、悬空 rowspan 生成隐式行 |
| 脚本 | 可信 `ScriptUnit` | 部分实现 | `<script>` 标签仍触发回退；受信任脚本由宿主经 `WeftDocumentRuntime` 执行（QuickJS FFI，ADR 0033）：墙钟/内存/栈/微任务预算内中断，能力经 `weft.*` 白名单暴露 |
| 自定义标签 | 宿主白名单 `<weft-*>` | 部分实现 | `WeftNormalizer.customTags` 保留属性驱动叶子元素（内容丢弃有诊断），`WeftTagRenderer` 输出 rect/text ops 由引擎绘制；无渲染器时空盒；不支持行内混排与 Float 环绕 |
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
| 方向 | `direction: rtl/ltr` | 已实现（ADR 0042）；`dir` 属性映射为 UA 级默认，CSS 层叠可覆盖 |
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
- 竖排、中性字符行缘 BiDi 重排和完整东亚排版规则（悬挂标点等）；基础 RTL（`dir`/`lang`/CSS `direction` 的块级方向、起始对齐、列表镜像）已由 ADR 0042 支持，行内双向重排交给 SkParagraph。

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

当前能力（ADR 0024/0026/0028/0030/0039/0040）：

- `RenderWeftSurface` 手动暴露阅读顺序文本、链接、图片和非折叠选区；普通文本不与子链接重复朗读，链接支持宿主 Semantics tap，已解析图片使用 alt，空 alt 作为装饰跳过。
- 标题与 `<th>` 子树暴露 header flag；`h1..h6` 的文本、链接、强调和图片 alt 同时输出 `headingLevel`（ADR 0039）。有序/无序列表项的首个朗读片段带 `1. ` / `• ` 标记，有序列表的 `start`/`value` 同时作用于视觉与语义 marker；标记不进入复制文本（ADR 0028/0039）。`ul/ol→li` 与 `table→tr→td/th` 生成嵌套 list/listItem、table/row/cell/columnHeader 角色，listItem/row/cell 带 indexInParent，thead/tbody 透明、caption 作为 table 前兄弟（ADR 0030）。显式 `aria-live="polite/assertive"` 子树的文本、链接、图片与自定义标签叶子带 Flutter `liveRegion` 标志；`off` 显式关闭并向下继承（ADR 0039）。标题内的链接/强调仍保留语义顺序。选区提供 value/selected/rect，并在宿主提供回调时暴露 copy action（ADR 0026）；WeftView 与复制按钮共用 Clipboard 策略，standalone 默认无 copy。同 document.id 的流式追加保留未变 SemanticsNode.id，屏外内容保留并支持 showOnScreen 滚动。
- ARIA 基础（ADR 0040）：`role` 保守映射——`button`/`link` 输出 isButton/isLink 标志（无激活动作），`img`/`heading` 折叠或派生 header/headingLevel，`dialog`/`alertdialog` 成为容器角色，`alert`/`status` 隐式化为 live+atomic 播报，`presentation`/`none` 抑制元素自身派生语义（内容仍朗读），其余角色丢弃并产出 `aria.role.unsupported` 诊断；显式 role 覆盖元素隐式语义（`<a role="button">` 不再是链接）。`aria-hidden="true"` 子树从语义树移除（视觉与复制文本不变）。`aria-label` 作为可访问名称：img 上优先于 alt，其余元素（table 族除外）子树折叠为单个命名叶子，`<a aria-label>` 保留 tap。live region 内 `aria-atomic="true"`（含 alert/status 隐式）将子树折叠为单个 liveRegion 叶子整组播报，替代逐叶子播报。
- 宿主可用 `ExcludeSemantics` 排除表面；`WeftSurface.onSemanticsLinkTap` 默认回退到 `onLinkTap`，WeftView 自动接入同一宿主回调。

边界与限制：尚无 table/list 角色导航、可编辑 setSelection/caret 动作、逐文本节点 selected state、landmark/tab/menu/radio 族角色、`aria-level`/`aria-labelledby`/`aria-describedby`、`polite`/`assertive` 播报优先级或语义虚拟化；`role=button`/`link` 只播报角色，不产生激活动作（引擎不执行脚本）；折叠类语义（aria-label/role=img/aria-atomic）不播报子树内容且不带列表 marker；presentation 表格后代 th 的 header flag 保留（记录在案的简化）。已解析图片位于链接内时不额外提供 tap，与当前 pointer 命中能力一致。

## 流式增量布局

当前能力（ADR 0023）：

- 同一 document 的连续快照可复用无 Float 的 body 顶层公共前缀块及其 TextPainter；完整尾部追加与最后一个顶层块持续增长都只重排变化后缀。
- 复用仍经过原块流的 margin collapse、列表计数和 cursor 计算；普通块、表格和块级图片以整个顶层块为单位，连续多轮快照可持续命中。
- 中部编辑、删除与头部插入（weft_live 更新形态）复用变化区之后的形状相同块：按共享垂直增量平移，命令/run/box/link/tag 的先序 nodeId 经旧→新映射重写，与全量重建逐条目等价并有光栅逐字节测试（ADR 0046）。
- 几何与命令实例完全未变的前缀 chunk 保留 ui.Picture；同 id/src 的已解析图片跨快照保留。diff 已证不变的顶层子成对沿用上一轮计算样式（ADR 0050），流式轮与样式表规模脱钩。文本索引在流式新快照上按块 diff 前缀复用上一索引条目、只构建后缀——lazy 部分测量前缀同样参与（ADR 0048）；头部插入/头删除等无前缀形态经反向 diff 的后缀映射采用旧条目（globalStart 平移 + nodeId 重映射，接缝标志不符的子 fresh 走查，ADR 0051）；前置不满足（样式表变化等全局键）或 lazy 轮（无后缀映射）即回退全量重建（ADR 0044）；同快照的滚动 relayout 直接复用上一结果的索引实例（ADR 0031），命中索引随新快照更新。

边界与限制：样式表、宽度、textScaler、换行规则或图片输入变化会全量回退；旧结果含 Float、body 直属 loose inline/text、空块折叠或未解析图片时不作为复用来源。变化区之后的后缀平移复用已交付（plain 路径，body 级 li 截断扫描，ADR 0046）；尚不支持 Float checkpoint、行级复用或布局虚拟化。

## 渐进式布局虚拟化

当前能力（ADR 0025）：

- `WeftView.enableLazyLayout` 默认开启：简单文档只精确测量并物化可见顶层块，未测后缀以同类块高度估算滚动 extent；`lazyOverscan` 可调整窗口外预取（默认 250px）。
- 已测前缀坐标与 canonical 一致；滚出窗口的 TextPainter/commands 会释放，重新进入时按保守绘制区间索引直接定位，并恢复 Float 上下文重建（ADR 0036）。表格整块处理，不做表内虚拟化。
- body 在 `white-space: normal` 下的 ASCII 格式化空白不进入块流；原快照、逻辑文本及分块序号不变。准入与后缀估算按有效输入缓存，热态换窗不重新采样高度；流式新快照按块 diff 已证前缀沿用上一轮准入结论与逐子估算、只验证/重建变化后缀（ADR 0049）；NBSP、正文与预格式化空白仍保守 full。
- 跳到估算底部后随 extent 校正使用 ScrollPosition.correctBy 跟随；同 id 流式尾部追加继续保留未变可见资源。
- 顶层块内部及 body 直属、已解析 `img` 的左右 Float 可进入 lazy；排除区按顶层块保存并在离屏复用/重新物化时恢复，后续文字行宽与 clear 保持 canonical。
- 非空 selection、非图片/inline 祖先 Float、未解析图片、body loose inline 或复杂结构会升级/回退完整布局；升级按 document.id 粘滞。Semantics 不再触发升级（ADR 0041）：读屏直接在 lazy 结果上组装——物化窗口精确、band 内未物化块折叠为逐块粗叶子、未测后缀滚动物化后出现。

- `WeftViewState.scrollToAnchor` 可按逻辑文本锚点导航；懒布局使用 focus 精确测量并物化目标块，保留当前窗口和 lazy 状态，alignment 支持顶部/居中/底部，无效锚点安全返回 false。
- `scrollToAnchorAsync` 将深链测量拆成逐帧预算（默认每 pass 32 块）；测量期间保持当前滚动内容，完成后才定位，取消/文档变化返回 false。
- 非锚点的深跳与深 seed 同样分帧（ADR 0031）：视口末端距已测前缀超过一屏或首帧 seed 深于 overscan 时，每帧最多新测 32 个顶层块，post-frame 续帧逐帧推进直至窗口覆盖；近距滚动保持单次同步测量。同快照 relayout 跳过节点 diff 与样式表比对，复用跨帧样式缓存与文本索引实例。
- 冷深跳/深 seed 分帧测量期间，`WeftView.lazySettlingBuilder` 可在视口上覆盖宿主提供的静态占位；`WeftViewState.isLazySettling` / `onLazySettlingChanged` 报告开始与结束（post-frame、去重，ADR 0037）。引擎不绘制占位，未配置 builder 时仍是空白渐进填充。异步锚点与近 frontier 同步滚动不会触发 settling。
- `scrollToNode` / `scrollToNodeAsync` 定位元素内首个可朗读文本锚点，复用同一 alignment/lazy focus 与分帧路径。
- 边界与限制：滚动条长度在未测完时是估算值；深跳目标区在测到之前为空白（渐进填充），配置 `lazySettlingBuilder` 时由宿主遮罩覆盖，但仍不承诺零空白；分帧预算为内部常量；首次锚点导航目标靠后时仍需逐帧测量前缀，不承诺未测区域的精确 O(1)/O(log N) 随机定位。病态区间重叠和大量历史 Float 可能退化；超高顶层块、表内局部 Float 和图片解码资源仍未细分虚拟化。

## 当前明确限制

- 链接点击交给 `WeftView.onLinkTap`，引擎不会自行打开浏览器或执行导航。
- 图片必须由宿主 `WeftImageResolver` 提供 `ImageProvider`；引擎不进行隐式网络请求。未解析或加载失败时显示 `alt` 文本。
- 图片默认 `display: inline`（与浏览器 UA 样式表一致），以原子（U+FFFC 占位符）参与行内混排；显式 `display: block` 退回块级替换盒。行内原子忽略自身 `margin`，padding/border 只预留空间不绘制；`vertical-align` 只支持 baseline/middle。
- 图片百分比宽度相对包含块 content 宽解析；CSS `height`（px）显式给出时宽度按比例推导；height 百分比按 auto 处理。
- Float 仅支持作为块级容器直接子元素的 `img`；行内元素内部的嵌套浮动图片当前不参与布局。
- 浮动图片自身的 `margin`、`padding` 和边框参与排除区；`clear` 作用于后续块级元素。
- 宽度和边框只作用到块级盒：块级支持 px/em/rem 与百分比宽度、水平 `auto` margin 和显式 `height`（ADR 0021）；行内内容的 border、百分比宽度、`auto` margin 与 CSS 高度不生效，块级圆角不绘制。
- 边框只支持 `solid` 简写；`dashed/dotted/double` 等当前按无边框处理。
- `WeftView` 自带内部滚动；lazy 路径的布局命令只覆盖当前物化窗口，复杂文档和完整几何查询仍使用全文。
- 固定字体下块级几何与 Chromium 误差小于 0.5px；`float_image` 案例的全部块/图片几何实测误差 ≤ 0.16px，逐行词盒由浏览器几何基线测试覆盖，但跨引擎像素差异仍高于 1% advisory 预算，主要来自字形抗锯齿。
- 1:1 图片绘制目标在绘制时对齐整像素（浏览器同款行为）；缩放绘制仍按 FilterQuality.medium 重采样。
- CJK 无固定可分发的像素字体，跨引擎像素验收按 ADR 0032 重定界为结构几何门禁 + 固定字体拉丁像素黄金；中文正确性由禁则测试、CJK 语料与浏览器几何基线覆盖，中文内容不设像素黄金。
- 表格列宽为两遍自动布局（min/max-content + 比例分配）：固定字体下单元格边界与 Chromium 偏差约 ≤ 1px，自由分配场景可差数像素；`colgroup/col` 支持 px 固定列、百分比列与 span 轨道（ADR 0022），但浏览器级 auto 列宽分配精度仍有差距；嵌套表格触发 `requiresWebView`。详见 ADR 0012/0022。

## Float 的 MVP 边界

当前已支持图片的左右浮动、逐行可用行框、`clear`、同侧堆叠、对侧并排、跨段落环绕和文档滚动高度。

尚未支持任意元素的 Float、浮动与表格/行内格式化上下文的交互、`clear` 的 margin 合并细节。Float 的定位与排除区在 `layout_engine.dart` 的 `_FloatContext` 中维护，后续表格和 Flexbox 必须复用同一套行框可用区查询，不得另建绕过机制。行内图片以原子参与浮动旁的逐行排版（见 ADR 0018）。

## 受限 JavaScript（阶段 4，ADR 0033）

当前能力：

- 受信任脚本由宿主经 `WeftDocumentRuntime` 执行：单文档 Context、`weft.state/events/net` 能力桥（网络仅 GET）、恢复不重放网络副作用且 `(sessionId, sequence)` 可去重。
- 墙钟/内存/栈/微任务四类预算由 QuickJS 原生层强制，能力调用风暴有单轮上限；未启用能力在 JS 中不可见。

尚未实现：

- `weft.net` 的 POST、请求体与取消令牌；`<script>` 标签仍触发回退（不存在声明式脚本执行）。

## 不支持输入处理

未知标签按策略选择 drop、unwrap 或 error。非关键 CSS 可丢弃并警告；Canvas、WebGL、需要完整 DOM 的交互、表格和未接入资源策略的图片必须在有能力渲染前设置 `requiresWebView`。任何策略都不得无诊断地静默改变内容语义。

## WebView 回退（阶段 5，ADR 0034）

- `SupportReport.requiresWebView` 时宿主把**原始 HTML** 交给自己的 WebView（或专用库）；`WeftView.fallbackBuilder` 是接入点，`example/weft_fallback` 给出可运行演示：`decideWeftFallback` 三路决策（原生渲染 / requiresWebView → 宿主 WebView / 其余错误 → 诊断卡片），`webview_flutter` 只出现在示例包。
- 快照 JSON 线格式（`WeftDocumentJson`）带 format+version 门禁：宿主钉回旧版本引擎时，新版本快照被显式拒绝而不是静默误读；版本策略与回滚演练见 `docs/release-runbook.md`。
