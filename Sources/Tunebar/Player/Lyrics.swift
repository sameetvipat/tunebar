import Foundation

/// Lyrics for the playing song, fetched as each track starts so the Lyrics button knows whether to
/// offer them.
extension Player {
    /// Playing a video rather than a song: a music video, or any upload that isn't a song. Lyrics
    /// aren't offered for these.
    var isPlayingVideo: Bool { hasVideoVersion ? playingVideoVersion : hasVideo }

    func loadLyrics(for videoId: String) {
        lyricsFor = videoId
        lyrics = nil
        lyricsLoading = !videoId.isEmpty
        guard !videoId.isEmpty else { return }
        Task {
            let found = try? await bridge(Lyrics.self, "lyrics", videoId)
            guard lyricsFor == videoId else { return } // the track changed meanwhile
            lyrics = found?.isEmpty == false ? found : nil
            lyricsLoading = false
        }
    }
}
