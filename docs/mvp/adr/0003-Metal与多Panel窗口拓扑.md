# ADR 0003：Metal 与多 Panel 窗口拓扑

- 状态：已采纳
- 日期：2026-08-19

## 背景

刘海液体既需要连续的 metaball 视觉，也必须让绝大多数透明区域点击穿透。单个大透明窗口难以同时满足稳定渲染和精确交互。

## 决定

- 液面和最多 8 个水滴由 `MTKView` 中的原生 Metal fragment shader 渲染。
- Canvas/Path 只绘制普通矢量、裂纹和装饰，不承担液体场计算。
- `NotchRenderPanel` 全程忽略鼠标；可见任务各自使用最小透明 `DropletHitPanel`，数量为 0～8。
- HoverCard、TransitionOverlay、Aquarium、QuickCapture 和 MainWindow 使用独立窗口职责。
- renderer 与命中窗口消费同一个不可变布局快照。

## 影响

M0 必须在实机验证窗口层级、全屏、点击穿透、坐标转换与 8 水滴性能。业务状态不得依赖动画回调。

## 备选方案

曾考虑 Canvas 距离场和单一大透明 Panel。前者不适合作为已确认液体场基线，后者会扩大鼠标拦截范围，因此未采纳。

## 回滚条件

只有 M0 实机证据证明 Metal 或小型命中 Panel 无法达到验收标准，且已有替代原型与测量结果时，才允许通过新 ADR 调整。
