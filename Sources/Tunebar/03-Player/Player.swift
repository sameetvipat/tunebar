import AppKit
import WebKit

/// The playback position and length. They change several times a second, so they live apart from
/// `Player`: only the progress bar observes them. (Publishing them from Player re-rendered every
/// view on each tick, which also collapsed open submenus.)
final class PlaybackClock: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
}

/// Owns the hidden YouTube Music web page that does the actual playback, mirrors its state for the
/// native UI, and holds the navigation stack of pages shown in the popover.
///
/// Split across files by concern:
/// - `Player.swift`: the web view, state reported by the page, bridge calls, messages
/// - `Navigation.swift`: loading pages and moving between them
/// - `Playback.swift`: playing, transport controls, mixes, "go to" the playing track's pages
/// - `Queue.swift`: Up Next
/// - `Account.swift`: ratings, library and playlist editing
@MainActor
final class Player: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView
    let clock = PlaybackClock()

    // MARK: Now playing (reported by the page)

    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: URL?
    @Published var isPaused = true
    @Published var isExplicit = false
    @Published var autoplay = true            // keep playing similar songs after the queue ends
    @Published var volume: Double = 100       // 0–100
    @Published var isMuted = false
    @Published var videoId = ""               // empty when nothing is playing
    @Published var likeStatus = Rating.none
    @Published var currentListId = ""         // the playlist or mix it plays from
    @Published var currentArtistId = ""
    @Published var currentArtistName = ""
    @Published var currentAlbumId = ""
    @Published var currentMixEndpoint = ""
    @Published var currentInLibrary = false
    @Published var currentLibraryAdd = ""
    @Published var currentLibraryRemove = ""

    // MARK: Pages and account data

    @Published var stack: [Page] = []
    /// Bumped on every navigation (not on in-place updates such as a rating change), so views can
    /// react to "the page changed", e.g. by leaving the queue view.
    @Published private(set) var navigation = 0
    @Published var queue: [QueueItem] = []
    @Published var ownPlaylists: [PlaylistRef] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toast: String?

    var current: Page? { stack.last }
    var canGoBack: Bool { stack.count > 1 }

    // MARK: Bookkeeping

    /// Changes made through the API that the hidden page's own state doesn't know about.
    var likeOverrides: [String: Rating] = [:]
    var libraryOverrides: [String: Bool] = [:]
    /// Artist/album of tracks started from a list (keyed by video id), shown until the page reports them.
    var knownLinks: [String: TrackLinks] = [:]
    /// Bumped by every play request; only the latest may fall back to reloading the page.
    var playRequest = 0
    /// The last query searched, so reopening the popover doesn't search again.
    var lastQuery = ""
    /// Set while the volume slider is being dragged.
    var adjustingVolume = false

    struct TrackLinks {
        var artistId: String?
        var artistName: String?
        var albumId: String?
        var mixEndpoint: String?
    }

    /// Safari's user agent, so Google doesn't reject sign-in as an embedded browser.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// - Parameters:
    ///   - dataStore: Where cookies live. The default store persists them, so sign-in survives
    ///     restarts; the self-test passes a throwaway one.
    ///   - extraScripts: Additional scripts to inject (the self-test mutes playback).
    init(dataStore: WKWebsiteDataStore? = nil, extraScripts: [String] = []) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore ?? .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        for source in [Self.bridgeSource] + extraScripts {
            config.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760), configuration: config)
        webView.customUserAgent = Self.userAgent
        super.init()
        webView.configuration.userContentController.add(self, name: "ytm")
        webView.load(URLRequest(url: URL(string: "https://music.youtube.com/")!))
    }

    /// Resources/bridge.js, copied into the app bundle by build.sh.
    private static let bridgeSource: String = {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("bridge.js is missing from the app bundle; build with ./build.sh")
        }
        return source
    }()

    // MARK: State from the page

    /// Receives bridge.js's now-playing reports (several per second while playing). Only assigns
    /// what changed, so unchanged state doesn't re-render the UI.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }
        func string(_ key: String) -> String { d[key] as? String ?? "" }
        func update<T: Equatable>(_ path: ReferenceWritableKeyPath<Player, T>, _ value: T) {
            if self[keyPath: path] != value { self[keyPath: path] = value }
        }

        clock.time = d["time"] as? Double ?? 0
        if let duration = d["duration"] as? Double, duration != clock.duration { clock.duration = duration }

        let id = string("videoId")
        update(\.videoId, id)
        update(\.title, string("title"))
        update(\.artist, string("artist"))
        update(\.artwork, URL(string: string("artwork")))
        update(\.isPaused, d["paused"] as? Bool ?? true)
        update(\.isExplicit, d["explicit"] as? Bool ?? false)
        update(\.autoplay, d["autoplay"] as? Bool ?? true)
        if !adjustingVolume { // don't fight the slider while it's being dragged
            update(\.volume, (d["volume"] as? Double) ?? volume)
            update(\.isMuted, d["muted"] as? Bool ?? false)
        }
        update(\.currentListId, string("listId"))
        update(\.likeStatus, likeOverrides[id] ?? Rating(rawValue: string("likeStatus")) ?? .none)
        update(\.currentInLibrary, libraryOverrides[id] ?? d["inLibrary"] as? Bool ?? false)
        update(\.currentLibraryAdd, string("libraryAdd"))
        update(\.currentLibraryRemove, string("libraryRemove"))

        // Until the page knows the track's artist/album, use what the list it was started from said.
        let known = knownLinks[id]
        func linked(_ key: String, _ fallback: String?) -> String {
            let value = string(key)
            return value.isEmpty ? fallback ?? "" : value
        }
        update(\.currentArtistId, linked("artistId", known?.artistId))
        update(\.currentArtistName, linked("artistName", known?.artistName))
        update(\.currentAlbumId, linked("albumId", known?.albumId))
        update(\.currentMixEndpoint, linked("mixEndpoint", known?.mixEndpoint))
    }

    // MARK: Bridge

    /// Calls `window.ytmBridge.<function>(args…)` in the page and returns its result.
    @discardableResult
    func bridge(_ function: String, _ args: Any...) async throws -> Any? {
        try await callBridge(function, args)
    }

    /// Calls a bridge function that returns JSON and decodes it. Nil if the task was cancelled.
    func bridge<T: Decodable>(_ type: T.Type, _ function: String, _ args: Any...) async throws -> T? {
        let raw = try await callBridge(function, args)
        guard !Task.isCancelled, let json = raw as? String else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// Arguments travel as named JavaScript values (a0, a1, …), so no escaping is needed.
    private func callBridge(_ function: String, _ args: [Any]) async throws -> Any? {
        var named: [String: Any] = [:]
        for (i, arg) in args.enumerated() { named["a\(i)"] = arg }
        let list = args.indices.map { "a\($0)" }.joined(separator: ", ")
        return try await webView.callAsyncJavaScript(
            "return await window.ytmBridge.\(function)(\(list));", arguments: named, contentWorld: .page)
    }

    /// True once the page and the bridge have loaded (waits up to 30 s).
    func waitUntilReady() async -> Bool {
        for _ in 0..<60 {
            let ready = try? await webView.callAsyncJavaScript(
                "return !!(window.ytcfg && window.ytmBridge && document.querySelector('ytmusic-app'))",
                contentWorld: .page)
            if ready as? Bool == true { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    // MARK: Messages

    /// A short message at the bottom of the popover.
    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }

    /// A readable message for an error. JavaScript exceptions carry theirs in userInfo.
    static func describe(_ error: Error) -> String {
        (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }

    // MARK: Stack changes

    /// Replaces the whole stack (a new root destination).
    func show(_ pages: [Page]) {
        stack = pages
        navigation += 1
    }

    /// Pages kept above the home page; following links deeper drops the oldest.
    private static let maxDepth = 10

    func push(_ page: Page) {
        stack.append(page)
        let floor = stack.first?.isHome == true ? 1 : 0 // never drop home
        if stack.count - floor > Self.maxDepth { stack.remove(at: floor) }
        navigation += 1
    }

    func goBack() {
        guard canGoBack else { return }
        stack.removeLast()
        navigation += 1
    }
}
