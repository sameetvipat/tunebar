import AppKit
import WebKit

/// Smoke test for everything that depends on YouTube Music's internals: response shapes, the in-page
/// router, the queue store and the player. Run after a YouTube Music update to see what broke:
///
///     TUNEBAR_SELFTEST=1 ./Tunebar.app/Contents/MacOS/Tunebar
///
/// Signed out, muted, with a throwaway data store, so it never touches your account or settings.
/// Prints one line per check and exits non-zero if any failed.
@MainActor
final class SelfTest: NSObject, NSApplicationDelegate {
    private var player: Player!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mute = """
            const play = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function() { this.muted = true; return play.apply(this, arguments); };
            """
        player = Player(dataStore: .nonPersistent(), extraScripts: [mute])
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = player.webView
        window.parkInvisibly()
        Task {
            let failures = await run()
            report(failures == 0 ? "PASS" : "FAIL (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }

    // MARK: Helpers

    private var failures = 0

    private func report(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private func check(_ ok: Bool, _ label: String) {
        report((ok ? "ok    " : "FAIL  ") + label)
        if !ok { failures += 1 }
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func waitUntil(_ timeout: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await wait(0.5)
        }
        return false
    }

    // MARK: Checks

    private func run() async -> Int {
        check(await player.waitUntilReady(), "page loaded")

        await player.loadHome()
        let home = player.current?.items ?? []
        check(player.current?.isHome == true && !home.isEmpty, "home feed: \(Set(home.map(\.section)).count) sections")

        await player.search("balthazar")
        let results = player.current?.items ?? []
        check(results.contains { $0.section == "Songs" }, "search: \(results.count) results")
        check(results.contains { $0.videoId != nil && $0.artistId != nil && $0.segments?.contains(where: \.isLink) == true },
              "artist links in rows")
        checkShareLinks(results)
        if let page = player.current {
            await checkSearchViewAll(page)
        }
        await checkPages(results)

        guard let song = results.first(where: { $0.videoId != nil }), let songId = song.videoId else {
            check(false, "a song to play")
            return failures
        }
        await checkPlayback(song: song, songId: songId, results: results)
        await checkQueue(songId: songId, results: results)
        await checkMix(results)

        let before = player.title
        player.next()
        check(await waitUntil(5) { player.title != before }, "next ('\(player.title)')")
        return failures
    }

    private func checkShareLinks(_ results: [SearchItem]) {
        let song = results.first { $0.videoId != nil }?.shareURL?.absoluteString ?? ""
        let album = results.first { $0.pageType == PageType.album }?.shareURL?.absoluteString ?? ""
        let artist = results.first(where: \.isArtist)?.shareURL?.absoluteString ?? ""
        check(song.contains("/watch?v=") && album.contains("/playlist?list=") && artist.contains("/channel/UC"),
              "share links (\(song), \(album), \(artist))")
    }

    private func checkSearchViewAll(_ page: Page) async {
        let kinds = (page.filters ?? [:]).keys.sorted().joined(separator: ", ")
        await player.viewAll("Songs", of: page)
        let songs = player.current?.filterName == "Songs" ? player.current?.items ?? [] : []
        check(songs.count > 20 && songs.allSatisfy { $0.videoId != nil }, "view all songs: \(songs.count) (filters: \(kinds))")
        if player.current?.filterName != nil { player.goBack() }
    }

    private func checkPages(_ results: [SearchItem]) async {
        if let artist = results.first(where: \.isArtist) {
            await player.browse(artist)
            let page = player.current
            check(page?.items.contains { $0.videoId != nil } == true, "artist page: \(page?.items.count ?? 0) items")
            // Not every artist's Albums shelf has a "See all" page; use whichever shelf does.
            let links = (page?.more ?? [:]).keys.sorted()
            if let page, let shelf = links.first(where: { $0.contains("Album") }) ?? links.first(where: { $0 != "Top songs" }) {
                let shown = page.items.filter { $0.section == shelf }.count
                await player.viewAll(shelf, of: page)
                let all = player.current?.filterName == shelf ? player.current?.items.count ?? 0 : 0
                check(all >= shown && all > 0, "artist view all \(shelf): \(all) (page showed \(shown))")
                if player.current?.filterName != nil { player.goBack() }
            } else {
                check(false, "artist view all links (found: \(links))")
            }
            player.goBack()
        }
        if let playlist = results.first(where: { $0.pageType == PageType.playlist }) {
            await player.browse(playlist)
            check(player.current?.ownerId != nil, "playlist creator link (\(player.current?.ownerName ?? "-"))")
            player.goBack()
        }
        if let album = results.first(where: { $0.pageType == PageType.album }) {
            await player.browse(album)
            let page = player.current
            check(page?.playlistId != nil && page?.items.first?.videoId != nil, "album page: \(page?.items.count ?? 0) items")
            check(await waitUntil(8) { player.current?.released != nil },
                  "album release date and label (\(player.current?.released ?? "-"), \(player.current?.label ?? "-"))")
            // Playing a whole album is a list-only request; it must start in the page, not by reloading it.
            if let list = page?.playlistId {
                let started = try? await player.bridge("play", "", list, "")
                check(started as? Bool == true, "album plays in-page")
            }
            player.goBack()
        }
    }

    private func checkPlayback(song: SearchItem, songId: String, results: [SearchItem]) async {
        // Picking a second song right away must not bounce back to the first.
        if let other = results.first(where: { $0.videoId != nil && $0.videoId != songId }) {
            player.select(other)
            await wait(0.3)
            player.select(song)
            await wait(5)
            check(player.videoId == songId, "latest play wins")
        }
        await player.loadQueue()
        check(player.queue.first(where: \.selected)?.videoId == player.videoId, "queue marks the playing song")

        let started = Date()
        let navigated = try? await player.bridge("play", songId, "", "")
        check(navigated as? Bool == true, String(format: "in-page navigation (%.2fs)", Date().timeIntervalSince(started)))

        // Signed-out sessions may get an ad first; wait for the real track.
        let clock = player.clock
        check(await waitUntil(45) { player.title == song.title && clock.duration > 30 && clock.time > 1 },
              "playing '\(player.title)'")
        player.togglePlay()
        check(await waitUntil(3) { player.isPaused }, "pause")
        player.togglePlay()
        check(await waitUntil(3) { !player.isPaused }, "resume")
        player.seek(to: 60)
        await wait(1.5)
        check(clock.time > 59, "seek")
        player.setVolume(30)
        check(await waitUntil(3) { abs(player.volume - 30) < 1 && !player.isMuted }, "volume")
        player.toggleMute()
        check(await waitUntil(3) { player.isMuted }, "mute")
        player.toggleMute()
        check(await waitUntil(3) { !player.isMuted }, "unmute")
        player.setVolume(100)
        check(await waitUntil(5) { !player.currentArtistId.isEmpty && player.hasCurrentAlbum },
              "track links (artist \(player.currentArtistName))")
    }

    private func checkQueue(songId: String, results: [SearchItem]) async {
        let others = results.compactMap(\.videoId).filter { $0 != songId }
        if others.count >= 2 {
            player.enqueue(videoId: others[0], playlistId: nil, playNext: true)
            player.enqueue(videoId: others[1], playlistId: nil, playNext: false)
            await wait(2)
            await player.loadQueue()
            let current = player.queue.firstIndex(where: \.selected) ?? -1
            let nextUp = current >= 0 && current + 1 < player.queue.count ? player.queue[current + 1].videoId : ""
            check(nextUp == others[0], "play next (queue has \(player.queue.count))")
            check((player.queue.firstIndex { $0.videoId == others[1] } ?? -1) > current + 1, "add to queue")
            if let target = player.queue.first(where: { $0.videoId == others[0] }) {
                player.playQueueItem(target)
                check(await waitUntil(5) { player.videoId == others[0] }, "jump to queue item")
            }
        }

        await player.loadQueue()
        let queued = player.queue.filter { !$0.autoplay }.count
        if let removable = player.queue.last(where: { !$0.selected && !$0.autoplay }) {
            player.removeFromQueue(removable)
            await wait(1)
            check(player.queue.filter { !$0.autoplay }.count == queued - 1, "remove from queue")
        }
        player.clearQueue()
        await wait(1.5)
        let mine = player.queue.filter { !$0.autoplay }
        check(mine.count == 1 && mine.first?.selected == true, "clear queue (left \(mine.count) of yours)")

        player.setAutoplay(false)
        check(await waitUntil(5) { !player.autoplay }, "autoplay off")
        player.setAutoplay(true)
        check(await waitUntil(5) { player.autoplay }, "autoplay on")
    }

    /// A mix should stay on the song itself, not hop to its music video and back.
    private func checkMix(_ results: [SearchItem]) async {
        guard let song = results.first(where: { $0.videoId != nil && $0.mixEndpoint != nil }), let id = song.videoId else { return }
        player.startMix(videoId: id, endpoint: song.mixEndpoint)
        var seen: [String] = []
        for _ in 0..<12 {
            await wait(0.5)
            if seen.last != player.videoId { seen.append(player.videoId) }
        }
        let steady = seen.last == id && !seen.dropFirst().dropLast().contains { $0 != id }
        check(steady && player.currentListId.hasPrefix("RD"), "mix stays on the song (\(seen))")
    }
}
