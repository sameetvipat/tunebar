import AppKit
import SwiftUI

extension View {
    /// Put inside a ScrollView's content: its scroll bar floats over the content, as with a trackpad,
    /// even when System Settings shows scroll bars always (e.g. with a mouse). Otherwise the bar takes
    /// a strip of its own and the page shifts sideways as it appears.
    func overlayScrollers() -> some View {
        background(OverlayScrollers())
    }
}

private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollersView { OverlayScrollersView() }
    func updateNSView(_ view: OverlayScrollersView, context: Context) {}
}

final class OverlayScrollersView: NSView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        // The scroll view goes back to the system's style whenever that setting changes.
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
    }

    private func apply() {
        guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
        scrollView.scrollerStyle = .overlay
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
