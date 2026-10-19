import AppKit

/// The menu bar item's icon, drawn in code.
enum MenuBarIcon {
    /// The YouTube Music mark (a disc with a ring and a play triangle cut out) as a template image,
    /// so macOS tints it like every other menu bar icon, in light and dark menu bars alike.
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: 9, y: 9)
            func circle(_ radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2))
            }
            // Even-odd filling of nested shapes alternates filled/empty: disc, ring gap, inner disc,
            // triangle.
            let path = circle(8)
            path.append(circle(5.4))
            path.append(circle(4.2))
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 7.5, y: 6.6))
            triangle.line(to: NSPoint(x: 7.5, y: 11.4))
            triangle.line(to: NSPoint(x: 11.6, y: 9))
            triangle.close()
            path.append(triangle)
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tunebar"
        return image
    }()
}
