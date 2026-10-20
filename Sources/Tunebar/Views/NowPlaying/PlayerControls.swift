import SwiftUI

/// The track name, as a link to its album when it has one (not during ads), else plain text.
struct AlbumLink<Label: View>: View {
    @ObservedObject var player: Player
    @ViewBuilder let label: () -> Label

    var body: some View {
        if player.hasCurrentAlbum && !player.isAd {
            Button(action: player.openCurrentAlbum, label: label)
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Go to album")
        } else {
            label()
        }
    }
}

/// The playing track's "…" menu, on the card and on Now Playing. Off during ads, whose track isn't
/// the song's.
struct CurrentTrackMenu<Label: View>: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            Button { player.startMix(videoId: player.videoId, endpoint: player.currentMixEndpoint) } label: {
                SwiftUI.Label("Start Mix", systemImage: "dot.radiowaves.left.and.right")
            }
            AddToPlaylistMenu(videoId: player.videoId, player: player, ui: ui)
            if player.currentLibraryAdd.nonEmpty != nil || player.currentLibraryRemove.nonEmpty != nil {
                LibraryMenuItem(inLibrary: player.currentInLibrary) { player.setCurrentInLibrary($0) }
            }
            Divider()
            Button(action: player.openCurrentArtist) { SwiftUI.Label("Go to Artist", systemImage: "music.mic") }
                .disabled(player.currentArtistId.isEmpty)
            Button(action: player.openCurrentAlbum) { SwiftUI.Label("Go to Album", systemImage: "square.stack") }
                .disabled(!player.hasCurrentAlbum)
            Button(action: player.openCurrentPlaylist) { SwiftUI.Label("Go to Playlist", systemImage: "music.note.list") }
                .disabled(!player.hasCurrentPlaylist)
            Divider()
            ShareItems(url: ShareLinks.url(videoId: player.videoId, playlistId: nil, browseId: nil, pageType: nil),
                       title: player.title)
        } label: { label() }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .disabled(player.isAd)
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

/// Elapsed time, slider and length. The only view observing the fast-ticking clock. During an ad
/// the slider is locked, and "Skip" appears once the page offers it.
struct ProgressRow: View {
    let player: Player
    @ObservedObject var clock: PlaybackClock
    @ObservedObject var ui: UIState
    // Passed as values: `player` isn't observed here, so changes to it alone wouldn't redraw this row.
    var isAd = false
    var canSkipAd = false

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
            .disabled(isAd)
        Text(Self.format(clock.duration))
        if canSkipAd {
            Button("Skip", action: player.skipAd)
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Skip Ad")
        }
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Like and dislike for the playing track, off during ads (they'd rate the song, not the ad).
struct RatingToggles: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack(spacing: 12) {
            let rating = player.likeStatus
            Button { player.setRating(player.videoId, rating == .like ? .none : .like) } label: {
                Image(systemName: Rating.likeSymbol(filled: rating == .like)).contentTransition(.symbolEffect(.replace))
            }
            .help(rating == .like ? "Remove from Liked Songs" : "Like")
            Button { player.setRating(player.videoId, rating == .dislike ? .none : .dislike) } label: {
                Image(systemName: Rating.dislikeSymbol(filled: rating == .dislike)).contentTransition(.symbolEffect(.replace))
            }
            .help(rating == .dislike ? "Remove Dislike" : "Dislike")
        }
        .disabled(player.isAd)
    }
}
