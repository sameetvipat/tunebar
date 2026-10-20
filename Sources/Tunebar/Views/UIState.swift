import Foundation

/// What Now Playing shows in place of the artwork.
enum NowPlayingPanel {
    case queue, lyrics
}

/// State that belongs to the views rather than the player. Kept in an ObservableObject instead of
/// @State because SwiftUI's @State macro needs the macro plugin that ships only with full Xcode, and
/// this project builds with the Command Line Tools.
final class UIState: ObservableObject {
    @Published var query = ""
    @Published var isSearching = false
    @Published var cardPanel: NowPlayingPanel? // Up Next or the lyrics, opened above the card
    var showingQueue: Bool {
        get { cardPanel == .queue }
        set { cardPanel = newValue ? .queue : cardPanel == .queue ? nil : cardPanel }
    }
    @Published var showingVolume = false
    @Published var showingProfile = false
    /// The first-launch card saying Tunebar lives in the menu bar; once dismissed, never again.
    @Published var showingWelcome = !UserDefaults.standard.bool(forKey: UIState.welcomedKey)
    private static let welcomedKey = "welcomed"

    /// Searches you finished (by opening a result or closing the box), newest first; on this Mac only.
    @Published private(set) var recentSearches = UserDefaults.standard.stringArray(forKey: UIState.recentKey) ?? []
    private static let recentKey = "recentSearches"

    func rememberSearch(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        recentSearches = Array(([query] + recentSearches.filter { $0.caseInsensitiveCompare(query) != .orderedSame }).prefix(8))
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }

    func forgetSearch(_ query: String?) {
        recentSearches = query.map { q in recentSearches.filter { $0 != q } } ?? []
        UserDefaults.standard.set(recentSearches, forKey: Self.recentKey)
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: Self.welcomedKey)
        showingWelcome = false
    }
    @Published var showingNowPlaying = false {
        didSet {
            guard showingNowPlaying != oldValue else { return }
            surfaceOrder += 1
            if showingNowPlaying { cardRevealed = false } else { nowPlayingRevealed = false }
        }
    }
    /// Bumped each time the card and Now Playing trade places, so the one arriving draws on top of
    /// the one leaving (which keeps its old, lower value while it fades).
    @Published var surfaceOrder = 0
    // The text and controls of the card and of Now Playing fade in as the other's fade out, while
    // the artwork and background, drawn at full strength, grow or shrink between the two.
    @Published var nowPlayingRevealed = false
    @Published var cardRevealed = true
    @Published var nowPlayingPanel: NowPlayingPanel? // Up Next or lyrics, in place of the artwork
    @Published var nowPlayingVideo = false  // Now Playing's Video tab
    @Published var lyricsFollow = true      // the lyrics keep the current line in view (off once you scroll)
    @Published var lyricsVisible: [Int] = [] // the lyric lines on screen
    @Published var cardHeight: CGFloat = 110 // the player card's, so pages leave room for it
    @Published var hoveredID: String?
    @Published var scrub: Double?          // slider position while dragging
    @Published var descriptionExpanded = false
    @Published var contentScrolled = false // the page is scrolled down: blur under the top bar
    @Published var shelfPositions: [String: String] = [:] // sideways shelf title → item at its left edge

    // Bumped on each press to trigger the transport buttons' bounce.
    @Published var playTaps = 0
    @Published var nextTaps = 0
    @Published var previousTaps = 0

    // Playlist editor: shown for the page whose browseId matches.
    @Published var editingBrowseId: String?
    @Published var editTitle = ""
    @Published var editDescription = ""
    @Published var editPrivacy = "PRIVATE"
    @Published var confirmDelete = false

    // Select mode: rows get checkboxes; `selectable` is what the page lets you remove.
    @Published var isSelecting = false
    @Published var selection: Set<String> = []
    @Published var selectable: Set<String> = []

    // New playlist panel.
    @Published var isCreatingPlaylist = false
    @Published var newTitle = ""
    @Published var newPrivacy = "PRIVATE"
    @Published var pendingVideoId: String? // a song to start the new playlist with

    /// Asking to go somewhere leaves Now Playing and Up Next, before the page has even loaded (a page
    /// loading in the background then doesn't close them).
    func leavePlayer() {
        cardPanel = nil
        showingNowPlaying = false
        nowPlayingPanel = nil
    }

    /// Leaving a page ends anything tied to it: the editor, select mode, the new playlist panel.
    func resetForNavigation() {
        showingVolume = false
        contentScrolled = false // the new page starts at the top
        descriptionExpanded = false
        shelfPositions = [:]
        editingBrowseId = nil
        isCreatingPlaylist = false
        endSelecting()
    }

    func beginSelecting(_ items: [SearchItem]) {
        selectable = Set(items.map(\.id))
        selection = []
        isSelecting = true
    }

    func endSelecting() {
        isSelecting = false
        selection = []
        selectable = []
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func beginEditing(_ page: Page) {
        editTitle = page.title ?? ""
        editDescription = page.description ?? ""
        editPrivacy = page.privacy ?? "PRIVATE"
        confirmDelete = false
        editingBrowseId = page.browseId
    }

    func beginCreating(with videoId: String? = nil) {
        newTitle = ""
        newPrivacy = "PRIVATE"
        pendingVideoId = videoId
        isCreatingPlaylist = true
    }
}
