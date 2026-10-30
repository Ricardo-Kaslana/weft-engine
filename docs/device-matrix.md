# 真机矩阵（阶段 5，ADR 0034）

单测与 CI 只能证明逻辑正确与几何一致；帧耗时、内存和触控手感必须在真机
上确认。本文定义目标设备档位、执行步骤与通过标准，运行载体是
`example/weft_lab`（每阶段交付物都以它为可运行示例）。

## 1. 设备档位

| 档位 | 代表设备 | OS 范围 | 关注点 |
|---|---|---|---|
| A 低端 | 4GB Android（如 Redmi/低端三星 A 系） | Android 10–14 | 懒布局首帧、滚动帧耗时 p95、内存预算 |
| B 中端 | 6–8GB Android（Pixel A 系/主流国产中端） | Android 12–15 | 全路径：选择、流式追加、锚点跳转 |
| C 高端/iOS | iPhone 12 及以上 | iOS 15–17 | 长文流畅度上限、ProMotion 差异 |

文本缩放：每档至少跑一组 `1.0` 与系统最大字号（无障碍），确认把手/
复制按钮不遮挡内容、CJK 禁则不回退。

## 2. 执行步骤

1. `cd example/weft_lab && flutter run --profile -d <device>`（性能数据
   只认 profile/release，debug 数据一律不作数）。
2. 打开 AppBar 的速度图标启用性能浮层（阶段 5 加入），依次执行：
   - 冷启动到首帧可交互（秒表 × 5 次取中位）；
   - 长文（≥300 块语料）匀速滚动 30s，记录浮层 p95/p99 帧耗时；
   - 快速深跳（拖到顶部再到底部）× 10，观察是否有 >33ms 帧；
   - 长按选择拖拽扩展，确认把手跟手、无掉帧尖峰；
   - 运行脚本控制（阶段 4 runtime 演示），确认能力调用无 UI 卡顿。
3. Android 用 `flutter run --profile` + DevTools Memory 记录滚动前后
   峰值；iOS 用 Instruments Core Animation + Allocations。
4. 结果记入下表（提交到本文件的结果段落）。

### 2.1 原生库预检（ADR 0035）

JS 在移动端依赖随包分发的原生库，先确认它存在、符号正确，再开始计时：

```bash
# Android：APK 内应有三个 ABI 的库
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libweft_quickjs

# iOS（macOS）：可执行文件里应有 weft_* 符号
nm -gU Runner.app/Runner | grep weft_
```

真机首启若 `QuickJsNativeLibrary.load()` 抛 `StateError`，按错误文案给出的
平台补救处理（重打 APK / `pod install` 后重建），不要当成性能问题排查。

### 2.2 iOS 首次验证清单（暂缓，2026-10-28）

暂无 macOS 环境，iOS 的构建与真机验证整体挂起。拿到机器后按顺序执行，
哪一步失败都先解决再往下走：

```bash
cd example/weft_lab
flutter create --platforms=ios .      # 仓库不携带平台目录
flutter pub get
pod install --project-directory=ios
flutter build ios --no-codesign
nm -gU build/ios/iphoneos/Runner.app/Runner | grep weft_   # 期望 10 个
```

符号为空或少于 10 个 → 先查 `-ObjC`（`use_frameworks!` 会改变链接形态），
再确认 `WeftQuickJsAnchor.m` 进了 pod target，最后看 `WEFT_EXPORT` 的
`used`。构建通过后跑一次 runtime 示例，把结果补进 §4.1。

## 3. 通过标准

- 滚动帧耗时 p95 ≤ 16.7ms（A 档放宽到 p95 ≤ 33ms 且无可感知停顿）。
- 冷启动首帧 ≤ 500ms（B/C 档）、≤ 800ms（A 档）。
- 深跳过程无 >50ms 单帧（ADR 0031 的分帧预算在真机上生效）。
- 滚动往返 10 轮后内存增量 < 20MB（缓存有界，ADR 0032）。
- 选择、复制、链接点按、自定义标签点按全部可用，无手势冲突。

## 4. 结果记录

（首次真机轮结果提交时填写；CI 无法替代这一步。）

移动端首轮还要单独记录「JS 原生库加载」是否通过（ADR 0035）：Android 与
iOS 各至少一台设备跑通 runtime 示例，才算该端可用。Android 已于 2026-10-28
完成（§4.1）；iOS 暂缓（§2.2）。

### 4.1 原生库冒烟（ADR 0035）

2026-10-28 · Huawei JNY-AL10（Android 10，arm64-v8a，debug APK，仅 arm64）

| 检查 | 结果 |
|---|---|
| `DynamicLibrary.open('libweft_quickjs.so')` | 通过 |
| JSON 值编组 `({a:1,b:"x",c:[true,null]})` | 通过，回读 `{a: 1, b: x, c: [true, null]}` |
| 字符串求值 `"weft-" + (40 + 2)` | 通过，`weft-42` |
| 堆预算中断（持续分配数组） | 通过，`RuntimeFailureKind.memoryLimit` |
| 墙钟预算中断 `while (true) {}` | 通过，2s 预算在 2.0s 处返回 `RuntimeFailureKind.timeout` |

采集方式：`adb logcat -s flutter:I | grep PROBE|`；探针是临时 App（依赖
`weft_quickjs`，不随仓库分发）。这只证明原生库在真机可用。

### 4.2 帧耗时（2026-10-28）

设备：Huawei JNY-AL10（Kirin 810，7.5GB RAM，1080×2310 @480dpi，Android 10 /
SDK 29）——按档位定义介于 A 与 B 之间：内存够 B 档，SoC 与系统版本偏 A。
文档：601 个顶层块（300 节，每节标题 + 两段），profile APK，仅 arm64，
探针自驱滚动，不依赖 adb 输入。

| 指标 | 第一轮 | 第二轮 | 判定 |
|---|---|---|---|
| 滚动 p50 | 7.1ms | 12.6ms | — |
| 滚动 p95 | 9.4ms | 29.9ms | A 档 ≤33ms：通过（第二轮贴边） |
| 滚动 p99 | 12.9ms | 30.7ms | — |
| 滚动最大帧 | 73.2ms（>33ms 两帧） | 118.7ms（>33ms 六帧） | 有可感知停顿 |
| 深跳 p95 | 13.1ms | 16.1ms | — |
| 深跳最大帧 | 316.3ms | 312.8ms | **不通过**（标准 ≤50ms） |
| 内存增量（滚动后） | ~0MB | +9.3MB | <20MB：通过 |
| 冷启动（`am start -W` ×3） | 883 / 817 / 801ms，中位 817ms | — | A 档 ≤800ms：边缘超标 |

结论：

- 常规滚动基本达标，两轮 p95 都在 A 档上限内；但第二轮出现 6 帧 >33ms，
  设备发热或后台负载下会掉帧，不能只看第一轮。
- **深跳有一次稳定复现的 ~313ms 单帧**（两轮差 3.5ms）。这与 ADR 0031
  「每帧至多新测 32 块」的分帧预期不符，怀疑 `jumpTo` 到估算底部时走了同步
  全量测量或一次性 correction，列为待查缺陷（handoff 下一步 B）。
- 冷启动中位 817ms 刚好越过 A 档 800ms 线。601 块比 lab 示例重，需要把
  「引擎启动」与「文档规模」分开再优化。

复现方式：临时探针（`build/perf_probe`，不随仓库分发）驱动 20s 匀速滚动 +
5 次往返深跳，用 `SchedulerBinding.addTimingsCallback` 采集 `FrameTiming`，
`adb logcat -s flutter:I | grep PERF|` 读取。定位慢帧时给 `WeftSurface` 加了
临时开关（`--dart-define=weft.lazyTrace=true`）打印每次 ≥8ms 的排版及其
`lazy/budget/prefix/vh` 字段；结论采完后已回滚。

| 档位 | 设备/OS | 冷启动中位 | 滚动 p95/p99 | 深跳最大帧 | 内存增量 | 结论 |
|---|---|---|---|---|---|---|
| A–B | JNY-AL10 / Android 10 | 817ms | 9.4–29.9 / 12.9–30.7ms | 316ms | ~0–9.3MB | 历史结果；ADR 0036 复测见 §4.4 |

### 4.3 历史定位：美化排版关闭懒布局（ADR 0036 已修复，复测见 §4.4）

埋点给出了比数字更重要的结论——**带换行缩进的普通 HTML 完全不走懒布局**：

1. 规范化保留 body 下的空白文本节点：探针文档 901 个元素 + 900 个 `\n`
   文本节点，`body.children.length == 1801`。
2. `_supportsLazyLayout` 见到 body 的任意文本子节点即返回 false；即便通过，
   块循环里的 `WeftText` 分支还会调用 `_disableTopLevelCache`，让引擎把懒
   结果丢弃、退回全量布局。
3. 结果：首帧一次性排 1801 个节点（实测 198–280ms），随后 `debugIsLazy`
   为 false，滚动根本不触发重排——所以滚动数字好看，但那是因为**没有虚拟化**。

试验性修复（已回滚，未提交）：懒路径跳过 body 的格式化空白 + 计数改用元素
子节点。修好后做了完整两轮测量，结论是**这条路不能走**：

| 指标 | 现状（懒布局关闭） | 打开懒布局后 |
|---|---|---|
| 首帧排版 | 1801 节点全量，198–280ms | 17ms |
| 滚动 p50 | 9.9–13.4ms | 17.3–17.9ms |
| 滚动 p95 | 9.4–29.9ms | **140ms** |
| 滚动 >50ms 帧 | 1–2 / 20s | **126–129 / 20s** |
| 20s 内帧数 | 1184–1189 | 443–449 |
| 深跳 p95 / max | 11–14 / 21–26ms | 22–25 / 67–70ms |

原因：懒布局打开后滚动每帧都要重排，每次只新测 1–2 块却要扫全 900 个元素、
重新物化窗口，并反复触发 extent correction（`correctBy` 回写滚动位置），
形成"重排→校正→再重排"的反馈，帧率掉到 ~22fps。

所以当时正确的下一步不是放宽懒布局的准入条件，而是 ADR 0031 里记的窗口直物化。
ADR 0036 已按该方向实现并在 §4.4 复测通过；本节保留 2026-10-28 的历史结论，
说明为何准入放宽被回滚，不描述当前实现。

另外：3 次埋点运行中，深跳最大帧都是 21–26ms，**没有再出现 316ms**，且
深跳期间没有任何 ≥8ms 的排版 pass，说明那次尖峰不在 `layout()` 里，更像
光栅/合成侧的一次性成本，后续用 `FrameTiming.buildDuration` 与
`rasterDuration` 分列再判。

### 4.4 ADR 0036：窗口直物化验收（2026-10-28）

已实现保守绘制区间索引、块流与后缀估算缓存、格式化空白接入及 `correctBy` 后实际视口同步。命令与具体数据见 ADR 0036；本次生成器明确为 300/1000 个段落，紧凑 body 分别 300/1000 个节点，换行 body 分别 599/1999 个节点。§4.2 的“601 块”与 §4.3 实际 901 元素不是同一可靠计数口径，设备复测必须打印实际数量，不沿用标签。

1000 段同快照、完整测量后的顶/底往返 20 轮：紧凑 `layoutViewport` 调用 p95 为 1.372 → 0.667ms，换行为 85.350 → 0.490ms，改后均走 lazy，每次仅重建/持有 4 块。换行首屏 API 耗时 78.666 → 10.079ms；冷深跳仍拆成 32 pass。这些是 Windows 测试进程的 Stopwatch 数据，旧 full 文档在 WeftView 滚动时不会反复调用该 API，不能把该倍率描述成真实滚动帧率收益。

实际交互已在临时 Flutter Web 宿主与 Edge 上完成：真实 Lab 脚本、图片、长文滚动、Top/Bottom、异步第 270 节锚点、链接、选择升级 full 与复制通过；901 元素长文回顶的已测窗口只访问 28 条目。冷 Bottom 仍有分帧期间短暂空白；build/raster 分列记录与截图在本地 `build/adr0036-evidence/`，仅代表 Web debug，不是设备验收。探针与临时 workspace 项已清理。

Android 真机（JNY-AL10 / Android 10，profile APK 仅 arm64-v8a，901 元素 / 1801 个 body 子节点）复测：

| 指标 | 结果 | 标准 | 判定 |
|---|---|---|---|
| 冷启动 `am start -W` ×3 | 606 / 635 / 670ms，中位 635ms | ≤800ms | 通过 |
| 滚动 20s（1196–1201 帧）combined p95 | 25.52–25.99ms | ≤33ms | 通过 |
| 滚动 >50ms 帧 | 0（2 / 1 帧 >33ms） | 无 >50ms 停顿 | 通过 |
| 深跳最大帧 | 冷跳 12.05 / 14.80ms；滚动后 33.37 / 37.12ms | ≤50ms | 通过 |
| 内存增量（TOTAL PSS） | +9.4～10.0MB | <20MB | 通过 |

首帧 lazy=true，prefix 12/901，visited=1813（首次建条目允许 O(N)），eligibility=902；滚动末帧只新排 4–5 块、物化 15–16 块，estimated=0，全程未 full。冷深跳 31 帧收敛、10 次 extent 校正，offset 自动跟随；异步锚点到第 270 节返回 true 且保持 lazy。历史 ~313ms 尖峰未复现，build/raster 分列下所有阶段无 >50ms 帧。

严格 60fps 的 combined p95 ≤16.7ms 未达成：raster p95 ≈17.2ms、build p95 ≈9.9ms，combined p50 为 14.6–23.6ms，瓶颈在光栅/合成而非排版。后续要冲 60fps 应先做光栅画像。冷跳测量期间仍可能有短暂空白（与 ADR 0036 一致），本次未做像素级零空白断言。

iOS 继续暂缓；Web debug 与桌面画像只作结构性证据，不替代设备矩阵。完整日志、Web 截图与 build/raster 记录在本地 `build/adr0036-evidence/`。

### 4.5 光栅 A/B 画像（ADR 0036 后续，2026-10-29）

设备同上（Kirin 810 / Mali-G52，GLES 3.2；Impeller 实际走 Vulkan）。同一 profile APK、同一 901 元素文档，SCROLL 为 20s 滚动相，PURE_PAINT 为完全测量后在已物化窗口 ±120px 振荡 5s。

| 后端 | 相位 | build p50/p95 | raster p50/p95 | raster max | >50ms |
|---|---|---|---|---|---|
| Impeller | SCROLL（3 轮） | 7.8/9.6 | **15.9/17.2** | 31.2–38.6 | 0 |
| Impeller | PURE_PAINT（3 轮） | 4.6/6.2 | **6.1/8.3** | 9.8–16.3 | 0 |
| Skia | SCROLL | 6.7–7.9/9.4–9.8 | 5.2–13.9/16.5–17.1 | 38.1–44.0 | total 1（50.8） |
| Skia | PURE_PAINT | 3.0–5.7/4.6–6.3 | 4.1–9.6/5.9–16.8 | 22.6–32.1 | 0 |

观察：

- Impeller 两相差异稳定且显著：raster p50 15.9 → 6.1，build 7.8 → 4.6；但 PURE_PAINT 仍每帧约重建 2.5 个 Picture（SCROLL ≈4.7），`cachedPictures` 维持 15–16，因此它并非严格“纯绘制”，只是没有全量重排（prefix 901/901、`fullRequired=false`）。
- 这指向成本随「新块物化 / Picture 重建」增长，而非固定每帧后端开销；但无法据此把差额精确拆成字形上传、图片录制与 GPU 绘制。
- Skia 的 SCROLL p50 在 5.2–13.9ms 间波动，p95 仍贴近 16.5–17.1ms，未显示稳定优于 Impeller；两后端尾部都接近 60Hz 节拍。`FrameTiming.rasterDuration` 含排队/围栏等待，不是精确 GPU 时间。
- 没有可复现的 >50ms 光栅帧；唯一超限是 Skia 一帧 combined 50.8ms。

限制：±120px 仍会跨越块窗口边界（rebuilt 未归零），温度稳定但后台负载未严格隔离。下一步应先按 layout 身份过滤帧、把振荡限制在 needed-set 不变的区间，再决定是否做 Picture 保留缓存或后端建议；当前不支持“60fps 已达成”或“已定位到具体代码”的结论。日志：`build/adr0036-evidence/raster-impeller.log`、`raster-skia.log`。

### 4.6 严格纯绘制归因（2026-10-29）

新增 `PAINT_ONLY` 相：每帧仅 `markNeedsPaint()`，滚动位置、layout 与 chunk 集完全不变（5 轮均验证 layout 身份不变、Picture rebuilt 增量为 0、cached 12→12）。

| 后端 | 相位 | build p50/p95 | raster p50/p95 | >50ms |
|---|---|---|---|---|
| Impeller | PAINT_ONLY（3 轮） | 1.25–1.34/1.56–1.62 | **6.84–7.16/7.51–8.38** | 0 |
| Impeller | SCROLL（3 轮） | 5.88–8.08/9.15–9.95 | 14.87–16.18/16.89–17.11（一轮 p50 4.38 离群） | 0 |
| Skia | PAINT_ONLY（2 轮） | 1.27–1.30/1.63–1.65 | 3.77–5.86/7.08–9.64 | 0 |
| Skia | SCROLL（2 轮） | 7.35–7.53/9.27–9.54 | 5.40/15.84（双峰）/16.38–17.64 | 0 |

归因修正：

- **“滚动光栅成本来自 Picture 重建”被推翻**。零重建的缓存图全屏重绘本身在 Impeller 上就要 ~7ms；±120px 相的 6.1ms 与之同量级（此前把两者差异误读为重建驱动）。Picture 重建只体现在 build（4.6 → 1.3ms）。
- SCROLL 相对 PAINT_ONLY 的 raster 增量（约 +8–9ms）只能归因于新物化块的**首次绘制/上传**与视口移动，而非重录缓存图。
- Skia 的 PAINT_ONLY p50（3.8–5.9）低于 Impeller（6.8–7.2），SCROLL 呈双峰（缓存命中/未命中？），仅 2 轮不足以推荐后端切换；已按 §4.7 完成 12+12 轮交替与热控，未发现稳定后端优势，不建议切换。
- 结论：本机 60fps 缺口 = 全屏文本基线光栅（~7ms，后端/驱动相关）+ 新内容首次光栅（~8–9ms，虚拟化渲染的固有成本）。继续压榨需要后端层手段（图片光栅缓存、减少每帧新内容面积），引擎侧无免费优化；A 档 ≤33ms 标准仍由当前实现满足。日志：`build/adr0036-evidence/paint-only-impeller.log`、`paint-only-skia.log`。

### 4.7 B1 后端 A/B：Impeller vs Skia（2026-10-31）

§4.6 的 Skia 数据只有 2 轮，不足以判断旧 Mali 设备是否应关闭 Impeller。本轮补齐 12 + 12 轮 ABBA 交替复测，24 轮全部通过完整性校验（单实例串行、每轮一次成功）。

方法：

- 设备同上（JNY-AL10 / Android 10 / Kirin 810，Mali-G52；Impeller 实际走 Vulkan）。profile APK 仅 arm64-v8a；同一安装包通过 `am start --ez enable-impeller true|false` 切换后端，每轮核对 `Using the Impeller rendering backend (Vulkan).` 只出现在 Impeller 轮，Skia 轮为 0 次。
- 原 ADR 0036 探针源码未入库且已清理，本轮在 `build/perf_probe` 重建：结构对齐 §4.4 的 901 元素长文（DOC 断言 `elements=901`、`rawChildren=1801`、`section270Id=2425`），但正文更长，实测 extent 99671.96（原 82928.96）。因此本节的绝对耗时只在轮间比较，不与 §4.5/§4.6 直接对比。
- 相位：冷启动 → WARMUP → 冷深跳/回顶 → PAINT_ONLY（5 s，仅 `markNeedsPaint()`）→ SCROLL（20 s，每帧 500 px，约 6 次全文往返；每帧跨窗口并触发新块物化）。每轮 force-stop + 10 s 冷却；顺序为 I,S,S,I 重复 6 次（ABBA）。
- 帧分类：Ticker 起始快照 + post-frame 结束快照记录 layout 身份与 `rebuilt` 计数。PAINT_ONLY 的 stable 子集为 256–259 帧，`changing=0`、`rebuiltDelta=0`；SCROLL 在 500 px/帧扫掠下全部帧重排/重建（stable=0），因此用 PAINT_ONLY 作为同身份基线。
- 温度：电池全程 29–30°C，未见热漂移；`dumpsys thermalservice` 的 GPU 传感器固定 54.0°C（不可用），本节不据此判断 GPU 热状态。
- 统计：表中为 12 轮中位数（括号内为 min–max）；p 值为对中位数差的双侧置换检验（每组 n=12）。

| 指标（ms） | Impeller | Skia | Δ 中位数（Imp−Skia） | p |
|---|---|---|---|---|
| PAINT_ONLY raster p50 | 5.78（3.75–16.38） | 5.07（3.93–9.70） | +0.71 | 0.70 |
| PAINT_ONLY raster p95 | 8.77（7.61–18.25） | 9.75（5.05–17.16） | −0.98 | 0.42 |
| SCROLL raster p50 | 4.47（4.45–14.60） | 5.00（4.58–10.72） | −0.53 | 0.68 |
| SCROLL raster p95 | 13.50（7.88–17.22） | 14.38（10.58–16.40） | −0.88 | 0.65 |
| SCROLL total p95 | 25.70（21.02–27.97） | 24.49（23.43–28.18） | +1.20 | 0.33 |
| SCROLL build p95 | 13.38（12.99–13.65） | 13.01（12.13–13.18） | +0.38 | 0.001 |

观察与结论：

- 唯一统计显著的是 SCROLL build p95（Skia 低 0.38 ms），与光栅无关，对帧预算没有实际意义。
- 光栅与 combined 的轮间离散度远大于后端中位数差：SCROLL total p95 覆盖 21.0–28.2 ms，而中位数差仅 1.2 ms，且 p=0.33。多轮 raster p50 在约 4 ms 与 7–10 ms 两档之间跳变，提示 DVFS/频率状态主导轮间波动；按 4 轮一组的 ABBA 配对方向也不一致（前三组 Impeller 更低，后三组 Skia 更低或接近）。
- **没有可复现证据支持在旧 Mali 设备关闭 Impeller**；不建议把后端切换作为冲 60fps 的手段。strict 60fps 仍未达成（本轮 SCROLL total p95 中位 24.5–25.7 ms），光栅缺口仍由基线全屏绘制与新内容首绘构成，与 §4.6 一致。
- 限制：重建探针的正文长度与 §4.4 不同，而且 500 px/帧扫掠是压力相，不代表慢速自然滚动；`FrameTiming.rasterDuration` 仍含排队/围栏等待。证据：`build/adr0036-evidence/b1/`（原始 logcat、perf 过滤、`summary.tsv`、`report.md/json`）；临时探针与 workspace 项已清理。
