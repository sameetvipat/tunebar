import AppKit
import SwiftUI
import WebKit

/// Google's own sign-in page in a small window of its own. It shares the player's cookie store, so
/// signing in here signs the player in, and it closes itself as soon as Google hands back to YouTube
/// Music. (Passwords go to Google's page, never to Tunebar.)
@MainActor
final class SignInWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: ((Bool) -> Void)?

    /// Google's YouTube sign-in, continuing to YouTube Music. `passive` skips the form if already signed in.
    private static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")!

    /// Shows the window (or brings it forward); `onFinish` gets whether sign-in completed.
    func present(onFinish: @escaping (Bool) -> Void) {
        NSApp.activate()
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        self.onFinish = onFinish

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // the player's store
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Player.userAgent
        webView.navigationDelegate = self

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Sign In to YouTube Music"
        window.contentView = Self.layout(hint: NSHostingView(rootView: PasskeyHint()), above: webView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        webView.load(URLRequest(url: Self.signInURL))
        window.makeKeyAndOrderFront(nil)
    }

    /// The note pinned above Google's page.
    private static func layout(hint: NSView, above webView: NSView) -> NSView {
        let container = NSView()
        for view in [hint, webView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: container.topAnchor),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: hint.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// Google sends the browser back to YouTube Music once you're signed in: that's the cue to close.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard action.request.url?.host == "music.youtube.com" else { return .allow }
        finish(signedIn: true)
        return .cancel
    }

    func windowWillClose(_ notification: Notification) {
        finish(signedIn: false) // closed by hand before finishing
    }

    private func finish(signedIn: Bool) {
        guard let done = onFinish else { return }
        onFinish = nil
        let closing = window
        window = nil
        closing?.close()
        done(signedIn)
    }
}

/// Passkeys and Keychain passwords only work in Safari and other apps Apple approves as browsers,
/// so Google's page can't offer them here. This says what to pick instead.
private struct PasskeyHint: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Passkeys aren't available outside your browser. If Google asks for one, click **Try another way**, then choose a **prompt on your phone** (quickest) or your **password**.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
