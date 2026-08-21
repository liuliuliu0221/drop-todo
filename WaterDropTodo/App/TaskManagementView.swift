import AppKit
import SwiftUI

private enum TaskListSection: String, CaseIterable, Identifiable {
    case active
    case completed
    case ruined

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "进行中"
        case .completed: "已完成"
        case .ruined: "时间废墟"
        }
    }
}

private enum TaskTagFilter: String, CaseIterable, Identifiable {
    case all
    case work
    case life
    case inspiration

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部标签"
        case .work: "工作"
        case .life: "生活"
        case .inspiration: "灵感"
        }
    }

    var tag: TaskTag? {
        switch self {
        case .all: nil
        case .work: .work
        case .life: .life
        case .inspiration: .inspiration
        }
    }
}

struct TaskManagementView: View {
    @EnvironmentObject private var environment: AppEnvironment

    @State private var section: TaskListSection = .active
    @State private var tagFilter: TaskTagFilter = .all
    @State private var editingTask: TaskRecord?
    @State private var pendingCancelTaskID: UUID?
    @State private var showsClearCompletedConfirmation = false
    @State private var recallSession = RecallTapSession()
    @State private var recallDeadline = Date().addingTimeInterval(30 * 60)
    @State private var pendingBurnTask: TaskRecord?
    @State private var actionError: String?
    @State private var isMutating = false

    private var filteredActiveTasks: [TaskRecord] {
        TaskQuery.active(environment.activeTasks, tag: tagFilter.tag)
    }

    var body: some View {
        GroupBox("任务管理") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("任务区域", selection: $section) {
                    ForEach(TaskListSection.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("tasks.section")

                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("tasks.error")
                }

                switch section {
                case .active:
                    activeList
                case .completed:
                    completedList
                case .ruined:
                    ruinedList
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(
                task: task,
                onCancel: { editingTask = nil },
                onSave: { changes in
                    try await environment.updateTask(id: task.id, changes: changes)
                    editingTask = nil
                }
            )
            .environmentObject(environment)
        }
        .alert("清除全部完成记录？", isPresented: $showsClearCompletedConfirmation) {
            Button("保留记录", role: .cancel) {}
                .accessibilityIdentifier("tasks.keepCompleted")
            Button("确认清除", role: .destructive) {
                runMutation { try await environment.clearCompletedTasks() }
            }
            .accessibilityIdentifier("tasks.confirmClearCompleted")
        } message: {
            Text("将删除全部已完成记录，此操作不能撤销。")
        }
        .alert("彻底焚毁这项任务？", isPresented: Binding(
            get: { pendingBurnTask != nil },
            set: { if !$0 { pendingBurnTask = nil } }
        )) {
            Button("保留废墟", role: .cancel) { pendingBurnTask = nil }
            Button("确认焚毁", role: .destructive) {
                guard let taskID = pendingBurnTask?.id else { return }
                pendingBurnTask = nil
                runMutation { try await environment.burnTask(id: taskID) }
            }
            .accessibilityIdentifier("ruins.confirmBurn")
        } message: {
            Text("该废墟记录将被永久删除，无法恢复；由它召回的新任务不会被删除。")
        }
    }

    private var activeList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("标签筛选", selection: $tagFilter) {
                    ForEach(TaskTagFilter.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .frame(width: 150)
                .accessibilityIdentifier("tasks.tagFilter")
                Spacer()
                Text("\(filteredActiveTasks.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if filteredActiveTasks.isEmpty {
                emptyState(
                    symbol: "checklist",
                    title: tagFilter == .all ? "还没有进行中的任务" : "此标签下没有任务",
                    detail: "点击右上角“新建任务”或按 ⌥T 开始。"
                )
            } else {
                ForEach(filteredActiveTasks) { task in
                    activeRow(task)
                    if task.id != filteredActiveTasks.last?.id { Divider() }
                }
            }
        }
    }

    private func activeRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.urgency.taskColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier("task.title.\(task.id.uuidString)")
                HStack(spacing: 8) {
                    Label(
                        task.deadline.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock"
                    )
                    if let tag = task.tag {
                        Text(tag.displayName)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }
                    Text("重要程度：\(task.urgency.displayName)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("编辑") { editingTask = task }
                .accessibilityIdentifier("task.edit.\(task.id.uuidString)")
            Button("完成") {
                runMutation { _ = try await environment.completeTask(id: task.id) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("task.complete.\(task.id.uuidString)")
            if pendingCancelTaskID == task.id {
                Button("保留") { pendingCancelTaskID = nil }
                    .accessibilityIdentifier("tasks.keepTask")
            }
            Button(pendingCancelTaskID == task.id ? "确认取消" : "取消") {
                if pendingCancelTaskID == task.id {
                    pendingCancelTaskID = nil
                    runMutation { try await environment.cancelTask(id: task.id) }
                } else {
                    pendingCancelTaskID = task.id
                }
            }
            .accessibilityIdentifier(
                pendingCancelTaskID == task.id
                    ? "tasks.confirmCancel"
                    : "task.cancel.\(task.id.uuidString)"
            )
            .foregroundStyle(.red)
        }
        .padding(.vertical, 8)
        .overlay {
            ScreenFrameReader { frame in
                environment.updateTaskRowFrame(taskID: task.id, frame: frame)
            }
            .allowsHitTesting(false)
        }
        .disabled(isMutating)
    }

    private var completedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("按完成时间倒序，只读显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清除完成记录", role: .destructive) {
                    showsClearCompletedConfirmation = true
                }
                .disabled(environment.completedTasks.isEmpty || isMutating)
                .accessibilityIdentifier("tasks.clearCompleted")
            }

            if environment.completedTasks.isEmpty {
                emptyState(symbol: "checkmark.circle", title: "暂无完成记录", detail: "完成的任务会出现在这里。")
            } else {
                ForEach(environment.completedTasks) { task in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.headline)
                            if let completedAt = task.completedAt {
                                Text("完成于 \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("只读")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("completed.task.\(task.id.uuidString)")
                    if task.id != environment.completedTasks.last?.id { Divider() }
                }
            }
        }
    }

    private var ruinedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连续点击同一任务右侧的“点击召回”按钮 10 次可召回；超过 1 秒或改点其他任务会重置裂纹。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if environment.ruinedTasks.isEmpty {
                VStack(spacing: 10) {
                    emptyState(symbol: "hourglass", title: "时间废墟为空", detail: "到期任务会自动从进行中移入这里。")
                    Button("返回进行中") { section = .active }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 0) {
                        ForEach(environment.ruinedTasks) { task in
                            ruinedRow(task, now: context.date)
                            if task.id != environment.ruinedTasks.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func ruinedRow(_ task: TaskRecord, now: Date) -> some View {
        let progress = recallSession.taskID == task.id ? recallSession.clickCount : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RuinCrackView(progress: progress)
                    .frame(width: 44, height: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                    Text("截止于 \(task.deadline.formatted(date: .abbreviated, time: .shortened))")
                    Text("已逾期 \(overdueDescription(now.timeIntervalSince(task.deadline)))")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()
                Button {
                    registerRecallTap(for: task)
                } label: {
                    Label {
                        Text(progress == 0 ? "点击召回" : "继续召回 \(progress)/10")
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(isMutating || progress == RecallTapSession.requiredTapCount)
                .accessibilityLabel("召回 \(task.title)，当前 \(progress) 次")
                .accessibilityIdentifier("ruins.recall.\(task.id.uuidString)")
                Button("焚毁", role: .destructive) { pendingBurnTask = task }
                    .disabled(isMutating)
                    .accessibilityIdentifier("ruins.burn.\(task.id.uuidString)")
            }

            if recallSession.taskID == task.id,
               recallSession.clickCount == RecallTapSession.requiredTapCount {
                VStack(alignment: .leading, spacing: 10) {
                    Text("为召回任务选择新截止时间")
                        .font(.callout.bold())
                    HStack {
                        Button("30 分钟后") { recallDeadline = Date().addingTimeInterval(30 * 60) }
                        Button("1 小时后") { recallDeadline = Date().addingTimeInterval(60 * 60) }
                        Button("2 小时后") { recallDeadline = Date().addingTimeInterval(2 * 60 * 60) }
                        DatePicker(
                            "自定义",
                            selection: $recallDeadline,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    HStack {
                        Button("取消召回") { recallSession.reset() }
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("确认召回") {
                            let taskID = task.id
                            let deadline = recallDeadline
                            recallSession.reset()
                            runMutation {
                                _ = try await environment.recallTask(id: taskID, newDeadline: deadline)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isMutating)
                        .accessibilityIdentifier("ruins.confirmRecall")
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 8)
    }

    private func registerRecallTap(for task: TaskRecord) {
        let count = recallSession.registerTap(taskID: task.id, at: Date())
        NSHapticFeedbackManager.defaultPerformer.perform(
            count == RecallTapSession.requiredTapCount ? .levelChange : .alignment,
            performanceTime: .now
        )
        if count == RecallTapSession.requiredTapCount {
            recallDeadline = Date().addingTimeInterval(30 * 60)
        }
    }

    private func overdueDescription(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return "\(max(1, minutes)) 分钟"
    }

    private func emptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
    }

    private func runMutation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isMutating else { return }
        actionError = nil
        isMutating = true
        Task { @MainActor in
            do {
                try await operation()
            } catch {
                actionError = error.localizedDescription
            }
            isMutating = false
        }
    }
}

private struct RuinCrackView: View {
    let progress: Int

    private var crackCount: Int {
        min(max(progress, 0), RecallTapSession.requiredTapCount)
    }

    var body: some View {
        ZStack {
            AsphaltDropShape()
                .fill(
                    LinearGradient(
                        colors: [.black, Color(white: 0.10), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

            AsphaltDropShape()
                .stroke(.white.opacity(0.10), lineWidth: 0.8)

            Ellipse()
                .fill(.white.opacity(0.13))
                .frame(width: 9, height: 15)
                .rotationEffect(.degrees(24))
                .offset(x: -9, y: -9)
                .blur(radius: 0.5)
                .mask(AsphaltDropShape())

            ZStack {
                ForEach(0..<crackCount, id: \.self) { index in
                    RuinCrackSegment(index: index)
                        .stroke(
                            Color.orange.opacity(0.82),
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: .orange.opacity(0.35), radius: 1)
                        .transition(
                            .scale(scale: 0.2, anchor: .top)
                                .combined(with: .opacity)
                        )
                }
            }
            .clipShape(AsphaltDropShape())
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: crackCount)
    }
}

private struct AsphaltDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: width * 0.51, y: height * 0.03))
        path.addCurve(
            to: CGPoint(x: width * 0.88, y: height * 0.52),
            control1: CGPoint(x: width * 0.59, y: height * 0.17),
            control2: CGPoint(x: width * 0.86, y: height * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.67, y: height * 0.91),
            control1: CGPoint(x: width * 0.94, y: height * 0.72),
            control2: CGPoint(x: width * 0.82, y: height * 0.89)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.34, y: height * 0.92),
            control1: CGPoint(x: width * 0.58, y: height * 0.98),
            control2: CGPoint(x: width * 0.43, y: height * 0.97)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.12, y: height * 0.55),
            control1: CGPoint(x: width * 0.18, y: height * 0.90),
            control2: CGPoint(x: width * 0.05, y: height * 0.73)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.51, y: height * 0.03),
            control1: CGPoint(x: width * 0.14, y: height * 0.34),
            control2: CGPoint(x: width * 0.43, y: height * 0.16)
        )
        path.closeSubpath()
        return path
    }
}

private struct RuinCrackSegment: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let points: [(CGPoint, CGPoint)] = [
            (point(0.51, 0.20, in: rect), point(0.43, 0.30, in: rect)),
            (point(0.43, 0.30, in: rect), point(0.54, 0.40, in: rect)),
            (point(0.54, 0.40, in: rect), point(0.46, 0.51, in: rect)),
            (point(0.46, 0.51, in: rect), point(0.56, 0.62, in: rect)),
            (point(0.56, 0.62, in: rect), point(0.48, 0.73, in: rect)),
            (point(0.48, 0.73, in: rect), point(0.53, 0.88, in: rect)),
            (point(0.54, 0.40, in: rect), point(0.70, 0.34, in: rect)),
            (point(0.46, 0.51, in: rect), point(0.29, 0.47, in: rect)),
            (point(0.56, 0.62, in: rect), point(0.72, 0.69, in: rect)),
            (point(0.48, 0.73, in: rect), point(0.32, 0.82, in: rect))
        ]

        guard points.indices.contains(index) else { return Path() }
        var path = Path()
        path.move(to: points[index].0)
        path.addLine(to: points[index].1)
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.width * x, y: rect.height * y)
    }
}

private struct EditTaskView: View {
    let task: TaskRecord
    let onCancel: () -> Void
    let onSave: (TaskChanges) async throws -> Void

    @State private var title: String
    @State private var deadline: Date
    @State private var tag: TaskTag?
    @State private var urgency: Urgency
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var titleIsFocused: Bool

    init(
        task: TaskRecord,
        onCancel: @escaping () -> Void,
        onSave: @escaping (TaskChanges) async throws -> Void
    ) {
        self.task = task
        self.onCancel = onCancel
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _deadline = State(initialValue: task.deadline)
        _tag = State(initialValue: task.tag)
        _urgency = State(initialValue: task.urgency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑任务")
                .font(.title2.bold())

            Form {
                TextField("任务名称", text: $title)
                    .focused($titleIsFocused)
                    .accessibilityIdentifier("edit.title")
                DatePicker(
                    "截止时间",
                    selection: $deadline,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("edit.deadline")
                Picker("标签", selection: $tag) {
                    Text("无标签").tag(TaskTag?.none)
                    ForEach(TaskTag.allCases, id: \.self) { value in
                        Text(value.displayName).tag(TaskTag?.some(value))
                    }
                }
                Picker("重要程度", selection: $urgency) {
                    ForEach(Urgency.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("edit.error")
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .accessibilityIdentifier("edit.save")
            }
        }
        .padding(24)
        .frame(width: 460, height: 390)
        .onAppear { titleIsFocused = true }
    }

    private func save() {
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true
        let changes = TaskChanges(
            title: title == task.title ? nil : title,
            deadline: deadline == task.deadline ? nil : deadline,
            tag: tag == task.tag ? .unchanged : .set(tag),
            urgency: urgency == task.urgency ? nil : urgency
        )
        Task { @MainActor in
            do {
                try await onSave(changes)
            } catch {
                errorMessage = error.localizedDescription
                titleIsFocused = true
            }
            isSaving = false
        }
    }
}

private extension Urgency {
    var taskColor: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}
