# ADR 0014：几何基线驱动器、一键门禁与布局诊断工具

- 状态：已接受
- 日期：2026-10-25

## 背景

图片/Float 与表格两个切片的开发过程暴露了三类重复摩擦：

1. 硬性约束要求依次运行 format、analyze、verify、golden 四条命令，其中 `flutter test` 在 Windows 输出 `\r`、每次重复 resolve 依赖，本地镜像还会改写 `pubspec.lock`。
2. 每个几何基线案例都要手写“文档顺序 → Chrome `data-geo` 标记”的位置映射，映射代码本身出了三轮错才对齐。
3. 调试布局时反复写一次性 dump 测试、跑完再删，每轮 3 分钟以上。

## 决策

### 通用几何门禁（`test/conformance_geometry_test.dart` + `tool/geometry_baseline.dart`）

- manifest 中所有 `geometry: true` 的案例由同一驱动器比对：按“标记 tag 集合过滤后的文档顺序”与 Chrome 参考一一配对，任何数量或标签错位都以显式失败报告，绝不静默跳过。
- 比对容差按标签分级：文本块（p/h1-h6/hr）0.5px，替换与表格元素 1.5px（shrink-to-fit 的字形测量舍入）。
- 新增几何案例的接入成本 = 写案例 HTML + `node tool/browser_references.mjs --case <id> --emit-reference`，零测试代码。
- `float_image_geometry_test.dart` 与 `table_basic_geometry_test.dart` 保留各自独有的行为断言（行框避让、晚加载收敛、跨距结构关系），删除与通用门禁重复的元素矩形比对。

### 一键门禁（`tool/check.sh`）

- format → analyze → verify → golden 一条命令；`--fast` 跳过像素门禁用于纯布局迭代。
- 统一 `tr -d '\r'` 修复 Windows 输出管道；`verify.dart` 对 Flutter 包加 `--no-pub` 避免 resolve 重复。
- 结束时自动 `git checkout pubspec.lock`（`WEFT_KEEP_LOCK=1` 豁免），防止本机镜像的 URL 改写泄漏进提交。

### 布局诊断（`tool/dump_layout.sh` → `tool/dump_layout_test.dart`）

- `dart run` 无法直接执行 Flutter 包，诊断入口走测试外壳并经环境变量传参（`WEFT_DUMP_FILE/WIDTH/DIFF/RUNS`）。
- 默认打印盒子、行命令与逻辑文本；`--runs` 追加 painter→节点 run 映射（选择调试）；`--diff` 输出逐元素 Weft-vs-Chrome 偏差表，`ok/~/!!` 三档标记。
- 调试迭代从“写临时测试→跑→删”变为一条命令读固定输出文件。

### 布局引擎拆分（part 文件）

- `layout_engine.dart`（骨架 + 块流 + 图片）、`table_layout.part.dart`（表格 extension + `_TableCell`）、`inline_flow.part.dart`（Float 排除区 + 行内累积器 + 数据类）。
- 同一库内私有成员互见，语义零变化；文件边界即后续并行开发的合并边界。

## 后果

- 本地验证一条命令，几何基线接入零代码，布局调试一条命令。
- CI 不变（CI 本身就是四条命令的串行）；`check.sh` 是其本地等价物。
- 后续改动 `table_layout.part.dart` 与 `inline_flow.part.dart` 的切片可由不同会话并行推进，合并冲突面显著缩小。
