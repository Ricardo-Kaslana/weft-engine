# Weft 交接说明

本文用于把当前项目交给另一个 Agent（Codex、其它 IDE Agent 或人工团队）继续开发。先读“交接提示词”，再按需阅读后面的状态与约束。

## 交接提示词（可直接粘贴）

```text
你接手 Weft：一个面向 Flutter 的受控 HTML/CSS 渲染引擎，用于 CMS 文章、商品描述、帮助文档和 AI 流式内容，目标是替代这些场景下的 WebView。

当前代码已经实现并可测试：
- 受控 HTML 规范化、标签/属性白名单、结构化 CSS 选择器与层叠。
- Block/Inline 布局、空白折叠、CSS 2.1 margin 折叠、半行距、块级宽度/box-sizing/solid 边框。
- 链接跨行命中、宿主图片解析、块级图片、左右 Float、clear 和跨段落文字环绕。
- 表格：table 系标签、colspan/rowspan（含隐式行）、caption、separate/collapse 边框、border-spacing 和 vertical-align。
- 逻辑文本索引与选区解析：跨段锚点→视觉矩形与复制文本，表面绘制选择高亮。
- 分块渲染（ADR 0017）：按块缓存 ui.Picture、可见窗口裁剪、选区矩形与 caret 独立缓存；命中解析经分块索引裁剪（ADR 0020）。
- 行内图片基线混排（ADR 0018）：img 默认 inline 原子参与断行，CSS 宽高（含百分比宽）。
- 块级盒模型（ADR 0021）：显式 height（不裁剪溢出）、百分比宽度、水平 auto margin。
- 表格列轨道（ADR 0022）：colgroup/col 声明 px 固定列、百分比列与 span 轨道。
- 流式增量布局（ADR 0023/0044/0046）：复用无 Float 的顶层前缀块/TextPainter，尾部重排；未变 Picture 跨快照复用；文本索引按块 diff 前缀复用条目（plain 与 lazy 部分窗口，ADR 0044/0048），变化区之后的形状相同块平移复用（plain，ADR 0046）；lazy 轮的准入结论与逐子估算按已证前缀沿用（ADR 0049），plain 复用块样式成对沿用（ADR 0050），头部插入/头删除轮的旧索引条目平移重映射（plain，ADR 0051）——四种流式形态 plain 91–97% saving，lazy 滚动会话轮 0047 基线 −77–84%。
- 可访问性语义（ADR 0024/0026/0028/0030）：单表面文本/链接/图片/选区、标题与表头 header、列表标记、list/table 嵌套角色、链接 tap、选区 copy、稳定节点 id 与屏外 showOnScreen。
- 渐进式布局虚拟化（ADR 0025/0041）：WeftView 只物化可见顶层块，估算后缀 extent，复杂文档/选区回退 full；Semantics 直接在 lazy 结果上组装窗口化语义（物化窗口精确、视口附近未物化块粗叶子、未测后缀滚动物化后出现）。
- 锚点导航（ADR 0027/0029）：`scrollToAnchor` 同步 focus 定位，`scrollToAnchorAsync` 逐帧测量深链前缀并保持当前内容；无效/取消安全返回 false。
- 懒布局异步分帧与同快照复用（ADR 0031）：非锚点深跳/深 seed 每帧至多新测 32 个顶层块并逐帧收敛，消除冷跳底部单帧全量测量；同快照 relayout 跳过节点 diff、复用跨帧样式缓存与文本索引实例。
- 已测窗口直物化（ADR 0036）：保守区间索引、缓存块流与后缀估算、格式化空白准入、Float 上下文恢复、correctBy 后视口同步；JNY-AL10 profile 已验收。
- 选择交互（ADR 0019）：长按选词/拖拽扩展/把手微调/复制按钮/tap 放 caret。
- 图片/Float 与表格的浏览器几何基线（Chrome 参考固化在 conformance/reference/）。
- 移动端原生构建（ADR 0035）：`weft_quickjs` 声明为 ffiPlugin；Android 模块用 CMake 就地编出 `libweft_quickjs.so`（16 KB 页对齐、只导出 `weft_*`），iOS pod 把垫片静态编进 app image 并用 ObjC 锚点防止 dead-strip；加载器按平台分派，显式路径可覆盖。

请继续下一个切片，优先级如下：
1. D1 RTL/语言属性已完成（ADR 0042）：`dir`/`lang` 白名单、块级基方向（含 `dir=auto` first-strong 检测与 CSS `direction`）、RTL 对齐/断行/列表镜像/caret 边缘、lang→locale、语义 textDirection 透传；`rtl_paragraph` Chrome 几何参考钉住方向边缘。C3 语义虚拟化（ADR 0041）、C2 ARIA 基础（ADR 0040）、C1（ADR 0039）、C0（ADR 0038）与 B2（ADR 0037）此前已完成。**增量布局画像（ADR 0043）与三方向全部落地：①文本索引增量（ADR 0044，U(2000) −60%、appendIncremental 7.1 → 5.8–6.0ms）；②逐行 probe 窗口化（ADR 0045，8000 字段落 764 → 11.1ms −98.5% 二次方转线性、floatWrap 6–9 → 4.8ms）；③后缀平移（ADR 0046，中部编辑 21.6 → 2.3ms、头部插入 40.9 → 2.4ms——weft_live 形态 saving ≈0% → 93%；plain 路径，先序 id 经形状比较 + 映射重写）。plain 宿主流式四形态全部进入 91–95% saving 档。「样式与状态跨快照」家族画像已交付（ADR 0047）：lazy 流式轮 97–99% 是每快照重付的家族工作（全量索引 T 38–63%、准入样式 S 12–18%、估算走查残差），真机 4× 后所有规模超帧预算。方向①(a) 文本索引增量参与已交付（ADR 0048）：参与门按内容纯函数论证放宽，lazy 部分测量窗口复用索引条目；配套修复 0044 两个潜伏缺陷（部分前缀尾 trim/drop 还原、前缀 checkpoint 播种——链式轮不再隔轮回退）；滚动会话尾追加轮 −52–68%（e4bs 形态）。①(b) 准入与估算前缀采用已交付（ADR 0049）：diff 已证前缀沿用上一轮准入结论与逐子估算（`_LazyChild` 克隆重绑 element），只验证/重建后缀；同机对比滚动轮再降 −22/−36/−46%，准入访问后缀化（931→111@300）。①(c) 种子消费/走查后缀采用已按数据降级缓办（剩余池 ~1–1.7ms@2000、机制最重，留案）；方向② plain 走查样式跨快照采用已交付（ADR 0050）：diff 已证顶层子成对种子化上一轮样式，E4f 同机 A/B 8 条规则 −27%、256 条 −60%——复用轮与样式表规模脱钩。方向③ k=0 头部插入的索引条目平移已交付（ADR 0051）：`buildFromSuffix` 接缝标志比对 + 逐子走查或采用（流首剥离分歧 fresh 回退），E1 head-insert 同机 A/B @300 2.11→1.16–1.38ms、@1000 7.82→3.02–3.09ms。0047 家族清单全部销账；下一步 = 按「先画像再选择」重新画像剩余轮成本（或先测 mid-edit 后缀采用推广的后缀走查份额）；行级缓存继续留案（E4e 记收益上界）。不要再改 layout/overscan、重复后端 A/B，或把遮罩当成零空白；禁止把桌面 layoutViewport 画像当真机帧耗时。**
2. 语义真机抽查：C1 只在 `SemanticsOwner` 层验证 headingLevel/liveRegion 标志，尚未在 TalkBack/Web 读屏上验收播报；若产品需要，按 JNY-AL10 手动验证标题导航和 live region 播报并记录到 device-matrix。
3. 深跳尖峰定性：ADR 0036 复测已把 FrameTiming 拆成 build/raster，~313ms 尖峰未复现且全程无 >50ms 帧；若再现，按 §4.4 的 build/raster 方法继续定位。
4. iOS 构建与真机验证（**暂缓**：暂无 macOS 环境）：按 docs/device-matrix.md §2.2 清单执行；未验证前 iOS 不得宣称可用，发布说明要写明缺席。
5. 语义/增量布局后续：按产品需要，见下文「建议的下一步」。

硬性约束：
- 不做完整浏览器；不执行不可信脚本；不把 HTML 节点映射为独立 Widget。
- 不支持的内容必须生成 SupportReport 并显式回退。
- 图片资源只能由宿主 WeftImageResolver 提供；引擎不得隐式发起网络请求。
- 每次修改必须运行 `dart format --output=none --set-exit-if-changed .`、`dart analyze`、`dart run tool/verify.dart` 和 `packages/weft_engine/tool/golden_pixel_test.dart`。
- 新增能力必须附带单元测试；影响布局时必须评估黄金基线与 conformance/reference/ 下的浏览器几何基线。
- 改动 `packages/weft_quickjs/native/`、`android/` 或 `ios/` 后必须跑 `packages/weft_quickjs/tool/build_native.sh` 重编桌面库并执行 `dart test`（weft_quickjs）；平台工程的编译参数必须与桌面脚本保持一致（ADR 0035）。
- 重要技术取舍写入 docs/adr/（下一个编号为 0052）。

接手前先知道的坑（本轮实测踩出来的，能省你几个小时）：
- 历史上美化排版会关掉懒布局，首帧退化成 1801 节点全量排版（198–280ms）。ADR 0036 已在窗口化之后接入 ASCII 格式化空白，但保留了正文/NBSP/pre 的 full 边界；旧真机数字不能用于宣称改后通过，详见 device-matrix §4.3/§4.4。
- profile 构建卡 5 分钟不是编译慢：Gradle 要下 41.6MB 的 `arm64_v8a_profile` jar，本机镜像不提供 `.sha1`、吞吐还会掉到 1.6MB/s，30s socket 超时后反复重试。先查 `~/.gradle/caches/modules-2/files-2.1/io.flutter/` 里 jar 是否真的存在；缺就手动下好按 `<文件sha1>/<原文件名>` 放进去，并给 app 的 `gradle.properties` 加 `socketTimeout`。
- 插件的 ABI 裁剪必须用 `defaultConfig.externalNativeBuild.cmake.abiFilters`；`ndk.abiFilters` 管不住 externalNativeBuild（实测仍编 4 个 ABI）。
- 探针流程：临时 App 放 `build/perf_probe`（gitignored），必须临时加入根 `pubspec.yaml` 的 `workspace:` 才能解析；退出后只撤销本轮添加的 workspace 项和锁文件差异，不用整文件 checkout 覆盖用户改动。探针 Dart 文件也会被根 format 扫到；运行期间门禁使用 `WEFT_KEEP_LOCK=1 tool/check.sh`，结束后清理再重跑。
- 设备掉线/unauthorized 先试 `adb kill-server && adb start-server`；`tool/check.sh` 输出用文件重定向再看 `$?`，`| tail` 会掩盖退出码。

先阅读 README.md、docs/architecture.md、docs/supported-subset.md 和 docs/handoff.md，再选择第一个任务并给出计划。

开发工作流提示（ADR 0014）：用 `tool/check.sh` 做本地门禁；新增几何案例走 `--emit-reference` 接入通用门禁，零测试代码；调布局用 `tool/dump_layout.sh --diff` 直接看偏差表；表格改动落在 `table_layout.part.dart`、行内/Float 改动落在 `inline_flow.part.dart`，两边可并行。
```

## 当前仓库状态

- 分支：`main`
- 最新提交：见 `git log`（本节只保证指南有效，不追踪哈希）
- Flutter：3.35.5 stable（引擎/示例编译下限，ADR 0038）；Dart：3.9.2；ADR 51 份（0001–0051）；包版本 0.7.0-dev.1
- 常规测试 587 项（weft_engine 343、weft_document 84、weft 78、weft_quickjs 28、weft_capabilities 15、weft_runtime_fake 12、weft_runtime_contract 9、weft_runtime_api 2、weft_lab 1、weft_live 8、weft_fallback 7；D1 新增 14 项，增量布局画像与三方向新增 28 项、样式状态画像与 lazy 索引参与新增 10 项、lazy 前缀采用新增 11 项、plain 样式采用新增 7 项、头部插入条目平移新增 8 项）、像素黄金 3 项 + 选区高亮 1 项、性能门禁 14 场景（7 布局 + 3 绘制 + 4 命中）+ 增量布局画像工具（ADR 0043/0047，手动运行）；`dart analyze` 无问题，公开 API 文档覆盖零缺口。开发计划阶段 0–5 已完成（阶段 5 见 ADR 0034），阶段 5 之后补了移动端原生构建（ADR 0035）、懒布局窗口直物化（ADR 0036）、冷深跳 settling 遮罩（ADR 0037）、Flutter 3.35.5 兼容基线（ADR 0038）、语义补全（ADR 0039）、ARIA 基础（ADR 0040）、语义虚拟化（ADR 0041）、RTL/语言属性（ADR 0042）、增量布局画像及三方向优化（ADR 0043–0046）、样式状态家族画像（ADR 0047）、lazy 轮文本索引增量参与（ADR 0048）、lazy 准入估算前缀采用（ADR 0049）、plain 走查样式跨快照采用（ADR 0050）与 k=0 头部插入索引条目平移（ADR 0051）。
- GitHub Actions 使用 Windows 执行像素黄金门禁（仓库尚无远端，CI 尚未真正跑过）。
- 2026-10-28 增量：Android 真机构建与执行验证、插件单 ABI 裁剪、回环直连修复与首轮矩阵；之后交付 ADR 0036 窗口直物化及桌面结构/耗时证据（docs/device-matrix.md §4.4）。真实 Flutter Web＋Edge 的滚动、锚点与选择复制已验证；JNY-AL10 profile 复测四项标准通过（中位冷启 635ms、滚动 p95 ≈26ms、深跳最大 37ms、内存 +10MB），strict 60fps 受 raster 限制。证据位于本地 build/adr0036-evidence。iOS 验证仍暂缓。
- 2026-10-31 增量：B1 后端 A/B 完成（12 Impeller + 12 Skia，ABBA，JNY-AL10 profile，24 轮全部有效）。PAINT_ONLY 与 SCROLL 的 raster/total 均无显著差异（SCROLL total p95 中位 25.70 vs 24.49ms，p=0.33；PAINT_ONLY stable raster p95 8.77 vs 9.75ms，p=0.42），唯一显著项是 SCROLL build p95 差 0.38ms，无实际意义。结论：不建议旧 Mali 关闭 Impeller；strict 60fps 仍未达成。证据在本地 `build/adr0036-evidence/b1/`，详见 device-matrix §4.7。
- 2026-10-31 增量（B2）：冷深跳 settling 交付（ADR 0037）。`WeftView.lazySettlingBuilder` 在分帧测量期间渲染宿主视口遮罩；`onLazySettlingChanged` 与 `WeftViewState.isLazySettling` 从 post-frame 报告起止，未配置 builder 时树与黄金不变。引擎不改布局预算/overscan/后端，也不伪造未测量块；首帧仍可能空白，遮罩不加速测量。Android 验收（遮罩 544ms、29 帧收敛、无 >50ms 帧；异步/近距不触发）与证据见 device-matrix §4.8。
- 2026-10-31 增量（C0）：Flutter 3.35.5 兼容基线（ADR 0038）。所有 Flutter 依赖包与示例声明 `flutter: ">=3.35.5"`，纯 Dart 包保持 Dart 3.5；包版本统一升到 0.7.0-dev.1。此前的 3.22 下限与实际 `SemanticsRole` 依赖不符，3.22–3.34 宿主无法编译。无运行时行为、快照/bridge 契约或黄金变化，测试仍为 491 项。
- 2026-10-31 增量（C1）：语义补全（ADR 0039）。`h1..h6` 输出 `headingLevel`；显式 `aria-live` 子树按三态继承标记叶子 `liveRegion`（`polite/assertive` 统一为布尔，`off` 关闭）；`ol start`/`li value` 同时控制视觉 marker 与语义 marker。规范化器保留三个新属性、非法值丢弃并诊断；`synthetic_lists_and_quotes` 向量随 `<ol start>` 保留重新生成，其余 20 个向量未变。无新语义容器，像素黄金不变。
- 2026-10-31 增量（C2）：ARIA 基础（ADR 0040）。规范化器全局保留 `role`/`aria-hidden`/`aria-atomic`/`aria-label`（修复了自定义标签引擎在读而标准标签被丢弃的错位）；语义层保守映射 `role`——button/link 走 isButton/isLink flag（无激活动作）、img/heading 折叠或派生 header/headingLevel、dialog/alertdialog 成容器角色、alert/status 隐式化为 live+atomic、presentation/none 抑制自身派生语义（内容仍朗读）、其余丢弃并产出 `aria.role.unsupported`（info）；显式 role 覆盖隐式语义。`aria-hidden=true` 子树移出语义树（视觉与复制文本不变）。`aria-label` 在 img 上优先于 alt，其他元素折叠为单个命名叶子（table 族排除，`<a aria-label>` 保留 tap）。live region 内 `aria-atomic=true` 整组播报，替代 C1 的逐叶子播报。21 个规范化向量不含新属性，逐字节不变；布局/绘制/像素黄金不变。测试 495 → 508。
- 2026-10-31 增量（C3）：语义虚拟化（ADR 0041）。`assembleSemanticsNode` 删除 `'semantics'` full 升级，直接在 lazy 结果上组装：物化窗口块精确（现状逻辑不变）、已测未物化且在视口 ±2–3 屏 band 内的块折叠为逐块粗叶子（key `block:<id>`、label 为 textIndex 扁平文本、rect 为保留几何带）、未测后缀滚动物化后出现；band 外不产出。selection/anchor/image/engine-fallback 的 full 升级与粘滞全部不变。语义开启的冷深跳现在真正触发 settling 遮罩与 `onLazySettlingChanged`；`scrollToAnchorAsync` 在语义开启时照常分帧。粗→精升级节点 key 变化（辅助技术重新聚焦）。布局/绘制/像素黄金不变；21 个向量不变。测试 508 → 509（重写 5 项契约测试、新增 1 项）。真机语义滚动帧耗时未验证（无设备在线）。
- 2026-10-31 增量（增量布局）: 画像与三方向优化（ADR 0043–0046）。`tool/incremental_profile_test.dart` 把流式轮分解为 diff/样式/textIndex/复用走查（textIndex 56–81%、diff 近乎免费）并测得形态阶梯；文本索引按前缀复用条目（U(2000) −60%）；Float 逐行 probe 窗口化（8000 字段落 764 → 11.1ms，二次方转线性）；后缀平移（中部编辑 21.6 → 2.3ms、头部插入 40.9 → 2.4ms，weft_live 形态 saving ≈0% → 93%）。plain 宿主四种流式形态全部进入 91–95% saving 档；向量与像素黄金零 diff。测试 523 → 551。真机帧耗时未测（桌面 Stopwatch 仅相对比较）。
- 2026-10-31 增量（样式状态画像）: 「样式与状态跨快照」家族画像（ADR 0047）。E4 实验测得 lazy 流式轮 U−F = 3.3–42ms（host，300–2000 块）而同快照地板 ≈ 0.1ms——97–99% 是每快照重付的家族工作；成分 = 全量索引 T 38–63%（增量门要求前缓存覆盖全文，lazy 部分窗口恒不满足）+ 准入样式 S 12–18% + 估算走查残差；样式每 resolve 成本随规则数陡增（8 → 256 条约 7–9×）；float-plain 轮 99% 为走查/逐行残差（行级缓存收益上界）。决策：① lazy 流式轮 O(change) 化（索引门放宽 → 准入/估算持久化 → 视数据走查采用）→ ② plain 样式跨快照采用 → ③ k=0 索引条目平移；行级缓存留案。引擎零改动，551 项测试不变；桌面绝对值受后台负载影响（两轮 ~1.4× 波动），份额与结构计数稳定。
- 2026-10-31 增量（lazy 索引增量）: ADR 0047 决策 ①(a) 交付（ADR 0048）。`_incrementalTextIndex` 门按内容纯函数论证放宽——lazy 部分测量窗口参与增量索引；配套修复 0044 两个潜伏缺陷：部分前缀内尾 trim/drop 条目还原（今日 plain 中部编辑即可触发的腐蚀）与前缀 checkpoint 播种（增量产物 checkpointCount==children，链式轮不再隔轮回退）。新 e4bs 滚动形态：尾追加轮 6.3→2.7 / 14.7→7.1 / 48.2→15.3ms（−57/−52/−68%）；E4b fresh 与 E1 lazy 形态持平（窗口界住），head-insert k=0 仍全量。WeftTextIndex 新增 debugReusedEntryCount。测试 551 → 561。
- 2026-11-01 增量（lazy 前缀采用）: ADR 0047 决策 ①(b) 交付（ADR 0049）。决策块重排为 diff 先行 + `_admitLazyLayout`：前 verdict 沿用 + 只验证 raw 后缀（provisional allowLazy 不合格时重跑 plain 模式 diff 保后缀平移）；`_prepareLazyState` 前缀段采用上一轮 `_LazyChild`（element 重绑），边界 pendingMargin/leading/orderedItem 零歧义恢复，`_minimumPaintOffset` 硬断言隐患从构造上消除。同机对比滚动轮 2.01→1.57 / 6.02→3.88 / 12.76→6.94ms（−22/−36/−46%），eligibility 后缀化（931→111）；家族累计 0047 fresh U(2000) 30.8–42.4 → 6.9ms（−77–84%），真机 4× 后 300 档首次进入 8ms 预算。`debugEligibilityVisitCount` 语义收窄为后缀访问。测试 561 → 572。
- 2026-11-01 增量（plain 样式采用）: ADR 0047 决策 ② 交付（ADR 0050），①(c) 按数据降级缓办。决策块在 reusedMaps 终态后成对种子化：前缀连续正扫 + 后缀尾逆扫，把上一轮 styleCache 的顶层样式写进新缓存（前提 = `_sameNode`/`_sameNodeShape` + 样式表签名 + body 壳 + tagRenderers 身份；lazy 前缓存缺条目自然断首、优雅退化）。E4f 同机 A/B：mid-edit@300 轮 8 条规则 2.61→1.91ms（−27%）、256 条 29.14→11.66ms（−60%）——复用轮与样式表规模脱钩，剩余为 diff + 后缀克隆。新增 `debugAdoptedStyleCount`。测试 572 → 579。
- 2026-11-01 增量（头部插入条目平移）: ADR 0047 决策 ③ 交付（ADR 0051），家族清单全部销账。`WeftTextIndex.buildFromSuffix`：头部子 fresh 走查后，carried 子逐个比对接缝四标志（hardBreaks/blockBreakPending/lastEmittedBreak/atLeadingEdge）——相等则旧条目平移 + `ids` 重映射采用并止，不等则 fresh 走查该子（流首剥离分歧唯一信号，走满即等价全量构建）；尾 trim/drop 还原为 0048 镜像；头部走查镜像 body 级 `blockBreakPending` 初值。探索钉死：旧 body 含体级 text 子时 0046 缓存门整体拒绝 diff（部分采用仅在新侧插入空白时可达）。E1 head-insert 同机 stash A/B：@300 2.11→1.16–1.38ms、@1000 7.82→3.02–3.09ms（entries=0→1500/5000 钉参与），head-insert 与 mid-edit 反差消失。E1 每轮行新增 `entries=` 读数。测试 579 → 587。

已实现至 ADR 0051（Android 四项设备标准已通过，strict 60fps raster 待优化；B2 冷跳 settling 遮罩已交付；C0 兼容基线已交付；C1 语义补全已交付；C2 ARIA 基础已交付；C3 语义虚拟化已交付；D1 RTL/语言属性已交付；增量布局画像与三方向优化、样式状态家族画像、lazy 轮文本索引增量参与、lazy 准入估算前缀采用、plain 走查样式跨快照采用、k=0 头部插入索引条目平移已交付）。ADR 0042：RTL 基础方向与语言属性——dir/lang 白名单、块级基方向（auto first-strong + CSS direction）、RTL 对齐/断行/列表镜像/caret 边缘、lang→locale（缺省 zh 零回归）、语义 textDirection；rtl_paragraph Chrome 几何参考。ADR 0043：增量布局画像——流式轮成分分解（textIndex 56–81%、diff 近乎免费）与形态阶梯，方向选择的数据依据。ADR 0044：文本索引前缀复用——流式新快照按块 diff 前缀复用条目、只构建后缀，未命中回退全量。ADR 0045：逐行 probe 窗口化——Float 断行探测窗口化，fit 前缀单调保证断点不变。ADR 0046：后缀平移——变化区之后形状相同的块按共享垂直增量平移复用，先序 id 经形状比较 + 映射重写；Float 守卫与 body 级 li 截断保等价。ADR 0047：样式状态家族画像——E4 测得 lazy 流式轮 97–99% 为每快照重付的家族工作（全量索引 T 38–63%、准入样式 S 12–18%、估算走查残差）与样式表规模敏感性（每 resolve 随规则数陡增），决策 lazy 流式轮 O(change) 化三步走。ADR 0048：lazy 轮文本索引增量参与——参与门按内容纯函数放宽，lazy 部分窗口复用条目；修复 0044 的部分前缀尾 trim/drop 还原洞与前缀 checkpoint 播种（链式轮不再隔轮回退）；滚动会话尾追加轮 −52–68%。ADR 0049：lazy 准入估算前缀采用——diff 已证前缀沿用上一轮准入结论与 `_LazyChild` 逐子估算（element 重绑），只验证/重建后缀，provisional allowLazy 不合格重跑保 plain 后缀平移；滚动轮同机再降 −22/−46%。ADR 0050：plain 走查样式跨快照采用——diff 已证顶层子成对种子化上一轮样式，复用轮与样式表规模脱钩（E4f A/B 256 条规则 −60%）；①(c) 按数据降级缓办。ADR 0051：k=0 头部插入索引条目平移——`buildFromSuffix` 接缝标志比对 + 逐子走查或采用，旧条目平移 + ids 重映射（流首剥离分歧 fresh 回退；E1 A/B @1000 −60%）；mid-edit 后缀采用推广留案。ADR 0041：语义虚拟化——Semantics 不再升级 full，lazy 结果上组装窗口化语义（物化窗口精确、band 内未物化块粗叶子、未测后缀滚动物化后出现）；语义开启深跳进入 settling。ADR 0040：ARIA 基础——role 保守映射、aria-hidden/label 与 aria-atomic 整组播报；修复 aria-label 接缝错位；21 个规范化向量不变。ADR 0039：语义补全——headingLevel、`aria-live` live region 与有序列表 `start`/`value`；规范化向量同步更新。ADR 0038：Flutter 3.35.5 兼容基线——Flutter 依赖包/示例统一下限，版本 0.7.0-dev.1，运行时不变。ADR 0037：冷深跳 settling——WeftView 宿主视口遮罩与 post-frame 信号，未配置 builder 时行为不变。ADR 0036：已测区间索引直接物化、单所有者块元数据、增量后缀估算、格式化空白准入与 correctBy 后视口同步。ADR 0017–0033：分块渲染与命中裁剪（ADR 0017/0020）、行内图片（ADR 0018）、选择 chrome（ADR 0019）、块级盒模型（ADR 0021）、表格列轨道（ADR 0022）、流式顶层前缀复用（ADR 0023）、单表面 Semantics（ADR 0024/0026/0028/0030）、渐进式布局虚拟化（ADR 0025）、同步/异步锚点导航（ADR 0027/0029）、懒布局异步分帧与同快照复用（ADR 0031）、阶段 0–3 验收证据与重定界（ADR 0032）和受限 JS 运行时（QuickJS FFI + 能力网关 + 恢复去重 + 自定义标签，ADR 0033）。ADR 0034（阶段 5）：快照 JSON 线格式（format+version 门禁）与 21 个规范化一致性向量、种子化模糊测试（CI 快跑 + tool/fuzz.dart 长跑，修复诊断上限绕过与 toString 崩溃两个真实问题）、能力策略 8 子集矩阵、example/weft_fallback WebView 回退示例、发布手册与回滚演练测试、API 文档门禁、真机矩阵计划。ADR 0035：QuickJS 移动平台构建——ffiPlugin 声明、Android CMake 就地编译（16 KB 对齐）、iOS 静态链接与 dead-strip 锚点、按平台分派的加载器。

## 包结构

```text
packages/
  weft/                 公开 API：WeftController、WeftView
  weft_document/        纯 Dart 文档模型、规范化、样式表、支持度报告
  weft_engine/          布局、绘制、图片、Float、表格、命中测试、选择、渲染表面
    lib/src/layout_engine.dart     引擎骨架、块流、图片（公共入口 layout()）
    lib/src/table_layout.part.dart 表格：槽位网格、列宽、折叠边框（extension）
    lib/src/inline_flow.part.dart  Float 排除区、行内累积器、数据类
    lib/src/lazy_layout.part.dart  已测窗口索引、块流元数据、后缀估算
  weft_runtime_api/     JS Runtime 与能力桥抽象
  weft_quickjs/         vendor QuickJS 源码、C 垫片与 dart:ffi 后端
    android/            Gradle 模块 + CMake，就地编出 libweft_quickjs.so
    ios/                podspec + ObjC 锚点，把垫片静态编进 app image
  weft_capabilities/    能力策略与内置命名空间
  weft_runtime_fake/    脚本化 FakeRuntime 后端
  weft_runtime_contract/  后端中立 JsSession 契约套件
example/weft_lab/       开发实验室、阶段 4 演示与图片资源
example/weft_live/      实时专题页演示（Web target、动态快照、自定义标签）
example/weft_fallback/  WebView 回退示例（requiresWebView → 宿主 WebView）
conformance/            语料、固定字体、图片资产、Flutter 基线、浏览器几何参考
tool/                   check 门禁、dump 诊断、资产生成、浏览器参考、跨引擎报告
docs/adr/               架构决策记录
```

## 已实现能力

- 规范化：标签白名单（含 table 系）、属性清洗（含 colspan/rowspan 1..1000）、URL 与图片源策略、节点/深度/输入限制、诊断与显式回退；嵌套表格触发 requiresWebView。
- CSS：标签/类/ID/复合/后代/子代/逗号选择器，特异性与源码顺序，内联样式，margin/padding 简写，宽度约束，`float`、`clear`、`border-collapse`、`border-spacing`、`vertical-align`。
- 布局：标题、段落、强调、列表、引用、代码块、分隔线、`<br>`；margin 折叠；CSS 半行距；块级宽度/box-sizing/solid 边框。
- 表格（ADR 0012）：槽位网格、colspan/rowspan、隐式行、caption、两遍 min/max 列宽、行槽拉伸、separate/collapse 边框（中心线模型，最宽者胜）、单元格复用块级布局。
- 图片：宿主解析、异步解码失效、块级替换盒、固有比例、alt 回退；1:1 绘制像素对齐。
- Float：图片左右浮动、逐行行框避让、clear、同侧堆叠、对侧并排、文档滚动高度。
- 链接：跨行命中矩形、宿主 `onLinkTap`；单元格内链接同样可点。
- 选择（ADR 0013/0015/0019）：逻辑文本索引（块边界/`<br>` 换行、空白裁剪）、`selectionRects`/`selectionText`、表面高亮；长按选词、拖拽扩展、把手微调端点、复制按钮（剪贴板策略在 weft 层）、tap 放 caret；`WeftView.onSelectionChanged`。
- 分块渲染（ADR 0017）：绘制命令按 body 顶层子节点分块缓存 `ui.Picture`，三层可见矩形策略（canvas clip → viewport transform → 全绘兜底）；选区矩形与 caret 独立 memo，选区变化不重建 Picture。
- 行内图片（ADR 0018）：img 默认 `display: inline`（UA 语义）以 U+FFFC 占位原子参与两条行内路径的断行，`vertical-align: baseline/middle`，占位符不随 textScaler 缩放；CSS height px 与百分比宽（相对包含块）。
- 块级盒模型（ADR 0021）：显式 `height`（box-sizing 换算，溢出不裁剪照绘，阻止自垮塌）；百分比 `width` 相对包含块 content 宽；水平 `margin: auto` 分配剩余空间（双边居中/单边全吃/负按 0）。
- 命中裁剪（ADR 0020）：`WeftLayoutResult.attachDocument` 后命中查询经分块索引（段 bounds 条带）裁剪，语义与全量倒扫逐点等价；`WeftView.scrollController` 可注入。
- 列轨道（ADR 0022）：`colgroup/col` 的 px 固定列（min=max=声明值）、百分比列（基数 = 表内容宽）、span 轨道与 colspan 平摊绕过固定列；带轨道 collapse 表采用 Chrome 盒语义。
- 流式增量（ADR 0023/0044/0046/0048–0051）：公共顶层前缀按规范化子树与全局输入键复用，在原块流中跳过递归排版并保留 TextPainter；连续快照重新绑定缓存节点。流式新快照的文本索引按块 diff 前缀复用条目、只构建后缀（plain 与 lazy 部分测量窗口均参与，ADR 0044/0048；增量构建携带前缀 checkpoint，链式轮每轮参与）；变化区之后的形状相同块平移复用（plain，先序 id 经形状比较 + 映射重写，ADR 0046）；头部插入/头删除轮的索引经反向 diff 后缀映射采用旧条目——平移 + id 重映射，接缝标志不符的子 fresh 走查（plain，ADR 0051）；lazy 轮的准入结论与逐子估算（style/gap/marker/minimumPaintOffset）按已证前缀沿用、只验证/重建后缀（ADR 0049）；plain 复用块顶层样式成对沿用上一轮缓存（ADR 0050）。旧结果含 Float、全局输入/样式表变化等情况按门回退全量，lazy 轮的索引仍全量（无后缀映射）；未变前缀 Picture 跨布局保留。
- Semantics（ADR 0024/0026/0028/0030/0039/0040）：RenderWeftSurface 手动组装阅读顺序文本、链接、图片和选区节点；标题子树带 header flag 与 `headingLevel`，显式 `aria-live` 子树的叶子带 `liveRegion`，有序列表 marker 使用 `ol start`/`li value`。ARIA 基础：`role` 保守映射（button/link 输出 isButton/isLink flag 但无激活动作，img/heading 折叠或派生，dialog/alertdialog 容器，alert/status 隐式 live+atomic，presentation/none 抑制自身派生语义，其余丢弃并诊断）；显式 role 覆盖隐式语义；`aria-hidden=true` 子树移出语义树；`aria-label` 在 img 上优先于 alt、其他元素折叠为单个命名叶子；live region 内 `aria-atomic=true` 整组播报。链接语义 tap 与选区 copy 走独立回调入口，WeftView pointer/剪贴板职责不变。节点 key 对齐 NodeId，流式更新保留身份；屏外节点可 showOnScreen，选区仅暴露 value/selected/rect/copy，不伪装 text field。live region 不创建额外容器，`polite/assertive` 统一为布尔。
- 布局虚拟化（ADR 0025）：`layoutViewport` 在原块流中连续测量精确前缀，只物化 viewport+250px 窗口；未测后缀按同类块中位数估算 extent。隐藏块释放 commands/painter，previous/current 继续单 owner 转移；跳到估算底部用 correctBy 跟随。顶层块内及 body 直属的已解析图片 Float 都以块级排除区 checkpoint 跨离屏复用；非图片/inline 祖先 Float、非空 selection（含首帧）、Semantics、未解析图片/loose inline 回退或粘滞 full。full 退出会递增 generation 并清除陈旧校正，初始 ScrollController offset 会 seed 首帧物化窗口。
- 懒布局异步分帧与同快照复用（ADR 0031）：视口末端距已测前缀超过一屏或首帧 seed 深于 overscan 时，每帧至多新测 32 个顶层块，post-frame 续帧按 `_needsLazyRelayout` 收敛，`_lazyGeneration` 取消；同快照 relayout 跳过节点 diff 与样式表比对，元素级样式缓存随增量缓存跨帧存活（宽度/缩放/图片不参与计算样式），文本索引实例直接复用。300 块冷跳底部从 124.8ms 单帧降为 10 帧 × 中位 5.8ms。
- 冷深跳 settling（ADR 0037）：`RenderWeftSurface.isLazySettling`/`onLazySettlingChanged` 在 budgeted pass 后判定，post-frame 去重上报；`WeftView.lazySettlingBuilder` 提供视口固定的宿主遮罩（`IgnorePointer`），`onLazySettlingChanged`/`WeftViewState.isLazySettling` 暴露起止。near-frontier、异步锚点、已测量窗口不触发；`_exitLazyMode`/文档替换/dispose 复位。未配置 builder 时树与黄金不变。
- 测试：规范化、布局、margin、盒模型、图片、浮动、表格（17 项）、选择（15 项，含 10 万字符随机选区与流式重映射）、CJK、长文档、公开层、语义（headingLevel/liveRegion、列表 start/value 与 ARIA role/hidden/label/atomic）、像素基线、两个浏览器几何基线，以及语料结构断言（无丢失/无重叠/无越界）与敌意输入诊断扫描（ADR 0032）。
- 移动端原生构建（ADR 0035）：`weft_quickjs` 的 `flutter.plugin.platforms` 声明 android/ios 为 ffiPlugin，包本身不依赖 Flutter；Android 由 `android/src/main/cpp/CMakeLists.txt` 就地编译 vendor 源码（`-fvisibility=hidden`、16 KB 页对齐、`compileSdk 36`/NDK 27），iOS 由 podspec 编进 app image，`WEFT_EXPORT` 的 `used` 属性 + ObjC 锚点防止 `-dead_strip` 丢掉 `dlsym` 目标；`librarySourceFor()` 按平台分派（显式路径 > iOS process() > Android 按名打开 > 桌面文件搜索）。APK 已实测含三 ABI 的 `libweft_quickjs.so` 且恰好导出 10 个 `weft_*`；真机（Huawei JNY-AL10 / Android 10）跑通加载、JSON/字符串求值与内存/墙钟两类预算中断。

## 明确未实现

- **严格 60fps 未达成**：ADR 0036 在 JNY-AL10 上四项标准通过（冷启动中位 635ms、滚动 p95 ≈26ms 无 >50ms、深跳最大 37ms、内存 +10MB），但 combined p95 仍高于 16.7ms，瓶颈是 raster；冷跳分帧期间可能有短暂空白。B1（12+12 轮后端 A/B，device-matrix §4.7）未发现可复现后端优势，切换 Skia 不解决该缺口。
- 未测区域的精确 O(1)/O(log N) 随机跳转，以及超高顶层块/表内行/图片解码资源虚拟化；冷跳与首次深锚点仍需逐帧测量目标前缀，病态区间重叠或大量 Float 可能退化。配置 `lazySettlingBuilder` 时可由宿主遮罩空白，但首帧仍可能可见、遮罩不加速测量，不承诺零空白（ADR 0037）。
- 非图片 Float 与表格局部 Float 的 checkpoint；增量布局的行级复用与跨快照行级缓存（后缀平移已由 ADR 0046 交付——plain 路径）；lazy 种子消费/状态整体采用（①(c)）按 0049 数据降级留案——滚动轮剩余 = O(前缀) 种子 append + diff + 后缀物化；行内原子的 margin 参与行框与 top/bottom 对齐。
- CJK 像素基线（跨引擎像素验收已按 ADR 0032 重定界为结构几何门禁；真机帧计时仍以 weft_lab 为准）。
- 表格：嵌套表格（触发回退）、浏览器级 auto 列宽分配精度、`col` 的 min/max 语义。
- Semantics 的跨行跨列语义索引、table/list 角色导航、可编辑 selection/caret 动作、landmark/tab/menu/radio 族角色、`aria-level`/`aria-labelledby`/`aria-describedby`、`polite`/`assertive` 播报优先级与语义虚拟化。`role=button`/`link` 只播报角色，无激活动作；aria-label/role=img/aria-atomic 折叠不播报子树内容，presentation 表格后代 th 的 header flag 保留（ADR 0040 记录在案的简化）。
- 受限 JS 的既有边界：bridge 风暴上限按单轮计数、`weft.net` 仅 GET、自定义标签不支持行内混排与 Float 环绕、JSON 编组把 undefined 折叠为 null（ADR 0033 后续小节）。
- 移动端验收证据：Android 已完成构建、打包与真机执行（Huawei JNY-AL10 / Android 10，加载/求值/内存与墙钟预算共 6 项冒烟全过）；iOS 构建与运行（需 macOS + Xcode + CocoaPods）**暂缓**——podspec 与锚点只经过代码审查，未执行过 `pod install`（ADR 0035）。

## 关键约束

1. 内容呈现优先，不追求完整 W3C/WHATWG 兼容。
2. 只执行可信脚本；JS 不接触布局或渲染树。
3. 布局、选择、资源加载和 Runtime 保持分层；引擎不得知道 QuickJS。
4. 修改布局必须检查 `conformance/reference/` 基线和跨引擎差异。
5. 像素差异报告中字形抗锯齿属预期，不允许为通过测试直接放宽阈值。
6. 图片资源安全由宿主解析器负责，引擎只接受已解码 `ui.Image`。

## 验证命令

```bash
# 一键门禁 = format + analyze + verify + golden；--fast 跳过像素门禁
tool/check.sh

# QuickJS 原生库（首次克隆或改动 native/ 后执行；缺失时 FFI 测试跳过并给出本命令）
packages/weft_quickjs/tool/build_native.sh

# 移动端原生库：Android 需 SDK 36 + NDK 27，宿主工程需先生成 android/ 平台目录
flutter build apk --debug --target-platform android-arm64
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libweft_quickjs

# profile 构建（真机帧耗时只认 profile/release）
# 若卡住 5 分钟：Gradle 在下 41.6MB 的 arm64_v8a_profile jar，见「常见的坑」
flutter build apk --profile --target-platform android-arm64

# 真机帧耗时：临时探针（build/perf_probe，需临时加进 workspace）自驱滚动 + 深跳
adb logcat -c && adb shell am start -n <pkg>/.MainActivity && sleep 55
adb logcat -d -s flutter:I | grep -a "PERF|"

# 逐项运行
flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart run tool/verify.dart
cd packages/weft_engine && flutter test tool/golden_pixel_test.dart --timeout 60s

# 浏览器诊断参考（本机 Chrome/Edge + Node 22）
node tool/browser_references.mjs

# 布局诊断：打印盒子/行/逻辑文本；--diff 输出逐元素 Weft-vs-Chrome 偏差表
tool/dump_layout.sh conformance/cases/table_basic.html --diff
tool/dump_layout.sh conformance/cases/float_image.html --runs

# 重新生成几何参考并直写 conformance/reference/（提交前人工审查 diff）
node tool/browser_references.mjs --case <id> --emit-reference

# 跨引擎像素报告（需要 Pillow）
python tool/compare_goldens.py --report-only

# 重新生成确定性图片资产（改动 conformance/assets 时）
python tool/generate_assets.py
```

## 建议的下一步

开发计划阶段 0–5 已完成。以下为既有技术路线的延续候选（阶段 5 的验收边界外）。

### A. iOS 构建验证（暂缓，等待 macOS 环境）

目标：在 macOS + Xcode 上完成首次 `pod install` 与构建，确认 `weft_*` 符号未被剥离，并在 iOS 真机/模拟器跑通 runtime 示例；结果写入 `docs/device-matrix.md`。

状态：2026-10-28 决定暂缓——手头没有 macOS 设备。Android 已真机验证，桌面与 CI 路径不受影响；恢复时按 device-matrix §2.2 的清单逐条执行。未验证前不得对外宣称 iOS 可用，发布说明中要写明缺席。

注意：若符号缺失，先查 `-ObjC` 是否被宿主 Podfile 覆盖，再考虑把 vendor 源码移进 `ios/`（CocoaPods 文件模式不支持 `..`，当前用绝对路径绕过）。

### B. ADR 0036 后续：60fps 光栅画像（B1 已完成，2026-10-31）

窗口直物化已完成并在 JNY-AL10 通过四项设备标准：冷启动中位 635ms、滚动 combined p95 25.5–26.0ms 且无 >50ms 帧、深跳最大 37.12ms、内存 +9.4～10.0MB。排版侧已不是瓶颈（build p95 ≈9.9ms），raster p95 ≈17.2ms 主导，因此严格 16.7ms 未达成。

光栅归因已完成（device-matrix §4.5/§4.6）：严格 PAINT_ONLY（零重排、零 Picture 重建）在 Impeller 上 raster 仍 ~7ms，证明全屏文本基线光栅是后端/驱动成本；SCROLL 的额外 ~8–9ms 来自新物化块的首次绘制/上传，Picture 重建只影响 build。

B1 后端 A/B 已完成（device-matrix §4.7）：12 Impeller + 12 Skia ABBA 交替、24 轮全部有效；PAINT_ONLY 与 SCROLL 的 raster/total 均无显著差异（SCROLL total p95 中位 25.70 vs 24.49ms，p=0.33），唯一显著项是 SCROLL build p95 差 0.38ms，无实际意义。**结论：不建议旧 Mali 设备关闭 Impeller，也不要把后端切换当作 60fps 方案。** strict 60fps 仍未达成，轮间 DVFS 离散度大于后端差异。

引擎侧没有免费的 60fps 优化空间：继续压榨需要后端层手段（图片光栅缓存、减少每帧新内容面积），或接受 A 档 ≤33ms 标准（当前已满足）。B2 已完成（ADR 0037）：冷跳空白可由宿主遮罩覆盖，但测量速度与 60fps 缺口不变。下一步转 C 语义增强或 D 增量布局；不要再改 layout/overscan、重复后端 A/B，或把遮罩当成零空白。

### C. 语义增强（C0–C3 已完成）与 RTL（D1 已完成）

C0 兼容基线（ADR 0038）、C1 语义补全（ADR 0039）与 C2 ARIA 基础（ADR 0040）已完成：Flutter 依赖包/示例要求 `>=3.35.5`，包版本 `0.7.0-dev.1`，纯 Dart 包保持 Dart 3.5。C1 交付 headingLevel、显式 `aria-live` live region 与有序列表 `start/value` 标记。C2 交付 `role` 保守映射、`aria-hidden`、`aria-label`（修复接缝错位）与 `aria-atomic` 整组播报。table/list 嵌套角色已在 ADR 0030 交付，不要重复实现或扁平化。

C3 语义虚拟化（ADR 0041）已交付：Semantics 在 lazy 结果上组装窗口化语义，不再升级 full。D1 RTL（ADR 0042）已交付：块级基方向、lang→locale、语义 textDirection 透传；行内双向重排依赖 SkParagraph，中性字符行缘重排与竖排仍排除。后续候选：landmark/tab/menu/radio 族角色、`aria-level`/`aria-labelledby` 与可编辑 selection/caret 动作。注意：继续使用 describeSemanticsConfiguration/assembleSemanticsNode 的单表面模型；新增语义容器必须满足 Flutter 的严格父子校验（landmark/tab/menu/radio 族因校验不变量暂被拒绝，见 ADR 0040）。不要把静态文档伪装成 text field，也不要让语义节点持有旧 TextPainter。窗口化语义的规则（物化窗口精确、band 粗叶子、未测后缀缺位）见 ADR 0041，不要放宽为伪造未测块的节点。

### D. 增量布局扩展（①②③ 已完成）

目标不变：在保持全量等价的前提下减少剩余 O(块数) 流式轮固定成本，或支持含 Float 文档与更多编辑形态。

ADR 0043 画像结论：快照 diff 近乎免费；textIndex 全量重建是流式轮最大纯开销（56–81%）；形态阶梯为尾部追加/增长 ≪ 中部编辑 < 头部插入（≈0，weft_live 实际形态）；lazy 宿主流式轮的 O(doc) 三件套 = 准入走查 + 估算后缀重建 + textIndex。

①文本索引增量已交付（ADR 0044）：流式新快照按块 diff 前缀复用条目、只构建后缀；共享 walker + 每顶层块 checkpoint + 尾 trim 还原；lazy 部分测量前缀、头部插入（k=0）、样式表变化全部保守回退全量（ADR 0051 修订：k=0 已由方向③解除）；等价由增量 vs canonical 逐条目相等测试与加严的 `_expectLayoutEquals` 守护。U(2000) −60%，appendArticle300Incremental 7.1 → 5.8–6.0ms。流式轮剩余 O(doc) 主导成分 = 走查样式解析（S=5.3ms@2000），与 lazy 准入走查/估算后缀重建同属「样式与状态跨快照」家族。

②逐行 probe 窗口化已交付（ADR 0045）：断行探测窗口约两行字符量起步、断点距窗口尾 margin=16、×2 直至段尾（fit 前缀单调保证窗口断点==全文本断点），run 前缀表二分定位；8000 字段落 764 → 11.1ms（−98.5%，二次方转线性）、floatWrap 6–9 → 4.8ms、float-plain 流式轮 385 → 239ms；「不重叠段落切换整段路径」被否决——两路径断行非等价是 ADR 0016 文档化现状，切换即改变输出。Float 家族剩余成本为逐行模型线性常数，跨快照行级缓存归入 ③ 之后的同族另案。

**③ 后缀平移已交付（ADR 0046）**：中部编辑 21.6 → 2.3ms、头部插入 40.9 → 2.4ms（weft_live 形态 saving ≈0% → 93%）、mid-edit@1000 66.7 → 9.9ms；plain Float 文档不播种缓存故不参与，body 级 li 截断扫描。**画像三方向全部落地；「样式与状态跨快照」家族画像已交付（ADR 0047）**：lazy 流式轮 U−F = 3.3–42ms（host）而同快照地板 ≈ 0.1ms，97–99% 为每快照重付的家族工作（全量索引 T 38–63%、准入样式 S 12–18%、估算走查残差；真机 4× 后所有规模超帧预算），样式每 resolve 成本随规则数陡增（8 → 256 条约 7–9×），float-plain 轮 99% 为走查/逐行残差。**方向① lazy 流式轮 O(change) 化进行中：(a) 文本索引增量参与已交付（ADR 0048）**——参与门按内容纯函数论证放宽，lazy 部分测量窗口复用条目，并修复 0044 的部分前缀尾 trim/drop 还原洞与前缀 checkpoint 播种（链式轮不再隔轮回退）；滚动会话尾追加轮 6.3→2.7 / 14.7→7.1 / 48.2→15.3ms（−57/−52/−68%，e4bs 形态）。**①(b) 准入与估算前缀采用已交付（ADR 0049）**——diff 已证前缀沿用上一轮准入结论与 `_LazyChild` 逐子估算（element 重绑 + 边界三值恢复），只验证/重建后缀；provisional allowLazy 不合格时重跑 plain 模式 diff 保留后缀平移。滚动轮同机对比 2.01→1.57 / 6.02→3.88 / 12.76→6.94ms（−22/−36/−46%），eligibility 后缀化；家族累计 0047 fresh U(2000) 30.8–42.4 → 6.9ms（−77–84%）。**①(c) 已按数据降级缓办**（滚动轮剩余 6.94ms@2000 中种子 append 池仅 ~1–1.7ms 而机制最重，留案）；**方向② plain 走查样式跨快照采用已交付（ADR 0050）**——决策块在 reusedMaps 终态后成对种子化（前缀连续正扫 + 后缀尾逆扫），被采用样式与 fresh 解析值等（无身份消费者），lazy 前缓存缺条目自然断首优雅退化；E4f 同机 A/B 8 条规则 2.61→1.91ms（−27%）、256 条 29.14→11.66ms（−60%），复用轮与样式表规模脱钩，剩余为 diff + 后缀克隆。**方向③ k=0 头部插入的索引条目平移已交付（ADR 0051，家族清单全部销账）**——`buildFromSuffix`：头部子 fresh 走查后，carried 子逐个比对接缝四标志，相等则旧条目平移 + ids 重映射采用并止、不等则 fresh 走查（流首剥离分歧的唯一信号，走满即等价全量）；尾 trim/drop 还原为 0048 镜像；E1 head-insert 同机 A/B @300 2.11→1.16–1.38ms、@1000 7.82→3.02–3.09ms（entries=0→1500/5000），head-insert 与 mid-edit 反差消失。**下一步 = 按「先画像再选择」重新画像剩余轮固定成本**（候选：mid-edit 后缀采用的推广——先测其 suffix 走查份额；①(c) 与行级缓存维持留案）。方法与数据见 `docs/adr/0043-incremental-layout-profiling.md`、`docs/adr/0044-incremental-text-index.md`、`docs/adr/0045-windowed-line-break-probe.md`、`docs/adr/0046-suffix-translation.md`、`docs/adr/0047-style-state-family-profiling.md`、`docs/adr/0048-lazy-text-index-participation.md`、`docs/adr/0049-lazy-prefix-adoption.md`、`docs/adr/0050-plain-style-adoption.md`、`docs/adr/0051-head-insert-entry-shift.md`。

注意：不要把 ADR 0023/0025 的保守回退改成未验证的近似复用；文本索引的增量路径未命中即回退全量构建（ADR 0044 已实现该纪律），逐行路径的任何缓存同样不得近似未验证的断行结果。

## 常见误区

- 不要把 `img` 映射为 Flutter `Image` Widget；保持单一渲染表面。
- 不要在规范化器里清洗不可信脚本；它只处理受控子集。
- 不要恢复已销毁的 Runtime 或自动重放副作用。
- 不要绕过 `_FloatContext` 直接计算行框；表格单元格用独立 `_FloatContext`（近似 BFC），不要让浮动外溢单元格。
- 不要为跨引擎像素通过而修改测试字体、通道容差或遮挡真实差异。
- 不要在折叠边框模型外给单元格再画自身边框（半边框已折算为合成 padding）。
- 不要把选区高亮、caret 或任何 chrome 画进分块 `ui.Picture`——它们必须随选区即时重绘，进 Picture 会破坏 ADR 0017 的缓存计数与失效语义。
- 每个 TextPainter 必须恰好 dispose 一次：复用/平移克隆跨结果引用同一 painter 时，原件必须登记进 `reusedCommands` 经 `transferCommands` 让 previous 的 dispose 跳过，由持有现行命令的结果释放（ADR 0046）；不要绕过转移台账双持 painter。ADR 0036 的窗口状态也采用单 owner 转移，即使无绘制命令的高度块窗口，复用后的 previous 也失去缓存；dispose 同样使缓存失效。不要把旧 cache.blocks 的只读视图当作历史快照。
- 不要用 MergeSemantics 推导单画布内容，也不要同时暴露块全文和相同链接/图片子节点；语义数据必须跟随当前 document/layout，不能按可见 Picture 裁剪。
- 不要把未测后缀的估算高度当作精确块位置，也不要在 lazy 窗口外伪造命中、选择或 Semantics；需要完整几何时先升级 canonical full。
- 分帧续推的停机条件是 `_needsLazyRelayout()`，不是强求测完全文；格式化文本也不计入 cache.childCount。`measuredPrefixLength == body.children.length` 会混用元素与文本节点计数，可能永不结束；需要强制测完时必须指定末尾 focus 并设置有限迭代上限。
- 浏览器几何基线重新生成后必须人工审查 diff，不允许盲目覆盖。
- 阶段 4 的 QuickJS 需要 native 库：测试在库缺失时跳过并提示 `packages/weft_quickjs/tool/build_native.sh`；不要把跳过当验收，中断/内存证据以真实 QuickJS 测试为准。
- 能力调用风暴的上限按"单个事件循环轮次"计数（`_maxBridgeCallsPerTurn`），不是累计预算；跨轮的链式风暴由 `settle()` 的 256 轮兜底，两者都不能省。
- 自定义标签是属性驱动的叶子元素：内容在规范化时丢弃（有诊断），不要指望布局遍历其子树，也不要忘记 `WeftNormalizer.customTags` 与引擎 `tagRenderers` 两处要同步。
- 移动端编译参数要三处一致：`tool/build_native.sh`、`android/src/main/cpp/CMakeLists.txt`、`ios/weft_quickjs.podspec` 必须反映同一组宏（`CONFIG_VERSION`、`CONFIG_BIGNUM`、`-fno-strict-aliasing`）；只改一处会让同一脚本在不同平台行为分叉。
- 不要用「放宽懒布局准入条件」解决首帧慢：ADR 0036 之前的实测里滚动 p95 从 9–30ms 恶化到 140ms（docs/device-matrix.md §4.3）。首帧成本只能靠窗口化摊薄，不能靠打开每帧重排；窗口化已在 ADR 0036 交付。
- 桌面测试的 lazy pass 耗时（3–6ms）不能直接当设备预算：A 档真机放大约 3–4 倍（18–27ms），定目标时按 4× 估。
- 跨快照采用的等价性前提不许削弱：样式/索引条目/准入结论都是「内容 + 样式表签名」的纯函数，任何采用必须经 diff 门（`_sameNode`/`_sameNodeShape` + 签名 + body 壳 + tagRenderers 身份）；不要给 styleCache 或索引改 id 键控——后缀先序 id 随中部变化平移，会错误命中旧条目（ADR 0046 的核心发现）。
- `_minimumPaintOffset` 的 `styleCache[element]!` 硬断言靠「采用路径不接触前缀子 + 后缀子树刚被准入解析」保温：新增 lazy 消费方要么走 `styleFor` 按需解析，要么保证预热，不要直接读缓存。plain 轮不得消费 lazy 缓存的 diff 映射（未物化块零命令）——provisional allowLazy 的重跑规则不能省。`debugEligibilityVisitCount` 自 ADR 0049 起只计后缀访问，同快照轮恒 0。
- 0051 的条目采用以接缝四标志逐项相等为前提（`atLeadingEdge` 是流首剥离分歧的唯一信号，不能从比较中剔除）；头部走查必须镜像 body 级 `blockBreakPending` 初值，否则头部 checkpoint 会毒化下一轮的 `adoptPrefix`。旧 body 含体级 text 子时 0046 缓存门整体拒绝 diff——不要试图绕过它做部分采用。
- 不要用 `tool/check.sh | tail` 判断成败：管道会吞掉退出码，重定向到文件再看 `$?`。
- Flutter 下限已在 0.7.0-dev.1 统一为 `>=3.35.5`（ADR 0038），不要再写回 3.22：`weft_engine` 自 ADR 0030 起使用 Flutter 3.35.5 的 `SemanticsRole`，3.22–3.34 宿主会在编译期失败；包含 ADR 0030 的 0.5/0.6 版本在实际编译时同样要求 3.35.5。
- live region 不是语义容器：`aria-live` 只给叶子片段打 `liveRegion`，多个叶子可能被辅助技术分别播报；不要把整页包进 aria-live，也不要指望引擎合并临时消息或保留 polite/assertive 优先级。
- 规范化向量重新生成后必须人工审查 diff；C1 只改变了 `synthetic_lists_and_quotes`（保留 `ol start`），其余 20 个向量必须保持不变。
- 不要删除 iOS 的锚点类或 `WEFT_EXPORT` 的 `used` 属性：它们不是死代码，去掉后 `-dead_strip` 会连同 `dlsym` 目标一起丢弃，而桌面测试完全发现不了。
