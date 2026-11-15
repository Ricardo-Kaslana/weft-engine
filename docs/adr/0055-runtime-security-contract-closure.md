# 0055 · Runtime 安全契约闭环(bridge 字节/深度/队列上限与销毁竞争钉死)

日期:2026-11-16 · 状态:已接受 · 阶段 6 M1

## 背景

阶段 6(M0,ADR 0054)启动 M1 时,对账 `docs/security.md`、公开 Runtime
契约(`weft_runtime_api`)与 QuickJS/Fake 后端实现,发现文档描述的边界与
实现不一致:

| # | security.md 主张 | 实现现状 | 判定 |
|---|---|---|---|
| G1 | 桥接限制消息**字节数** | 契约无字段;QuickJS 请求/结果/事件三向均无门禁(请求方向仅受 JS 堆预算 16MB 间接约束) | 实现 |
| G2 | 桥接限制消息**深度** | `jsonDecode`/`jsonEncode` 无深度检查,任意嵌套都可穿越 | 实现 |
| G3 | 桥接限制**队列长度** | 单轮风暴帽 4096 是 QuickJS 私有常量(ADR 0033),非契约;跨轮 in-flight 派发集合无上限;Fake 后端无任何帽 | 实现 |
| G4 | 网络等异步操作有**取消令牌与独立 deadline** | `WeftNetworkPolicy` 只有 schemes/hosts/maxResponseBytes/maxRedirects;挂起的宿主派发无法取消 | 降级并改写文档 |
| G5 | 撤销和销毁后**立即失效** | 实现有 `_disposed` 守卫(bridge 回调/派发/回解三处),但契约测试只钉了 dispose 后调用,未钉「dispose 时仍有 in-flight 派发」的竞争 | 实现测试 |
| G6 | 恢复**不重放副作用** | 网关 `(sessionId, sequence)` 去重 + journal 已实现并有测试;「旧会话 in-flight 派发跨 recover 落地」未测 | 实现测试 |

## 决策

### D1 · `BridgeLimits` 进入公开契约

`RuntimeConfig` 新增 `bridgeLimits`(默认 `const BridgeLimits()`):
`maxMessageBytes = 256KB`、`maxDepth = 32`、`maxInflightCalls = 256`。
字节按值的 JSON 编码(`utf8(jsonEncode(value))`)计量,深度按 Map/List
嵌套层数计量——两个后端用 `weft_runtime_api` 导出的同一校验器,保证语义
一致。新值类型为纯 Dart,`weft_document` 快照格式与 bridge 协议不变。

### D2 · 违规以结构化失败拒绝,永不进入派发器

新增 `RuntimeFailureKind.bridgeLimit`。三个方向的违规(请求参数超限、
能力结果超限、事件载荷超限)都在 session 层拦截:

- QuickJS:违规调用经 `_resolveBridge` 以 `kind: 'bridgeLimit'` 的错误
  envelope 解析对应 JS promise(已挂起的调用不悬空),脚本看到被拒绝的
  promise,execute/settle 收敛为 `bridgeLimit` 失败;
- Fake:`issueBridge` 抛 `JsSessionFailure(bridgeLimit)`,行为捕获后按
  普通脚本失败处理;
- 两个后端都保证:违规调用**永不进入** `BridgeDispatcher`/能力网关,
  journal 不记账,网络客户端不被调用。

字节帽挡住的是解码、派发与 journal 记账;请求方向的瞬态字符串在检查前
已被物化,其上界由 JS 堆预算(原生强制)约束——两层叠加后 Dart 侧不处理
超限载荷。

### D3 · 队列上限两层,语义不同

- **单轮风暴帽(4096/轮)**保持 ADR 0033 的 fail-fast 语义不变、不进
  `BridgeLimits`:它防的是事件循环饿死,违规即置 storm failure 停止派发,
  不是资源配额。
- **in-flight 帽(`maxInflightCalls`)**是新资源配额:已在途的跨轮派发
  数达到帽时,新调用以 `bridgeLimit` 结构化拒绝,不排队。Default 256 与
  网关 journal 容量同阶。

### D4 · 取消令牌与 deadline 降级,security.md 改写为真实边界

0.7.0 不引入取消令牌 API。理由:取消必须贯穿 `BridgeDispatcher` 与宿主
`WeftNetworkClient`,否则只是「弃单不撤源」的安慰剂;而 HTTP 层 deadline
本来就是宿主 client 的职责(引擎不创建 transport,与图片解析器同一分工)。
结构性防线已足够收口资源:

1. 脚本执行自身受墙钟/堆/栈/微任务四类原生预算强制;
2. settle 有 256 轮上限,微任务有每轮帽;
3. in-flight 派发数有帽(D3),不会随时间无界累积;
4. dispose 后旧会话的派发结果被丢弃(`_disposed` 守卫),无 use-after-free;
5. 网络副作用幂等由网关 journal 去重保证,恢复不会二次扣款。

`WeftNetworkPolicy` 维持现状(schemes/hosts/maxResponseBytes/maxRedirects);
`security.md` 改写为:deadline 由宿主 client 实现,引擎保证的是上述五条
结构性防线。

### D5 · journal 保留上界的既有事实写入文档

网关 journal 容量 256 条;条目字节由模块输出策略约束(`weft.net` 的
`maxResponseBytes` 已有)。session 帽护 JS/Dart 边界,不重复管 journal。

### D6 · 契约测试与竞争钉死

- `weft_runtime_contract` 新增 `registerJsSessionBridgeSecurityTests`:
  超限参数、深嵌套参数、超限结果、in-flight 帽、dispose 竞争五组;QuickJS
  FFI 与 Fake 后端注册(参数帽按测试注入的小值);trivial inline 后端不
  注册(无真实编组,套件文档注明注册义务属于实现编组的后端)。
- `weft` 包补 recover 竞争测试:旧会话 in-flight 网络派发跨 recover 落地
  ——结果被丢弃、不触达新会话、网络客户端跨两轮恰好一次。

## 备选与取舍

- **在网关层统一 enforcement**(装饰 `BridgeDispatcher`):单点实现,但
  契约测试与自定义宿主直接注入 dispatcher 时不经过网关,session 层会裸奔;
  边界属于 JS/Dart 穿越,归属 session。
- **为字节帽改 C 垫片传长度**:可在物化前拒绝,但要改 FFI ABI 并重编
  三平台;瞬态物化已被 JS 堆预算约束,增量收益不抵 ABI 风险,留案。
- **给 `WeftNetworkPolicy` 加 requestTimeout**:`.timeout()` 只弃单不撤
  底层请求,与不做取消令牌同理,降级(D4)。
- **in-flight 帽也 fail-fast**:会让脚本在慢宿主下不可恢复;结构化拒绝
  让脚本能感知并停止,与风暴帽的「饿死防线」语义分开(D3)。

## 后果

- `weft_runtime_api` 公开面新增 `BridgeLimits`、`RuntimeConfig.bridgeLimits`、
  `RuntimeFailureKind.bridgeLimit`;`WeftDocumentRuntime.open` 透传。
- QuickJS/Fake 行为在超限路径上有可观察变化(此前无限穿越/排队,现在结构
  化拒绝)——属安全边界收紧,非回归。
- 像素黄金、快照向量、布局行为零变化(纯 runtime 层)。

## 验证

- 契约套件(QuickJS + Fake)新增安全组全绿;trivial 套件不变全绿。
- `weft` recover 竞争测试全绿。
- `tool/check.sh` ALL GREEN;像素黄金零 diff。
