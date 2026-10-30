# 内容规范化

## 目标

规范化把服务端或客户端输入转换为引擎定义的可预测子集，并生成机器可读支持度报告。它不是通用 XSS 清洗器，也不能把不可信脚本变成可信脚本。

阶段 2 已支持 `img` 标签的 `src/alt/width/height` 规范化，并继续对脚本、表格、Canvas 等复杂内容生成回退诊断。服务端参考实现、策略版本迁移和双端一致性语料尚未交付。

阶段 4 增加自定义标签白名单（ADR 0033）：`WeftNormalizer(customTags: {...})` 把命中的未知标签保留为属性驱动的叶子元素——class/id/style 与任意安全命名的属性（值截断，`on*` 与 `style` 除外，`href/src` 走既有清洗）保留，内部内容丢弃并产出 `html.tag.custom.contentIgnored` 诊断；不在白名单的未知标签保持原 unwrap 行为。

阶段 5 之后（ADR 0039）规范化器保留 `aria-live`（`off/polite/assertive`）以及 `ol[start]`、`li[value]`；非法值丢弃并分别产出 `aria.live.invalid`、`list.start.invalid`、`list.value.invalid` 诊断。

## 输入与输出

输入至少包含原始 HTML、可选可信样式、策略版本和内容 ID。输出契约为：

```text
NormalizedContent {
  contentId
  policyVersion
  normalizedHtml
  supportReport
  contentRevision
  diagnostics
}
```

`contentRevision` 必须在内容或策略变化时单调更新，以驱动缓存失效。服务端与客户端在相同输入和策略版本下必须产生相同语义输出。

## 处理顺序

1. 检查输入大小、嵌套深度和资源 URL 数量限制。
2. 解析并识别明确回退能力，例如 Canvas、WebGL 和编辑需求。
3. 按策略处理未知元素：drop、unwrap 或 error。
4. 移除不受支持的事件属性、`javascript:` URL 和未允许资源协议。
5. 过滤 CSS 声明并记录被丢弃规则。
6. 输出规范标签、属性顺序、空白规则和稳定诊断代码。
7. 重新检查资源预算和支持度，生成最终快照。

## 策略原则

- 对不影响内容语义的 CSS 可降级并警告。
- 对可能改变内容含义或需要完整浏览器的能力必须回退。
- 不允许把 script、iframe 或未知嵌入自动转换成“看似可用”的静态内容。
- 远程脚本默认拒绝；可信脚本需要独立的应用策略和内容来源。
- 图片、链接和网络请求分别使用资源策略，不因 HTML 被规范化而自动获得网络权限。

## 一致性测试

建立服务端/客户端共享语料，至少覆盖嵌套错误、未知标签、属性大小写、URL 协议、CSS 丢弃、脚本策略、CJK 空白和诊断顺序。每次策略版本升级必须报告语料差异并附迁移说明。
