# ADR 0015：选择手势与复制导出

- 状态：已接受
- 日期：2026-10-25

## 背景

ADR 0013 交付了锚点→矩形/文本的解析层与选择高亮绘制，但手势侧仍是空白：用户无法通过点击、长按或拖拽建立选区，宿主也无法拿到选中文本。本切片补齐手势定位锚点、长按选词、拖拽扩展与选区文本导出。架构约束不变：锚点是 `(NodeId, localUtf16Offset)`，Weft 是单一 RenderObject 表面，HTML 节点不映射为 Widget。

## 决策

### 命中定位（`WeftLayoutResult.anchorAt`）

- 逆序遍历 text 绘制命令（后绘制者胜出，覆盖浮动环绕行与表格后行），把 position 换算为 painter 局部坐标（`position - command.offset`）后调用 `TextPainter.getPositionForOffset`，再经 `command.runs` 映射为 `(nodeId, nodeStart + (painterOffset - run.painterStart))`。
- 命中语义取"命中即返回，全不命中返回 null"：painter 局部坐标必须落在该命令的已布局边界内（`painter.width/height`），否则跳过；块间距、空白边缘与浮动排除区因此返回 null，而不是被 `getPositionForOffset` 的钳制行为拉到最近的文字上。
- run 映射优先取节点仍在逻辑索引中且 painter offset 严格内含的 run；`<br>` 产生的换行 run 拥有 painter 文本但无逻辑文本条目，其接缝偏移回退到相邻文本 run，保证产出的锚点一定能被 `textIndex.order/between` 解析。

### 长按选词（`WeftLayoutResult.wordSelectionAt`）

- 与 `anchorAt` 同一定位路径，但用 `TextPainter.getWordBoundary` 取词边界，映射回锚点对：anchor 为词首，extent 为词尾。词可跨 run（如 `<b>Hel</b>lo`），起止两端各自独立映射。

### 视图层手势（`WeftView`）

- `WeftView` 改为 StatefulWidget（保留 fallback 与 ListenableBuilder 行为），持有内部 surface 的 GlobalKey，并把 surface 包进一个 `GestureDetector`（`deferToChild`）。
- 长按开始：`onLongPressDown` 记录起点，`onLongPressStart` 用 `wordSelectionAt` 建立选区；`onLongPressMoveUpdate` 用 `anchorAt` 作为新 extent（anchor 保持词首），落点不在文字上时保留上一个 extent 而不是清空选区。
- `WeftViewState` 公开，宿主经 `GlobalKey<WeftViewState>` 调用 `selectionText()`：内部经 GlobalKey 取 `RenderWeftSurface.selectionText(controller.selection)`。宿主自行决定 Clipboard 策略，引擎/视图不直接写剪贴板。

### 链接点击与选择共存

- `WeftView` 不再把 `onLinkTap` 透传给 `WeftSurface`，而是自己的 tap 处理器统一裁决：快速单击命中链接 → 回调 `onLinkTap` 且不改动选区；未命中 → `controller.updateSelection(null)` 清除选区。单一 tap 识别器避免了嵌套 GestureDetector 的手势竞技场竞争（内层 tap 胜出会导致"点击清除"失效）。
- 长按优先于链接：长按被识别后 tap 识别器在竞技场中失败，链接不会因长按被触发。

### 表面层查询（`RenderWeftSurface`）

- 暴露 `anchorAt(Offset)`、`wordSelectionAt(Offset)`、`selectionText(TextSelectionRange?)`，全部委托当前布局结果；布局失效后返回 null，与"安全清除"一致。

## 边界

- 点击只能清除选区或跟随链接，不产生光标（caret）概念；折叠选区仍由 `TextSelectionRange.collapsed` 表达但视图手势不生成。
- 选区拖拽把手（drag handle）绘制、选择工具条和双向文本的词边界语义不在本切片。
- `getWordBoundary` 依赖 Flutter 的 UAX #29 词边界，字素簇边界问题与引擎无关。
- `WeftSurface` 的内部链接点击检测保留，直接使用 `WeftSurface` 的宿主行为不变。

## 后果

- 手势坐标与绘制坐标同源（都是布局结果坐标），滚动容器内由 hit test 自动换算，无需额外偏移。
- 选区更新只走 `controller.updateSelection` → 重绘路径，不触发布局；长按拖拽流畅度与绘制成本解耦。
- 引擎层 5 项命中测试覆盖多行第二行、浮动 dx 偏移行、表格单元格、空白处 null 与整词选择；weft 包 2 项 widget 测试覆盖长按/拖拽/清除与链接共存，跨段 `selectionText()` 含换行。
