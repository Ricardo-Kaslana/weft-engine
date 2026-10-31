# 开发里程碑

每个阶段必须交付可运行示例、测试证据、架构更新、性能记录和 ADR。上一阶段的 S0/S1 缺陷未关闭，不进入下一阶段。

## 阶段 0：工程初始化（已完成）

交付 Pub workspace、包边界、公开契约、渲染表面、Runtime 适配边界、实验室、基础测试和项目文档。

验收：依赖可解析、格式化与静态检查通过、全部基础测试通过、CI 可复现。此阶段不宣称 HTML 或 JS 功能完成。

当前证据：Flutter 3.35.5 / Dart 3.9.2 下静态分析无问题，workspace 测试与 CI 入口可运行。

## 阶段 1：规范基线与静态渲染（已完成）

原目标为规范化器、HTML/CSS 解析适配、计算样式、Block/Inline/List、链接、基础文本和分块绘制。按 ADR 0007，阶段 1A 先交付直接布局和完整绘制命令，分块 Picture 与视口绘制移至阶段 3 的性能工作。

### 1A：基础静态渲染（已完成）

已交付：

- 受控 HTML 树、标签/属性过滤、节点和输入限制、结构化诊断。
- 结构化 CSS 选择器、特异性层叠、继承、内联样式及 margin/padding 简写展开。
- 标题、段落、行内强调、链接样式、列表、引用、代码、分隔线和换行。
- 单渲染表面、滚动入口、真实背景/文本绘制、文本缩放和资源释放。
- 空白折叠、相邻/父子/空块 margin 折叠、窄宽度换行、CJK 与 300 段长文档测试。
- CSS 半行距对齐，固定字体下块级几何与 Chromium 误差小于 0.5px。

### 1B：阶段 1 收尾（已完成）

已交付：

- 链接显示文本映射为按行命中矩形，支持跨行和相邻多链接。
- `WeftView.onLinkTap` 将清洗后的链接交给宿主；引擎不自行导航。
- 命中与手势测试覆盖布局层、渲染表面和公开视图。
- 块级宽度、最小/最大宽度、`box-sizing` 和 solid 边框已进入布局及绘制。
- 已建立六类代表性语料和自动化结构验收，覆盖链接、盒边界、最小高度与文本命令。
- 已建立 Chrome/Edge 诊断参考截图生成器，可记录浏览器版本和固定视口产物。
- 已固定 Roboto/Roboto Mono 字体，提交两个 Flutter 像素基线，并加入 Windows CI 黄金门禁。
- 已加入 Pillow 跨引擎差异报告；`box_model` 已进入 1% 预算。
- 已实现 CSS 2.1 相邻/父子/空块 margin 折叠和半行距，修正容器背景盒与文档高度。
- CSS 高度、百分比宽度、auto margin 已交付（ADR 0021）；圆角与虚线边框正式留在子集之外（supported-subset.md 矩阵）。
- 新增商品描述与帮助文档语料用例；语料结构验收扩展为无静默丢失（逐文本节点存活到逻辑索引）、无重叠（两两文本命令矩形不相交）、无越界（全部命令边界在文档范围内）（ADR 0032）。
- 敌意输入端到端扫描：script、嵌套表格、未知标签、危险图片源、注入属性均产出显式诊断（ADR 0032）。
- 跨引擎像素验收按 ADR 0032 重定界为结构几何门禁（块级 ≤0.5px、表格 ≤1.5px、逐行词盒）+ 固定字体拉丁像素黄金；CJK 像素基线因无可分发像素字体正式移出，中文正确性由禁则测试、CJK 语料与几何基线覆盖。
- 性能基线：与功能等价"标签→Widget"管线对比的首个解析+布局基准工具已建立（`tool/widget_baseline_benchmark_test.dart`），结果与重定界见 ADR 0032。

## 阶段 2：完整内容排版（已完成）

实现图片资源、左右 Float、Clear、表格、CJK 禁则和布局失效。

已交付：

- `img` 标签、`src/alt/width/height` 清洗、资源 URL 协议过滤和无效尺寸诊断。
- 宿主 `WeftImageResolver`、异步解码监听、布局失效和 `ImageInfo` 释放。
- 块级图片替换盒、固有比例、`max-width` 约束、`alt` 回退。
- 左右 Float、跨段落文字环绕、`clear`、同侧堆叠、对侧并排和文档滚动高度；Float 环绕下的逐行文本布局和跨行链接命中。
- 表格槽位网格、colspan/rowspan（含隐式行）、caption、separate/collapse 边框与 colgroup/col 列轨道（ADR 0012/0022）；嵌套表格触发显式回退。
- 行内图片基线混排（ADR 0018）；CJK 禁则（ADR 0016）；图片异步解码与身份变化触发布局失效。
- 晚解码 Float 等价测试：解码前 alt 回退、解码后接续布局与全新布局逐命令一致（ADR 0032）；Float 环绕在 280/360/480px 三档宽度下的结构断言（命令不越界、行框不重叠、环绕与 clear 生效）。
- 语料结构断言覆盖全部用例的无重叠、越界与静默缺失检查（ADR 0032）。
- 任意元素 Float 与复杂嵌套浮动按 ADR 0011/0025 的 MVP 边界正式限定为"已解析 `img` 且为块级容器直接子元素"，表格 cell 使用独立 `_FloatContext`（近似 BFC）；更广 Float 留待后续画像驱动。

## 阶段 3：长文档、选择与性能（已完成）

实现稳定全局文本索引、跨段选择、复制、可见区绘制、语义和滚动交互。

验收证据：

- 10 万字符参考文档（850 段，含 CJK/emoji 代理对）上执行 40 次种子化随机跨段选择与复制：无崩溃、复制文本无孤立代理、长度等于全局区间、矩形在文档范围内（ADR 0032）。
- 文档更新后选区正确重映射（同 id 流式追加保留锚点解析）或安全失效（删除编辑清空选区）。
- 性能记录（`tool/widget_baseline_benchmark_test.dart`，交错采样 10 次取中位）：首次解析与布局核心引擎 91.7ms vs 等价 Widget 基线 106.1ms（快 14%–16%）；按 ADR 0032 重定界，40% 目标落在架构服务的更新与视口路径上：尾部追加 6.7ms vs 31.8ms（79%）、懒首屏 3.2ms vs 43.6ms（93%）、深跳停顿消除（ADR 0023/0025/0031）。
- 滚动帧耗时（`tool/scroll_frame_benchmark_test.dart`，166 帧）：median 2.5ms / p95 4.8ms / p99 13.3ms，低于 16.7/33.4ms 目标；测试环境计时含框架开销，参考设备数据以 weft_lab 为准。
- 连续滚动后缓存进入稳定预算：多轮往返后 Picture 缓存、物化命令与增量缓存按文档规模有界，不随轮次增长（ADR 0032）。
- 分块渲染（ADR 0017）、命中裁剪（ADR 0020）、单表面语义（ADR 0024/0026/0028/0030）与锚点导航（ADR 0027/0029/0031）已交付并有专门测试。

## 阶段 4：受限 JS 与能力扩展（已完成）

接入 QuickJS、单文档 Context、状态/事件/网络能力、资源中断和恢复；交付自定义标签和 FakeRuntime 契约示例（ADR 0033）。

主要验收证据：

- QuickJS 2024-01-13 源码 vendor 至 `packages/weft_quickjs/native/`，经 C 垫片（`native/weft_glue.c`，扁平 FFI ABI + JSON 编组）与 `dart:ffi` 驱动；墙钟（中断处理器）、内存（`JS_SetMemoryLimit`）、栈（`JS_SetMaxStackSize`）与微任务（任务泵计数，新增 `RuntimeFailureKind.microtaskBudget`）四类预算原生强制。`packages/weft_quickjs/tool/build_native.sh` 构建动态库，CI 从同一源码构建。
- 真实 QuickJS 测试：`while(true)` 在 120ms 预算内超时；内存炸弹命中堆上限；深递归报 stackOverflow；微任务链在预算处停止；能力调用风暴（单轮 4096 上限）与 `settle()` 256 轮兜底防止事件循环饿死。
- 能力面：`weftCapabilitiesBootstrap` 只为启用命名空间安装 JS API（真实 JS 里 `typeof weft.net === 'undefined'`）；`CapabilityGateway` 按 `CapabilityPolicy` 拒绝未启用/未安装/描述符外方法。`weft.state/events/net` 模块就绪，网络仅 GET、白名单 host、逐跳重定向校验、响应体与跳数上限，`file:`/`javascript:`/`data:` 在调用宿主客户端前被拦截（客户端调用数为 0）。
- 恢复：`WeftDocumentRuntime.recover()` 只重跑能力引导；网关按 `(sessionId, sequence)` 去重，恢复后重投递旧命令返回记账结果，网络客户端跨两轮调用恰好一次；`WeftNetworkJournal` 审计每次副作用且跨恢复保留。
- 失败隔离：脚本失败不触发布局，表面重绘命令逐项一致（UI 保留最后可用帧）；失败经 `onRuntimeFailure` 通知宿主。
- 契约与示例：`packages/weft_runtime_contract` 契约套件同时覆盖 FakeRuntime 与 QuickJS FFI 后端；`packages/weft_runtime_fake` 脚本化后端用于编排测试与实验室；`example/weft_lab` 提供 `weft-badge` 自定义标签渲染器 + FakeRuntime 状态/事件演示。
- 自定义标签：`WeftNormalizer.customTags` 保留属性驱动叶子元素（内容丢弃有诊断），`WeftTagRenderer`（rect/text ops + semanticsLabel）由引擎钳制、归属 NodeId 并转常规命令；`WeftLayoutResult.tagRegions/tagAt`、`onTagTap`、语义标签齐备；渲染器集合换实例即整页重排。

## 阶段 5：回退、硬化与发布（已完成）

完成服务端/客户端规范化一致性、WebView 回退示例、模糊测试、真机矩阵、API 文档和发布回退流程（ADR 0034）。

主要验收证据：

- 快照线格式：`WeftDocumentSnapshot` 获得规范 JSON 编解码（`WeftDocumentJson`，format+version 门禁，确定性编码、严格解码）；服务端规范化一次、客户端解码消费的一致性由 `conformance/normalization/` 下 21 个固化向量保证（11 个 conformance 语料 + 10 个合成用例），测试逐字节复现，重新生成需人工审查 diff。
- 模糊测试：`packages/weft_document/test/fuzz_test.dart`（CI 层，种子化 400+ 迭代 × 2 种子）+ `tool/fuzz.dart`（发布层，默认 2 万迭代；发布清单要求 5 万）；发布前硬化扫描发现并修复两个真实问题——诊断列表两条路径绕过 `maxIssues` 上限、`package:html` 的 `ParseError.toString()` 在敌意输入下自身崩溃（诊断生成改防御性处理）。20000 迭代扫描全净。
- 能力开关矩阵：8 个策略子集全覆盖（启用的能力探针通过、禁用的被网关拒绝且网络客户端调用数严格等于策略允许数）；JS 整体关闭 = 不开 `WeftDocumentRuntime`，`WeftView` 无 runtime 依赖。
- WebView 回退示例：`example/weft_fallback`，`decideWeftFallback` 三路决策（原生渲染 / requiresWebView → 宿主 WebView / 错误卡片），`webview_flutter` 只进示例包，widget 测试经注入占位走完整决策路径。
- 发布回退：`docs/release-runbook.md`（统一版本号策略、兼容锚点表、发布清单、回滚层级）；回滚演练自动化在 `packages/weft_document/test/release_compat_test.dart`（旧向量逐字节复现、新版本快照被拒、外格式被拒）。
- API 文档：`tool/doc_coverage.dart` 门禁（导出面的公开声明零文档缺口），已接入 `tool/check.sh`；公开 API dartdoc 已补全。
- 真机矩阵：`docs/device-matrix.md` 定义设备档位、执行步骤、通过标准与结果表；`weft_lab` 增加性能浮层开关。Android 首轮与 ADR 0036 复测数据已填入 §4.1/§4.4（CI 不可替代）；iOS 仍暂缓。
- 门禁：`tool/check.sh`（format、analyze、全包测试、doc coverage、像素黄金）全绿。

阶段 5 之后补入（不算阶段 5 验收）：

- 移动端原生构建（ADR 0035）：Android 构建/打包/真机加载与预算中断通过；iOS 暂缓。
- 懒布局窗口直物化（ADR 0036）：JNY-AL10 四项设备标准通过，严格 60fps 受 raster 限制，见 `docs/device-matrix.md` §4.4。
- 冷深跳 settling 遮罩（ADR 0037）：WeftView 宿主视口遮罩 + post-frame settling 信号；未配置 builder 时保持原空白渐进填充。
- Flutter 3.35.5 兼容基线（ADR 0038）：Flutter 依赖包与示例统一收紧下限，纯 Dart 包保持 Dart 3.5；包版本对齐到 0.7.0-dev.1，运行时行为不变。
- 语义补全（ADR 0039）：标题 headingLevel、`aria-live` live region 与有序列表 `start`/`value`；规范化保留新属性，列表一致性向量重新生成并审查。
- ARIA 基础（ADR 0040）：role 保守映射、aria-hidden/label 与 aria-atomic 整组播报；修复 aria-label 接缝错位；21 个一致性向量不变。
- 语义虚拟化（ADR 0041）：Semantics 不再触发 lazy→full 升级，直接在 lazy 结果上组装窗口化语义；语义开启的冷深跳进入 settling。
- RTL/语言属性（ADR 0042）：dir/lang 白名单、块级基方向（auto first-strong + CSS direction）、RTL 对齐/断行/列表镜像/caret 边缘、lang→locale；新增 rtl_paragraph Chrome 几何参考与第 22 个规范化向量。
- 增量布局画像（ADR 0043）：新工具 `tool/incremental_profile_test.dart` 把流式轮分解为 diff/样式/textIndex/复用走查（textIndex 占 56–81%、diff 近乎免费），测得形态阶梯（尾部追加 84–93% saving、中部编辑 44–60%、头部插入 ≈0）与 Float 逐行路径成本（30× 常数 + 段内 O(n²)）；决策下一方向为文本索引增量，引擎零改动、523 项测试不变。
- 文本索引前缀复用（ADR 0044）：流式新快照按块 diff 前缀复用索引条目、只构建后缀（共享 walker + 每块 checkpoint + 尾 trim 还原；lazy 部分前缀/头部插入/样式表变化回退全量）；新快照轮 U(2000) 19.5–23.1 → 8.8ms（−60%），appendArticle300Incremental 同机对照 7.1 → 5.8–6.0ms；增量 vs 全量逐条目相等测试守护，测试 523 → 537。
- 逐行 probe 窗口化（ADR 0045）：Float 逐行路径的断行探测从全剩余文本改为「约两行字符量起步、断点距窗口尾留 margin、翻倍直至段尾」的窗口，配 run 前缀表二分定位；8000 字段落 764 → 11.1ms（−98.5%，二次方转线性），floatWrap 6–9 → 4.8ms、float-plain 流式轮 385 → 239ms；断行行为由 8 套既有 Float/禁则/几何/像素测试钉零 diff，测试 537 → 542。
- 后缀平移（ADR 0046）：块 diff 增加反向扫描，变化区之后形状相同的块按共享垂直增量平移复用（先序 id 随中部平移——形状比较 + id 重映射是能力前提；Float 守卫与 body 级 li 截断保等价）；中部编辑 21.6 → 2.3ms、头部插入 40.9 → 2.4ms（weft_live 形态 saving ≈0% → 93%）；测试 542 → 551。
- 样式状态家族画像（ADR 0047）：E4 实验分解 lazy 流式轮——U−F = 3.3–42ms（host）而同快照地板 ≈ 0.1ms，97–99% 为每快照重付的家族工作（全量索引 T 38–63%、准入样式 S 12–18%、估算走查残差）；走查顶层样式占全量解析 ~1/4，每 resolve 成本随规则数陡增（8 → 256 条约 7–9×），float-plain 轮 99% 为走查残差；决策方向① lazy 流式轮 O(change) 化分步走（索引门放宽 → 准入/估算持久化 → 视数据走查采用）、② plain 样式跨快照采用、③ k=0 索引条目平移，行级缓存留案。引擎零改动，551 项测试不变。
- lazy 轮文本索引增量参与（ADR 0048）：_incrementalTextIndex 门按内容纯函数论证放宽（删除 blocks.length==children、保留 checkpoint 对齐与 k 守卫），lazy 部分测量窗口参与增量索引；配套修复 0044 两个潜伏缺陷（部分前缀尾 trim/drop 还原、前缀 checkpoint 播种——链式轮不再隔轮回退）；新 e4bs 滚动形态画像：尾追加轮 6.3→2.7 / 14.7→7.1 / 48.2→15.3ms（−57/−52/−68%）；WeftTextIndex 新增 debugReusedEntryCount；测试 551 → 561。

## 并行规则

CI、测试语料和文档从阶段 1 持续建设。Runtime 接口可提前用 Fake 验证，但具体业务集成不得绕过阶段 1–3 的正确性门禁。性能优化不得删除正确性测试或扩大允许误差。
