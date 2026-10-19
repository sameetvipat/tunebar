import SwiftUI

/// The glass card at the bottom: the playing track, its actions, transport and progress.
/// Buttons are plain glyphs without backgrounds, like Apple Music's player.
struct NowPlayingBar: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: player.openCurrentCollection) {
                    Artwork(url: player.artwork, size: 42)
                }
                .buttonStyle(.plain)
                .disabled(!player.hasCurrentPlaylist && !player.hasCurrentAlbum)
                .help("Go to album or playlist")

                VStack(alignment: .leading, spacing: 1) {
                    Text(player.title.isEmpty ? "Not playing" : player.title).fontWeight(.semibold).lineLimit(1)
                    Button(action: player.openCurrentArtist) {
                        HStack(spacing: 4) {
                            if player.isExplicit { ExplicitBadge() }
                            Text(player.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentArtistId.isEmpty)
                    .help("Go to artist")
                }
                Spacer(minLength: 4)
                trackActions
            }
            HStack(spacing: 10) {
                transport
                ProgressRow(player: player, clock: player.clock, ui: ui)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// Like, dislike, Up Next and the "…" menu for the playing track.
    private var trackActions: some View {
        HStack(spacing: 6) {
            let rating = player.likeStatus
            Button { player.setRating(player.videoId, rating == .like ? .none : .like) } label: {
                Image(systemName: Rating.likeSymbol(filled: rating == .like))
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(rating == .like ? "Remove from Liked Songs" : "Like")

            Button { player.setRating(player.videoId, rating == .dislike ? .none : .dislike) } label: {
                Image(systemName: Rating.dislikeSymbol(filled: rating == .dislike))
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(rating == .dislike ? "Remove Dislike" : "Dislike")

            Button { ui.showingVolume.toggle() } label: {
                Image(systemName: VolumeControl.symbol(player.isMuted ? 0 : player.volume))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22) // the speaker's waves change its width
            }
            .help("Volume")
            .popover(isPresented: $ui.showingVolume, arrowEdge: .top) { VolumeControl(player: player) }

            Button { withAnimation(.snappy) { ui.showingQueue.toggle() } } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(ui.showingQueue ? Color.accentColor : Color.primary)
            }
            .help(ui.showingQueue ? "Hide Up Next" : "Up Next")

            Menu {
                Button { player.startMix(videoId: player.videoId, endpoint: player.currentMixEndpoint) } label: {
                    Label("Start Mix", systemImage: "dot.radiowaves.left.and.right")
                }
                AddToPlaylistMenu(videoId: player.videoId, player: player, ui: ui)
                if player.currentLibraryAdd.nonEmpty != nil || player.currentLibraryRemove.nonEmpty != nil {
                    LibraryMenuItem(inLibrary: player.currentInLibrary) { player.setCurrentInLibrary($0) }
                }
                Divider()
                Button(action: player.openCurrentArtist) { Label("Go to Artist", systemImage: "music.mic") }
                    .disabled(player.currentArtistId.isEmpty)
                Button(action: player.openCurrentAlbum) { Label("Go to Album", systemImage: "square.stack") }
                    .disabled(!player.hasCurrentAlbum)
                Button(action: player.openCurrentPlaylist) { Label("Go to Playlist", systemImage: "music.note.list") }
                    .disabled(!player.hasCurrentPlaylist)
                Divider()
                ShareItems(url: ShareLinks.url(videoId: player.videoId, playlistId: nil, browseId: nil, pageType: nil),
                           title: player.title)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .foregroundStyle(.primary)
        .disabled(player.videoId.isEmpty)
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
        }
        .buttonStyle(.borderless)
        .font(.title3)
        .foregroundStyle(.primary)
        .animation(.default, value: player.isPaused)
    }
}

/// The volume panel: mute/unmute and a level slider.
struct VolumeControl: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack(spacing: 10) {
            Button(action: player.toggleMute) {
                Image(systemName: Self.symbol(player.isMuted ? 0 : player.volume))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
            }
            .buttonStyle(.borderless)
            .help(player.isMuted ? "Unmute" : "Mute")
            Slider(value: Binding(get: { player.isMuted ? 0 : player.volume }, set: player.setVolume),
                   in: 0...100,
                   onEditingChanged: { player.adjustingVolume = $0 })
                .frame(width: 160)
            Text("\(Int(player.isMuted ? 0 : player.volume))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(12)
    }

    /// A speaker with one to three waves for the level, or slashed when silent.
    static func symbol(_ level: Double) -> String {
        switch level {
        case ..<1: "speaker.slash.fill"
        case ..<34: "speaker.wave.1.fill"
        case ..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Elapsed time, slider and length. The only view observing the fast-ticking clock.
struct ProgressRow: View {
    let player: Player
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var ui: UIState

    var body: some View {
        Text(Self.format(ui.scrub ?? clock.time))
        Slider(value: Binding(get: { ui.scrub ?? clock.time }, set: { ui.scrub = $0 }),
               in: 0...max(clock.duration, 1),
               onEditingChanged: { editing in
                   // Seek once, on release, rather than on every step of the drag.
                   if !editing, let position = ui.scrub {
                       player.seek(to: position)
                       ui.scrub = nil
                   }
               })
            .controlSize(.mini)
        Text(Self.format(clock.duration))
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
