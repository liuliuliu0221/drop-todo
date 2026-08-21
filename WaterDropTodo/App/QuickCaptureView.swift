import SwiftUI

private enum QuickDeadlineOption: String, CaseIterable, Identifiable {
    case none
    case after30Minutes
    case after1Hour
    case after2Hours
    case tonightAt20
    case tomorrowAt9
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "选择截止时间"
        case .after30Minutes: "30 分钟后"
        case .after1Hour: "1 小时后"
        case .after2Hours: "2 小时后"
        case .tonightAt20: "今晚 20:00"
        case .tomorrowAt9: "明天 09:00"
        case .custom: "自定义…"
        }
    }

    func deadline(selectedAt now: Date, customDate: Date) throws -> Date {
        let preset: DeadlinePreset
        switch self {
        case .none:
            throw QuickCaptureValidationError.deadlineRequired
        case .after30Minutes:
            preset = .after30Minutes
        case .after1Hour:
            preset = .after1Hour
        case .after2Hours:
            preset = .after2Hours
        case .tonightAt20:
            preset = .tonightAt20
        case .tomorrowAt9:
            preset = .tomorrowAt9
        case .custom:
            preset = .custom(customDate)
        }
        return try DeadlinePresetResolver.resolve(preset, selectedAt: now)
    }
}

private enum QuickCaptureValidationError: LocalizedError {
    case deadlineRequired

    var errorDescription: String? {
        "请选择截止时间。"
    }
}

struct QuickCaptureView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @FocusState private var focusedField: Field?

    let presentationRequestedAt: TimeInterval
    let onCancel: () -> Void
    let onCreated: () -> Void

    @State private var title = ""
    @State private var deadlineOption: QuickDeadlineOption = ProcessInfo.processInfo.arguments
        .contains("--ui-testing-default-deadline") ? .after30Minutes : .none
    @State private var customDate = Date().addingTimeInterval(30 * 60)
    @State private var tag: TaskTag?
    @State private var urgency: Urgency = .medium
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var presentationLatencyMilliseconds: Double?

    private enum Field {
        case title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("快速创建")
                        .font(.title2.bold())
                    Text("⌥T 随时打开 · Enter 保存 · Esc 关闭")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("要完成什么？", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focusedField, equals: .title)
                .onSubmit(submit)
                .accessibilityIdentifier("quickCapture.title")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("截止时间")
                    Picker("截止时间", selection: $deadlineOption) {
                        ForEach(QuickDeadlineOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("quickCapture.deadline")
                }

                if deadlineOption == .custom {
                    GridRow {
                        Text("")
                        DatePicker(
                            "自定义截止时间",
                            selection: $customDate,
                            in: Date().addingTimeInterval(60)...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                    }
                }

                GridRow {
                    Text("标签")
                    Picker("标签", selection: $tag) {
                        Text("无标签").tag(TaskTag?.none)
                        ForEach(TaskTag.allCases, id: \.self) { value in
                            Text(value.displayName).tag(TaskTag?.some(value))
                        }
                    }
                    .labelsHidden()
                }

                GridRow {
                    Text("重要程度")
                    Picker("重要程度", selection: $urgency) {
                        ForEach(Urgency.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("quickCapture.error")
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("创建任务", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                    .accessibilityIdentifier("quickCapture.save")
            }

            if ProcessInfo.processInfo.arguments.contains("--ui-testing-performance"),
               let presentationLatencyMilliseconds {
                Text(String(format: "%.3f", presentationLatencyMilliseconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("quickCapture.latency")
                    .accessibilityLabel(String(format: "%.3f", presentationLatencyMilliseconds))
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
                await Task.yield()
                presentationLatencyMilliseconds = max(
                    0,
                    (ProcessInfo.processInfo.systemUptime - presentationRequestedAt) * 1_000
                )
            }
        }
    }

    private func submit() {
        guard !isSaving else { return }
        errorMessage = nil
        isSaving = true

        Task { @MainActor in
            do {
                let now = Date()
                let deadline = try deadlineOption.deadline(
                    selectedAt: now,
                    customDate: customDate
                )
                _ = try await environment.createTask(
                    CreateTaskInput(
                        title: title,
                        deadline: deadline,
                        tag: tag,
                        urgency: urgency
                    )
                )
                isSaving = false
                onCreated()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
                focusedField = .title
            }
        }
    }
}
