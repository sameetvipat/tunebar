import SwiftUI

/// The pieces the card and Now Playing share: each one moves from its place in one to its place in
/// the other as the card grows into the page and back.
enum Hero: Hashable {
    case surface, artwork, title, artist, transport, progress
    case rating, volume, queue, more, lyrics
}

/// The player along the bottom of the popover: the card, Up Next rising out of it, and Now Playing,
/// which the card grows into. Card and page share their pieces (background, artwork, titles,
/// controls), so opening one carries each piece to its new place instead of sliding a new page in.
struct PlayerSurface: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    @Namespace private var hero

    var body: some View {
        ZStack(alignment: .bottom) {
            // The one arriving appears at once, its pieces starting where the other's are; the one
            // leaving fades as its pieces travel. So every piece moves as one, and nothing pops.
            if ui.showingNowPlaying {
                NowPlayingView(player: player, ui: ui, hero: hero)
                    .zIndex(Double(ui.surfaceOrder))
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            } else {
                VStack(spacing: 8) {
                    // Up Next or the lyrics, rising out of the card.
                    if let panel = ui.cardPanel {
                        Group {
                            switch panel {
                            case .queue: QueueView(player: player, ui: ui)
                            case .lyrics: LyricsPanel(player: player, ui: ui)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.horizontal, 10)
                        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                    }
                    PlayerCard(player: player, ui: ui, hero: hero)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { ui.cardHeight = $0 }
                }
                .zIndex(Double(ui.surfaceOrder))
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = player.toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(in: Capsule())
                    .padding(.bottom, ui.showingNowPlaying ? 64 : ui.cardHeight + (ui.cardPanel != nil ? 356 : 8))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        // A video coming on closes the lyrics, which aren't offered for it.
        .onChange(of: player.isPlayingVideo) { _, video in
            guard video else { return }
            withAnimation(.move) {
                if ui.cardPanel == .lyrics { ui.cardPanel = nil }
                if ui.nowPlayingPanel == .lyrics { ui.nowPlayingPanel = nil }
            }
        }
        .animation(.move, value: ui.cardPanel)
        .animation(.quick, value: player.toast)
        // A new track's artwork, titles and badges fade in rather than jump.
        .animation(.quick, value: player.videoId)
        .animation(.quick, value: player.title)
        .animation(.quick, value: player.isAd)
    }
}
