import SwiftUI

/// A list row: artwork, title, linked subtitle, and on hover a "…" menu. In select mode, a checkbox
/// instead, and a tap toggles it.
///
/// Rows (and cards) use a tap gesture rather than being Buttons, so the artist and album links in
/// the subtitle receive their own clicks.
struct ResultRow: View {
    let item: SearchItem
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    /// On album pages: shown in place of the artwork.
    var trackNumber: Int? = nil

    private var hovered: Bool { ui.hoveredID == item.id }
    private var selected: Bool { ui.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            if ui.isSelecting {
                SelectionMark(selected: selected, enabled: ui.selectable.contains(item.id))
            }
            if let trackNumber {
                TrackNumber(number: trackNumber, item: item, hovered: hovered && !ui.isSelecting, player: player)
            } else {
                Artwork(url: item.thumbnail, size: 44, circle: item.isArtist)
                    .overlay {
                        if hovered && !ui.isSelecting { ArtworkPlayButton(item: item, size: 26, player: player) }
                    }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(item.description == nil ? 1 : 2)
                LinkedSubtitle(item: item, player: player)
                if let description = item.description { // podcast episodes
                    Text(description).font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if item.isQueueable && !ui.isSelecting {
                QueueButton(item: item, player: player).opacity(hovered ? 1 : 0)
            }
            if let videoId = item.videoId, !ui.isSelecting {
                RatingButtons(rating: item.likeStatus ?? .none, hovered: hovered) {
                    player.setRating(videoId, $0, item: item)
                }
            }
            if item.hasActions && !ui.isSelecting {
                Menu { ItemMenuItems(item: item, page: page, player: player, ui: ui) } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .opacity(hovered ? 1 : 0)
            }
            if item.isBrowsable {
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.18) : hovered ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { tap(item, player: player, ui: ui) }
        .padding(.horizontal, 6)
        .onHover { inside in
            if inside { ui.hoveredID = item.id } else if ui.hoveredID == item.id { ui.hoveredID = nil }
        }
        .contextMenu { ItemMenuItems(item: item, page: page, player: player, ui: ui) }
        .animation(.quick, value: hovered)
    }
}

/// A tile for carousels and grids.
struct CardItem: View {
    let item: SearchItem
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState
    var size: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Artwork(url: item.thumbnail, size: size, circle: item.isArtist)
                .overlay(alignment: .topLeading) {
                    if ui.isSelecting {
                        SelectionMark(selected: ui.selection.contains(item.id), enabled: ui.selectable.contains(item.id))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if ui.hoveredID == item.id && !ui.isSelecting {
                        ArtworkPlayButton(item: item, size: 36, player: player).padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if ui.hoveredID == item.id && !ui.isSelecting && item.isQueueable {
                        QueueButton(item: item, player: player, size: 28).padding(8)
                    }
                }
            Text(item.title).lineLimit(2).multilineTextAlignment(.leading)
            LinkedSubtitle(item: item, player: player)
        }
        .frame(width: size, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { tap(item, player: player, ui: ui) }
        .onHover { inside in
            if inside { ui.hoveredID = item.id } else if ui.hoveredID == item.id { ui.hoveredID = nil }
        }
        .contextMenu { ItemMenuItems(item: item, page: page, player: player, ui: ui) }
        .animation(.quick, value: ui.hoveredID == item.id)
    }
}

/// Tapping an item: toggles it in select mode, otherwise opens or plays it.
@MainActor
private func tap(_ item: SearchItem, player: Player, ui: UIState) {
    if ui.isSelecting {
        if ui.selectable.contains(item.id) { ui.toggleSelection(item.id) }
    } else {
        player.select(item)
    }
}

/// A song's like and dislike (in that order), as small buttons. The like is always there, filled once
/// liked; the dislike shows on hover, or once disliked.
struct RatingButtons: View {
    let rating: Rating
    let hovered: Bool
    let rate: (Rating) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button { rate(rating == .like ? .none : .like) } label: {
                Image(systemName: Rating.likeSymbol(filled: rating == .like))
                    .foregroundStyle(rating == .like ? Color.primary : Color.secondary)
            }
            .help(rating == .like ? "Remove from Liked Songs" : "Like")
            if hovered || rating == .dislike {
                Button { rate(rating == .dislike ? .none : .dislike) } label: {
                    Image(systemName: Rating.dislikeSymbol(filled: rating == .dislike))
                }
                .help(rating == .dislike ? "Remove Dislike" : "Dislike")
            }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .contentTransition(.symbolEffect(.replace))
    }
}

/// An album track's number, as Apple Music shows it: ▶ on hover, a waveform while it's playing.
private struct TrackNumber: View {
    let number: Int
    let item: SearchItem
    let hovered: Bool
    @ObservedObject var player: Player

    private var isCurrent: Bool { item.videoId != nil && item.videoId == player.videoId }

    var body: some View {
        Group {
            if hovered {
                Button { player.select(item) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.plain)
                    .help("Play")
            } else if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: !player.isPaused)
            } else {
                Text("\(number)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 36) // narrower than artwork; rows stay the same height
    }
}

/// The play button shown on artwork on hover: plays a song, or a whole album/playlist, without
/// opening its page. Nothing for items that don't play (artists, profiles).
struct ArtworkPlayButton: View {
    let item: SearchItem
    let size: CGFloat
    let player: Player

    private var playable: Bool {
        item.videoId != nil || item.playlistId != nil || [PageType.album, PageType.playlist].contains(item.pageType)
    }

    var body: some View {
        if playable {
            Button {
                if item.videoId != nil { player.select(item) } else { player.playCollection(item) }
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Play")
            .transition(.opacity)
        }
    }
}

/// Add to Queue in one click, for a song or a whole album/playlist (Play Next is in the ⋯ menu).
/// With `size`, a glass circle for laying over artwork; without, a plain glyph for rows.
struct QueueButton: View {
    let item: SearchItem
    let player: Player
    var size: CGFloat? = nil

    var body: some View {
        Button {
            player.enqueue(videoId: item.videoId, playlistId: item.videoId == nil ? item.playlistId : nil, playNext: false)
        } label: {
            if let size {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .glassEffect(.regular.interactive(), in: Circle())
                    .contentShape(Circle())
            } else {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
            }
        }
        .buttonStyle(.borderless)
        .help("Add to Queue")
        .transition(.opacity)
    }
}

/// Select mode's checkbox. Items the page can't remove (e.g. suggestions) show it dimmed.
struct SelectionMark: View {
    let selected: Bool
    let enabled: Bool

    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .background(Circle().fill(.background).padding(2))
            .opacity(enabled ? 1 : 0.3)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Marks the playing item as an ad: track skipping and seeking are off until it ends.
struct AdBadge: View {
    var body: some View {
        Text("Ad")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.yellow, in: Capsule())
            .help("Ad: skipping is off until it ends")
    }
}

/// The explicit-content "E", shown before a subtitle as YouTube Music does.
struct ExplicitBadge: View {
    var body: some View {
        Image(systemName: "e.square.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Explicit")
            .help("Explicit")
    }
}

/// A subtitle whose artist, album and creator names open their pages.
struct LinkedSubtitle: View {
    let item: SearchItem
    let player: Player

    var body: some View {
        HStack(spacing: 4) {
            if item.explicit == true { ExplicitBadge() }
            if let segments = item.segments, segments.contains(where: \.isLink) {
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        Group {
                            if segment.isLink, let id = segment.id {
                                Button(segment.text) { player.open(id: id, pageType: segment.type, title: segment.text) }
                                    .buttonStyle(.plain)
                                    .pointerStyle(.link)
                            } else {
                                Text(segment.text)
                            }
                        }
                        // Earlier pieces win, so the line truncates at its end rather than in every name.
                        .layoutPriority(Double(segments.count - index))
                    }
                }
            } else {
                Text(item.subtitle)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// Remote artwork, square with rounded corners or round for artists. Asks for the image at the
/// size it's shown, so a 44 pt thumbnail doesn't download and decode a 1200-pixel cover.
/// The playing track's artwork at whatever size it's given, for the artwork that grows and shrinks
/// between the card and Now Playing (see Hero). Sized by its container, so place it inside a frame.
struct HeroArtwork: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.secondary.opacity(0.2)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .transition(.opacity)
                        .id(image) // the next track's artwork cross-fades in
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(.quick, value: image)
    }
}

struct Artwork: View {
    let url: URL?
    let size: CGFloat
    let circle: Bool

    init(url: URL?, size: CGFloat, circle: Bool = false) {
        self.url = url
        self.size = size
        self.circle = circle
    }

    init(url: String?, size: CGFloat, circle: Bool = false) {
        self.init(url: url.flatMap(URL.init(string:)), size: size, circle: circle)
    }

    var body: some View {
        AsyncImage(url: Self.sized(url, points: size), transaction: Transaction(animation: .quick)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill().transition(.opacity) // fades in once loaded
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }

    /// The same image at `points` × 2 pixels (for Retina screens). Google's image hosts take the size
    /// after the last "=" (e.g. "=w544-h544-l90-rj"); YouTube video stills come in fixed sizes.
    static func sized(_ url: URL?, points: CGFloat) -> URL? {
        guard let url, let host = url.host else { return url }
        let pixels = Int(points * 2)
        let string = url.absoluteString
        if host.hasSuffix("googleusercontent.com") || host.hasSuffix("ggpht.com"),
           let equals = string.lastIndex(of: "="), !string[equals...].contains("/") {
            return URL(string: string[..<equals] + "=w\(pixels)-h\(pixels)-l90-rj")
        }
        if host == "i.ytimg.com", pixels <= 320 {
            return url.deletingLastPathComponent().appendingPathComponent("mqdefault.jpg") // 320 × 180
        }
        return url
    }
}
