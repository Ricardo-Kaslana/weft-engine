# 一致性语料

此目录保存跨引擎静态内容语料、固定字体、浏览器参考输入和 Flutter 像素基线。`manifest.json` 是案例、视口、结构验收下限和像素开关的唯一来源。

## 当前语料

- `article`：标题、段落、强调、列表、引用、代码和链接。
- `typography`：标题层级、行内样式、对齐、行高和分隔线。
- `box_model`：content-box、border-box、padding、边框和最大宽度。
- `nested_lists`：嵌套无序/有序列表与引用。
- `cjk_wrap`：中文标点、混合文本和固定宽度换行。
- `pixel_basic`：拉丁文字的文章、行内样式、列表、引用、链接和边框；启用像素基线。

`packages/weft_engine/test/conformance_corpus_test.dart` 会自动读取 manifest，验证：

- 文件存在且案例 ID 唯一。
- 内容在支持子集内，未请求回退。
- 能完成布局并达到最小高度、文本命令和盒数量。
- 链接目标符合 manifest。
- 块盒和链接区域不超出声明宽度或内容高度。

该测试是结构验收，不替代像素测试。

## 固定字体

`fonts/` 保存从 Flutter SDK 复制的 Roboto 和 Roboto Mono，使用 Apache 2.0 许可。字体文件不进入公开 Weft 包，只作为一致性测试夹具。详见 `fonts/README.md`。

当前像素案例只使用拉丁字符。中文结构测试已覆盖，但尚无合法可分发的固定 CJK 字体，因此不启用 CJK 像素门禁。

## Flutter 像素黄金门禁

基线位于 `goldens/flutter/images/`。本地比较：

```bash
cd packages/weft_engine
flutter test tool/golden_pixel_test.dart --timeout 120s
```

有意修改布局并审查差异后更新基线：

```bash
cd packages/weft_engine
flutter test tool/golden_pixel_test.dart --update-goldens --timeout 120s
```

`golden` CI 任务在 Windows 上固定 Flutter 3.35.5 运行该测试。基线使用固定 TTF、固定视口、DPR 1 和显式白色背景，不依赖操作系统字体回退。更新基线必须在 PR 中提供差异图和浏览器参考理由。

## 浏览器参考截图

使用本机 Chrome 或 Edge 生成诊断截图，需要 Node.js 22 或更高版本：

```bash
node tool/browser_references.mjs
```

工具通过 Chrome DevTools Protocol 设置视口，而不是依赖无头模式中会被最小宽度限制的 `--window-size`。每张图都会校验 `window.innerWidth/innerHeight` 与 PNG 尺寸，不一致时直接失败。Roboto/Roboto Mono 以 data URI 嵌入页面，避免系统字体回退。

输出到 `build/conformance/browser/`，包括包装后的 HTML、PNG 和浏览器版本元数据。可指定浏览器或单一案例：

```bash
node tool/browser_references.mjs --browser "C:/path/to/chrome.exe"
node tool/browser_references.mjs --case pixel_basic --case box_model
```

浏览器参考图仍是诊断输入，不是 CI 阻断门禁。

## 跨引擎像素报告

先生成浏览器截图和 Flutter 基线，再安装 Pillow 比较：

```bash
python -m pip install -r tool/requirements-goldens.txt
python tool/compare_goldens.py --report-only
```

输出位于 `build/conformance/diff/`：

- `report.json`：差异像素数、比例、浏览器版本和阈值。
- `overlay/`：差异像素叠加在原图上的可视化。
- `diff-only/`：放大 8 倍的通道差异图。

`manifest.json` 的 `crossEngineTarget` 是 advisory 目标：通道差不超过 8、差异像素不超过 1%。Flutter 基线门禁是阻断性的；跨引擎目标尚未达到，不能把当前比较报告描述为像素一致。

2026-10-25 使用 Chrome 156 和 Flutter 3.35.5 的首次测量：

- `box_model`：1.064% 差异像素，结构尺寸一致，差异集中在文字抗锯齿和边框边缘。
- `pixel_basic`：7.260% 差异像素，块位置基本对齐，差异集中在字形光栅、1–2px 基线和引用内部 margin 处理。
- 通过调整引用内部 `p` 的 margin，差异已从 14.204% 降至 7.260%；这暴露出 Weft 尚缺完整的父子 margin 折叠。

## 首轮人工检查记录

- Chrome 无头模式最初受约 500px 最小布局宽度影响，已改为 CDP 视口覆盖并通过运行时尺寸校验。
- 浏览器默认 `<pre>` 不换行；Weft 当前按容器换行。像素语料暂用 `pre-wrap` 明确该差异，后续需要实现明确的溢出策略。
- 浏览器与 Flutter 使用相同 Roboto 后，标题、列表、引用和边框块的位置基本一致，但字形抗锯齿仍产生显著原始像素差。

## 仍需补齐

1. 固定并合法分发覆盖 CJK 的测试字体，启用中文像素案例。
2. 改进父子 margin 折叠，减少结构性偏移。
3. 固定浏览器构建并在 CI 或容器中运行跨引擎比较。
4. 根据修复后的数据重新评估通道容差和差异比例，不直接放宽阈值。
