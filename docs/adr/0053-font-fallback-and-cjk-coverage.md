# ADR 0053：为字体回退提供 CSS 字体列表与宿主级 fallback

- 状态：已接受
- 日期：2026-11-03

## 背景

CJK 文本在 Weft 里始终渲染为豆腐块（空心方框）。排查确认根因不在排版算法，而在字体：

1. `WeftComputedStyle.toTextStyle()` 只输出 `fontFamily`，没有 `fontFamilyFallback`。
   Flutter 的 `TextStyle` 缺少 fallback 列表时，缺字形直接画成 tofu。
2. `WeftStyleResolver._fontFamily()` 只取 `font-family` 逗号列表里的**第一个**值，
   其余候选被丢弃。这不符合 CSS 规范——`font-family` 本来就是一个有序候选列表，
   浏览器按顺序为每个字形挑第一个能覆盖它的字体。
3. 引擎没有任何宿主注入点：宿主即使加载了中文字体，也没有办法告诉引擎「用这个字体兜底」。
   结果是引擎只能依赖 Flutter 平台默认字体族，而该族在多数测试/嵌入场景下是纯拉丁字体。

具体表现：

- 平台默认字体为 Roboto（拉丁）时，中文全是豆腐块；
- `font-family: monospace` / `serif` 这类通用族被当作具名字族原样传给 Flutter，
  与 Flutter 的 `monospace` 语义并不等价；
- 宿主的 `font-family` 即使写成 `"Noto Sans CJK SC", sans-serif`，第二个候选也被丢弃。

## 决策

1. **解析 CSS 字体列表**。`WeftStyleResolver._fontFamilies()` 按逗号切分 `font-family`，
   具名字族按原顺序保留；第一个候选作为 `fontFamily`，其余作为 `fontFamilyFallback`。
   通用关键字没有可查的字族名，只在它是列表里第一个可用项时才参与映射：
   `monospace` / `serif` 保持原有语义，`sans-serif` / `cursive` / `fantasy` / `system-ui`
   交给 Flutter 默认字族。原先的 `_fontFamily()` 删除。

   顺带修正一处与 CSS 不符的行为：`font-family: Georgia, serif` 旧实现因整串包含
   `serif` 而直接返回 `serif`，把前面的 `Georgia` 丢掉；现在返回 `Georgia`。
2. **宿主级默认回退**。`WeftStyleResolver` 新增 `defaultFontFamilyFallback`，
   `WeftLayoutEngine.layout()` / `layoutViewport()` 新增同名参数，
   `WeftSurface` / `WeftView` 同样透传。宿主传入的族在作者 CSS 没有覆盖时生效。
3. **合并规则**。宿主 fallback 只追加作者未提及的族：作者已声明的族优先级更高，
   宿主列表仅作为补充。
4. **继承语义**。`fontFamilyFallback` 与 `fontFamily` 一样沿父节点继承，
   子节点可以覆盖。
5. **缓存失效**。回退列表被写进每个计算样式，并经整形后的 `TextPainter`
   进入每条绘制命令。宿主在两次布局之间改变列表时，入口直接把 `previous`
   丢弃、退化为冷布局，而不是让每条复用路径（样式缓存、块复用、命令转移）
   都去识别这个新键。宿主换字体是低频事件，一次冷布局是更划算的取舍。

## 后果

- 中文、emoji 等缺字形不再渲染为豆腐块，宿主只需加载一个 CJK 字体并声明一次。
- CSS `font-family` 列表语义与浏览器对齐，同一份样式在 Weft 与 Chromium 下的
  字体选择结果一致。
- `WeftComputedStyle` 增加一个字段，`toTextStyle()` 的输出多出 `fontFamilyFallback`，
  既有像素黄金基线在纯拉丁用例下不受影响（fallback 列表为空时行为不变）。
- 宿主 API 表面变大：需要中文字形的宿主应当显式声明 fallback，
  不再依赖平台默认字体恰好覆盖目标字符集。

## 验证

- `packages/weft_engine` 344 项测试全绿（新增 9 项覆盖本 ADR），
  `packages/weft` 78 项全绿，`tool/check.sh` ALL GREEN（含 3 项像素黄金）。
- `test/font_fallback_test.dart` 覆盖：候选顺序、通用关键字、宿主追加与去重、
  继承、以及回退列表变化时样式缓存必须失效。
- 写测试时发现并修复两个真实缺陷：`layout()` 声明了 `fontFamilyFallback`
  但没有往下传给 `_layoutDocument`（主 API 路径下宿主 fallback 完全失效）；
  懒布局回退路径的内部递归调用同样漏传。
- 用 `FontLoader` 加载 `C:/Windows/Fonts/msyh.ttc` 后，引擎渲染的中文文章、
  表格与特性墙均正常出字，标点与禁则正确。
