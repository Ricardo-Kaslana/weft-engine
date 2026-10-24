# ADR 0004：将 QuickJS 隐藏在可替换 Runtime 接口后

- 状态：已接受
- 日期：2026-10-25

## 背景

QuickJS 的轻量解释执行符合受控场景，但原生 FFI、平台构建和生命周期具有长期维护成本，核心不应依赖其 C API。

## 决策

以 `JsRuntimeBackend/JsSession` 为唯一核心边界，QuickJS 通过 `QuickJsNativeAdapter` 接入。Runtime 按文档隔离，执行预算、桥接和错误类型保持后端中立，所有后端通过同一契约测试。

## 后果

该方案支持 FakeRuntime 和未来 Wasm 等后端，但增加少量适配工作。替换后端不自动获得相同性能或安全属性，仍需独立通过中断、内存和恢复测试。当前尚未接入真实 QuickJS。
