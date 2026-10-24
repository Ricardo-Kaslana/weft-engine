# 一致性语料

此目录保存跨引擎的静态内容语料和浏览器参考生成输入。`manifest.json` 是案例、视口和结构验收下限的唯一来源。

## 当前语料

- `article`：标题、段落、强调、列表、引用、代码和链接。
- `typography`：标题层级、行内样式、对齐、行高和分隔线。
- `box_model`：content-box、border-box、padding、边框和最大宽度。
- `nested_lists`：嵌套无序/有序列表与引用。
- `cjk_wrap`：中文标点、混合文本和固定宽度换行。

`packages/weft_engine/test/conformance_corpus_test.dart` 会自动读取 manifest，验证：

- 文件存在且案例 ID 唯一。
- 内容在支持子集内，未请求回退。
- 能完成布局并达到最小高度、文本命令和盒数量。
- 链接目标符合 manifest。
- 块盒和链接区域不超出声明宽度或内容高度。

该测试是结构验收，不是像素黄金测试。

## 浏览器参考截图

使用本机 Chrome 或 Edge 生成诊断截图，需要 Node.js 22 或更高版本：

```bash
node tool/browser_references.mjs
```

工具通过 Chrome DevTools Protocol 设置视口，而不是依赖无头模式中会被最小宽度限制的 `--window-size`。每张图都会校验 `window.innerWidth/innerHeight` 与 PNG 尺寸，不一致时直接失败。

输出到 `build/conformance/browser/`，包括包装后的 HTML、PNG 和浏览器版本元数据。可指定浏览器或单一案例：

```bash
node tool/browser_references.mjs --browser "C:/path/to/chrome.exe"
node tool/browser_references.mjs --case article --case box_model
```

这不是 CI 像素门禁：当前未固定可用字体文件、浏览器构建、操作系统字体回退和 Flutter 截图管线。参考图用于人工差异分析和后续黄金基线准备，不得仅凭截图宣称浏览器像素一致。

## 首轮人工检查记录

2026-10-25 使用 Chrome 156 生成首轮参考图：

- 文章、盒模型、嵌套列表和中文换行均位于 320/360/480 CSS px 的精确视口内。
- 文章中的预格式化代码保持浏览器默认“不换行”行为，长行会水平溢出；Weft 当前会按容器宽度换行，后续必须在溢出策略或黄金门禁中明确取舍。
- Chrome 的标题行高、默认代码块字体和列表缩进与 Weft 当前默认样式存在差异，需在固定字体后量化为像素差异。
- 窄视口最初受无头浏览器最小窗口宽度影响，已改为 CDP 视口覆盖并通过运行时尺寸校验。


## 成为黄金门禁前必须补齐

1. 固定并合法分发测试字体。
2. 固定浏览器版本与运行环境。
3. 生成 Flutter 同视口、同字体截图。
4. 建立像素差异阈值、差异图和不通过即阻断的 CI 任务。
5. 对跨平台字体光栅差异与真实布局错误分别记录。
