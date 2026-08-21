import AppKit
import SwiftUI

struct ScreenFrameReader: NSViewRepresentable {
    let onFrameChange: @MainActor (CGRect) -> Void

    func makeNSView(context: Context) -> ScreenFrameTrackingView {
        let view = ScreenFrameTrackingView()
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ view: ScreenFrameTrackingView, context: Context) {
        view.onFrameChange = onFrameChange
        Task { @MainActor [weak view] in
            view?.reportFrame()
        }
    }
}

@MainActor
final class ScreenFrameTrackingView: NSView {
    var onFrameChange: (@MainActor (CGRect) -> Void)?
    private var lastReportedFrame: CGRect?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    func reportFrame() {
        guard let window, !bounds.isEmpty else { return }
        let windowRect = convert(bounds, to: nil)
        let screenFrame = window.convertToScreen(windowRect)
        guard screenFrame != lastReportedFrame else { return }
        lastReportedFrame = screenFrame
        onFrameChange?(screenFrame)
    }
}
