import SwiftUI

/// The glass card at the bottom: the playing track, its actions, transport and progress.
/// Buttons are plain glyphs without backgrounds, like Apple Music's player.
struct PlayerCard: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    let hero: Namespace.ID

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // The artwork opens Now Playing; the corner arrow says so.
                Button {
                    ui.nowPlayingPanel = nil // the artwork, not whatever panel was open last
                    expand()
                } label: {
                    HeroArtwork(image: player.artworkImage, cornerRadius: 6)
                        .matchedGeometryEffect(id: Hero.artwork, in: hero)
                        .frame(width: 42, height: 42)
                        .overlay(alignment: .bottomTrailing) {
                            ExpandBadge().opacity(ui.cardRevealed ? 1 : 0).offset(x: 3, y: 3)
                        }
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(player.videoId.isEmpty)
                .help("Open Now Playing")

                VStack(alignment: .leading, spacing: 1) {
                    AlbumLink(player: player) {
                        Text(player.title.isEmpty ? "Not playing" : player.title).fontWeight(.semibold).lineLimit(1)
                    }
                    .matchedGeometryEffect(id: Hero.title, in: hero, properties: .position)
                    Button(action: player.openCurrentArtist) {
                        HStack(spacing: 4) {
                            if player.isAd { AdBadge() }
                            if player.isExplicit { ExplicitBadge() }
                            Text(player.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .disabled(player.currentArtistId.isEmpty || player.isAd)
                    .help("Go to artist")
                    .matchedGeometryEffect(id: Hero.artist, in: hero, properties: .position)
                }
                .opacity(ui.cardRevealed ? 1 : 0)
                Spacer(minLength: 4)
                trackActions
                    .opacity(ui.cardRevealed ? 1 : 0)
            }
            HStack(spacing: 10) {
                transport
                    .matchedGeometryEffect(id: Hero.transport, in: hero, properties: .position)
                HStack(spacing: 10) {
                    ProgressRow(player: player, clock: player.clock, ui: ui, isAd: player.isAd, canSkipAd: player.canSkipAd)
                }
                .matchedGeometryEffect(id: Hero.progress, in: hero)
                // Lyrics open above the card, like Up Next; greyed out when the song has none.
                Button {
                    ui.lyricsFollow = true
                    ui.cardPanel = ui.cardPanel == .lyrics ? nil : .lyrics // animated by PlayerSurface
                } label: {
                    Image(systemName: ui.cardPanel == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                        .font(.body) // the same size as the card's other buttons, not the row's small text
                        .imageScale(.large)
                        .frame(width: 22)
                        .foregroundStyle(ui.cardPanel == .lyrics ? Color.accentColor : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .matchedGeometryEffect(id: Hero.lyrics, in: hero, properties: .position)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.primary)
                .disabled(player.lyrics == nil || player.isAd || player.isPlayingVideo)
                .help(player.isPlayingVideo ? "Lyrics aren't shown for videos"
                      : player.lyrics != nil ? "Lyrics" : player.lyricsLoading ? "Looking for lyrics…" : "No lyrics for this song")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .opacity(ui.cardRevealed ? 1 : 0)
        }
        .padding(12)
        .background {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .matchedGeometryEffect(id: Hero.surface, in: hero)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .onAppear { withAnimation(.move.delay(0.05)) { ui.cardRevealed = true } }
    }

    private func expand() {
        ui.cardPanel = nil
        ui.showingNowPlaying = true // animated by ContentView
    }

    /// Like, dislike, volume, Up Next and the "…" menu for the playing track.
    private var trackActions: some View {
        HStack(spacing: 6) {
            RatingToggles(player: player)
                .disabled(player.videoId.isEmpty)
                .matchedGeometryEffect(id: Hero.rating, in: hero, properties: .position)

            Button { ui.showingVolume.toggle() } label: {
                Image(systemName: VolumeControl.symbol(player.isMuted ? 0 : player.volume))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22) // the speaker's waves change its width
            }
            .help("Volume")
            .popover(isPresented: $ui.showingVolume, arrowEdge: .top) { VolumeControl(player: player) }
            .matchedGeometryEffect(id: Hero.volume, in: hero, properties: .position)

            Button { ui.showingQueue.toggle() } label: { // animated by PlayerSurface
                Image(systemName: "list.bullet")
                    .foregroundStyle(ui.showingQueue ? Color.accentColor : Color.primary)
            }
            .help(ui.showingQueue ? "Hide Up Next" : "Up Next")
            .matchedGeometryEffect(id: Hero.queue, in: hero, properties: .position)

            CurrentTrackMenu(player: player, ui: ui) { Image(systemName: "ellipsis") }
                .disabled(player.videoId.isEmpty)
                .matchedGeometryEffect(id: Hero.more, in: hero, properties: .position)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .foregroundStyle(.primary)
    }

    /// Previous, play/pause, next. Each bounces when pressed; play/pause morphs between its symbols.
    private var transport: some View {
        HStack(spacing: 14) {
            Button {
                ui.previousTaps += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill").symbolEffect(.bounce, value: ui.previousTaps)
            }
            .help("Previous")
            .disabled(player.isAd)

            Button {
                ui.playTaps += 1
                player.togglePlay()
            } label: {
                Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                    .font(.title)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, value: ui.playTaps)
                    .frame(width: 26, height: 26)
            }
            .help(player.isPaused ? "Play" : "Pause")

            Button {
                ui.nextTaps += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill").symbolEffect(.bounce, value: ui.nextTaps)
            }
            .help("Next")
            .disabled(player.isAd)
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .foregroundStyle(.primary)
        .animation(.quick, value: player.isPaused)
    }
}

/// The small arrow on the card's artwork: click to open Now Playing.
private struct ExpandBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(.black.opacity(0.55)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
}
