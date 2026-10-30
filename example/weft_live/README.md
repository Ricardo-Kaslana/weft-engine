# Weft Live

一张完全由 Weft 渲染的实时专题页：直播数据、自动快照、投票、鼓掌、
主题切换、话题筛选、深链接和文本选择都落在同一张 `RenderWeftSurface` 上。
页面不使用 WebView、DOM 生成或第三方脚本。

## 运行

```bash
cd example/weft_live
flutter run -d chrome
```

仓库已带 `web/` 平台目录；也可以先构建再静态托管：

```bash
flutter build web --no-pub --no-web-resources-cdn
```

深链接示例：

```text
/?section=agenda
/?theme=dark&section=poll
```

## 演示内容

- 每 2 秒更新在线人数、互动量、现场脉冲图和封面相位；每 12 秒有一条新的
  直播记录从流顶部进入。
- 顶部暂停按钮冻结当前快照；筛选按钮只改变直播流的叙述范围。
- 站内导航使用 `WeftViewState.scrollToNodeAsync`，深链接在首帧后定位章节。
- 投票和鼓掌是宿主白名单里的自定义标签：点击区域由引擎命中，宿主更新状态，
  下一次快照重算比例条。
- 页面支持长按选择、拖拽把手与复制按钮；主题切换会重新生成明/暗两套 CSS。
- 顶部跳底按钮直接驱动像素深跳；专题页正文包在单个 `.content` 顶层块中，
  懒布局无法在块内切窗，因此 `lazySettlingBuilder` 的骨架主要在多顶层块的
  长文中出现（示例测试注入 300 段验证）。
- 直播标题、图表、议程和投票数据均为演示内容。

## 自定义标签

`live_tag_renderers.dart` 用 Weft 的 rect/text ops 绘制：

| 标签 | 作用 |
|---|---|
| `weft-cover` | 主视觉中的编织信号场与相位变化 |
| `weft-live-band` | 当前环节、在线人数与直播/暂停状态 |
| `weft-pulse` | 最近 90 秒的活跃度柱状脉冲 |
| `weft-vote` | 带比例填充、票数和选中态的投票选项 |
| `weft-clap` | 现场鼓掌 CTA 与计数 |

标签必须同时出现在 `liveCustomTags`（规范化白名单）和
`liveTagRenderers`（受信任 Dart 渲染器）中。属性是唯一的数据契约。

## 测试

```bash
flutter test --no-pub
```

测试覆盖文档规范化、筛选/暂停、明暗主题切换、直接跳底的 settling 骨架、
异步章节导航不触发遮罩，以及通过语义树定位并点击投票和鼓掌标签的完整宿主闭环。
