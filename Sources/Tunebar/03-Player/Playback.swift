import Foundation

/// Playing things, transport controls, mixes, and opening the playing track's artist/album/playlist.
extension Player {
    /// What tapping an item does: open its page, or play it.
    func select(_ item: SearchItem) {
        errorMessage = nil
        if item.isBrowsable {
            Task { await browse(item) }
            return
        }
        if let videoId = item.videoId {
            if knownLinks.count > 200 { knownLinks.removeAll() } // only the latest few matter
            knownLinks[videoId] = TrackLinks(artistId: item.artistId, artistName: item.artistName,
                                             albumId: item.albumId, mixEndpoint: item.mixEndpoint)
        }
        play(videoId: item.videoId, playlistId: item.playlistId,
             endpoint: item.videoId != nil ? item.playEndpoint : nil)
    }

    /// Plays a track and/or list in the page without reloading it.
    ///
    /// `endpoint` is the item's own request from the web app (JSON); when given, its ids win.
    /// Only if the in-page start fails does the page reload at the track's address. A newer request,
    /// or the track turning out to be playing after all, cancels that fallback, so a slow first start
    /// isn't restarted and a quick second pick doesn't bounce back to the first.
    func play(videoId: String?, playlistId: String?, endpoint: String? = nil) {
        var videoId = videoId, playlistId = playlistId
        if let endpoint, let ids = Self.ids(inEndpoint: endpoint) { (videoId, playlistId) = ids }
        guard videoId != nil || playlistId != nil else { return }
        playRequest += 1
        let request = playRequest
        Task {
            _ = await waitUntilReady() // pressed while the page is still starting up
            guard request == playRequest else { return }
            let started = try? await bridge("play", videoId ?? "", playlistId ?? "", endpoint ?? "")
            guard (started as? Bool) != true, request == playRequest else { return }
            if let videoId, self.videoId == videoId { return }

            Log.write("play: in-page start failed; reloading for v=\(videoId ?? "-") list=\(playlistId ?? "-")")
            var address = URLComponents(string: "https://music.youtube.com/watch")!
            address.queryItems = [("v", videoId), ("list", playlistId)].compactMap { name, value in
                value.map { URLQueryItem(name: name, value: $0) }
            }
            webView.load(URLRequest(url: address.url!))
        }
    }

    /// Plays an album or playlist without opening it. Cards that carry no playable list (some home
    /// shelves) are looked up first.
    func playCollection(_ item: SearchItem) {
        if let playlistId = item.playlistId {
            play(videoId: nil, playlistId: playlistId)
        } else if let browseId = item.browseId {
            Task {
                guard let page = try? await bridge(Page.self, "browse", browseId),
                      let playlistId = page.playlistId else { return }
                play(videoId: nil, playlistId: playlistId)
            }
        }
    }

    private static func ids(inEndpoint json: String) -> (String?, String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let watch = (object["watchEndpoint"] ?? object["watchPlaylistEndpoint"]) as? [String: Any]
        else { return nil }
        return (watch["videoId"] as? String, watch["playlistId"] as? String)
    }

    // MARK: Transport

    func togglePlay() { control("toggle") }
    func next() { control("next") }
    func previous() { control("previous") }

    func seek(to seconds: Double) {
        clock.time = seconds
        control("seek", seconds)
    }

    func setVolume(_ level: Double) {
        volume = level
        if level > 0 { isMuted = false }
        control("volume", level.rounded())
    }

    func toggleMute() {
        isMuted.toggle()
        control("mute", isMuted ? 1 : 0)
    }

    private func control(_ command: String, _ value: Double = 0) {
        Task {
            do {
                try await bridge("control", command, value)
            } catch {
                Log.write("control \(command) failed: \(Self.describe(error))")
            }
        }
    }

    // MARK: Mixes

    /// Starts a mix (YouTube Music's endless radio) from a song, preferring the item's own "Start mix"
    /// request. The fallback mirrors it: params "wAEB" marks a mix.
    func startMix(videoId: String, endpoint: String? = nil) {
        let fallback = #"{"watchEndpoint":{"videoId":"\#(videoId)","playlistId":"RDAMVM\#(videoId)","params":"wAEB"}}"#
        play(videoId: videoId, playlistId: nil, endpoint: endpoint.nonEmpty ?? fallback)
        showToast("Starting mix")
    }

    /// Starts a mix from an album or playlist.
    func startMix(playlistId: String, endpoint: String? = nil) {
        let mixId = playlistId.hasPrefix("RD") ? playlistId : "RDAMPL" + playlistId
        let fallback = #"{"watchPlaylistEndpoint":{"playlistId":"\#(mixId)","params":"wAEB"}}"#
        play(videoId: nil, playlistId: mixId, endpoint: endpoint.nonEmpty ?? fallback)
        showToast("Starting mix")
    }

    // MARK: The playing track's pages

    var hasCurrentAlbum: Bool { !currentAlbumId.isEmpty }

    /// Playing from a real playlist: not a mix ("RD…") and not an album's own list ("OLAK…").
    var hasCurrentPlaylist: Bool {
        !currentListId.isEmpty && !currentListId.hasPrefix("RD") && !currentListId.hasPrefix("OLAK")
    }

    func openCurrentArtist() {
        guard !currentArtistId.isEmpty else { return }
        open(id: currentArtistId, pageType: PageType.artist, title: currentArtistName)
    }

    func openCurrentAlbum() {
        guard hasCurrentAlbum else { return }
        let artwork = artwork?.absoluteString
        Task { await browse(id: currentAlbumId, pageType: PageType.album, title: "Album", thumbnail: artwork) }
    }

    func openCurrentPlaylist() {
        guard hasCurrentPlaylist else { return }
        open(id: "VL" + currentListId, pageType: PageType.playlist, title: "Playlist")
    }

    /// What the artwork opens: the playlist it plays from, else its album.
    func openCurrentCollection() {
        if hasCurrentPlaylist { openCurrentPlaylist() } else { openCurrentAlbum() }
    }
}
