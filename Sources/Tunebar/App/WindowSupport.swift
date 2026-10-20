import AppKit
import SwiftUI

/// Hosting view that acts on the first click even while the popover isn't the key window yet (an
/// accessory app isn't always activated by the time you click), instead of swallowing that click.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSWindow {
    /// Keeps the window "on screen" as far as WebKit is concerned, but invisible and out of the way.
    /// A window that was never shown makes its page hidden, and WebKit then won't load media.
    func parkInvisibly() {
        alphaValue = 0
        ignoresMouseEvents = true
        collectionBehavior = [.transient, .ignoresCycle]
        setFrameOrigin(NSPoint(x: -20000, y: -20000))
        orderBack(nil)
    }

    /// Undoes `parkInvisibly` and brings the window forward.
    func unpark() {
        alphaValue = 1
        ignoresMouseEvents = false
        collectionBehavior = []
        center()
        makeKeyAndOrderFront(nil)
    }
}
