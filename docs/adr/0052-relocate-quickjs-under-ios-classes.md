# ADR 0052：将 vendored QuickJS 放进 iOS pod 的 Classes 目录

- 状态：已接受
- 日期：2026-11-01

## 背景

iOS 构建验证首次暴露了一个此前只经过代码审查、没有在 macOS 上执行的缺陷：

- 原 podspec 将 `source_files` 设置为 `Dir.glob(File.expand_path('../native', __dir__))`，生成绝对路径。
  CocoaPods 报 `File patterns must be relative and cannot start with a slash`，`pod install` 直接失败。
- 改成相对 `../native/**/*.{c,h}` 后 `pod install` 可以完成，CocoaPods 也不会遍历父目录，
  实际没有收集任何 QuickJS 源文件；app 仍能构建，但链接结果中只有 `_main`。
- 加上 `-Wl,-u,_weft_now_ms` 强制引用后，链接器报 `Undefined symbol: _weft_now_ms`，
  证明静态库确实没有包含 vendored 源文件，而不是符号被单纯 dead-strip。

CocoaPods 的 podspec 文件模式要求路径位于 pod 根目录内；`prepare_command` 在本地开发 pod
上的执行时机也不稳定。继续把原生源码放在包根目录的 `native/`，只能依赖符号链接或复制，
两者都会给 Windows checkout、缓存一致性或后续维护带来额外风险。

## 决策

1. 将 `packages/weft_quickjs/native/quickjs/` 与 `native/weft_glue.c` 移到
   `packages/weft_quickjs/ios/Classes/native/`。
2. `weft_quickjs.podspec` 使用合法相对模式 `Classes/**/*.{c,h,m}`；
   license 路径也改为 `Classes/native/quickjs/LICENSE`。
3. 桌面构建脚本、Android CMake 和 Dart 动态库候选路径统一指向新位置；
   桌面动态库构建产物仍位于 `ios/Classes/native/build/`（gitignored）。
4. 保留 `s.user_target_xcconfig` 的 `-Wl,-u,_weft_now_ms`。Flutter 宿主不保证
   `-ObjC`，这个引用把 `weft_glue.o` 及其 QuickJS 对象拉入最终链接；ObjC
   `+load` 锚点保留为第二道保险。
5. iOS 编译也必须带 `-fvisibility=hidden`，与 Android/桌面一致；只有
   `WEFT_EXPORT` 的 10 个入口应为默认可见符号，内部
   `weft_register_bridge_function` 不得出现在导出集合中。
6. 这是唯一一份源码，不复制到 Android 或桌面目录；所有平台继续使用同一批 C 文件。

## 验证

`macOS 15` CI 任务会创建临时 iOS 宿主，通过 Git 依赖引入 `weft_quickjs`，
执行 `pod install`、无签名 release 构建，并扫描 app bundle 中 Runner 与
framework 的完整 `_weft_*` 符号集合（期望 10 个）。该任务通过前，不把 iOS
构建称为已验证。

真机/模拟器的 `QuickJsNativeLibrary.load()` 与脚本求值仍是后续验收项；
本次只证明构建、CocoaPods 集成、链接与导出符号。

## 后果

- iOS 构建不再依赖绝对路径或父目录 glob，podspec 可由 CocoaPods 正常校验。
- 原生源码路径变得 iOS 中心化，但桌面脚本和 Android CMake 显式共享同一目录，
  不存在副本漂移。
- 历史上的 ADR 0035 记录了当时的绝对路径尝试；本 ADR 覆盖其中的路径部分，
  静态链接、dead-strip 防护和平台加载分派仍沿用 ADR 0035。
