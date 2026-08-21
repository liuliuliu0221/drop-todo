import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var logEntries: [AppLogEntry] = []
    @State private var showsClearAllConfirmation = false
    @State private var dataMessage: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var systemMessage: String?

    var body: some View {
        Form {
            Section("快速创建") {
                KeyboardShortcuts.Recorder(
                    "全局快捷键",
                    name: .quickCapture
                )
                Text("默认是 ⌥T。录制器会阻止系统或应用菜单已经占用的组合键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("刘海显示") {
                LabeledContent("当前状态", value: environment.visibilityReason.title)
                Toggle("其他应用全屏时隐藏刘海水滴", isOn: Binding(
                    get: { environment.hideInFullscreen },
                    set: { environment.setHideInFullscreen($0) }
                ))
                Button("重新检测显示器") {
                    environment.refreshDisplayPolicy()
                }
            }

            Section("系统") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        updateLaunchAtLogin(enabled)
                    }
                LabeledContent(
                    "减少动态效果",
                    value: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "系统已开启" : "系统未开启"
                )
                if let systemMessage {
                    Text(systemMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("数据与诊断") {
                LabeledContent("进行中", value: "\(environment.activeTasks.count)")
                LabeledContent("已完成", value: "\(environment.completedTasks.count)")
                LabeledContent("废墟", value: "\(environment.ruinedCount)")
                LabeledContent("花园完成积累", value: "\(environment.gardenSnapshot.totalCompletions)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("花园完成积累 \(environment.gardenSnapshot.totalCompletions)")
                    .accessibilityIdentifier("settings.garden.total")
                LabeledContent("底边草地覆盖", value: "\(environment.gardenCoveragePercent)%")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("底边草地覆盖 \(environment.gardenCoveragePercent)%")
                    .accessibilityIdentifier("settings.garden.coverage")
                HStack {
                    Button("导出任务 JSON") {
                        runDataAction { try await environment.exportTasksJSON() }
                    }
                    Button("导出近 7 天日志") {
                        runDataAction { try await environment.exportRecentLogs() }
                    }
                    Spacer()
                    Button("清除全部数据", role: .destructive) {
                        showsClearAllConfirmation = true
                    }
                }
                if let dataMessage {
                    Text(dataMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("导出仅由你选择保存位置，不会自动上传；诊断日志不包含任务名称。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: BuildInfo.displayVersion)
                    .accessibilityIdentifier("settings.version")
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "未知")
                Text("任务和诊断数据默认只保存在本机；应用不会自动上传数据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

#if DEBUG
            Section("本地调试日志") {
                HStack {
                    Text("仅记录分类、任务 ID 和状态，不记录任务名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新") {
                        Task { logEntries = await LocalLogBuffer.shared.snapshot() }
                    }
                }

                if logEntries.isEmpty {
                    Text("暂无日志")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(logEntries.suffix(12).reversed())) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[\(entry.category.rawValue)] \(entry.level) · \(entry.timestamp.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
#endif
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 520, height: 520)
        .task {
#if DEBUG
            logEntries = await LocalLogBuffer.shared.snapshot()
#endif
        }
        .alert("清除全部任务数据？", isPresented: $showsClearAllConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久清除", role: .destructive) {
                Task { @MainActor in
                    do {
                        try await environment.clearAllTasks()
                        dataMessage = "全部任务数据已清除。"
                    } catch {
                        dataMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("进行中、已完成、废墟和召回历史都会被永久删除，且无法恢复。")
        }
    }

    private func runDataAction(_ operation: @escaping @MainActor () async throws -> URL?) {
        Task { @MainActor in
            do {
                if let url = try await operation() {
                    dataMessage = "已导出：\(url.lastPathComponent)"
                }
            } catch {
                dataMessage = error.localizedDescription
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            systemMessage = enabled ? "已启用登录时启动。" : "已关闭登录时启动。"
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            systemMessage = error.localizedDescription
        }
    }
}
