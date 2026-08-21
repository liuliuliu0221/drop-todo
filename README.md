# 水滴待办（WaterDropTodo）

水滴待办是一款本地优先的 macOS 时间感知待办应用。它把临近截止的任务显示为 MacBook 刘海下方的液态水滴，用颜色和位置传达紧迫程度，并通过完成花园、废墟与召回交互呈现任务的完整生命周期。

当前版本：`0.2.0 (2)`，第二阶段完成花园版本。

## 核心功能

- 刘海水滴：最多显示 8 个最近截止的任务，位置、颜色和形态由任务状态自动决定。
- 快速创建：使用全局快捷键 `⌥T` 打开唯一的快速创建面板。
- 悬停保护：悬停水滴可查看任务，并暂时冻结该任务的到期处理。
- 完成花园：完成任务后，水滴坠向屏幕底边并四溅，在随机落点长出小草；持续完成会让草地越来越密，并有 2% 概率长出稀有小花。
- 时间废墟：逾期任务进入废墟，可通过连续点击召回按钮恢复，也可永久焚毁。
- 本地持久化：任务使用沙盒内 JSON 存储，支持损坏恢复、导出和重启一致性。
- 辅助体验：支持“减少动态效果”、全屏隐藏策略和本地诊断日志。

## 运行环境

- macOS 13.0 或更高版本
- 带内置刘海屏的 Apple Silicon MacBook
- Xcode 26.6 或兼容的 Swift 6 工具链（源码构建）

无刘海设备不会启用水滴窗口。连接多个显示器、使用镜像显示或仅使用外接屏时，刘海水滴会暂停；任务数据与时间状态仍会继续维护。

## 技术架构

- SwiftUI：主窗口、任务管理、设置和快速创建界面
- AppKit：刘海、命中区域、悬停卡片、底部花园及跨窗口动画 Panel
- Metal：液态水滴 fragment shader；不可用时回退到位图渲染
- Swift 6 严格并发：领域服务、时间引擎与持久化边界
- Swift Testing / XCTest：单元、集成、UI、性能与可靠性验证
- KeyboardShortcuts `3.0.1`：全局快捷键，版本由 `Package.resolved` 锁定

## 从源码运行

```bash
git clone https://github.com/liuliuliu0221/drop-todo.git
cd drop-todo
open WaterDropTodo.xcodeproj
```

在 Xcode 中选择 `WaterDropTodo` Scheme 和 `My Mac`，然后运行。Swift Package Manager 会自动解析已锁定的依赖。

也可以使用命令行构建：

```bash
xcodebuild \
  -project WaterDropTodo.xcodeproj \
  -scheme WaterDropTodo \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## 验证与打包

执行 Release 质量门禁：

```bash
scripts/m4_quality_gate.sh
```

生成仅供本机验证的临时签名 DMG：

```bash
scripts/m4c_release.sh dry-run
```

`dry-run` 产物不能绕过 Gatekeeper 对外分发。交付给其他用户的版本必须使用 Developer ID 签名并完成 Apple 公证。

## 项目结构

```text
WaterDropTodo/          应用源码
WaterDropTodo/Garden/   花园密度、随机分布和持久化
WaterDropTodoTests/     单元与集成测试
WaterDropTodoUITests/   UI 自动化测试
scripts/                质量、可靠性与分发脚本
```

## 隐私

水滴待办不创建账户，不包含广告、分析 SDK 或遥测，当前版本没有联网功能。

- 任务和设置默认只保存在本机应用沙盒内。
- 只有用户主动导出时，任务 JSON 或诊断日志才会写入所选位置。
- 本地诊断日志仅保留最近 7 天，并且不记录任务名称。
- 应用不请求通讯录、日历、相机、麦克风、位置、屏幕录制或辅助功能权限。
- 全局快捷键依赖不会上传键盘输入。
- 删除应用不会自动删除 Application Support 中的数据；需要彻底清除时，请先在设置中执行清除数据。

## 状态

项目当前处于 `0.2.0` 完成花园内测阶段。建议提交问题时附上版本与构建号、Mac 机型、macOS 版本、显示器与全屏状态、复现步骤以及期望/实际结果；请勿在 Issue 中公开完整任务 JSON。
