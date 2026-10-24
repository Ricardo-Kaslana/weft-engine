# ADR 0009：在布局阶段解析块级边框盒宽度

- 状态：已接受
- 日期：2026-10-25

## 背景

CSS 的 `width` 语义依赖 `box-sizing`、padding、border、最小/最大宽度和父级可用宽度。若在样式解析时直接把声明转换为最终像素盒宽，会丢失内容盒与边框盒的区别，也无法可靠处理约束求交。

## 决策

计算样式只保存经过单位换算的 `width/min-width/max-width`、`box-sizing` 和四边边框。布局阶段根据父级内容宽度、水平 margin、padding、border 计算 used border-box width：

1. 默认 `content-box` 将 width 加上水平 padding 和 border，转换为边框盒宽度。
2. `border-box` 直接使用声明值作为边框盒宽度。
3. 依次应用 max-width、min-width、父级可用宽度约束。
4. padding 与 border 之和构成内容宽度的下限，内容宽度不为负。

边框作为独立绘制命令，在背景之后、文本与列表标记之前绘制；四边支持独立宽度和颜色，但当前只解析 `solid`。

## 后果

盒宽语义集中在布局层，后续图片、表格和 Float 可复用同一换算规则。`WeftLayoutResult.boxes` 对外表达边框盒，文本命令则位于内容盒偏移。

当前只覆盖块级盒、px/em/rem 宽度、solid 边框；百分比、auto margin、height、圆角和虚线未实现。新增这些能力时应扩展尺寸解析和盒模型接口，而不是在样式层写死最终宽度。
