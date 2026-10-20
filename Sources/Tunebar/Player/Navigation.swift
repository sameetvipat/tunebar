import Foundation

/// Loading pages into the popover and moving between them. The home feed is the root of the stack;
/// search, library tabs and other destinations sit on top of it.
extension Player {
    /// The home page, if it's at the bottom of the stack.
    private var root: [Page] { stack.first.map { $0.isHome ? [$0] : [] } ?? [] }

    func loadHome() async {
        beginLoading()
        defer { endLoading() }
        guard await waitUntilReady() else {
            errorMessage = "YouTube Music didn't load. Try Reload from the right-click menu."
            return
        }
        do {
            guard var home = try await bridge(Page.self, "browse", "FEmusic_home", 4) else { return }
            home.pageType = Page.homeType
            // Slid in underneath whatever is showing; that isn't a navigation.
            if root.isEmpty { stack.insert(home, at: 0) } else { stack[0] = home }
            errorMessage = nil
            await refreshOwnPlaylists()
        } catch {
            errorMessage = "Couldn't load home: \(Self.describe(error))"
        }
    }

    /// Opens home, or, when it's already showing, fetches a fresh feed and fades it in at the top.
    func goHome() {
        _ = beginNavigation()
        lastQuery = ""
        if current?.isHome == true {
            guard !refreshingHome else { return }
            refreshingHome = true
            Task {
                await loadHome()
                refreshingHome = false
                if current?.isHome == true { show(root) } // unless you've gone elsewhere meanwhile
            }
        } else if root.isEmpty {
            show([])
            Task { await loadHome() }
        } else {
            show(root)
        }
    }

    /// Opens a library tab. Tabs replace each other rather than stacking up.
    func openLibrary(_ tab: LibraryTab = .playlists) async {
        let request = beginNavigation()
        beginLoading()
        defer { endLoading() }
        guard await waitUntilReady() else { return }
        do {
            guard var page = try await bridge(Page.self, "browse", tab.browseId, 3, tab.rawValue) else { return }
            page.libraryTab = tab
            if !page.playsAsList { page.playlistId = nil }
            if tab == .songs { page.items.removeAll { $0.videoId == nil } } // its "Shuffle all" row; Shuffle All covers it
            guard isLatest(request) else { return }
            show(root + [page])
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your library: \(Self.describe(error))"
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        // The search field's task re-runs whenever the popover reopens; don't redo the same search
        // and throw away pages opened since. Clearing the field keeps the current page.
        guard query != lastQuery else { return }
        lastQuery = query
        guard !query.isEmpty else { return }
        let request = beginNavigation()
        beginLoading()
        defer { endLoading() }
        do {
            async let related = try? bridge([String].self, "searchSuggestions", query)
            guard var page = try await bridge(Page.self, "search", query) else {
                lastQuery = "" // cancelled (popover closed or typing continued): allow a retry
                return
            }
            page.query = query
            page.suggestions = (await related ?? nil)?.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
            guard isLatest(request) else { return }
            show(root + [page])
            errorMessage = nil
        } catch {
            lastQuery = ""
            if !Task.isCancelled { errorMessage = "Search failed: \(Self.describe(error))" }
        }
    }

    // MARK: Pages on top

    func browse(_ item: SearchItem) async {
        guard let id = item.browseId else { return }
        await browse(id: id, pageType: item.pageType, title: item.title, thumbnail: item.thumbnail,
                     params: item.params)
    }

    /// Explore: new releases, charts, moods & genres. Replaces whatever is above home, like the library.
    func openExplore() async {
        let request = beginNavigation()
        beginLoading()
        defer { endLoading() }
        guard await waitUntilReady() else { return }
        do {
            guard var page = try await bridge(Page.self, "browse", "FEmusic_explore", 1) else { return }
            page.pageType = Page.exploreType
            page.browseId = "FEmusic_explore"
            page.title = nil // its sections say what's what
            guard isLatest(request) else { return }
            show(root + [page])
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Explore: \(Self.describe(error))"
        }
    }

    /// Opens a browse page.
    /// - Parameters:
    ///   - title, thumbnail: Shown if the page's own header lacks them.
    ///   - params: For "See all" pages.
    ///   - asList: Show it as a plain list titled `title` (a "See all" page) rather than with a header.
    func browse(id: String, pageType: String?, title: String, thumbnail: String? = nil,
                params: String? = nil, asList: Bool = false) async {
        let request = beginNavigation()
        beginLoading()
        defer { endLoading() }
        do {
            // Long playlists arrive in pages; follow them so editing sees every track.
            guard var page = try await bridge(Page.self, "browse", id, 20, asList ? title : "Songs", params ?? "")
            else { return }
            page.browseId = id
            page.pageType = pageType
            // Only albums, playlists and artists (shuffle) play as a whole. A creator's profile has no
            // list of its own; the bridge's fallback would pick whichever playlist is listed first.
            if ![PageType.album, PageType.playlist, PageType.artist].contains(pageType) { page.playlistId = nil }
            if asList {
                page.title = nil
                page.filterName = title
                page.more = nil
            } else if page.title == nil {
                page.title = title
            }
            if page.thumbnail == nil { page.thumbnail = thumbnail }
            guard isLatest(request) else { return }
            push(page)
            errorMessage = nil
            let tracks = page.items.compactMap(\.videoId)
            if pageType == PageType.album, !tracks.isEmpty {
                Task { await loadAlbumDetails(browseId: id, tracks: tracks) }
            }
        } catch {
            errorMessage = "Couldn't open \(title): \(Self.describe(error))"
        }
    }

    /// Opens a page from a view without awaiting it.
    func open(id: String, pageType: String?, title: String) {
        Task { await browse(id: id, pageType: pageType, title: title) }
    }

    /// Whether a section has a "View all": a search filter, or a shelf's "See all" page.
    func hasViewAll(_ section: String, on page: Page) -> Bool {
        page.filterName == nil && (page.filters?[section] != nil || page.more?[section] != nil)
    }

    func viewAll(_ section: String, of page: Page) async {
        if let link = page.more?[section] {
            await browse(id: link.browseId, pageType: link.pageType, title: section, params: link.params,
                         asList: link.params != nil)
            return
        }
        guard let query = page.query, let params = page.filters?[section] else { return }
        let request = beginNavigation()
        beginLoading()
        defer { endLoading() }
        do {
            guard var all = try await bridge(Page.self, "search", query, params, 4, section) else { return }
            all.query = query
            all.filterName = section
            guard isLatest(request) else { return }
            push(all)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load all \(section.lowercased()): \(Self.describe(error))"
        }
    }

    /// Fills in an open album's release date and label, which come from its tracks.
    private func loadAlbumDetails(browseId: String, tracks: [String]) async {
        guard let details = try? await bridge(AlbumDetails.self, "albumDetails", tracks) else { return }
        for i in stack.indices where stack[i].browseId == browseId {
            stack[i].released = details.released
            stack[i].label = details.label
        }
    }

    /// Re-fetches any open copy of a page, so edits made from elsewhere show up. Takes the fresh
    /// header too: a playlist only reports that it's yours once it has songs.
    func refreshPages(browseId: String) async {
        guard stack.contains(where: { $0.browseId == browseId }),
              let fresh = try? await bridge(Page.self, "browse", browseId, 20) else { return }
        for i in stack.indices where stack[i].browseId == browseId {
            stack[i].items = fresh.items
            stack[i].subtitle = fresh.subtitle
            stack[i].stats = fresh.stats
            stack[i].thumbnail = fresh.thumbnail ?? stack[i].thumbnail
            stack[i].playlistId = fresh.playlistId ?? stack[i].playlistId
            stack[i].description = fresh.description
            if fresh.owned == true {
                stack[i].owned = true
                stack[i].privacy = fresh.privacy
            }
        }
    }
}
