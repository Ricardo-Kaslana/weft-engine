# 0034 · 回退、硬化与发布（快照 JSON、一致性向量、模糊测试、发布兼容）

日期：2026-10-27 · 状态：已接受 · 阶段 5

## 背景

阶段 0–4 交付了渲染、选择、性能与受限 JS，但三件事在发布前仍缺：

1. 服务端/客户端规范化一致性没有机器可验证的契约——服务器规范化一次、
   客户端直接消费的管线（省流量/省电）无从谈起。
2. 对抗性输入只覆盖了手工构造的敌意用例（ADR 0032），没有系统性的模糊
   测试；发布前需要硬化扫描。
3. 版本兼容与回滚只有口头约定：快照结构、bridge 协议、bootstrap 脚本
   的版本锚点没有固化，回滚路径没有演练。

## 决策

### D1 · 快照 JSON 线格式（`WeftDocumentJson`）

`WeftDocumentSnapshot` 获得规范 JSON 编解码（`packages/weft_document/lib/
src/document_json.dart`）：`format` 标签 + 整数 `version` 门禁。编码确定性
（插入序保持、选择器 class 排序），解码严格（类型逐字段校验、未知版本以
`FormatException` 拒绝——**宁可回退失败也不静默误读**）。选 JSON 而非二进
制：诊断/审查友好，服务端语言无关，体积在文章语料下不是瓶颈。

### D2 · 规范化一致性向量（`conformance/normalization/`）

21 个向量 = 11 个 conformance 语料 + 10 个合成用例（脚本回退、嵌套表格、
自定义标签、CJK/emoji、实体、void/注释、不支持元素、表格列轨道、解析警
告、列表引用）。每个向量固化「输入 + normalizer 配置 + 期望快照字节」。
测试逐字节复现；重新生成必须人工审查 diff（与浏览器几何基线同政策）。
这就是「服务端/客户端规范化一致性」的验收：符合契约的生产者对记录输入必
须产出记录字节。

### D3 · 模糊测试（种子化，双层）

- CI 层：`packages/weft_document/test/fuzz_test.dart`（400+ 迭代 + 不同
  种子），不变量：不抛异常、issue 数 ≤ maxIssues、节点 id 唯一且父子递增、
  body/normalizedHtml 一致性、抽样 encode→decode→encode 字节稳定。
- 发布层：`tool/fuzz.dart` CLI（默认 2 万迭代，`--iterations` 可放大），
  崩溃输入写 `build/fuzz/` 复现。
- 语料 = conformance HTML + 一致性向量输入，变异算子 8 类（截断、字符翻
  转、切片复制/删除、标签汤注入、嵌套炸弹、属性风暴、实体风暴）。

硬化修正（模糊测试直接发现）：诊断列表的 `parser.errors` 与样式表诊断两
条路径绕过 `maxIssues` 上限（已改为统一封顶入口）；`package:html` 的
`ParseError.toString()` 在敌意输入下自身抛空指针（诊断生成改为防御性
`_safeDescribe`，退化到 runtime type）。

### D4 · 能力开关矩阵

`packages/weft/test/runtime_capability_matrix_test.dart` 覆盖 built-in
能力的全部 8 个策略子集：启用的能力探针通过、禁用的被网关拒绝且无副作用
（网络客户端调用数严格等于策略允许数）；bootstrap 只引用启用的命名空间。
JS 整体关闭不需要开关：`WeftView` 不依赖 runtime，不开 `WeftDocumentRuntime`
即无 JS。

### D5 · WebView 回退示例（`example/weft_fallback`）

`webview_flutter` 只进示例包，核心包保持零依赖（架构 §8）。`decideWeft
Fallback` 纯函数给出三路决策（原生渲染 / requiresWebView→宿主 WebView /
错误卡片）；`WeftFallbackCoordinator` 持有宿主原始 HTML 并注入平台 WebView
构造器，widget 测试用占位 WebView 走完整决策路径，不触平台通道。

### D6 · 版本兼容与回滚演练（`docs/release-runbook.md`）

全包统一版本号一起升；兼容锚点固化为表（`WeftDocumentJson.version=1`、
`bridgeVersion: 1`、`weft/bootstrap`、向量基线）。回滚演练自动化在
`packages/weft_document/test/release_compat_test.dart`：旧向量逐字节复现
（钉回旧版仍可读旧文档）、新版本快照被拒、外格式被拒、锚点值与文档一致。

### D7 · API 文档门禁（`tool/doc_coverage.dart`）

扫描每个包入口导出（含 part）的全部公开声明，要求 `///` 文档；零缺口才
过门禁。发布检查清单将其列为第 2 步。

## 备选与取舍

- **快照二进制格式（CBOR/flatbuffers）**：更小更快，但服务端实现成本与
  审查成本高；文章语料 JSON 尺寸可接受（21 向量合计 <100KB）。留待真实
  流量画像驱动。
- **`public_member_api_docs` lint**：会把引擎内部（part 文件、非导出
  src）一并纳入，噪音大；专用扫描器只覆盖导出面，误报可控。
- **模糊测试放 CI 长跑**：CI 时间预算不允许；分层（CI 快跑 + 发布前
  CLI 长跑）兼顾。
- **weft_fallback 用真实 WebView 进 widget 测试**：需要平台通道桩，收益
  低；注入占位已覆盖决策契约，真机行为归 device matrix 流程。

## 后续

- 真机矩阵首轮数据（docs/device-matrix.md 结果表）在下一阶段设备轮填入。
- 快照格式 v2（若引入）必须在同一提交更新 runbook §2 表 + 向量 +
  release_compat_test 分组。
