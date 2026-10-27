# ADR 0033：受限 JavaScript 运行时与自定义标签扩展（阶段 4）

- 状态：已接受
- 日期：2026-10-27

## 背景

阶段 4 要求接入 QuickJS、单文档 Context、状态/事件/网络能力、资源中断和恢复，并交付自定义标签与 FakeRuntime 契约示例。验收：无限循环与内存炸弹在配置预算内中断且 UI 保留最后可用帧；未启用能力不可见、白名单重定向与非法协议被拦截；恢复不自动重放网络副作用且命令序号可去重；替换后端不修改引擎核心。

## 决策

### 1. QuickJS 通过扁平 C 垫片接入，JSValue 不跨越 FFI 边界

- QuickJS 2024-01-13（MIT）源码 vendor 到 `packages/weft_quickjs/native/quickjs/`，由 `tool/build_native.sh` 编译为单个动态库（Windows `weft_quickjs.dll` / POSIX `libweft_quickjs.so`），构建产物不入库，CI 从同一份源码构建。
- `native/weft_glue.c` 暴露纯指针/整数 ABI：`weft_new_runtime / weft_eval / weft_pump_jobs / weft_resolve / weft_send_event / weft_install_bridge`。JSON 是唯一编组格式；Dart 侧 `QuickJsFfiSession`（`dart:ffi`）解析结果信封。
- 预算在原生层强制：`JS_SetMemoryLimit`（内存）、`JS_SetMaxStackSize`（栈）、`JS_SetInterruptHandler` + 单调时钟 deadline（墙钟，覆盖脚本、Promise 任务与所有同步执行）。异常消息分类为 `timeout/memory/stack/script`；微任务预算由 `JS_ExecutePendingJob` 泵计数产生新的 `RuntimeFailureKind.microtaskBudget`。
- 桥接是异步的：`__weftBridge(ns, method, argsJson)` 由 C 垫片创建 Promise 并登记 `(callId, resolve/reject)`；Dart 回调（`NativeCallable.isolateLocal`）解析请求、经 `BridgeDispatcher` 分发，完成后 `weft_resolve` 回填并泵 Promise 任务。
- 防风暴：单个事件循环轮次内超过 4096 次能力调用的链式风暴直接以错误回填，微任务级联不再饿死事件循环；`settle()` 以 256 轮为界报告未收敛。

### 2. 能力面：未启用即不可见，网关是第二道闸

- `weftCapabilitiesBootstrap(enabled)` 生成会话引导脚本，只为启用命名空间安装 `weft.state/events/net`——JS 里 `typeof weft.net === 'undefined'`（有真实 QuickJS 测试证明）。
- `CapabilityGateway`（`weft_capabilities`）实现 `BridgeDispatcher`：按 `CapabilityPolicy` 拒绝未启用/未安装/描述符外方法（`WeftCapabilityDenied`），构造时拒绝"安装了但未启用"的模块组合。
- 内置模块：`weft.state`（宿主 `WeftStateStore`）、`weft.events`（emit 到宿主；宿主经 `session.send` 进 JS `__weftOnEvent` 分发）、`weft.net`（GET-only fetch）。

### 3. 网络策略与副作用审计

- 引擎核心不持有网络客户端：`WeftNetworkClient` 由宿主注入，`WeftNetworkPolicy` 要求 scheme 白名单 + host 精确白名单（空集 = 全拒绝）。
- `fetch` 在调用客户端前校验 URL（`file:`、`javascript:`、`data:` 直接拦截，客户端调用数为 0），响应回填后逐跳校验 `redirectChain`——重定向离开白名单即失败且不交付 body；跳数与响应体大小有上限。
- `WeftNetworkJournal` 记录每次副作用（requested/completed/blocked/failed），跨恢复保留。

### 4. 恢复语义：不重放、可去重

- `WeftDocumentRuntime`（`weft` 包）是单文档 JS 宿主：一个会话、一个网关、一份审计。`recover()` 只重跑能力引导，不重跑文档脚本、不重发任何已记账请求。
- 网关按 `(sessionId, sequence)` 记录已结算调用；恢复后重投递的旧命令命中去重，返回记账结果而不再执行模块——网络客户端跨两轮调用恰好一次（有测试证明）。

### 5. 契约测试与 FakeRuntime

- `packages/weft_runtime_contract` 输出后端中立契约测试（值返回、错误、四类预算中断、桥接路由、事件、settle、dispose 后拒绝），`packages/weft_runtime_fake` 提供脚本化 `FakeRuntimeBackend`（墙钟超时真实执行，堆/栈/微任务以上下文助手模拟）。
- QuickJS FFI 后端与 FakeRuntime 通过同一契约套件；编排层测试在两者上运行（Fake 常驻，QuickJS 在库可用时运行）——"替换后端不改引擎核心"由测试结构保证。
- `FakeRuntimeBackend` 默认对 `weft/bootstrap` 执行空操作；`execute` 使用 `Future.sync` 而非 `Future()`，后者经 `Timer.run` 在 testWidgets 的 FakeAsync 区里永不触发。

### 6. 自定义标签：受信任 Dart 渲染器，非 JS 注册

- 规范化器接受 `customTags` 白名单：命中标签保留为**属性驱动的叶子元素**（class/id/style + 任意 `name ≤ 64` 且非 `on*` 的属性，值截断 1024；`href/src` 仍走既有清洗），内部内容丢弃并产出 `html.tag.custom.contentIgnored` 诊断；不在白名单的未知标签保持原有展开行为。
- `WeftTagRenderer.layout(context) → WeftTagLayout{height, ops, semanticsLabel}`：ops 仅 `WeftTagRectOp` / `WeftTagTextOp`（文本由引擎以 `TextPainter` 按 `textScaler` 整形），引擎钳制到内容盒、以元素 NodeId 归属、转成常规绘制命令——分块渲染、命中裁剪与命令复用零改动。渲染器抛异常退化为空盒。
- 自定义标签默认 `display: block`（作者 CSS 仍可覆盖），永不自折叠；`WeftLayoutResult.tagRegions/tagAt` 提供命中，`WeftSurface.onTagTap`/`WeftView.onTagTap` 回调宿主，语义树输出渲染器标签。渲染器集合的**实例同一性**参与增量块复用判定，换集合即整页重排。
- 块级缓存 `WeftCachedLayoutBlock` 增加 tagRegions 分片，复用路径原样回放。

## 后果

- 引擎核心（weft_engine）不知道任何 JS 后端；weft_quickjs 不知道布局；编排层只依赖 `weft_runtime_api` 契约——替换后端不需要修改引擎或编排代码。
- 换后端不自动获得相同性能或安全属性：真实的中断证据在 QuickJS FFI 测试（本机及 CI 构建后运行；库缺失时跳过并提示构建命令），FakeRuntime 的堆/栈/微任务是模拟执行。
- 未尽事项：bridge 风暴上限按轮次计数而非累计预算；`weft.net` 仅 GET；自定义标签不支持行内混排与 Float 环绕（opaque 块）；JSON 编组将 undefined 折叠为 null。这些在阶段 5 画像后重估。

## 验收证据映射

| 验收项 | 证据 |
|---|---|
| 无限循环/内存炸弹预算内中断，UI 保留最后可用帧 | `quickjs_session_test.dart`（timeout/memoryLimit/stackOverflow/microtaskBudget）、`weft_runtime_view_test.dart`（失败后命令逐项一致、无异常） |
| 未启用能力不可见，白名单重定向与非法协议拦截 | `weft_runtime_quickjs_test.dart`（`typeof weft.net === 'undefined'`、file:// 拦截且客户端 0 调用）、`capability_modules_test.dart`（重定向出白名单被拦、跳数上限） |
| 恢复不重放网络副作用，命令序号可去重 | `weft_document_runtime_test.dart`（恢复后客户端仍 1 次调用、重投递命中记账结果、新会话可再请求） |
| 后端替换不修改引擎核心 | `runtime_contract.dart` 契约套件同时跑 FakeRuntime 与 QuickJS；编排层仅依赖契约接口 |
