import SwiftUI

/// Up Next: your queue, then (with Autoplay on) YouTube Music's autoplay mix. Click a song to jump
/// to it; right-click to remove it. Clear empties your queue; Autoplay decides whether playback
/// carries on after it or stops at the end of the current song.
struct QueueView: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        // With Autoplay off, the page keeps its autoplay list but won't play it, so don't show it.
        let entries = player.autoplay ? player.queue : player.queue.filter { !$0.autoplay }
        let canClear = player.queue.contains { !$0.autoplay && !$0.selected }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text("Up Next").font(.headline)
                        Spacer()
                        Toggle("Autoplay", isOn: Binding(get: { player.autoplay }, set: player.setAutoplay))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Keep playing similar songs after your queue ends")
                        if canClear {
                            Button { player.clearQueue() } label: { Label("Clear", systemImage: "xmark") }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.capsule)
                                .help("Remove your queue except the current song")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    if entries.isEmpty {
                        Text("Nothing queued. Play something to start a queue.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    let firstAutoplay = entries.first(where: \.autoplay)?.index
                    ForEach(entries) { item in
                        if item.index == firstAutoplay {
                            Text("Autoplay")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 6)
                        }
                        QueueRow(item: item, isPlaying: !player.isPaused, player: player, ui: ui)
                            .id(item.index)
                            .contextMenu {
                                if !item.selected {
                                    Button(role: .destructive) { player.removeFromQueue(item) } label: {
                                        Label("Remove from Queue", systemImage: "minus.circle")
                                    }
                                }
                            }
                    }
                }
                .padding(.bottom, 8)
            }
            .onScrollGeometryChange(for: Bool.self, of: PageView.isScrolled) { ui.contentScrolled = $1 }
            .onDisappear { player.queue = [] } // reloaded whenever Up Next opens
            .task(id: player.videoId) {
                // Load now and again once the page has caught up with a track change.
                for delay in [0, 800, 2500] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard !Task.isCancelled else { return }
                    await player.loadQueue()
                    if delay < 2500, let current = player.queue.first(where: \.selected) {
                        proxy.scrollTo(current.index, anchor: .center)
                    }
                }
            }
        }
    }
}

/// One queue entry; the playing one shows an animated waveform over its artwork. A tap gesture
/// rather than a Button, so its rating buttons get their own clicks.
private struct QueueRow: View {
    let item: QueueItem
    let isPlaying: Bool
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    private var hoverID: String { "queue|\(item.index)" }
    private var hovered: Bool { ui.hoveredID == hoverID }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Artwork(url: item.thumbnail, size: 40)
                if item.selected {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 6))
                    Image(systemName: "waveform")
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).fontWeight(item.selected ? .semibold : .regular).lineLimit(1)
                HStack(spacing: 4) {
                    if item.explicit { ExplicitBadge() }
                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            RatingButtons(rating: item.likeStatus ?? .none, hovered: hovered) {
                player.setRating(item.videoId, $0, item: item.asItem)
            }
            Text(item.length).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(item.selected ? Color.primary.opacity(0.08) : hovered ? Color.primary.opacity(0.05) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { player.playQueueItem(item) }
        .padding(.horizontal, 6)
        .onHover { inside in
            if inside { ui.hoveredID = hoverID } else if ui.hoveredID == hoverID { ui.hoveredID = nil }
        }
    }
}
