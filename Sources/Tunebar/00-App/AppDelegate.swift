import AppKit
import Carbon.HIToolbox

/// Sets up the menu bar item, its popover, the hidden web player window and the global hotkey.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let player = Player()
    private let ui = UIState()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var webWindow: NSWindow!
    private var hotKey: EventHotKeyRef?

    static let popoverSize = NSSize(width: 420, height: 620)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The web player lives in a window that's normally parked invisibly; "Show Web Player" reveals
        // it for signing in. It must stay in a window, or WebKit stops loading media.
        webWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
        webWindow.title = "YouTube Music"
        webWindow.contentView = player.webView
        webWindow.isReleasedWhenClosed = false
        webWindow.delegate = self
        webWindow.parkInvisibly()

        let content = NSViewController()
        content.view = FirstClickHostingView(rootView: ContentView(player: player, ui: ui))
        content.view.frame = NSRect(origin: .zero, size: Self.popoverSize)
        popover.contentViewController = content
        popover.contentSize = Self.popoverSize
        popover.behavior = .transient

        // Fixed width and a fixed icon, so the item (and the popover anchored to it) never shifts.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        registerHotKey()
        handleSpaceBar()

        // .transient closes on clicks elsewhere but not when another app takes focus some other way
        // (⌘Tab, Spotlight, a notification), so also close whenever this app stops being active.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }

        Task { await player.loadHome() }
    }

    // MARK: Popover and menu

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Web Player (Sign In)", action: #selector(showWebPlayer), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach again, so a left click opens the popover
    }

    @objc private func showWebPlayer() {
        NSApp.activate()
        webWindow.unpark()
    }

    @objc private func reload() {
        player.webView.reload()
        Task {
            try? await Task.sleep(for: .seconds(1)) // let the old page go away first
            await player.loadHome()
        }
    }

    /// Closing the web player window for real would stop playback, so it's parked instead.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.parkInvisibly()
        return false
    }

    // MARK: Keyboard

    /// Space plays/pauses while the popover is focused, except while the search box is open or any
    /// text field is being typed in (its field editor is then the first responder).
    private func handleSpaceBar() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.keyCode == UInt16(kVK_Space),
                      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      event.window === self.popover.contentViewController?.view.window,
                      !self.ui.isSearching, !(event.window?.firstResponder is NSText) else { return false }
                self.ui.playTaps += 1 // the play button's bounce
                self.player.togglePlay()
                return true
            }
            return handled ? nil : event // consumed, so it doesn't also press a focused button
        }
    }

    /// ⌃⌥M toggles the popover from anywhere. Carbon hot keys need no Accessibility permission.
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.togglePopover() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x544E_4252), id: 1) // "TNBR"
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }
}
