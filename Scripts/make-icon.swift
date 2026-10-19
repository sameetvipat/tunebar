// Generates Resources/AppIcon.icns: the YouTube Music mark (white ring and play triangle) on a red
// macOS-style rounded square. Run from the project root:
//
//     swift Scripts/make-icon.swift
//
// The result is checked in; rerun only to change the icon.

import AppKit

let output = URL(fileURLWithPath: "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")

/// Draws the icon on a 1024×1024 canvas, scaled to `pixels`.
func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSAffineTransform().with { $0.scale(by: scale) }.concat()

    // Rounded square on the standard macOS icon grid (824 pt inside a 1024 pt canvas), with a soft
    // drop shadow.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor(red: 0.9, green: 0, blue: 0, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 1, green: 0.2, blue: 0.16, alpha: 1),
               ending: NSColor(red: 0.85, green: 0, blue: 0, alpha: 1))!.draw(in: tile, angle: -90)

    // The mark: a white ring and a white play triangle.
    NSColor.white.set()
    let ring = NSBezierPath(ovalIn: NSRect(x: 512 - 250, y: 512 - 250, width: 500, height: 500))
    ring.lineWidth = 46
    ring.stroke()
    let triangle = NSBezierPath()
    triangle.move(to: NSPoint(x: 450, y: 395))
    triangle.line(to: NSPoint(x: 450, y: 629))
    triangle.line(to: NSPoint(x: 652, y: 512))
    triangle.close()
    triangle.lineJoinStyle = .round
    triangle.lineWidth = 24
    triangle.fill()
    triangle.stroke() // rounds the corners slightly

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

extension NSAffineTransform {
    func with(_ change: (NSAffineTransform) -> Void) -> NSAffineTransform { change(self); return self }
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
