import AppKit
import SwiftUI

struct HoverCardContent: Sendable, Equatable {
    let task: TaskRecord
    let frozenRemainingTime: TimeInterval
    let isGraceExpired: Bool
    let isCompleting: Bool

    var remainingTimeText: String {
        if isGraceExpired { return "已到期" }
        if frozenRemainingTime < 60 { return "不足 1 分钟" }
        let minutes = Int(ceil(frozenRemainingTime / 60))
        return "剩余 \(minutes) 分钟"
    }
}

@MainActor
final class HoverCardPanel: NSPanel {
    static let cardSize = CGSize(width: 280, height: 172)
    private var onDismiss: (@MainActor () -> Void)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    func show(
        content: HoverCardContent,
        frame: CGRect,
        receivesEscape: Bool,
        onHover: @escaping @MainActor (Bool) -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        self.onDismiss = onDismiss
        contentView = NSHostingView(
            rootView: HoverTaskCardView(
                content: content,
                onHover: onHover,
                onDismiss: onDismiss,
                onComplete: onComplete
            )
        )
        setFrame(frame, display: true)
        if receivesEscape {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }
}

@MainActor
final class HoverCorridorPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(frame: CGRect, onHover: @escaping @MainActor (Bool) -> Void) {
        contentView = NSHostingView(rootView: HoverCorridorView(onHover: onHover))
        setFrame(frame, display: true)
        orderFrontRegardless()
    }
}

private struct HoverTaskCardView: View {
    let content: HoverCardContent
    let onHover: @MainActor (Bool) -> Void
    let onDismiss: @MainActor () -> Void
    let onComplete: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.task.title)
                .font(.headline)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.remainingTimeText)
                    .font(.title3.bold())
                    .foregroundStyle(content.isGraceExpired ? .red : .primary)
                Text("截止于 \(content.task.deadline.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if let tag = content.task.tag {
                    Label(tag.displayName, systemImage: "tag")
                }
                Label("重要程度：\(content.task.urgency.displayName)", systemImage: "exclamationmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(content.isGraceExpired ? "已到期" : content.isCompleting ? "完成中…" : "完成") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(content.isGraceExpired || content.isCompleting)
                .accessibilityIdentifier("notchCard.complete")
            }
        }
        .padding(16)
        .frame(width: HoverCardPanel.cardSize.width, height: HoverCardPanel.cardSize.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onExitCommand(perform: onDismiss)
    }
}

private struct HoverCorridorView: View {
    let onHover: @MainActor (Bool) -> Void

    var body: some View {
        Color.white.opacity(0.001)
            .onHover(perform: onHover)
    }
}
