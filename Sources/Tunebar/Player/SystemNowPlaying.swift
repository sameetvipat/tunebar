import AppKit
import MediaPlayer

/// The Mac's own Now Playing: Control Center and the lock screen show the playing track, and the
/// media keys (and AirPods' controls) play, pause, skip and seek. Skipping is off during ads.
@MainActor
final class SystemNowPlaying {
    private let player: Player
    private var shown = "" // what the info was last built from, to rebuild only on changes
    private var lastElapsed: Double = 0
    private var lastUpdate = Date()

    init(player: Player) {
        self.player = player
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlay() } ?? .commandFailed }
        commands.playCommand.addTarget { [weak self] _ in self?.run { if $0.isPaused { $0.togglePlay() } } ?? .commandFailed }
        commands.pauseCommand.addTarget { [weak self] _ in self?.run { if !$0.isPaused { $0.togglePlay() } } ?? .commandFailed }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run { $0.seek(to: event.positionTime) } ?? .commandFailed
        }
        player.onStateChange = { [weak self] in self?.update() }
    }

    private func run(_ action: (Player) -> Void) -> MPRemoteCommandHandlerStatus {
        guard !player.videoId.isEmpty else { return .noActionableNowPlayingItem }
        action(player)
        return .success
    }

    /// Rebuilds the info when the track, its artwork, play state or length changes, or when the
    /// position jumps (a seek); in between the system counts the time itself.
    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard !player.videoId.isEmpty else {
            if !shown.isEmpty { center.nowPlayingInfo = nil; center.playbackState = .stopped; shown = "" }
            return
        }
        let elapsed = player.clock.time
        let expected = lastElapsed + (player.isPaused ? 0 : Date().timeIntervalSince(lastUpdate))
        let state = [player.videoId, player.title, player.artist, "\(player.isPaused)", "\(player.isAd)",
                     "\(Int(player.clock.duration))", "\(player.artworkImage.map { ObjectIdentifier($0).hashValue } ?? 0)"]
            .joined(separator: "|")
        guard state != shown || abs(elapsed - expected) > 2 else { return }
        shown = state
        lastElapsed = elapsed
        lastUpdate = Date()

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title,
            MPMediaItemPropertyArtist: player.artist,
            MPMediaItemPropertyPlaybackDuration: player.clock.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPaused ? 0.0 : 1.0,
        ]
        if let image = player.artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
        center.playbackState = player.isPaused ? .paused : .playing
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = !player.isAd
        commands.previousTrackCommand.isEnabled = !player.isAd
        commands.changePlaybackPositionCommand.isEnabled = !player.isAd
    }
}
