# 0035 · QuickJS 移动平台构建（Android CMake、iOS 静态链接、加载分派）

日期：2026-10-28 · 状态：已接受 · 阶段 6（发布前补齐）

## 背景

阶段 4 用 vendor QuickJS + `dart:ffi` 交付了受限 JS，但构建路径只有一个：
`tool/build_native.sh` 在开发机/CI 上编出桌面动态库（Windows `weft_quickjs.dll`、
Linux `libweft_quickjs.so`）。包内既没有 `android/` 也没有 `ios/`：

- Android 上 APK 不会包含任何原生库，`DynamicLibrary.open` 无库可载；
- iOS 上更根本：App 不能像桌面那样分发并 `dlopen` 一个独立 dylib。

真机因此完全无法执行脚本，README 一直把它列为发布阻断项。移动端与桌面
的约束不同，需要分别决策。

## 决策

### D1 · 用 FFI 插件声明，但不让包依赖 Flutter

`packages/weft_quickjs/pubspec.yaml` 增加：

```yaml
flutter:
  plugin:
    platforms:
      android: { ffiPlugin: true }
      ios: { ffiPlugin: true }
```

插件元数据只被宿主 App 的构建读取，包本身仍然只依赖 `ffi` 与
`weft_runtime_api`，**不 import Flutter**。这样 `dart test` 继续用纯 Dart
测试运行器跑完全部 28 项（含真实 QuickJS 执行），不引入 widget 测试环境；
`environment.flutter` 只表达平台工程要求的最低 Flutter 版本。

### D2 · Android：模块内 `externalNativeBuild` 就地消费 vendor 源码

`android/build.gradle` 注册 `src/main/cpp/CMakeLists.txt`，CMake 直接引用
`native/` 下的 6 个 C 文件（`weft_glue.c` + quickjs/lregexp/libunicode/
cutils/libbf），**不复制、不生成中间副本**——桌面脚本与移动构建编译同一批
文件，避免两份源码漂移。

编译/链接参数：

- 与桌面一致：`-std=gnu99`、`-fno-strict-aliasing`、`-D_GNU_SOURCE`、
  `-DCONFIG_BIGNUM`、`CONFIG_VERSION="2024-01-13"`；
- `-fvisibility=hidden`：只让 `WEFT_EXPORT` 的 10 个入口进入动态符号表，
  QuickJS 内部符号不外泄（也避免与宿主自带库重名）；
- `-Wl,-z,max-page-size=16384`：Play 对 targetSdk 35+ 要求 16 KB 页对齐，
  NDK r27 的 lld 仍按 4 KB 布局，必须显式请求；对齐更宽对 4 KB 设备兼容；
- `compileSdk 36` / `minSdk 21` / `ndkVersion 27.0.12077973`：与 Flutter
  3.35 的默认值一致，避免宿主工程出现"NDK 未安装"的二义性。

### D3 · iOS：pod 把垫片编进 app image，锚点防 dead-strip

`ios/weft_quickjs.podspec` 把 `native/` 的源码与 `Classes/` 一起作为 pod
源文件编译进宿主二进制，Dart 侧用 `DynamicLibrary.process()` 解析符号。
选择静态链接而不是 xcframework 的理由见"备选与取舍"。

一个容易踩的坑：CocoaPods 的文件模式**不支持 `..` 穿越父目录**（podspec
指南 "File patterns" 明写）。所以 podspec 不用 `'../native/**/*'`，而是在
求值时用 `Dir.glob(File.expand_path('../native', __dir__))` 展开成绝对路径
数组交给 `source_files`。开发 pod（`:path`）本身就在 Pods sandbox 之外，
绝对引用与 Flutter 插件平时的引用方式同源；若某个 CocoaPods 版本仍拒绝
sandbox 外的绝对路径，回退方案是把 vendor 源码移进 `ios/`。

静态链接还有一个陷阱：CocoaPods 产出静态库，链接器只拉取"能解决未定义符号"
的目标文件；Dart 是运行时 `dlsym`，链接期看不到任何引用，`-dead_strip`
会把 `weft_*` 乃至整个 QuickJS 丢掉。两道保险：

1. `WEFT_EXPORT` 在非 Windows 下增加 `__attribute__((used))`，函数级保留；
2. `ios/Classes/WeftQuickJsAnchor.m` 定义带 `+load` 的 ObjC 类（CocoaPods
   传 `-ObjC`，类必被链接），在 `+load` 中取 `weft_now_ms` 地址，制造一个
   未定义引用，强制拉入 `weft_glue.o` 及其引用的 QuickJS 目标文件。

### D4 · 加载分派：显式路径 > 平台默认

`lib/src/library_loader.dart` 的 `librarySourceFor()` 决定来源：

| 优先级 | 条件 | 行为 |
|---|---|---|
| 1 | `explicitPath` 或 `WEFT_QUICKJS_LIBRARY` 非空 | `DynamicLibrary.open(path)` |
| 2 | iOS | `DynamicLibrary.process()` |
| 3 | Android | `DynamicLibrary.open('libweft_quickjs.so')` |
| 4 | 其余（桌面/CI） | 沿用 `resolveLibraryPath()` 的文件搜索 |

失败时 `describeLoadFailure()` 按来源给补救：iOS 提示 `pod install` 后重建、
Android 提示重打 APK、桌面提示跑 `build_native.sh`。显式路径仍可在真机上
覆盖为自定义构建（调试/热替换）。

## 备选与取舍

- **Android 用 prefab 分发预编译 `.so`**：需要预编译产物入库或额外 AAR，
  ABI 矩阵与 flag 容易和桌面漂移；源码就在仓库，就地编译更简单。
- **iOS 打包 `.xcframework`**：最接近"预编译分发"，但需要 macOS 构建机，
  二进制入库后源码与产物成为两份真相；当前仓库没有 macOS CI。代价是 iOS
  首次构建要多编一次 QuickJS（桌面测约 1 分钟量级）。
- **iOS 用 `-force_load` 指向 pod 静态库路径**：路径依赖 CocoaPods 内部
  目录布局，升级易断；锚点只依赖标准的 `-ObjC` 行为。
- **把 `android/`、`ios/` 放进独立 federated 包**：当前只有 Android/iOS
  两个平台且共享同一份 native 源码，拆包会引入无收益的间接层。

## 验证与边界

已验证（Windows + Flutter 3.35.5 + NDK 27.0.12077973 + Android SDK 36）：

- `flutter build apk --debug` 成功（临时探针 App 依赖 `weft_quickjs`，
  构建后已删除）；
- APK 内 `lib/arm64-v8a`、`lib/armeabi-v7a`、`lib/x86_64` 三个 ABI 均含
  `libweft_quickjs.so`（arm64 约 1.1 MB）；
- `llvm-nm -D --defined-only` 显示恰好 10 个 `weft_*` 导出、无 QuickJS
  内部符号；`llvm-readelf -l` 的 LOAD 段对齐为 `0x4000`（16 KB）；
- 桌面 `dart test`（weft_quickjs 28 项）通过；新增 6 项加载分派与错误
  文案单测。

真机执行（2026-10-28，Huawei JNY-AL10 / Android 10 / arm64-v8a，debug
APK 仅 arm64）：

- `DynamicLibrary.open('libweft_quickjs.so')` 成功；
- `({a:1,b:"x",c:[true,null]})` 回读为 `{a: 1, b: x, c: [true, null]}`，
  `"weft-" + (40 + 2)` 得到 `weft-42`；
- 持续分配数组以 `RuntimeFailureKind.memoryLimit` 中断；
- `while (true) {}` 在 2s 预算处返回 `RuntimeFailureKind.timeout`，说明
  原生中断处理器在真机生效。

未验证（不得当作已验收）：

- **iOS 构建与运行**：需要 macOS + Xcode + CocoaPods；本机（Windows）既无
  Ruby 也无 CocoaPods，podspec 只经过代码审查与官方语法文档核对，未执行
  `pod install` / `pod lib lint`。

iOS 一项记入 `docs/device-matrix.md` 的待补证据，发布前必须补齐。

## 后续

- 真机跑 `weft_lab` 的 runtime 示例，把结果填进设备矩阵。
- iOS 构建若发现符号仍被剥离，优先检查 `-ObjC` 是否被宿主 Podfile 覆盖
  （`use_frameworks!` 场景下 pod 变动态框架，`process()` 仍可用，但锚点
  逻辑要重新评估）。
- 若后续要支持 macOS 桌面，可复用 pod 思路，或继续走 `build_native.sh`。
