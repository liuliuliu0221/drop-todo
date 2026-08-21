import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showsWelcome: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let completed = UserDefaults.standard.bool(forKey: ShellWindowCoordinator.onboardingKey)
        _showsWelcome = State(initialValue: !arguments.contains("--ui-testing") && !completed)
    }

    var body: some View {
        if showsWelcome {
            welcome
        } else {
            dashboard
        }
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(systemName: "drop.fill")
                .font(.system(size: 68))
                .foregroundStyle(.blue)
            Text("欢迎使用水滴待办")
                .font(.largeTitle.bold())
            Text("任务保存在本机。以后应用会安静驻留在菜单栏，按 ⌥T 即可快速创建。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            VStack(alignment: .leading, spacing: 10) {
                Label("菜单栏水滴：查看数量和最近截止时间", systemImage: "menubar.rectangle")
                Label("全局 ⌥T：打开唯一的快速创建面板", systemImage: "keyboard")
                Label("关闭主窗口后，任务和到期检查继续运行", systemImage: "clock.arrow.circlepath")
            }
            .padding(20)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))

            Button("开始使用") {
                UserDefaults.standard.set(true, forKey: ShellWindowCoordinator.onboardingKey)
                showsWelcome = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("welcome.continue")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(42)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let error = environment.taskErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                summary
                TaskManagementView()
                displayPolicy
#if DEBUG
                transitionDebug
#endif

                Text("M5 正在接入完成坠落、水花与屏幕底部花园。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 680, minHeight: 620)
        .task { await environment.refreshTasks() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("水滴待办")
                    .font(.title2.bold())
                Text("M5 · 完成花园")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("设置") { environment.requestSettings() }
            Button("新建任务") { environment.requestQuickCapture() }
                .buttonStyle(.borderedProminent)
                .disabled(!environment.taskStoreReady)
                .accessibilityIdentifier("main.newTask")
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            summaryCard("进行中", count: environment.activeTasks.count, color: .blue)
            summaryCard("已完成", count: environment.completedTasks.count, color: .green)
            summaryCard("废墟", count: environment.ruinedCount, color: .orange)
        }
    }

    private func summaryCard(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var displayPolicy: some View {
        GroupBox("当前显示策略") {
            VStack(alignment: .leading, spacing: 8) {
                Label(environment.visibilityReason.title,
                      systemImage: environment.visibilityReason.symbolName)
                    .font(.headline)
                Text(environment.geometrySummary)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

#if DEBUG
    private var transitionDebug: some View {
        GroupBox("跨窗口动画 Spike") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("普通 SwiftUI 测试任务")
                            .font(.headline)
                        Text("此行通过 NSView 坐标转换获得全局屏幕起点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.down.right")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    ScreenFrameReader { frame in
                        environment.updateListSourceFrame(frame)
                    }
                    .allowsHitTesting(false)
                }

                HStack {
                    Button("刘海点 → 屏幕底边") { environment.playNotchTransition() }
                        .accessibilityIdentifier("transition.notch")
                    Button("列表行 → 屏幕底边") { environment.playListTransition() }
                        .accessibilityIdentifier("transition.list")
                    Spacer()
                    Label("坠向屏幕底边、不抢焦点", systemImage: "cursorarrow.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(environment.transitionSummary)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(environment.transitionSummary)
                    .accessibilityIdentifier("transition.status")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
#endif
}
