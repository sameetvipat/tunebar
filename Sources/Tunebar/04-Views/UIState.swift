import Foundation

/// State that belongs to the views rather than the player. Kept in an ObservableObject instead of
/// @State because SwiftUI's @State macro needs the macro plugin that ships only with full Xcode, and
/// this project builds with the Command Line Tools.
final class UIState: ObservableObject {
    @Published var query = ""
    @Published var isSearching = false
    @Published var showingQueue = false
    @Published var showingVolume = false
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

    /// Leaving a page ends anything tied to it: Up Next, the editor, select mode, the new playlist panel.
    func resetForNavigation() {
        showingQueue = false
        showingVolume = false
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
