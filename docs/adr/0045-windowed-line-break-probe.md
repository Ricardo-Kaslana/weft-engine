# ADR 0045：Float 逐行路径的窗口化断行探测

- 状态：已接受
- 日期：2026-10-31

## 背景

ADR 0043 画像把 Float 家族的成本根源钉在逐行路径的 probe 上：`buildLines` 每行用 `maxLines: 1` 的探测 painter 对**全部剩余文本**做 shaping（`_spanForRange(offset, plainText.length)` + `layout`），单段 O(n²)——8000 字段落 763.9ms vs 整段路径 1.2ms；首个 Float 之后所有段落粘性走逐行路径（`_FloatContext.exclusions` 只增不减），Float 文章流式轮 328–430ms。`runSpecs`/`_spanForRange` 还各有一层 O(lines×runs) 的全 runs 扫描。

探索确认的设计前提：

- **probe 的唯一产出是行尾偏移**：禁则后处理 `_adjustForLineBreakRules`、`\n` 吞并、`_paintableEnd`、行 painter、y 推进、link 盒全部操作完整 plainText，与 probe 输入长度无关。
- **fit 判定前缀单调**：窗口装不下时（`maxLines: 1` 溢出），窗口内 line-0 断点 == 全文本 line-0 断点——超出窗口的文本不可能容纳更早的断点之后的任何断点，而窗口内更晚的断点已被贪心极大化排除。
- 断行行为不变的实践面由既有测试钉住：float_image Chrome 逐行几何（±1.5px）与像素黄金、cjk_kinsoku 逐行禁则、inline_image/image_layout 行几何、RTL Float 覆盖长度、perf_gate floatWrap。

## 决策

### 1. probe 窗口化（inline_flow `buildLines`）

- **窗口起点（确定性）**：`offset + clamp((lineWidth / fontSize).ceil(), 1, 4088) × 2 + 16`——约 2 行 CJK / 4 行拉丁的字符量加 margin。
- **接受条件**（满足其一即用该 probe 的结果）：窗口到达段尾（与旧实现完全相同的输入，精确）；`consumed <= offset`（既有退化兜底，一个 code unit 前进）；`consumed <= windowEnd − 16`（断点严格位于窗口内部，margin=16 code units）。
- **否则窗口 ×2 重探**，直到段尾。窗口到段尾后行为与旧实现逐字节一致——所有病态输入（不可断长词、退化 metrics）最终都回落到全文本窗口。
- 正确性论证：被截断窗口的 line-0 断点等于全文本断点，因为 (a) fit 决策只依赖 `[offset, B]` 的字形宽度（贪心前缀单调）；(b) 断点机会是局部属性（UAX #14 的 look-ahead 在断点邻域数个 code unit 内）；(c) 断点距窗口尾 ≥16 保证 line-0 字形与窗口截断处无共享 shaping/joining 上下文（HarfBuzz 按样式 run 分段 shape，截断只影响窗口尾邻域的字形，它们位于溢出行）；(d) RTL 的视觉远端探测（`_lineBreakEnd` 的 caretX=0）与 caretY 行中点公式不变。margin 同时兜底 bidi 中性字符层级解析依赖后继强字符的极端情况——病态内容随窗口翻倍自然回落到全文本即精确。

### 2. run 定位二分化

`runSpecs` 与 `_spanForRange` 每次线性扫全部 runs；runs 按 cursor 有序。新增 `_runCursors()`（flush 时构建一次、随 `_InlineLines` 下传）与 `_firstRunIndexAtOrAfter`（前缀表上二分），两处扫描改为「二分定位首个相交 run + 顺序推进、越过 end 即 break」。跳过/切片逻辑逐条保留——输出与线性版完全一致；整段路径与 `runSpecs(0, …)` 不传 cursors 时内部重建前缀表，行为不变。

### 3. 拒绝的优化

- **不与浮动重叠的段落切换整段路径**：两路径断行非等价且是 ADR 0016 文档化现状（禁则只服务逐行路径、probe 对后缀独立 shaping、行 painter 定宽 vs 整段 maxWidth），切换会改变输出，违反「优化只改执行方式不改输出」纪律。
- **跨快照行级缓存（block 级断行 checkpoint）**：机制面大（断行结果对宽度/样式/浮动槽状态的失效键），留待本切片后按数据另案——它属于方向③「后缀平移」同一族的流式形态优化。

## 画像数据（Windows 开发机，落地后 vs ADR 0043 基线）

| 指标 | 0043 基线 | 0045 后 | 说明 |
|---|---|---|---|
| E3 linewrap 1000 字 | 11.5 ms | 1.7 ms | |
| E3 linewrap 2000 字 | 53.4 ms | 3.1 ms | |
| E3 linewrap 4000 字 | 171.3 ms | 5.5 ms | |
| E3 linewrap 8000 字 | **763.9 ms** | **11.1 ms（−98.5%）** | 逐行/整段比 650× → 3.2× |
| 倍增耗时比 | 3.2–4.6×（二次方） | 1.8–2.0×（线性） | |
| E3 float-plain 流式轮 | 328–430 ms | 222–243 ms | 二次项消除；剩余为逐行模型线性常数（每行 probe+行 painter 两次 layout + slot/link 盒） |
| E3 float-lazy 流式轮 | 5.2–5.6 ms | 2.4–5.1 ms | 窗口物化本来就只排视口内段落 |
| floatWrap 基准 | ~6–9 ms | 4.8 ms | testing-strategy 表更新 |

## 测试

- 新增 `test/float_line_break_test.dart`（5 项）：长 CJK 段（>60 行）覆盖率与逐行禁则、宽度网格上的行数单调性（兼作窗口边界扫描）、不可断长词的窗口增长与确定性、行尾空白裁剪语义（只允许删行尾空格的子序列断言）、多内联样式跨窗口行的 run 铺贴（painterStart 零间隙）。
- 既有 8 套 Float/禁则/几何/像素/RTL 测试零 diff 为主证；总数 537 → 542（以 `tool/verify.dart` 输出为准）。

## 后果与已知限制

- 逐行路径 shaping 量从 O(段长²) 降为 O(段长)×常数；长段落（AI 流式单段追加、长产品描述旁浮动）首排与流式轮同时受益。
- 流式 Float 文档剩余成本是逐行模型的线性常数（每行两次 layout 与固定开销）——若真机数据仍超预算，出路是跨快照行级缓存或整段路径切换（两者都需先解决等价性论证，见拒绝项）。
- 已知限制：margin=16 与 ×2 增长是确定性启发式，极端 bidi/上下文按设计回落到全文本窗口（精确）；probe 窗口让每行的 TextPainter 输入变小，`computeLineMetrics` 的行高仅空行分支使用（不变）。
- `runSpecs` 新增可选 `cursors` 参数（`_InlineAccumulator` 为私有类，公开 API 面不变）。
