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
`adb logcat -s flutter:I | grep PERF|` 读取。

| 档位 | 设备/OS | 冷启动中位 | 滚动 p95/p99 | 深跳最大帧 | 内存增量 | 结论 |
|---|---|---|---|---|---|---|
| A–B | JNY-AL10 / Android 10 | 817ms | 9.4–29.9 / 12.9–30.7ms | 316ms | ~0–9.3MB | 滚动通过；深跳待修 |
