import SwiftUI

/// One page from the stack: its header (or library tabs), then its sections.
struct PageView: View {
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        // One container, so the error line and the page move and fade as one view.
        VStack(spacing: 0) {
            if let error = player.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .textSelection(.enabled)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if player.signedIn == false {
                        SignInPrompt(player: player)
                    }
                    if let suggestions = page.suggestions, !suggestions.isEmpty {
                    RelatedSearches(queries: suggestions, ui: ui)
                }
                if let tab = page.libraryTab {
                        LibraryTabs(selected: tab, player: player)
                        if page.items.isEmpty && !player.isLoading {
                            Text(tab == .history ? "Nothing played yet." : "Nothing here yet.")
                                .foregroundStyle(.secondary)
                                .padding(16)
                        }
                    } else if page.title != nil {
                        PageHeader(page: page, player: player, ui: ui)
                    }
                    if ui.isSelecting {
                        SelectionBar(page: page, player: player, ui: ui)
                    }
                    ForEach(Array(page.sections.enumerated()), id: \.offset) { index, section in
                        sectionHeader(section.title, items: section.items, isFirst: index == 0)
                        sectionBody(section.title, section.items)
                        if index == 0 { PageFooter(page: page) } // right under the track list, before other shelves
                    }
                }
                .padding(.bottom, 8)
                .overlayScrollers()
            }
            .onScrollGeometryChange(for: Bool.self, of: Self.isScrolled) { ui.contentScrolled = $1 }
        }
    }

    /// Scrolled away from the top (the offset starts at minus the top bar's inset).
    static func isScrolled(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentOffset.y + geometry.contentInsets.top > 2
    }

    // MARK: Sections

    /// How a section's items are laid out.
    private enum Layout {
        case grid       // cards wrapping in rows: the library and "View all" pages
        case carousel   // cards scrolling sideways
        case quickPicks // rows in a four-high grid scrolling sideways (home)
        case categories // coloured tiles, two to a row (Explore, Moods & Genres)
        case list       // rows, scrolling with the page

        /// Items one arrow press moves a sideways shelf by, and roughly how many fit in view.
        var step: Int { self == .quickPicks ? 4 : 2 }
    }

    private func layout(_ items: [SearchItem]) -> Layout {
        if items.allSatisfy(\.isCategory) { return .categories }
        if items.allSatisfy(\.isCard) { return page.isLibrary || page.filterName != nil ? .grid : .carousel }
        return page.isHome ? .quickPicks : .list
    }

    /// The item at a sideways shelf's left edge, kept in step with scrolling (by arrow or trackpad).
    private func shelfPosition(_ title: String) -> Binding<String?> {
        Binding(get: { ui.shelfPositions[title] }, set: { ui.shelfPositions[title] = $0 })
    }

    private func sectionHeader(_ title: String, items: [SearchItem], isFirst: Bool) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if isFirst, !ui.isSelecting, !player.removableItems(on: page).isEmpty {
                Button("Select") { ui.beginSelecting(player.removableItems(on: page)) }
                    .buttonStyle(.glass)
                    .help("Select items to remove")
            }
            if isFirst, page.playsAsList, let playlistId = page.playlistId {
                let shuffled = page.libraryTab == .songs // YouTube Music offers library songs shuffled
                Button { player.play(videoId: nil, playlistId: playlistId) } label: {
                    Label(shuffled ? "Shuffle All" : "Play All", systemImage: shuffled ? "shuffle" : "play.fill")
                }
                .buttonStyle(.glassProminent)
            } else if isFirst, page.libraryTab == .playlists {
                Button { ui.beginCreating() } label: { Label("New Playlist", systemImage: "plus") }
                    .buttonStyle(.glass)
            }
            if player.hasViewAll(title, on: page) {
                Button("View All") { Task { await player.viewAll(title, of: page) } }
                    .buttonStyle(.glass)
                    .help("See all \(title.lowercased())")
            }
            let shelf = layout(items)
            if shelf == .carousel || shelf == .quickPicks, items.count > shelf.step {
                ShelfArrows(items: items, step: shelf.step, position: shelfPosition(title))
            }
        }
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Card shelves scroll sideways like the web app, or wrap into a grid in the library and on
    /// "View all" pages. Quick picks on home become a sideways grid four rows high.
    @ViewBuilder private func sectionBody(_ title: String, _ items: [SearchItem]) -> some View {
        switch layout(items) {
        case .grid:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3),
                      spacing: 16) {
                ForEach(items) { CardItem(item: $0, page: page, player: player, ui: ui, size: 118) }
            }
            .padding(.horizontal, 16)
        case .carousel:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { CardItem(item: $0, page: page, player: player, ui: ui) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent) // margins, not padding, so arrow steps line up with them
            .scrollPosition(id: shelfPosition(title), anchor: .leading)
        case .quickPicks:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(54), spacing: 0), count: min(4, items.count)),
                          spacing: 0) {
                    ForEach(items) { ResultRow(item: $0, page: page, player: player, ui: ui).frame(width: 340) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .scrollPosition(id: shelfPosition(title), anchor: .leading)
        case .categories:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(items) { CategoryTile(item: $0, player: player) }
            }
            .padding(.horizontal, 16)
        case .list:
            // An album's own tracks are numbered instead of repeating its cover on every row.
            let numbered = page.pageType == PageType.album && title == page.sections.first?.title
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ResultRow(item: item, page: page, player: player, ui: ui, trackNumber: numbered ? index + 1 : nil)
            }
        }
    }
}

/// Shown in select mode: Select All / Deselect All, the count, Remove and Done.
struct SelectionBar: View {
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        let removable = player.removableItems(on: page).filter { ui.selectable.contains($0.id) }
        let chosen = removable.filter { ui.selection.contains($0.id) }
        let allChosen = !removable.isEmpty && chosen.count == removable.count
        HStack(spacing: 8) {
            Button(allChosen ? "Deselect All" : "Select All") {
                ui.selection = allChosen ? [] : Set(removable.map(\.id))
            }
            Spacer()
            Text("\(chosen.count) selected").font(.callout).foregroundStyle(.secondary)
            Button(role: .destructive) {
                player.removeItems(chosen, from: page)
                ui.endSelecting()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .disabled(chosen.isEmpty)
            Button("Done", action: ui.endSelecting)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

/// Artwork, title, owner and the page's actions.
struct PageHeader: View {
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Artwork(url: page.thumbnail, size: 96, circle: page.isArtist)
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.title ?? "").font(.title3.weight(.semibold)).lineLimit(2)
                    if let ownerId = page.ownerId, let ownerName = page.ownerName {
                        Button(ownerName) { player.open(id: ownerId, pageType: page.ownerType, title: ownerName) }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .fontWeight(.medium)
                            .help(page.ownerType == PageType.artist ? "Go to artist" : "Go to creator")
                    }
                    if let subtitle = page.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            actions
            if let description = page.description?.nonEmpty {
                PageDescription(text: description, expanded: $ui.descriptionExpanded)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Your own profile, which you can't subscribe to.
    private var isOwnProfile: Bool {
        guard let mine = player.account?.channelId else { return false }
        return page.channelId == mine || page.browseId == mine
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let playlistId = page.playlistId {
                Button { player.play(videoId: nil, playlistId: playlistId) } label: {
                    Label(page.isArtist ? "Shuffle" : "Play", systemImage: page.isArtist ? "shuffle" : "play.fill")
                }
                .buttonStyle(.glassProminent)
                if !page.isArtist {
                    Button { player.playShuffled(playlistId: playlistId) } label: {
                        Image(systemName: "shuffle").frame(height: 17)
                    }
                    .buttonBorderShape(.circle)
                    .help("Shuffle")
                    Button { player.startMix(playlistId: playlistId) } label: {
                        Label("Start Mix", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
            if let subscribed = page.subscribed, !isOwnProfile {
                Button { player.setSubscribed(page, !subscribed) } label: {
                    Label(subscribed ? "Subscribed" : "Subscribe",
                          systemImage: subscribed ? "checkmark" : "bell")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(subscribed ? "Unsubscribe" : page.subscribers.map { "\($0) subscribers" } ?? "Subscribe")
            }
            if page.isOwnedPlaylist {
                Button { ui.beginEditing(page) } label: { Label("Edit", systemImage: "pencil") }
            } else if let inLibrary = page.inLibrary {
                Button { player.setPageInLibrary(page, !inLibrary) } label: {
                    Label(inLibrary ? "Added" : "Add", systemImage: inLibrary ? "checkmark" : "plus")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(inLibrary ? "Remove from library" : "Add to library")
            }
            if (page.playlistId != nil && !page.isArtist) || page.shareURL != nil {
                Menu {
                    if let playlistId = page.playlistId, !page.isArtist {
                        QueueMenuItems(player: player, videoId: nil, playlistId: playlistId)
                    }
                    if let ownerId = page.ownerId {
                        Divider()
                        GoToItem(owner: page.ownerType, id: ownerId, name: page.ownerName, player: player)
                    }
                    Divider()
                    ShareItems(url: page.shareURL, title: page.title ?? "")
                } label: { Image(systemName: "ellipsis") }
                .menuIndicator(.hidden)
                .buttonBorderShape(.circle)
                .fixedSize()
                .help("More")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// ‹ › for a sideways shelf: moves it by `step` items, greyed out at either end.
private struct ShelfArrows: View {
    let items: [SearchItem]
    let step: Int
    @Binding var position: String?

    private var index: Int { items.firstIndex { $0.id == position } ?? 0 }
    private var lastStart: Int { max(items.count - step, 0) }

    var body: some View {
        // Plain glyphs without a background, like the player's buttons.
        HStack(spacing: 14) {
            Button { move(by: -step) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
                .help("Scroll left")
            Button { move(by: step) } label: { Image(systemName: "chevron.right") }
                .disabled(index >= lastStart)
                .help("Scroll right")
        }
        .buttonStyle(.borderless)
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
    }

    private func move(by offset: Int) {
        let target = min(max(index + offset, 0), lastStart)
        withAnimation(.move) { position = items[target].id }
    }
}

/// Shown while signed out: one click to Google's sign-in page.
struct SignInPrompt: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            YouTubeMusicMark().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in to YouTube Music").fontWeight(.semibold)
                Text("For your library, likes and recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Sign In", action: player.requestSignIn)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}

/// The small print under an album's or playlist's track list, as Apple Music shows it: release date,
/// length, label.
struct PageFooter: View {
    let page: Page

    var body: some View {
        let lines = [Self.releaseDate(page.released),
                     page.stats?.replacingOccurrences(of: " • ", with: ", "),
                     page.label.map { "℗ \($0)" }].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    /// "2004-02-10" → "10 February 2004", in the user's date format.
    private static func releaseDate(_ isoDate: String?) -> String? {
        guard let isoDate, let date = try? Date(isoDate, strategy: .iso8601.year().month().day()) else { return nil }
        return date.formatted(date: .long, time: .omitted)
    }
}

/// An album's, playlist's or artist's description: three lines, with More / Less when it's longer.
struct PageDescription: View {
    let text: String
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 3)
                .textSelection(.enabled)
            if text.count > 160 || text.contains("\n") {
                Button(expanded ? "Less" : "More") { withAnimation(.move) { expanded.toggle() } }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
            }
        }
    }
}

/// The library's tabs as capsules; the selected one is highlighted and scrolled into view.
struct LibraryTabs: View {
    let selected: LibraryTab
    @ObservedObject var player: Player

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    let button = Button { Task { await player.openLibrary(tab) } } label: {
                        Label(tab.shortTitle, systemImage: tab.symbol)
                    }
                    Group {
                        if tab == selected { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
                    }
                    .id(tab)
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        // Sideways only. (ScrollViewReader.scrollTo also moved the page itself, nudging it down.)
        .scrollPosition(id: Binding<LibraryTab?>(get: { selected }, set: { _ in }), anchor: .center)
        .padding(.top, 12)
    }
}

/// A Moods & Genres (or Explore) tile: its colour as a stripe and wash, like YouTube Music's.
private struct CategoryTile: View {
    let item: SearchItem
    let player: Player

    private var color: Color { item.color.flatMap(Color.init(hex:)) ?? .accentColor }

    var body: some View {
        Button { player.select(item) } label: {
            HStack(spacing: 0) {
                color.frame(width: 5)
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                Spacer(minLength: 0)
            }
            .frame(height: 48)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Related searches above search results; one click searches it.
private struct RelatedSearches: View {
    let queries: [String]
    @ObservedObject var ui: UIState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(queries, id: \.self) { query in
                    Button {
                        ui.rememberSearch(query)
                        ui.isSearching = true
                        ui.query = query
                    } label: {
                        Label(query, systemImage: "magnifyingglass").lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.top, 10)
    }
}

extension Color {
    /// "#RRGGBB".
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
