import Foundation

/// Up Next. The queue lives only in the hidden page; these read and change it through the bridge.
extension Player {
    func loadQueue() async {
        guard var items = try? await bridge([QueueItem].self, "queue") else { return }
        for i in items.indices { // ratings changed here, which the page's queue doesn't know about
            if let rating = likeOverrides[items[i].videoId] { items[i].likeStatus = rating }
        }
        queue = items
    }

    func playQueueItem(_ item: QueueItem) {
        Task {
            do {
                try await bridge("queuePlay", item.videoId, item.occurrence)
            } catch {
                Log.write("queuePlay failed: \(Self.describe(error))")
                showToast("Couldn't play that: \(Self.describe(error))")
                return
            }
            try? await Task.sleep(for: .milliseconds(600)) // let the page mark the new track
            await loadQueue()
        }
    }

    func removeFromQueue(_ item: QueueItem) {
        Task {
            do {
                try await bridge("queueRemove", item.autoplay, item.storeIndex)
            } catch {
                Log.write("queueRemove failed: \(Self.describe(error))")
                showToast("Couldn't remove that: \(Self.describe(error))")
            }
            await loadQueue()
        }
    }

    /// Moves one of your queued songs to where another one is (both from your queue, not autoplay).
    func moveQueueItem(_ item: QueueItem, to target: QueueItem) {
        guard !item.autoplay, !target.autoplay, item.storeIndex != target.storeIndex else { return }
        Task {
            _ = try? await bridge("queueMove", item.storeIndex, target.storeIndex)
            await loadQueue()
        }
    }

    /// Removes your queue except the playing track. What follows it is up to autoplay.
    func clearQueue() {
        Task {
            let cleared = try? await bridge("queueClear")
            showToast((cleared as? Bool) == true ? "Queue cleared" : "Nothing to clear")
            await loadQueue()
        }
    }

    func setAutoplay(_ on: Bool) {
        autoplay = on // reflect the switch at once; the page's next report confirms it
        Task {
            _ = try? await bridge("setAutoplay", on)
            try? await Task.sleep(for: .milliseconds(800)) // the page fetches or drops the autoplay mix
            await loadQueue()
        }
    }

    /// Play Next / Add to Queue for a song (`videoId`) or a whole album/playlist (`playlistId`).
    /// With nothing playing there's no queue to add to, so it just plays.
    func enqueue(videoId: String?, playlistId: String?, playNext: Bool) {
        Task {
            let added: Bool
            do {
                added = try await bridge("enqueue", videoId ?? "", playlistId ?? "", playNext) as? Bool == true
            } catch {
                Log.write("enqueue failed: \(Self.describe(error))")
                added = false
            }
            guard added else {
                // Only start it when there's nothing to interrupt.
                if self.videoId.isEmpty { play(videoId: videoId, playlistId: playlistId) }
                else { showToast("Couldn't add to the queue") }
                return
            }
            showToast(playNext ? "Playing next" : "Added to queue")
            await loadQueue()
        }
    }
}
