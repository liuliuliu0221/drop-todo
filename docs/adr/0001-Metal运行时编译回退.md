# ADR-0001：M0 使用 Metal 运行时编译作为工具链回退

- 状态：M0 临时采用
- 日期：2026-08-19

## 背景

Xcode 构建 `.metal` 文件时要求额外安装 Metal Toolchain。本机通过 Xcode 界面和
`xcodebuild -downloadComponent MetalToolchain` 获取组件均失败，错误为无法获取
`com.apple.MobileAsset.MetalToolchain` 资产目录。

## 决策

M0 技术验证保留原生 Metal fragment shader，将 MSL 源码作为 Swift 字符串交给
`MTLDevice.makeLibrary(source:)` 运行时编译。CPU 仍只提交固定上限 8 个水滴参数，
不会生成逐像素位图，也不改用 Canvas 或第三方渲染框架。

## 影响

- 优点：不阻塞 M0C/M0D，继续验证 Metal 与多 Panel 架构；
- 代价：首次创建 renderer 会承担运行时编译开销，shader 错误不能在普通构建阶段发现；
- 后续：Metal Toolchain 可用后恢复 `.metal` 构建期编译，并增加 pipeline 创建失败的诊断测试。
