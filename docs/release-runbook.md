# 发布与回退手册（ADR 0034）

本文定义 Weft 各包的版本策略、兼容契约、发布检查清单和回退演练。阶段 5 验收项
「发布产物版本兼容明确」与「回滚路径经过演练」的证据都在这里。

## 1. 版本策略

- 所有引擎包（weft、weft_document、weft_engine、weft_runtime_api、
  weft_capabilities、weft_runtime_fake、weft_runtime_contract、weft_quickjs）
  **共用一个版本号**，在同一个提交中一起递增。宿主升级时按同一版本对齐，
  不支持跨版本混搭。
- 当前基线：`0.6.0-dev.1`（阶段 5 之后，移动端构建 ADR 0035 进入本版本）。
  首个稳定版为 `1.0.0`，此前一切变更都在 CHANGELOG 的 Unreleased 小节累积。
  上一个基线是 `0.5.0-dev.1`（阶段 5），宿主回滚时可钉回该版本。
- 语义化版本：布局输出、选区语义、诊断码、快照格式、bridge 协议的任何
  可观察变化都算破坏性，必须升主版本或（1.0 前）升 minor 并在 CHANGELOG
  标注 Migration。

## 2. 兼容契约（代码内的版本锚点）

| 契约 | 锚点 | 当前值 | 变更要求 |
|---|---|---|---|
| 文档快照 JSON | `WeftDocumentJson.version` | `1` | 升版本必须保留旧版本读取路径或提供迁移；测试见 `packages/weft_document/test/release_compat_test.dart` |
| 能力 bridge 协议 | bootstrap 内 `bridgeVersion` | `1` | 与 `weftCapabilitiesBootstrap` 一起改；契约套件跟随 |
| bootstrap 脚本 id | `weft/bootstrap` | 固定 | 宿主依赖该 id 识别能力引导 |
| 快照格式标签 | `WeftDocumentJson.formatId` | `weft.document` | 永不改变（识别用） |
| 规范化输出 | `conformance/normalization/` 向量 | 21 个 | 变更必须重新生成并人工审查 diff |

## 3. 发布检查清单

发布前逐项执行，全部通过才允许打 tag：

1. `tool/check.sh`（format、analyze、全部包测试、像素黄金）通过。
2. `dart run tool/doc_coverage.dart` 报告公开 API 文档零缺口。
3. `dart run tool/fuzz.dart --iterations 50000`（或本地接受的更大规模）
   无崩溃；发现的崩溃要么修复，要么固化为一致性向量。
4. 布局相关变更：`packages/weft_engine/tool/golden_pixel_test.dart` 通过，
   `conformance/reference/` 下浏览器几何基线 diff 已人工审查。
5. CHANGELOG Unreleased 小节整理为本版本条目；ADR 若有新增已列入
   architecture.md §9。
6. 所有包 pubspec 版本一起更新为发布版本；`dart pub get` 重新解析无冲突。
7. 移动端原生库（ADR 0035）：Android 必查——`flutter build apk` 后确认
   APK 内 `lib/<abi>/libweft_quickjs.so` 存在、恰好导出 10 个 `weft_*`、
   LOAD 段 16 KB 对齐。iOS **若本次发布包含 iOS 产物**，还须在 macOS 上
   `pod install` 后 `nm` 查可执行文件确认符号未被剥离；当前 iOS 验证暂缓
   （无 macOS 环境），未验证前不得发布 iOS 产物，发布说明中要写明缺席。
8. 打 tag `v<版本>`；tag 信息列出本版本 CHANGELOG 条目。

## 4. 回滚路径

发布后缺陷按影响选择回退层级：

### 4.1 宿主侧（最快）

宿主把依赖约束钉回上一个版本（如 `weft: 0.5.0-dev.1`）。兼容契约保证：

- 旧引擎读新文档：**被版本门禁拒绝**——`WeftDocumentJson.decode` 对大于
  自身支持版本的快照抛出 `FormatException`，不会静默误读（见
  `release_compat_test.dart` 的 forward-compat 用例）。
- 新引擎读旧文档：快照格式 v1 内的演进必须向后兼容；若不兼容，属于
  破坏性变更，发布前必须在 §2 表中声明。

### 4.2 引擎侧

- 在 main 上 revert 引入缺陷的提交，重新走 §3 清单（像素黄金与一致性
  向量是行为回退的自动守卫：revert 后向量必须与提交前一致，否则 revert
  不完整）。
- 回滚提交同样递增版本号（如 `0.5.1`），避免与已发布产物混淆。

### 4.3 行为回退开关

- JS 整体关闭：宿主不创建 `WeftDocumentRuntime`，渲染路径完全不经过
  runtime（`WeftView` 无 runtime 依赖）。
- 单能力关闭：`CapabilityPolicy(enabled: ...)` 逐命名空间开关，矩阵测试
  `packages/weft/test/runtime_capability_matrix_test.dart` 覆盖全部 8 个
  子集。
- 懒布局回退：`WeftView(enableLazyLayout: false)` 回到完整布局。

## 5. 回滚演练（已完成，随阶段 5 提交）

自动化演练位于 `packages/weft_document/test/release_compat_test.dart`：

1. **旧文档可读（升级/回退都安全）**：重放全部 21 个一致性向量——它们由
   旧版本生成器产出，当前引擎必须逐字节复现（宿主钉回旧版本时旧文档仍可
   渲染）。
2. **前向兼容门禁**：伪造 `version: 2` 的快照被当前解码器以明确报错拒绝。
3. **格式标签门禁**：非 `weft.document` 载荷被拒绝。
4. **生产者稳定性**：当前 normalizer 对向量输入的输出与固化字节一致
   （revert 完整性检查的机制与 §4.2 相同）。

发布新格式版本时，把 §2 表更新、向量重新生成并审查，然后新增一个
`release_compat_test` 分组保持该结构。
