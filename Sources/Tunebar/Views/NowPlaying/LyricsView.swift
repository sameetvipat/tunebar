import SwiftUI

/// The lyrics, or why there are none, for Now Playing and the panel above the card.
struct LyricsPanel: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        if let lyrics = player.lyrics {
            LyricsView(player: player, lyrics: lyrics, clock: player.clock, ui: ui)
        } else {
            VStack(spacing: 8) {
                if player.lyricsLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "quote.bubble").font(.title2)
                    Text("No lyrics for this song")
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The playing song's lyrics. Synced lyrics follow along: the line being sung is highlighted and
/// kept in the middle, and clicking a line jumps there. Scrolling yourself stops the following; an
/// arrow then points the way to the current line once it's off screen, and brings it back.
/// Plain lyrics just scroll.
private struct LyricsView: View {
    let player: Player
    let lyrics: Lyrics
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var ui: UIState

    var body: some View {
        // A little early, so the highlight lands as the line starts rather than just after.
        let current = lyrics.lineIndex(at: clock.time + 0.3)
        let direction = arrow(to: current)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if lyrics.isSynced {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            let active = index == current
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(active ? .primary : .secondary)
                                .opacity(active ? 1 : 0.5)
                                .scaleEffect(active ? 1 : 0.96, anchor: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { if !player.isAd { player.seek(to: line.time) } }
                                .pointerStyle(.link)
                                .id(index)
                        }
                    } else {
                        Text(lyrics.text ?? "")
                            .font(.body)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let source = lyrics.source {
                        Text(source).font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
                    }
                }
                .scrollTargetLayout()
                .padding(16)
                .animation(.quick, value: current)
            }
            .scrollIndicators(.never)
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ui.lyricsVisible = $0 }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .tracking { ui.lyricsFollow = false }
            }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: current) {
                guard let current, ui.lyricsFollow else { return }
                withAnimation(.move) { proxy.scrollTo(current, anchor: .center) }
            }
            .overlay(alignment: direction == .up ? .top : .bottom) {
                if let direction {
                    Button {
                        ui.lyricsFollow = true
                        if let current { withAnimation(.move) { proxy.scrollTo(current, anchor: .center) } }
                    } label: {
                        Image(systemName: direction == .up ? "chevron.up" : "chevron.down")
                            .font(.callout.weight(.semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Back to the current line")
                    .padding(10)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(.quick, value: direction)
        }
    }
}

private enum LyricsArrow { case up, down }

extension LyricsView {
    /// Which way the current line is, once you've scrolled it off screen; nil while it's in view
    /// or the lyrics are following it.
    fileprivate func arrow(to current: Int?) -> LyricsArrow? {
        guard lyrics.isSynced, !ui.lyricsFollow, let current,
              let first = ui.lyricsVisible.min(), let last = ui.lyricsVisible.max() else { return nil }
        if current < first { return .up }
        if current > last { return .down }
        return nil
    }
}
