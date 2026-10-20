import SwiftUI

/// The Video tab's picture: the frames the page sends (see `Player.streamVideo`), letterboxed in
/// black. Streams only while it's on screen.
struct VideoSurface: View {
    let player: Player
    @ObservedObject var feed: VideoFeed

    var body: some View {
        ZStack {
            Color.black
            if let frame = feed.frame {
                Image(nsImage: frame)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { player.streamVideo(true) }
        .onDisappear { player.streamVideo(false) }
    }
}
