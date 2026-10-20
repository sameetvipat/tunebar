import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Sets up the menu bar item, its popover, the hidden web player window, sign-in and the global hotkey.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let player = Player()
    private let ui = UIState()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var webWindow: NSWindow!
    private let signInWindow = SignInWindow()
    private var hotKey: EventHotKeyRef?
    private var systemNowPlaying: SystemNowPlaying?
    private var videoWasStreaming = false

    static let popoverSize = NSSize(width: 420, height: 620)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The web player lives in a window that's normally parked invisibly ("Show Web Player" reveals
        // it, for troubleshooting). It must stay in a window, or WebKit stops loading media.
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
        popover.delegate = self

        // Fixed width and a fixed icon, so the item (and the popover anchored to it) never shifts.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        registerHotKey()
        handleKeys()
        closeSearchOnClickOutside()
        player.onSignInRequested = { [weak self] in self?.signIn() }
        systemNowPlaying = SystemNowPlaying(player: player)

        // .transient closes on clicks elsewhere but not when another app takes focus some other way
        // (⌘Tab, Spotlight, a notification), so also close whenever this app stops being active.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }

        Task { await player.loadHome() }

        // First launch: open by itself, so the popover's arrow points at the icon to come back to.
        if ui.showingWelcome {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePopover() }
        }
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

    // No video frames while the popover is closed; they resume if the Video tab is still showing.
    func popoverWillClose(_ notification: Notification) {
        videoWasStreaming = ui.showingNowPlaying && ui.nowPlayingVideo
        player.streamVideo(false)
    }
    func popoverDidShow(_ notification: Notification) {
        if videoWasStreaming { player.streamVideo(true) }
    }

    private func showMenu() {
        let menu = NSMenu()
        if player.signedIn == true {
            menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Sign In…", action: #selector(signIn), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Web Player", action: #selector(showWebPlayer), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach again, so a left click opens the popover
    }

    // MARK: Account

    @objc private func signIn() {
        popover.performClose(nil)
        signInWindow.present { [weak self] signedIn in
            if signedIn { self?.player.reloadSession() }
        }
    }

    @objc private func signOut() {
        Task { await player.signOut() }
    }

    @objc private func showWebPlayer() {
        NSApp.activate()
        webWindow.unpark()
    }

    @objc private func reload() {
        player.reload()
    }

    /// Closing the web player window for real would stop playback, so it's parked instead.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.parkInvisibly()
        return false
    }

    // MARK: Keyboard

    /// Keys while the popover is focused:
    /// - Space plays/pauses, except while the search box is open or a text field is being typed in
    ///   (its field editor is then the first responder).
    /// - Escape collapses Now Playing, else closes Up Next or the lyrics.
    /// - ⌘F searches, from Now Playing too (whose top bar, with the search button, steps aside).
    private func handleKeys() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.popover.contentViewController?.view.window else { return false }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let typing = event.window?.firstResponder is NSText
                switch Int(event.keyCode) {
                case kVK_Space where modifiers.isEmpty && !self.ui.isSearching && !typing:
                    self.ui.playTaps += 1 // the play button's bounce
                    self.player.togglePlay()
                case kVK_Escape where self.ui.showingNowPlaying:
                    self.ui.showingNowPlaying = false
                case kVK_Escape where self.ui.cardPanel != nil:
                    self.ui.cardPanel = nil
                case kVK_ANSI_F where modifiers == .command && self.ui.showingNowPlaying:
                    self.ui.showingNowPlaying = false
                    self.ui.isSearching = true
                default:
                    return false
                }
                return true
            }
            return handled ? nil : event // consumed, so it doesn't also press a focused button
        }
    }

    /// A click anywhere but the search box closes it (the results stay). Checked after the click is
    /// handled, so the box's own ✕, which closes it too, isn't undone by reopening it.
    private func closeSearchOnClickOutside() {
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.ui.isSearching,
                      let window = event.window, window === self.popover.contentViewController?.view.window else { return }
                var hit = window.contentView?.hitTest(event.locationInWindow)
                while let view = hit {
                    if view is NSTextField || view is NSText { return } // in the search box
                    hit = view.superview
                }
                DispatchQueue.main.async {
                    guard self.ui.isSearching else { return }
                    self.ui.rememberSearch(self.ui.query)
                    withAnimation(.quick) {
                        self.ui.isSearching = false
                        self.ui.query = ""
                    }
                }
            }
            return event
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
