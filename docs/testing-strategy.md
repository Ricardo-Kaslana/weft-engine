# 测试与性能策略

## 测试分层

| 层级 | 内容 | 执行时机 |
|---|---|---|
| 单元测试 | 值类型、解析、级联、断行、浮动、选择映射、URL 策略 | 每次 PR |
| 契约测试 | Runtime 后端、能力 Schema、资源提供和自定义标签 | 每次 PR |
| Widget/集成 | 控制器、回退、手势、复制、语义和 Runtime 生命周期 | 每次 PR |
| 黄金测试 | 固定字体和视口的 Flutter 基线；Chromium 参考为诊断输入 | Windows CI 每次 PR；浏览器参考按需生成 |
| 模糊/属性测试 | 任意输入不崩溃、随机宽度、随机选区和脚本中止 | 烟测每次 PR，全量定期执行 |
| 真机性能 | 首次布局、帧耗时、内存、图片加载和恢复 | 候选版本及重大性能修改 |

## 当前验证入口

```bash
flutter pub get
packages/weft_quickjs/tool/build_native.sh
(cd packages/weft_quickjs && dart run tool/verify_native.dart)
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart
```

CI 在 `verify_native.dart` 失败时直接阻断，避免 QuickJS 测试因缺库被跳过却仍报绿。

外部消费者冒烟测试会从 Git 克隆当前仓库，在系统临时目录创建独立 Flutter 项目，通过 `packages/weft` Git 依赖解析并渲染 `WeftView`：

```bash
dart run tool/consumer_smoke.dart
dart run tool/consumer_smoke.dart --ref v0.7.0-dev.2
```

它验证 workspace 之外的依赖解析，不依赖本地 path 覆盖；CI 在 Linux `verify` 任务中执行。

iOS 构建/符号验证需要 macOS、Xcode 和 CocoaPods：

```bash
dart run tool/ios_smoke.dart
```

它创建临时 iOS 宿主、通过 Git 依赖引入 `weft_quickjs`、执行 `pod install` 和无签名 release 构建，并在 app bundle（Runner 或链接的 framework）中校验完整 10 个 `weft_*` 符号集合。CI 在独立 macOS 任务中执行；模拟器/真机运行仍不在 CI。

当前主 CI（2026-11-01 本地复核）覆盖格式、静态分析、纯 Dart 测试和 Flutter 单元/Widget 测试，共 587 项（weft_engine 343、weft_document 84、weft 78、weft_quickjs 28、weft_capabilities 15、weft_runtime_fake 12、weft_runtime_contract 9、weft_runtime_api 2、weft_lab 1、weft_live 8、weft_fallback 7）；具体数量以 `tool/verify.dart` 输出为准。QuickJS FFI 测试在本地 native 库缺失时会跳过；CI 在测试前执行 `packages/weft_quickjs/tool/verify_native.dart`，缺库直接失败，因此 CI 绿灯不允许以“跳过原生测试”换取。阶段 5 起还有两类门禁：规范化一致性向量（`conformance/normalization/` 22 个固化快照，逐字节复现）与公开 API 文档覆盖（`tool/doc_coverage.dart` 零缺口）；另有 Windows 独立执行的 3 项 Flutter 像素基线测试：

- 规范化：标签、属性、URL、未知元素、回退能力、节点上限、图片地址与尺寸。
- CSS：选择器结构、后代/子代匹配、特异性、内联覆盖、声明过滤。
- 布局：标题/段落、层叠、空白折叠、强制换行、列表、隐藏内容。
- Margin 折叠：父子边、padding 阻断、负 margin、空块折叠穿透、行内内容阻断和嵌套包装传播。
- 图片与 Float：属性尺寸、固有比例、max-width、alt 回退、左右浮动、跨段落环绕、CJK 环绕、clear、同侧堆叠、对侧并排和跨行链接命中。
- 表格：槽位网格、跨行跨列、caption、collapse/separate 边框、列轨道和 Chrome 几何基线。
- 选择与语义：10 万字符随机跨段选区、复制/重映射、选择手势与 chrome、标题/表头/列表/ARIA 语义。
- 分块与虚拟化：分块绘制像素等价、命中裁剪、懒布局窗口、锚点导航、settling 和增量快照复用。
- 图片资源：宿主解析、异步解码后的重新布局和资源释放。
- 稳健性：窄宽度换行、中文文本、CJK 禁则、基础 RTL 和 300 段长文档。
- 链接：跨行区域、相邻链接、非链接区域、渲染表面命中和公开回调。
- 命中裁剪（ADR 0020）：裁剪路径与全量扫描的逐点等价、chrome 散落文本命中、负 margin 跨块重叠下的扁平序、块间隙与文档外空点；`WeftView` 滚动透传（注入 controller、手势滚动、不加入 PrimaryScrollController）。
- 盒模型：content-box/border-box、最小/最大宽度、边框简写覆盖和不支持样式的降级。
- 一致性语料：12 个案例的内容、链接、盒边界、无静默丢失、无重叠和无越界检查。
- 公开层：控制器、显式回退、链接回调、图片解析器转发和渲染表面替换。
- Runtime：QuickJS 预算中断、能力网关、恢复去重、FakeRuntime 契约和 8 子集能力矩阵。

真机任务仍不在 CI（数据见 `docs/device-matrix.md`）；模糊冒烟、性能门禁与规范化一致性向量已随主 CI 执行（ADR 0034），但完整安全任务仍需发布前人工执行，不能把当前绿灯理解为产品发布门禁。像素基线覆盖三个拉丁案例（`pixel_basic`、`box_model`、`float_image`）；CJK 像素字体和跨引擎预算仍未完成，详见 `conformance/README.md`。

## 黄金一致性

目前已固定：

- Flutter 3.35.5、Windows CI runner、DPR 1、显式视口和白色背景。
- Apache 2.0 Roboto/Roboto Mono 字体文件及 Flutter `FontLoader` 别名。
- `pixel_basic`、`box_model` 和 `float_image` 三个 Flutter PNG 基线（图片案例在测试内预解码夹具）。

Flutter 黄金门禁在 Windows CI 执行 `packages/weft_engine/tool/golden_pixel_test.dart`，任何像素变化都会阻断。更新基线必须提供差异图、浏览器参考和合理原因，禁止批量无审查刷新。

Chromium 参考通过 DevTools Protocol 精确设置视口并校验运行时尺寸和 PNG 尺寸。当前跨引擎 advisory 目标为每通道容差 8、差异像素不超过 1%；实测 `box_model` 为 0.920%、`pixel_basic` 为 5.973%，后者仍未达标。

逐块几何对比显示固定字体下 Weft 与 Chromium 的 `body`、`h1`、首个段落位置完全一致（21.44 / 21.44 / 82.88），`h2` 起累计偏差小于 0.2px；剩余差异集中在字形抗锯齿和行高取整，而不是结构错位。跨引擎比较脚本输出 overlay 和放大的差异图，但在达到目标前不加入阻断 CI。

CJK 结构化布局已有测试，但尚无固定 CJK 字体，因此不提交中文像素基线，也不宣称中文像素一致。

## 长文档测试

建立固定语料和生成语料，覆盖数万至十万字符、多个段落、不同字素、左右浮动图片、表格和链接。随机选区测试同时验证：

- anchor/extent 正反向选择。
- 跨段、跨图片和跨浮动区域。
- 复制文本与逻辑模型一致。
- 宽度变化、图片晚加载和文档更新后的重映射。
- 快速滚动、自动滚动和销毁过程中的取消安全。

## 可访问性语义测试

`weft_surface_semantics_test.dart` 与 `weft_view_semantics_test.dart` 使用真实 `SemanticsOwner` 和公开 `find.semantics`/`containsSemantics` API，覆盖阅读顺序、文本不重复、链接 tap、图片 alt、标题/表头 header、标题 `headingLevel`、列表标记与 `ol start`/`li value` marker、list/table 嵌套角色父子关系、`aria-live` 的三态继承与 `liveRegion` 标志、选区 copy、流式节点身份、ExcludeSemantics 和屏外 `showOnScreen` 滚动；列表 marker 不得进入 selection/复制文本。测试必须显式 dispose `tester.ensureSemantics()` 返回的 handle；不依赖 Flutter SDK 内部 SemanticsTester，也不对无关祖先结构做全树 golden。

## 性能测量

基线必须是功能等价的“标签→Widget”实现，使用同设备、同文档、同字体和同本地资源。分别记录解析、样式、布局、首次绘制和滚动，不以单一总耗时隐藏回退。

报告 P50/P95/P99、峰值与稳定态内存，并保留原始数据。优化需先定位画像，不得仅凭主观感受接受。

## 性能门禁

`test/perf_gate_test.dart` 为固定场景提供 CI 稳定的宽松性能门禁,防止 10 倍级回归;精确数字由 `tool/layout_benchmark_test.dart` 在本机打印(每场景预热 1 次、测量 5 次取中位数,并给出最近邻秩 P95)。运行方式:

```bash
cd packages/weft_engine
flutter test tool/layout_benchmark_test.dart --no-pub             # 人工参考数字
flutter test tool/incremental_profile_test.dart --no-pub          # 增量布局画像(E0-E4)
flutter test test/perf_gate_test.dart --no-pub --timeout 120s     # CI 门禁
```

`tool/incremental_profile_test.dart` 负责增量布局画像(ADR 0043/0047):E0 把流式轮分解为 diff/样式/textIndex/复用走查,E1 测各流式形态(尾部追加、尾块增长、中部编辑、头部插入、lazy 宿主;每轮行带 entries= 字段钉索引条目采用——头部插入轮自 ADR 0051 起非零),E3 测 Float 宿主路径与逐行环绕标度,E4 测「样式与状态跨快照」家族(走查顶层/全量样式对照、lazy 轮差分分解 U−F−T−S 及滚动视口变体 e4bs、样式表规模敏感性、float-plain 残差、大样式表流式轮 e4f),并断言 lazy 同快照轮零准入、新快照轮必付准入(ADR 0049 起只计后缀访问);print 报告并按形态契约断言复用计数,不进 CI 门禁。增量优化动手前先跑它留底,改完在同一实验组复测比较成分与形态中位数;桌面 Stopwatch 只做相对比较,不当真机帧耗时。

| 场景 | 内容(宽度 360) | 实测中位数(Windows 开发机,2026-10) | 门禁上限 |
|---|---|---|---|
| article300 | 300 段中英混排文章,每 10 段一个标题,段内含强调与链接 | ~42–56 ms | 600 ms |
| appendArticle300Full | article300 尾部追加第 301 段,不使用 previous,永久保留全量对照 | 改前 ~37.3 ms;改后同轮 ~31.8 ms | 500 ms |
| appendArticle300Incremental | 同一追加场景,旧 300 段布局在计时前准备,计时内复用前缀并释放旧/新结果 | ~6.7 ms;文本索引前缀复用后 ~5.8–6.0 ms(同机对照改前 7.1 ms,ADR 0044) | 500 ms |
| lazyArticle300FirstViewport | article300 通过 RenderWeftSurface 懒布局首屏,800px 视口 + 250px overscan;结构探针记录实际布局/物化块数 | ~3.2 ms,首屏 6/6 块(全量 ~43.6 ms、330 块) | 500 ms |
| table48 | 48 行 × 6 列表格,collapse 边框、padding,每 7 行一个 rowspan=2、每 5 行一个 colspan=2 | ~26–28 ms | 500 ms |
| floatWrap | 10 组左浮动 120×96 假图(`ui.PictureRecorder` 生成)+ 长 CJK 段落逐行环绕 | ~6–9 ms;probe 窗口化后 ~4.8 ms(ADR 0045) | 500 ms |
| selection300 | 在 article300 布局结果上取跨 10 段(第 100–110 段)的选区,调用 `selectionRects` | ~0.7–0.9 ms(2026-10 末复测 ~1.8–1.9 ms,属环境漂移:改动暂存对照运行同为 ~1.9 ms) | 500 ms |
| paintArticle300Direct | 直绘 article300 全部命令到新画布(ADR 0017 分块前的全量重绘路径,作为基线保留) | ~1.7–2.1 ms | 500 ms |
| paintArticle300Full | `RenderWeftSurface` 分块绘制,可见区域 = 整篇文档(全部块命中) | ~0.9–1.1 ms | 500 ms |
| paintArticle300Window | `RenderWeftSurface` 分块绘制,800px 高窗口置于文档纵向中部 | <0.1 ms | 500 ms |
| hitAnchorTop | 对挂载文档的 article300 布局结果调用一次 `anchorAt`,点取文档顶部首个文本字形中心(ADR 0020) | 改前 ~20 µs → 改后 ~3 µs | 500 ms |
| hitAnchorMiddle | 同上,点取文档中部 | 改前 ~11 µs → 改后 ~2–3 µs | 500 ms |
| hitAnchorBottom | 同上,点取文档底部 | 改前 ~2 µs → 改后 ~3 µs | 500 ms |
| hitLinkArticle | 同一布局调用一次 `linkAt`,点取中部链接矩形中心 | 改前 ~8 µs → 改后 ~1 µs | 500 ms |

上限 = 实测中位数的 10 倍,向上取整到整百 ms,下限 500 ms(中位数低于 50 ms 的场景直接取 500 ms)。上限刻意放宽,原因:

- 门禁只测预热后的单次运行,不做多次采样,单次噪声本身可达中位数的数倍;
- CI runner 与开发机的性能差异、虚拟化和并发任务抖动都远小于 10 倍余量;
- 目标是拦截"数量级变慢"的回归(如缓存失效、重复文本测量、浮动语境下的整段重排),不追精度;真实画像仍按"性能测量"一节的方法离线采集 P50/P95/P99。

命中场景(hit*)的单次调用在微秒量级,基准工具对它们以 µs 打印;其门禁全部落在 500 ms 下限,只能拦截灾难性(千倍级)回归,精确对比以上表的改前/改后数字为准。改前数字在落地裁剪前测得(未挂载快照、全量逐命令/逐链接扫描的路径),改后为挂载快照后的分块裁剪路径(ADR 0020);两轮测量同为 1 次预热 + 5 次采样取中位数。

分块渲染等后续优化的对比方法:动手前先跑基准工具留底,改完后在同一场景上复测并比较中位数(以中位数为准,不看单次最快值),同时确认门禁仍绿;若中位数改善明显,可按同一规则(10 倍、取整到整百、下限 500 ms)收紧上限并更新本表。场景构造代码在基准工具与门禁测试中保持逐字一致,改动任一侧必须同步另一侧,否则上限与场景失去对应关系。

分块渲染(ADR 0017)按此方法落地:paintArticle300Direct 直绘全部命令,是分块前 paint 的基线场景,永久保留;paintArticle300Full/Window 走 `RenderWeftSurface.debugPaintChunks` 生产路径(基准与门禁均以预热建好 Picture 缓存后的稳态绘制为测量对象)。分块只允许改变执行方式,不允许改变输出:块绘制与直绘的逐字节像素等价由 `test/chunked_rendering_test.dart` 固化,黄金基线不因分块调整。

命中裁剪(ADR 0020)按同一方法落地:hitAnchor*/hitLinkArticle 的计时体恰为一次 `anchorAt`/`linkAt` 调用,基准与门禁均以预热建好命中索引后的稳态解析为测量对象。裁剪只允许改变执行方式,不允许改变结果:裁剪路径与全量扫描的逐点一致(含块间隙空点、chrome 散落文本、负 margin 跨块重叠)由 `test/hit_culling_test.dart` 固化。

流式增量布局(ADR 0023)保留 appendArticle300Full 作为永久全量对照;Incremental 的旧 300 段布局在计时外准备,每次运行使用独立 previous,避免所有权转移后重复消费。`test/incremental_layout_test.dart` 固化连续快照、尾段增长、失效回退、dispose 生命周期及与全量结果的几何/命中/选区/像素等价;`test/chunked_rendering_test.dart` 另行断言未变前缀 Picture 不重录。

锚点导航(ADR 0027/0029)测试覆盖：有效 anchor 使用 lazy focus 测量并物化目标块、无效/末尾 anchor 不布局、alignment 公式与滚动范围 clamp、注入/内部 controller、连续请求以及卸载后丢弃 post-frame 回调。异步模式额外验证单 pass 布局块数不超过预算、measuredPrefix 单调推进，以及逐帧测量期间当前内容与 offset 保持不变。

布局虚拟化(ADR 0025)的验收分两层:计时对比 lazy 首屏与 full article300,结构计数则断言首屏只布局/物化连续可见前缀,且必须远小于全文块数。`test/lazy_layout_test.dart` 覆盖精确前缀、冷跳收敛、结构化内容、multi-screen 正反向、首帧 selection、空命令块,以及嵌套图片 Float checkpoint 的多代往返、extent 和准入矩阵;`weft_view_lazy_test.dart` 覆盖滚动、初始 offset、约束变化、默认/强制 eager、底部校正、流式、Float 回退与 selection 升级,并验证 full 升级会清除 stale follow/pending 校正。语义虚拟化(ADR 0041)由 lazy 套件断言 Semantics 保持 lazy、窗口化标签随滚动物化出现、band 内未物化块折叠为粗叶子且 showOnScreen 可达;`weft_view_semantics_test.dart` 覆盖未测后缀暂无节点与 band 内离屏内容滚动到位。

冷深跳 settling(ADR 0037)由 `weft_view_settling_test.dart` 覆盖遮罩出现/消失、回调 true→false 序列、无 builder 时信号仍工作、近 frontier 与异步锚点不触发、底部跟随、文档替换/selection 复位与语义开启的深跳 settling(ADR 0041),以及 settled 后无额外帧调度;`lazy_layout_test.dart` 额外覆盖 surface 级回调序列、lazy 退出与文档替换复位、同 id 流式更新。

RTL 基础方向(ADR 0042)由 `test/rtl_layout_test.dart` 覆盖对齐几何、`dir=auto` first-strong 解析、嵌套 dir/CSS direction 覆盖、lang→locale、列表缩进与 marker 镜像、Float 逐行断行推进和 caret 行内首侧;`test/rtl_paragraph_geometry_test.dart` 对 `conformance/reference/rtl_paragraph.geometry.json` 比较 10 个元素的方向敏感文本边缘(±2px),该 case 不参与泛化盒级几何对比(Chrome RTL 列表盒落位差异,ADR 0042 记录)。

## Runtime 安全测试

至少包含无限循环、递归爆栈、内存炸弹、微任务风暴、超大桥接消息、队列积压、非法 URL、重定向越权、取消、销毁竞争和恢复后的副作用去重。测试必须验证整个宿主没有继续暴露已撤销能力。

能力策略矩阵（ADR 0034）覆盖 built-in 能力的全部 8 个子集：启用者探针通过、禁用者被网关拒绝且网络副作用严格为零；bootstrap 只引用启用命名空间。JS 整体关闭即不打开 `WeftDocumentRuntime`（渲染路径无 runtime 依赖）。

## 模糊测试与发布门禁（ADR 0034）

- CI 层：`packages/weft_document/test/fuzz_test.dart` 对 conformance 语料 + 一致性向量做种子化变异（400+ 迭代 × 2 种子），不变量：无异常逃逸、issue 数不超上限、节点 id 唯一且父子递增、body/normalizedHtml 一致、抽样 JSON 往返字节稳定。
- 发布层：`tool/fuzz.dart --iterations 50000`（发布清单要求）长跑，崩溃输入写入 `build/fuzz/` 复现；已发现并修复诊断上限绕过与 `ParseError.toString()` 崩溃。
- 回滚演练：`packages/weft_document/test/release_compat_test.dart`（旧向量逐字节复现、新版本快照被拒、外格式被拒、兼容锚点与 docs/release-runbook.md §2 一致）。
- 文档覆盖：`tool/doc_coverage.dart` 扫描导出面公开声明，要求 `///` 零缺口，已接入 `tool/check.sh`。

阶段 4 已交付（ADR 0033，证据见 `packages/weft_quickjs/test/quickjs_session_test.dart`、`packages/weft_capabilities/test/capability_modules_test.dart`、`packages/weft/test/weft_document_runtime_test.dart`）：无限循环墙钟中断、内存炸弹、递归爆栈、微任务风暴、非法协议与重定向越权拦截、恢复后的副作用去重、销毁后的执行拒绝、`weft_runtime_contract` 的后端中立契约套件。尚未覆盖：超大桥接消息、队列积压与取消令牌。
