# ADR 0044：流式快照的文本索引前缀复用

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0043 的画像把「文本索引全量重建」定为流式轮最大纯开销（新快照轮的 56–81%，且 `WeftTextIndex.build` 内部直连 resolver 绕过布局的 styleCache，每元素双重选择器匹配）。本切片实现跨快照前缀复用：流式更新（新快照实例、同 document.id）时，复用未变前缀顶层块对应的索引条目、只构建后缀；任何前置不满足即回退全量构建。

等价性前提（均已核实并有既有测试守护）：

- **条目是快照的纯函数**：`WeftTextIndex.build` 只读 document 与 styleResolver（ADR 0031 的论证同源）。
- **节点 id 跨同内容快照稳定**：`_TreeBuilder._nextId` 每次 normalize 归零、先序顺序分配；`normalizer_test.dart` 的 tail-append 保 id 测试与规范化向量逐字节复现双重守护。
- **复用边界免费获得**：`_reusableLayoutBlocks` 的块 diff 已对前缀做递归 `_sameNode`（覆盖全部后代节点的 id/text/属性），且 plain 可复用前提取要求 `cache.blocks.length == 旧 body.children.length`——前缀与索引 checkpoint 天然对齐。
- **previous.textIndex 在链式轮中持续可用**：`transferCommands` 只清 `incrementalCache`，不动 `textIndex`。

## 决策

### 1. 共享 walker：等价由构造保证

`text_index.dart` 抽出私有 `_TextIndexBuilder`，持有走查状态（entries、globalStart、hardBreaks、blockBreakPending、atLeadingEdge、lastEmittedBreak），`build()` 与新增的 `buildIncremental()` 走完全相同的 emit/visit/trim/join 代码；两条路径的差异只在输入（后者以前缀条目与 checkpoint 状态种子起步）。空内容判定从「buffer 非空」改为等价的「entries 非空」，使增量路径起步时状态语义一致。

### 2. 每顶层子块 checkpoint

build 时在每个 body 直接子元素走查后记录 `(entryCount, nextGlobalStart, hardBreaks, blockBreakPending, lastEmittedBreak, atLeadingEdge)`。`nextGlobalStart` 是含未裁尾空白与悬挂换行的真实走查计数器——它使还原后的前缀末条目 `globalEnd` 恰等于该值，后缀条目的 globalStart 与 join 间隙全部无缝续接。

### 3. 尾 trim 还原

上一索引的 `finish()` 会对流尾做两种修剪：末条目尾部空白裁掉（记 `_trailingTrimmedTail`）或整条纯空白条目删除（记 `_trailingRemovedEntry`，二者互斥）。内部空白缝隙的空白会绘制（行盒接缝），因此当复用前缀包含旧文档最后条目（`reusedTopLevelBlocks == previous.checkpointCount`）时必须还原，再由本次 `finish()` 在新文档末尾重新修剪——后缀为空时结果自然逐字节回到旧索引。

### 4. 引擎参与条件与回退（layout_engine `_incrementalTextIndex`）

全部满足才增量，否则全量构建：`!sameSnapshot && previousCache != null && previous.textIndex != null && reusableBlocks 非空 && previousCache.blocks.length == 旧 body.children.length && previous.textIndex.checkpointCount == 同值 && 前缀计数 k ≥ 1`。前缀计数由新 body 子元素顺序查 `reusableBlocks` 得到（O(k)，不依赖 map 插入顺序语义）。**lazy 部分测量前缀（blocks ≪ children）不参与**：其 diff 只验证测量窗口且经元素过滤列表比较，与 checkpoint 有错位风险，保守回退全量——lazy 流式轮行为与本切片前完全一致。head 插入（k=0）、样式表/id/宽度等全局键变化、无缓存文档全部走原全量路径。

### 5. 公开面

仅新增 `WeftTextIndex.buildIncremental`（doc 注明：错误的 `reusedTopLevelBlocks` 会静默错位全局偏移，非引擎调用方应使用 `build`）与 `checkpointCount`；checkpoint 结构与 trim 字段保持私有。

## 画像数据（Windows 开发机，ADR 0044 落地后，与 ADR 0043 两轮基线对比）

| 指标 | 0043 基线（两轮区间） | 0044 后 | 说明 |
|---|---|---|---|
| E0 新快照轮 U(300) | 2.3–2.7 ms | 1.5 ms | |
| E0 新快照轮 U(1000) | 7.9–8.6 ms | 3.2 ms | ≈ 地板 2.1 + 走查样式 1.4 |
| E0 新快照轮 U(2000) | 19.5–23.1 ms | 8.8 ms（**−60%**） | ≈ 地板 2.9 + 走查样式 5.3；全量 textIndex 12.3ms 被消除 |
| E1 尾部追加 plain 300 | 3.5–6.8 ms | 3.6 ms | 中位数贴住基线最优端 |
| E1 尾部追加 plain 1000 | 9.7–16.2 ms | 10.2 ms | |
| E1 中部编辑 300/1000 | 15.8–21.6 / 64.3–66.7 ms | 18.3 / 64.0 ms | 后缀重排主导，T 份额在运行噪声内 |
| E1 头部插入 300 | 31.1–40.9 ms | 31.2 ms | k=0，回退路径不变 ✓ |
| E1 尾部追加 lazy 300/1000 | 3.1–4.3 / 10.3–12.9 ms | 2.9 / 10.3 ms | lazy 回退不变 ✓ |
| E3 float-plain / float-lazy | 328–430 / 5.2–5.6 ms | 330 / 5.3 ms | 逐行路径未触碰 ✓ |

E0 的 U−T−S−F 恒等式自本切片起不再适用于常规轮（U 本身走增量路径，这正是优化目的）；新恒等式为 U ≈ 地板 + 走查样式 + 后缀索引，实测吻合。**流式轮剩余的 O(doc) 成分以走查样式解析（S=5.3ms@2000）为主**——属于「样式缓存跨快照」家族，与 lazy 轮的准入走查/估算重建同族，留待后续画像驱动。

## 测试与验证

- 新增 `test/incremental_text_index_test.dart`（14 项）：增量 vs canonical 全量逐条目相等（nodeId/text/globalStart + entryByNode + 逻辑串），场景覆盖尾部追加、边界尾空白还原、边界悬挂 `<br>`、纯空白末条目还原、隐藏/空边界块、变长中部编辑、头部插入回退、同内容新快照（结果回到旧索引）、**链式 A→B→C**、列表/嵌套/前导空白/CJK、无条目空白文档、样式表变化回退、lazy 部分前缀回退、跨缝选择矩形/文本一致。
- `incremental_layout_test.dart` 的 `_expectLayoutEquals` 升级：textIndex 比较从单字符串升级为逐条目（增量 vs 全量布局等价的既有场景全部加严）。
- 总数 523 → 537（以 `tool/verify.dart` 输出为准）；`tool/check.sh` ALL GREEN，规范化向量与像素黄金零 diff。

## 备选与拒绝原因

- **逻辑串跨快照直接拼接**（prevLogical + 后缀）避免 O(total) join：还原分支的间隙/裁剪组合使拼接正确性依赖多个隐式前提，join 重建是 memcpy 级成本（实测 U(2000) 8.8ms 已含它），不值得为省 ~1–2ms 引入脆弱性。
- **条目按 nodeId 重建映射而非前缀复用**：entryByNode 可由条目列表廉价重建，但前缀条目的 painted text/globalStart 仍需重算——等于没有省。
- **lazy 部分前缀也参与索引复用**：可验证前缀只有测量窗口（4–5 块），收益 O(窗口)，却引入元素过滤列表与 checkpoint 错位的等价性风险——按「未命中即回退」纪律全量构建。
- **同时做样式缓存跨快照**：S(2000)=5.3ms 是流式轮剩余主导成分，但它与布局走查的 styleCache 生命周期耦合（元素实例跨快照不同），等价性论证与失效面都更大，单独立项。

## 后果

- 流式新快照轮消除 textIndex 全量重建与前缀双重选择器匹配；plain 宿主全部形态受益，中部编辑/头部插入的剩余成本转移到后缀重排与走查样式（方向③/样式跨快照的输入）。
- `WeftTextIndex` 每实例多 O(块数) checkpoint（6 字段小对象）与两个小 trim 字段；内存量级远小于条目本身。
- 已知限制：lazy 部分测量前缀不参与（全量构建）；`buildIncremental` 的正确性依赖调用方满足前置（doc 注明）；`lastEmittedBreak` 目前恒为 false，随 checkpoint 携带以防未来 emit 规则变化破坏续走。
- 画像工具 E0 注释更新：U 的恒等式解释改为增量形态。
