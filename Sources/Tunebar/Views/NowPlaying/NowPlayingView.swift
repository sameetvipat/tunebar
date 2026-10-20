import SwiftUI

/// The full Now Playing page: big artwork (or the video), links, progress, transport, rating, volume
/// and actions. The card grows into it (see PlayerSurface); ⌄, Escape or opening any page shrinks it
/// back. Up Next and the lyrics open inside it, the artwork shrinking into a compact header.
struct NowPlayingView: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    let hero: Namespace.ID

    var body: some View {
        VStack(spacing: 14) {
            header
                .opacity(revealed)
            tabs
                .opacity(revealed)
            if let panel = ui.nowPlayingPanel {
                compactTrack
                panelContent(panel)
                    .opacity(revealed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
                stage
                titles
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ProgressRow(player: player, clock: player.clock, ui: ui, isAd: player.isAd, canSkipAd: player.canSkipAd)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .opacity(revealed)
            .matchedGeometryEffect(id: Hero.progress, in: hero)
            // The progress, transport and controls stay pinned to the bottom whatever is shown above.
            transport
                .opacity(revealed)
                .disabled(player.videoId.isEmpty)
                .matchedGeometryEffect(id: Hero.transport, in: hero, properties: .position)
            controls
                .opacity(revealed)
                .disabled(player.videoId.isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { surface }
        .animation(.quick, value: player.lyrics)
        .animation(.quick, value: player.hasVideo)
        .onAppear { withAnimation(.move.delay(0.05)) { ui.nowPlayingRevealed = true } }
        .onDisappear { ui.nowPlayingRevealed = false }
    }

    /// The text and controls, which fade in as the card's fade out (see UIState).
    private var revealed: Double { ui.nowPlayingRevealed ? 1 : 0 }

    /// Laid out like the top bar it replaces: ⌄ where Back was, ⋯ where Search was, and the same
    /// height, so the brand (drawn once by ContentView, above both) sits in the middle of either.
    private var header: some View {
        HStack {
            Button { ui.showingNowPlaying = false } label: { // animated by ContentView
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .help("Collapse (Esc)")
            Spacer()
            CurrentTrackMenu(player: player, ui: ui) {
                Image(systemName: "ellipsis").font(.title3).frame(width: 36, height: 36)
            }
            .matchedGeometryEffect(id: Hero.more, in: hero, properties: .position)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .frame(height: TopBar.height - 16)
        .padding(.vertical, 8)
        .padding(.horizontal, 10 - 22) // the top bar's edge inset, not the page's
    }

    /// Showing the video: picked, and the track has one.
    private var showingVideo: Bool { ui.nowPlayingVideo && player.hasVideo }

    /// No lyrics for a video, or on the Video tab (before the switch to the music video lands).
    private var lyricsOff: Bool { player.isPlayingVideo || showingVideo }

    /// Song or Video, as a glass capsule whose highlight slides between them. Video shows the playing
    /// video in place of the artwork and, for tracks that have both versions, switches to the music
    /// video (and Song back to the song). Off for songs that are only a still of their cover.
    private var tabs: some View {
        HStack(spacing: 2) {
            tab("Song", video: false)
            tab("Video", video: true)
                .disabled(!player.hasVideo)
                .help(player.hasVideo ? "Video" : "This song has no video")
        }
        .padding(3)
        .glassEffect(.regular, in: Capsule())
        .disabled(player.isAd || player.videoId.isEmpty)
    }

    private func tab(_ title: String, video: Bool) -> some View {
        let selected = showingVideo == video
        return Button {
            withAnimation(.move) {
                ui.nowPlayingVideo = video
                ui.nowPlayingPanel = nil // show what was picked
            }
            if player.hasVideoVersion && player.playingVideoVersion != video { player.setVideoVersion(video) }
        } label: {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        Capsule().fill(Color.primary.opacity(0.14)).matchedGeometryEffect(id: "tab", in: hero)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// The artwork, or the video on the Video tab.
    @ViewBuilder private var stage: some View {
        if showingVideo {
            VideoSurface(player: player, feed: player.videoFeed)
                .matchedGeometryEffect(id: Hero.artwork, in: hero)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        } else {
            HeroArtwork(image: player.artworkImage, cornerRadius: 10)
                .matchedGeometryEffect(id: Hero.artwork, in: hero)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }

    private var titles: some View {
        VStack(spacing: 3) {
            AlbumLink(player: player) {
                Text(player.title.isEmpty ? "Not playing" : player.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .matchedGeometryEffect(id: Hero.title, in: hero, properties: .position)
            artistLine
                .matchedGeometryEffect(id: Hero.artist, in: hero, properties: .position)
        }
        .opacity(revealed)
    }

    /// The artwork and titles in a row, above Up Next or the lyrics.
    private var compactTrack: some View {
        HStack(spacing: 12) {
            HeroArtwork(image: player.artworkImage)
                .matchedGeometryEffect(id: Hero.artwork, in: hero)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                AlbumLink(player: player) {
                    Text(player.title.isEmpty ? "Not playing" : player.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .matchedGeometryEffect(id: Hero.title, in: hero, properties: .position)
                artistLine
                    .matchedGeometryEffect(id: Hero.artist, in: hero, properties: .position)
            }
            .opacity(revealed)
            Spacer(minLength: 0)
        }
    }

    private var artistLine: some View {
        HStack(spacing: 4) {
            if player.isAd { AdBadge() }
            if player.isExplicit { ExplicitBadge() }
            Button(action: player.openCurrentArtist) { Text(player.artist).lineLimit(1) }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .disabled(player.currentArtistId.isEmpty || player.isAd)
                .help("Go to artist")
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private func panelContent(_ panel: NowPlayingPanel) -> some View {
        switch panel {
        case .queue:
            QueueView(player: player, ui: ui)
        case .lyrics:
            LyricsPanel(player: player, ui: ui)
        }
    }

    /// Previous, play/pause, next, larger than the card's.
    private var transport: some View {
        HStack(spacing: 30) {
            Button(action: player.shuffle) { Image(systemName: "shuffle").font(.title3) }
                .help("Shuffle Up Next")
                .disabled(player.isAd)
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
                    .font(.system(size: 40))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .symbolEffect(.bounce, value: ui.playTaps)
                    .frame(width: 48, height: 48)
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
            Button(action: player.cycleRepeat) {
                Image(systemName: player.repeatMode.symbol)
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .off ? Color.primary : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(player.repeatMode.help)
            .disabled(player.isAd)
        }
        .buttonStyle(.borderless)
        .font(.title)
        .foregroundStyle(.primary)
        .animation(.quick, value: player.isPaused)
    }

    /// Rating on the left, volume in the middle, lyrics and Up Next on the right.
    private var controls: some View {
        HStack(spacing: 12) {
            RatingToggles(player: player)
                .matchedGeometryEffect(id: Hero.rating, in: hero, properties: .position)
            Spacer(minLength: 0)
            VolumeControl(player: player)
                .padding(-12) // its own panel padding isn't wanted inline
                .matchedGeometryEffect(id: Hero.volume, in: hero, properties: .position)
            Spacer(minLength: 0)
            panelButton(.lyrics, symbol: "quote.bubble", title: "Lyrics")
                .disabled(player.lyrics == nil || player.isAd || lyricsOff) // greyed out when the song has none, or for videos
                .help(lyricsOff ? "Lyrics aren't shown for videos"
                      : player.lyrics != nil ? "Lyrics" : player.lyricsLoading ? "Looking for lyrics…" : "No lyrics for this song")
                .matchedGeometryEffect(id: Hero.lyrics, in: hero, properties: .position)
            panelButton(.queue, symbol: "list.bullet", title: "Up Next")
                .matchedGeometryEffect(id: Hero.queue, in: hero, properties: .position)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .foregroundStyle(.primary)
    }

    private func panelButton(_ panel: NowPlayingPanel, symbol: String, title: String) -> some View {
        let open = ui.nowPlayingPanel == panel
        return Button {
            withAnimation(.move) { ui.nowPlayingPanel = open ? nil : panel }
            ui.lyricsFollow = true
        } label: {
            Image(systemName: open && panel == .lyrics ? symbol + ".fill" : symbol)
                .foregroundStyle(open ? Color.accentColor : Color.primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .help(open ? "Hide " + title : title)
    }

    /// The page's background: the artwork, blurred and faint, over the window colour. It grows out of
    /// the card's glass, rounded like it, and reaches past the popover's edges once full size, so its
    /// corners end up hidden. Scaled up before blurring, so the blur's faded edges fall outside.
    private var surface: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            // Each track's artwork fades in.
            Color.clear
                .overlay {
                    if let image = player.artworkImage {
                        Image(nsImage: image).resizable().scaledToFill()
                            .transition(.opacity)
                            .id(image) // the next track's cross-fades in
                    }
                }
                .animation(.move, value: player.artworkImage)
            .scaleEffect(1.6)
            .blur(radius: 40)
            .opacity(0.4)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .matchedGeometryEffect(id: Hero.surface, in: hero)
        .padding(-24)
        .ignoresSafeArea()
    }
}
