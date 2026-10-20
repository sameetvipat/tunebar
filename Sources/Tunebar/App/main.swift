import AppKit

// Entry point. A menu bar app: no Dock icon, no main window.
// `TUNEBAR_SELFTEST=1` runs the smoke test instead of the app (see SelfTest.swift).

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate =
        ProcessInfo.processInfo.environment["TUNEBAR_SELFTEST"] != nil ? SelfTest() : AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
