import AppKit
import SwiftUI

struct DropletHitTarget: Identifiable, Sendable, Equatable {
    let id: UUID
    let index: Int
    let frame: CGRect
}

@MainActor
final class DropletHitPanel: NSPanel {
    init(
        target: DropletHitTarget,
        onHover: @escaping @MainActor (Bool) -> Void,
        onClick: @escaping @MainActor () -> Void
    ) {
        super.init(
            contentRect: target.frame,
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
        contentView = NSHostingView(
            rootView: HitAreaDebugView(
                hoverHandler: onHover,
                clickHandler: onClick
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(frame: CGRect) {
        setFrame(frame, display: true)
    }
}

@MainActor
final class HitTestCoordinator {
    typealias HoverHandler = @MainActor (UUID, Bool) -> Void
    typealias ClickHandler = @MainActor (UUID) -> Void

    private var panels: [UUID: DropletHitPanel] = [:]
    private var onHover: HoverHandler
    private var onClick: ClickHandler

    init(
        onHover: @escaping HoverHandler = { _, _ in },
        onClick: @escaping ClickHandler = { _ in }
    ) {
        self.onHover = onHover
        self.onClick = onClick
    }

    func setHoverHandler(_ handler: @escaping HoverHandler) {
        onHover = handler
    }

    func setClickHandler(_ handler: @escaping ClickHandler) {
        onClick = handler
    }

    func apply(_ targets: [DropletHitTarget]) {
        let visibleTargets = Self.disambiguatedTargets(Array(targets.prefix(8)))
        let visibleIDs = Set(visibleTargets.map(\.id))

        for target in visibleTargets {
            let panel = panels[target.id] ?? DropletHitPanel(
                target: target,
                onHover: { [weak self] isHovering in
                    self?.onHover(target.id, isHovering)
                },
                onClick: { [weak self] in
                    self?.onClick(target.id)
                }
            )
            panels[target.id] = panel
            panel.update(frame: target.frame)
            panel.orderFrontRegardless()
        }

        let staleIDs = panels.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            panels.removeValue(forKey: id)?.orderOut(nil)
        }
    }

    func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    nonisolated static func nearestTarget(
        to point: CGPoint,
        among targets: [DropletHitTarget]
    ) -> DropletHitTarget? {
        targets.min { lhs, rhs in
            lhs.frame.center.distanceSquared(to: point) < rhs.frame.center.distanceSquared(to: point)
        }
    }

    /// Adjacent hit panels may overlap when droplets are tightly packed. Split the
    /// overlap at the center midpoint so AppKit always routes the pointer to the
    /// same task that the nearest-center rule would select.
    nonisolated static func disambiguatedTargets(
        _ targets: [DropletHitTarget]
    ) -> [DropletHitTarget] {
        let sorted = targets.sorted { $0.frame.midX < $1.frame.midX }
        return sorted.enumerated().map { index, target in
            var frame = target.frame
            if index > 0 {
                let midpoint = (sorted[index - 1].frame.midX + frame.midX) / 2
                frame.origin.x = max(frame.minX, midpoint)
                frame.size.width = max(0, target.frame.maxX - frame.minX)
            }
            if index + 1 < sorted.count {
                let midpoint = (target.frame.midX + sorted[index + 1].frame.midX) / 2
                frame.size.width = max(0, min(target.frame.maxX, midpoint) - frame.minX)
            }
            return DropletHitTarget(id: target.id, index: target.index, frame: frame)
        }
    }
}

private struct HitAreaDebugView: View {
    let hoverHandler: @MainActor (Bool) -> Void
    let clickHandler: @MainActor () -> Void

    var body: some View {
        Group {
#if DEBUG
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                }
#else
            Color.clear
#endif
        }
        .onHover { isHovering in
            hoverHandler(isHovering)
        }
        .onTapGesture {
            clickHandler()
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
