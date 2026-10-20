import AppKit
import WebKit

/// The Video tab's current frame. Apart from `Player` for the same reason as the clock: it changes
/// many times a second, and only the video view should redraw.
final class VideoFeed: ObservableObject {
    @Published var frame: NSImage?

    func show(dataURL: String) {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let image = NSImage(data: data) else { return }
        frame = image
    }
}

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
/// - `Lyrics.swift`: the playing song's lyrics
/// - `SystemNowPlaying.swift`: media keys and Control Center
@MainActor
final class Player: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView
    let clock = PlaybackClock()
    let videoFeed = VideoFeed()
    private var videoStreaming = false

    // MARK: Now playing (reported by the page)

    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: URL?
    /// The artwork, downloaded once at Now Playing's size. The card and Now Playing both draw this
    /// one image, so it can grow and shrink between them without reloading.
    @Published var artworkImage: NSImage?
    @Published var isPaused = true {
        didSet { if isPaused != oldValue { stayAwake(!isPaused) } }
    }
    @Published var isExplicit = false
    @Published var autoplay = true            // keep playing similar songs after the queue ends
    @Published var repeatMode = RepeatMode.off
    @Published var volume: Double = 100       // 0–100
    @Published var isMuted = false
    @Published var signedIn: Bool? {         // nil until the page has said
        didSet { if signedIn != oldValue { loadAccount() } }
    }
    @Published var account: Account?          // who's signed in, for the profile button
    @Published var isAd = false               // an ad is playing: skipping tracks and seeking are off
    @Published var canSkipAd = false          // the page offers "Skip ad"
    @Published var hasVideoVersion = false    // the track has both a song and a music video version
    @Published var playingVideoVersion = false
    @Published var hasVideo = true            // false for a song that's only a still of its cover
    @Published var lyrics: Lyrics?            // the playing song's, once found; nil if it has none
    @Published var lyricsLoading = false
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
    /// reset what belonged to the old page, e.g. select mode.
    @Published private(set) var navigation = 0
    /// Bumped when you ask to go somewhere, before the page loads. Views leave Now Playing and Up Next
    /// on it, and a load only shows its page if no newer request came since.
    @Published private(set) var navigationRequest = 0
    @Published var queue: [QueueItem] = []
    @Published var ownPlaylists: [PlaylistRef] = []
    @Published var isLoading = false
    @Published var refreshingHome = false     // Home pressed while home: a fresh feed is loading
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
    /// Loads in progress; the spinner shows while there's any.
    private var loads = 0
    /// Bumped by every toast, so an older toast's timer doesn't hide a newer one.
    private var toastCount = 0
    /// The track the lyrics were last fetched for.
    var lyricsFor = ""
    /// Held while playing, so App Nap doesn't slow the app down (see `stayAwake`).
    private var playbackActivity: NSObjectProtocol?
    /// Set while the volume slider is being dragged.
    var adjustingVolume = false
    /// Shows the sign-in window (set by the app delegate, which owns it).
    var onSignInRequested: (() -> Void)?
    /// Called after each state report from the page (the system Now Playing listens).
    var onStateChange: (() -> Void)?

    struct TrackLinks {
        var artistId: String?
        var artistName: String?
        var albumId: String?
        var mixEndpoint: String?
    }

    /// Safari's user agent, so Google doesn't reject sign-in as an embedded browser.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

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
        webView.configuration.userContentController.add(self, name: "ytmFrame")
        webView.load(URLRequest(url: Self.homeURL))
    }

    /// Resources/bridge.js, copied into the app bundle by Scripts/build.sh.
    private static let bridgeSource: String = {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("bridge.js is missing from the app bundle; build with Scripts/build.sh")
        }
        return source
    }()

    // MARK: State from the page

    /// Receives bridge.js's now-playing reports (several per second while playing). Only assigns
    /// what changed, so unchanged state doesn't re-render the UI.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "ytmFrame" {
            if videoStreaming, let url = message.body as? String { videoFeed.show(dataURL: url) }
            return
        }
        guard let d = message.body as? [String: Any] else { return }
        func string(_ key: String) -> String { d[key] as? String ?? "" }
        func update<T: Equatable>(_ path: ReferenceWritableKeyPath<Player, T>, _ value: T) {
            if self[keyPath: path] != value { self[keyPath: path] = value }
        }

        clock.time = d["time"] as? Double ?? 0
        if let duration = d["duration"] as? Double, duration != clock.duration { clock.duration = duration }

        let id = string("videoId")
        update(\.videoId, id)
        if id != lyricsFor { loadLyrics(for: id) }
        update(\.title, string("title"))
        update(\.artist, string("artist"))
        let artworkURL = URL(string: string("artwork"))
        if artworkURL != artwork {
            artwork = artworkURL
            loadArtworkImage(artworkURL)
        }
        update(\.isPaused, d["paused"] as? Bool ?? true)
        update(\.isExplicit, d["explicit"] as? Bool ?? false)
        update(\.autoplay, d["autoplay"] as? Bool ?? true)
        update(\.repeatMode, RepeatMode(rawValue: string("repeat")) ?? .off)
        if let signedIn = d["signedIn"] as? Bool { update(\.signedIn, signedIn) }
        update(\.isAd, d["ad"] as? Bool ?? false)
        update(\.canSkipAd, d["adSkippable"] as? Bool ?? false)
        update(\.hasVideoVersion, d["hasVideoVersion"] as? Bool ?? false)
        update(\.playingVideoVersion, d["videoVersion"] as? Bool ?? false)
        update(\.hasVideo, d["hasVideo"] as? Bool ?? true)
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
        onStateChange?()
    }

    // MARK: Staying responsive

    /// While music plays, keeps macOS from napping the app (App Nap also slows timers), as music
    /// apps do. Sleep is still allowed.
    private func stayAwake(_ playing: Bool) {
        if playing, playbackActivity == nil {
            playbackActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "Playing music")
        } else if !playing, let activity = playbackActivity {
            ProcessInfo.processInfo.endActivity(activity)
            playbackActivity = nil
        }
    }

    // MARK: Artwork

    /// Keeps showing the previous image until the new one has arrived, so nothing flashes empty.
    private func loadArtworkImage(_ url: URL?) {
        guard let sized = Artwork.sized(url, points: 240) else {
            artworkImage = nil
            return
        }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: sized),
                  artwork == url, let image = NSImage(data: data) else { return }
            artworkImage = image
            onStateChange?()
        }
    }

    // MARK: Video

    /// Turns the Video tab's frames on or off (see bridge.js `videoFrames`). Off whenever the popover
    /// is closed, so no frames are made that nobody sees.
    func streamVideo(_ on: Bool) {
        guard on != videoStreaming else { return }
        videoStreaming = on
        if !on { videoFeed.frame = nil }
        Task { _ = try? await bridge("videoFrames", on) }
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
                "return !window.tunebarStale && !!(window.ytcfg && window.ytmBridge && document.querySelector('ytmusic-app'))",
                contentWorld: .page)
            if ready as? Bool == true { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    // MARK: Account session

    func requestSignIn() { onSignInRequested?() }

    /// Starts over on the home page with the current sign-in, e.g. after signing in or out.
    func reloadSession() {
        likeOverrides = [:]
        libraryOverrides = [:]
        ownPlaylists = []
        lastQuery = ""
        show([])
        reload()
    }

    /// Loads the page afresh at `url`, then the home feed.
    func reload(_ url: URL = Player.homeURL) {
        Task {
            await loadPage(url)
            await loadHome()
        }
    }

    /// Loads a new page. The old one is marked first, so `waitUntilReady` waits for the new page
    /// rather than mistaking the old one, still there for a moment, for it.
    func loadPage(_ url: URL) async {
        _ = try? await webView.callAsyncJavaScript("window.tunebarStale = true", contentWorld: .page)
        webView.load(URLRequest(url: url))
    }

    nonisolated static let homeURL = URL(string: "https://music.youtube.com/")!

    /// Signs out by removing Google's and YouTube's cookies and site data from Tunebar's store.
    /// Fetches the account once signed in; forgets it once signed out.
    private func loadAccount() {
        guard signedIn == true else {
            account = nil
            return
        }
        Task {
            guard let found = try? await bridge(Account?.self, "account"), signedIn == true else { return }
            account = found
        }
    }

    func signOut() async {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let google = records.filter { record in ["google", "youtube"].contains { record.displayName.contains($0) } }
        await store.removeData(ofTypes: types, for: google)
        signedIn = false
        reloadSession()
        showToast("Signed out")
    }

    // MARK: Messages

    /// A short message at the bottom of the popover.
    func showToast(_ message: String) {
        toast = message
        toastCount += 1
        let count = toastCount
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toastCount == count { toast = nil }
        }
    }

    // MARK: Loading

    func beginLoading() {
        loads += 1
        isLoading = true
    }

    func endLoading() {
        loads = max(loads - 1, 0)
        if loads == 0 { isLoading = false }
    }

    /// Starts a navigation you asked for; returns its number, for `isLatest`.
    func beginNavigation() -> Int {
        navigationRequest += 1
        return navigationRequest
    }

    /// Whether no navigation was asked for since `request`; an older load then drops its page.
    func isLatest(_ request: Int) -> Bool { request == navigationRequest }

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
        _ = beginNavigation()
        stack.removeLast()
        navigation += 1
    }
}
