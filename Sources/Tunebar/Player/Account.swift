import Foundation

/// Why an account action failed, as shown in the message at the bottom of the popover.
enum ActionError: LocalizedError {
    case failed(String)
    case duplicate // the song is already in that playlist

    var errorDescription: String? {
        switch self {
        case .failed(let reason): reason
        case .duplicate: "Already in the playlist"
        }
    }
}

/// Account actions: ratings, library saves and playlist editing. Each goes through YouTube Music's
/// API from inside the page, then updates the local pages so the UI changes without a reload.
extension Player {
    // MARK: Plumbing

    /// Calls a youtubei endpoint with a body built here, and checks the answer.
    @discardableResult
    private func callAPI(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let json = try await bridge("call", endpoint, body) as? String,
              let response = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw ActionError.failed("Unexpected response")
        }
        if let error = response["error"] as? [String: Any] {
            Log.write("\(endpoint) error: \(json.prefix(2000))")
            throw ActionError.failed(error["message"] as? String ?? "Error")
        }
        if let status = response["status"] as? String, status != "STATUS_SUCCEEDED" {
            Log.write("\(endpoint) \(status): \(json.prefix(2000))")
            // A duplicate add answers with a failed status and an "already in this playlist" dialog.
            if json.contains("DEDUPE") || json.localizedCaseInsensitiveContains("already") { throw ActionError.duplicate }
            throw ActionError.failed(status)
        }
        return response
    }

    /// Runs `work`, then shows `success`, or the error if it threw.
    private func perform(_ success: String, _ work: () async throws -> Void) async {
        do {
            try await work()
            showToast(success)
        } catch {
            Log.write("\(success) failed: \(Self.describe(error))")
            showToast("Couldn't do that: \(Self.describe(error))")
        }
    }

    /// The id to edit `page` with, or nil (after saying so) if it isn't a playlist you can edit.
    private func editableId(_ page: Page) -> String? {
        guard let id = page.editablePlaylistId else {
            Log.write("not editable: \(page.browseId ?? "-") owned=\(String(describing: page.owned))")
            showToast("This playlist can't be edited")
            return nil
        }
        return id
    }

    /// Applies a change to every copy of an item on every open page.
    private func updateItems(_ change: (inout SearchItem) -> Void) {
        for i in stack.indices {
            for j in stack[i].items.indices { change(&stack[i].items[j]) }
        }
    }

    // MARK: Keeping open lists current
    //
    // YouTube Music's own Liked and library lists take a few seconds to include a change, so
    // refetching them right after one shows the old list. Instead, open lists are updated here.

    /// Liked songs, opened from the library or as the "Liked music" playlist.
    private func isLikedList(_ page: Page) -> Bool { page.isLikedSongs || page.browseId == "VLLM" }

    /// The library tab an album or playlist belongs in.
    private func libraryTab(for item: SearchItem) -> LibraryTab? {
        switch item.pageType {
        case PageType.album: .albums
        case PageType.playlist: .playlists
        default: nil
        }
    }

    /// Puts `item` at the top of every open page matching `include` (below "Liked music" in
    /// Playlists), unless it's already there.
    private func insert(_ item: SearchItem, into include: (Page) -> Bool) {
        let key = item.videoId ?? item.browseId ?? item.playlistId
        for i in stack.indices where include(stack[i]) {
            guard !stack[i].items.contains(where: { ($0.videoId ?? $0.browseId ?? $0.playlistId) == key }) else { continue }
            var entry = item
            entry.section = stack[i].items.first?.section ?? stack[i].libraryTab?.rawValue ?? "Songs"
            entry.id = entry.section + "|" + (key ?? item.title)
            let top = stack[i].items.firstIndex { $0.browseId != "VLLM" } ?? stack[i].items.count // below the Liked music card
            stack[i].items.insert(entry, at: top)
        }
    }

    private func remove(where match: (SearchItem) -> Bool, from include: (Page) -> Bool) {
        for i in stack.indices where include(stack[i]) { stack[i].items.removeAll(where: match) }
    }

    /// The playing track as an item, for lists it should appear in.
    var currentTrackItem: SearchItem {
        SearchItem(id: videoId, section: "", title: title, subtitle: artist, thumbnail: artwork?.absoluteString,
                   explicit: isExplicit, videoId: videoId, artistId: currentArtistId.nonEmpty,
                   artistName: currentArtistName.nonEmpty, albumId: currentAlbumId.nonEmpty)
    }

    // MARK: Ratings

    /// Rates a song. `item` (the song as shown) lets a like appear in open Liked lists at once.
    func setRating(_ videoId: String, _ rating: Rating, item: SearchItem? = nil) {
        let message = [Rating.like: "Added to Liked songs", .dislike: "Disliked"][rating] ?? "Rating removed"
        Task {
            await perform(message) {
                let endpoint = [Rating.like: "like/like", .dislike: "like/dislike"][rating] ?? "like/removelike"
                try await callAPI(endpoint, ["target": ["videoId": videoId]])
                likeOverrides[videoId] = rating
                if videoId == self.videoId { likeStatus = rating }
                updateItems { if $0.videoId == videoId { $0.likeStatus = rating } }
                for i in queue.indices where queue[i].videoId == videoId { queue[i].likeStatus = rating }
                if rating == .like, var liked = item ?? (videoId == self.videoId ? currentTrackItem : nil) {
                    liked.style = nil
                    liked.likeStatus = .like
                    insert(liked, into: isLikedList)
                } else if rating != .like {
                    remove(where: { $0.videoId == videoId }, from: isLikedList)
                }
            }
        }
    }

    // MARK: Library

    /// Runs one of a "Save to library" toggle's endpoints.
    private func runLibraryEndpoint(_ endpoint: String) async throws {
        let result = try await bridge("runEndpoint", endpoint) as? String ?? "no result"
        guard result == "ok" else {
            Log.write("library endpoint \(result): \(endpoint.prefix(300))")
            throw ActionError.failed(result)
        }
    }

    /// Adds a song, album or playlist to your library, or removes it.
    func setInLibrary(_ item: SearchItem, _ add: Bool) {
        guard let endpoint = add ? item.libraryAdd : item.libraryRemove else { return }
        let key = item.videoId ?? item.playlistId ?? item.browseId
        Task {
            await perform(add ? "Added to library" : "Removed from library") {
                try await runLibraryEndpoint(endpoint)
                updateItems { if ($0.videoId ?? $0.playlistId ?? $0.browseId) == key { $0.inLibrary = add } }
                if let videoId = item.videoId, videoId == self.videoId { libraryOverrides[videoId] = add; currentInLibrary = add }
                if let tab = libraryTab(for: item) { showInLibrary(item, tab: tab, add) }
            }
        }
    }

    /// The album/playlist page's own Add button.
    func setPageInLibrary(_ page: Page, _ add: Bool) {
        guard let endpoint = add ? page.libraryAdd : page.libraryRemove else { return }
        Task {
            await perform(add ? "Added to library" : "Removed from library") {
                try await runLibraryEndpoint(endpoint)
                for i in stack.indices where stack[i].browseId == page.browseId { stack[i].inLibrary = add }
                let card = SearchItem(id: "", section: "", style: "card", title: page.title ?? "",
                                      subtitle: page.subtitle ?? "", thumbnail: page.thumbnail,
                                      playlistId: page.playlistId, browseId: page.browseId, pageType: page.pageType,
                                      inLibrary: add, libraryAdd: page.libraryAdd, libraryRemove: page.libraryRemove)
                if let tab = libraryTab(for: card) { showInLibrary(card, tab: tab, add) }
            }
        }
    }

    /// Adds an album/playlist card to (or takes it out of) its open library tab.
    private func showInLibrary(_ item: SearchItem, tab: LibraryTab, _ add: Bool) {
        var card = item
        card.inLibrary = add
        if add {
            insert(card, into: { $0.libraryTab == tab })
        } else {
            remove(where: { $0.browseId == item.browseId }, from: { $0.libraryTab == tab })
        }
    }

    /// The playing track, from the player's menu.
    func setCurrentInLibrary(_ add: Bool) {
        guard let endpoint = (add ? currentLibraryAdd : currentLibraryRemove).nonEmpty else { return }
        let videoId = self.videoId
        Task {
            await perform(add ? "Added to library" : "Removed from library") {
                try await runLibraryEndpoint(endpoint)
                libraryOverrides[videoId] = add
                currentInLibrary = add
                updateItems { if $0.videoId == videoId { $0.inLibrary = add } }
            }
        }
    }

    // MARK: Subscriptions

    /// Subscribes to an artist's channel, or unsubscribes.
    func setSubscribed(_ page: Page, _ subscribe: Bool) {
        guard let channelId = page.channelId else { return }
        Task {
            await perform(subscribe ? "Subscribed to \(page.title ?? "artist")" : "Unsubscribed") {
                try await callAPI(subscribe ? "subscription/subscribe" : "subscription/unsubscribe",
                                  ["channelIds": [channelId]])
                for i in stack.indices where stack[i].channelId == channelId { stack[i].subscribed = subscribe }
            }
        }
    }

    // MARK: Playlists

    /// Your playlists, for "Add to Playlist". The lookup needs some video id; any will do.
    func refreshOwnPlaylists() async {
        guard let anyVideo = videoId.nonEmpty ?? stack.lazy.flatMap(\.items).compactMap(\.videoId).first,
              let playlists = try? await bridge([PlaylistRef].self, "addTargets", anyVideo) else { return }
        ownPlaylists = playlists
    }

    func addToPlaylist(videoId: String, _ playlist: PlaylistRef) {
        Task {
            do {
                try await callAPI("browse/edit_playlist", [
                    "playlistId": playlist.id,
                    "actions": [["action": "ACTION_ADD_VIDEO", "addedVideoId": videoId, "dedupeOption": "DEDUPE_OPTION_CHECK"]],
                ])
                showToast("Added to \(playlist.title)")
                await refreshPages(browseId: "VL" + playlist.id)
            } catch ActionError.duplicate {
                showToast("Already in \(playlist.title)")
            } catch {
                Log.write("add to \(playlist.id) failed: \(Self.describe(error))")
                showToast("Couldn't add to \(playlist.title): \(Self.describe(error))")
            }
        }
    }

    /// Removes a song from one of your playlists (or unlikes it, on Liked songs).
    func removeFromPlaylist(_ item: SearchItem, on page: Page) {
        guard let videoId = item.videoId else { return }
        if page.isLikedSongs { setRating(videoId, .none); return }
        guard let playlistId = editableId(page), let setVideoId = item.setVideoId else { return }
        Task {
            await perform("Removed from \(page.title ?? "playlist")") {
                try await callAPI("browse/edit_playlist", [
                    "playlistId": playlistId,
                    "actions": [["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId, "removedVideoId": videoId]],
                ])
                for i in stack.indices where stack[i].browseId == page.browseId {
                    stack[i].items.removeAll { $0.id == item.id }
                }
            }
        }
    }

    // MARK: Removing several at once

    /// What "Select" can remove from `page`: your playlist's tracks, liked songs, or saved albums and
    /// playlists in the library. Empty when the page doesn't support it.
    func removableItems(on page: Page) -> [SearchItem] {
        if page.isOwnedPlaylist { return page.tracks }
        if page.isLikedSongs { return page.items.filter { $0.videoId != nil } }
        if [LibraryTab.songs, .albums, .playlists].contains(page.libraryTab) {
            return page.items.filter { $0.libraryRemove != nil }
        }
        return []
    }

    /// Removes `items` from `page`: one edit for a playlist, one request per item for likes and
    /// library saves. Items leave the page as each removal succeeds, so a failure part-way shows
    /// exactly what's left.
    func removeItems(_ items: [SearchItem], from page: Page) {
        guard !items.isEmpty else { return }
        func dropLocally(_ ids: Set<String>) {
            for i in stack.indices where stack[i].browseId == page.browseId && stack[i].libraryTab == page.libraryTab {
                stack[i].items.removeAll { ids.contains($0.id) }
            }
        }
        let count = items.count
        Task {
            await perform("Removed \(count) \(count == 1 ? "item" : "items")") {
                if page.isOwnedPlaylist {
                    guard let playlistId = editableId(page) else { return }
                    let actions: [[String: Any]] = items.compactMap { item in
                        guard let setVideoId = item.setVideoId, let videoId = item.videoId else { return nil }
                        return ["action": "ACTION_REMOVE_VIDEO", "setVideoId": setVideoId, "removedVideoId": videoId]
                    }
                    try await callAPI("browse/edit_playlist", ["playlistId": playlistId, "actions": actions])
                    dropLocally(Set(items.map(\.id)))
                } else if page.isLikedSongs {
                    for item in items {
                        guard let videoId = item.videoId else { continue }
                        try await callAPI("like/removelike", ["target": ["videoId": videoId]])
                        likeOverrides[videoId] = Rating.none
                        if videoId == self.videoId { likeStatus = .none }
                        dropLocally([item.id])
                    }
                    updateItems { item in
                        if items.contains(where: { $0.videoId == item.videoId }) { item.likeStatus = Rating.none }
                    }
                } else {
                    for item in items {
                        guard let endpoint = item.libraryRemove else { continue }
                        try await runLibraryEndpoint(endpoint)
                        dropLocally([item.id])
                    }
                }
            }
        }
    }

    /// Reorders a track of the playlist on top (indexes into its `tracks`). Applied locally at once,
    /// undone if the server refuses.
    func moveTrack(from source: IndexSet, to destination: Int) {
        guard let top = stack.indices.last, let from = source.first,
              let playlistId = editableId(stack[top]) else { return }
        var tracks = stack[top].tracks
        let moved = tracks[from]
        tracks.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = tracks.firstIndex(of: moved), let setVideoId = moved.setVideoId else { return }
        let successor = newIndex + 1 < tracks.count ? tracks[newIndex + 1].setVideoId : nil
        let before = stack[top].items
        let browseId = stack[top].browseId
        stack[top].items = tracks + before.filter { $0.setVideoId == nil }

        Task {
            var action: [String: Any] = ["action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": setVideoId]
            if let successor { action["movedSetVideoIdSuccessor"] = successor }
            do {
                try await callAPI("browse/edit_playlist", ["playlistId": playlistId, "actions": [action]])
            } catch {
                if let i = stack.lastIndex(where: { $0.browseId == browseId }) { stack[i].items = before }
                showToast("Couldn't move: \(Self.describe(error))")
            }
        }
    }

    /// Saves whichever of title, description and privacy changed.
    func savePlaylistDetails(_ page: Page, title: String, description: String, privacy: String) {
        guard let playlistId = editableId(page) else { return }
        var actions: [[String: Any]] = []
        if title != page.title { actions.append(["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": title]) }
        if description != (page.description ?? "") {
            actions.append(["action": "ACTION_SET_PLAYLIST_DESCRIPTION", "playlistDescription": description])
        }
        if privacy != page.privacy { actions.append(["action": "ACTION_SET_PLAYLIST_PRIVACY", "playlistPrivacy": privacy]) }
        guard !actions.isEmpty else { return }
        Task {
            await perform("Playlist saved") {
                try await callAPI("browse/edit_playlist", ["playlistId": playlistId, "actions": actions])
                for i in stack.indices where stack[i].browseId == page.browseId {
                    stack[i].title = title
                    stack[i].description = description
                    stack[i].privacy = privacy
                }
                updateItems { if $0.browseId == page.browseId { $0.title = title } } // its cards elsewhere
                await refreshOwnPlaylists()
            }
        }
    }

    func deletePlaylist(_ page: Page) {
        guard let playlistId = editableId(page) else { return }
        Task {
            await perform("Deleted \(page.title ?? "playlist")") {
                try await callAPI("playlist/delete", ["playlistId": playlistId])
                show(stack.filter { $0.browseId != page.browseId })
                for i in stack.indices { stack[i].items.removeAll { $0.browseId == page.browseId } }
                await refreshOwnPlaylists()
            }
        }
    }

    /// Creates a playlist, optionally starting with one song, and opens it on top of the library's
    /// Playlists tab (so Back lands there, with the new playlist listed).
    func createPlaylist(title: String, privacy: String, videoId: String?) {
        Task {
            await perform("Created \(title)") {
                var body: [String: Any] = ["title": title, "description": "", "privacyStatus": privacy]
                if let videoId { body["videoIds"] = [videoId] }
                guard let id = try await callAPI("playlist/create", body)["playlistId"] as? String else {
                    throw ActionError.failed("No playlist id")
                }
                let browseId = "VL" + id
                await refreshOwnPlaylists()
                await openLibrary(.playlists)
                insert(SearchItem(id: "", section: "", style: "card", title: title, subtitle: "Playlist",
                                  playlistId: id, browseId: browseId, pageType: PageType.playlist),
                       into: { $0.libraryTab == .playlists })
                await browse(id: browseId, pageType: PageType.playlist, title: title)
                // A brand-new playlist doesn't report that it's yours until it has songs, so mark it.
                if let top = stack.indices.last, stack[top].browseId == browseId {
                    stack[top].owned = true
                    stack[top].privacy = privacy
                }
            }
        }
    }
}
