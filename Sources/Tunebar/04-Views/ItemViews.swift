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

    private var hovered: Bool { ui.hoveredID == item.id }
    private var selected: Bool { ui.selection.contains(item.id) }

    var body: some View {
        HStack(spacing: 12) {
            if ui.isSelecting {
                SelectionMark(selected: selected, enabled: ui.selectable.contains(item.id))
            }
            Artwork(url: item.thumbnail, size: 44, circle: item.isArtist)
                .overlay {
                    if hovered && !ui.isSelecting { ArtworkPlayButton(item: item, size: 26, player: player) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                LinkedSubtitle(item: item, player: player)
            }
            Spacer(minLength: 4)
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

/// A song's like and dislike (in that order), as small buttons. A rating that's set always shows; both show on hover.
struct RatingButtons: View {
    let rating: Rating
    let hovered: Bool
    let rate: (Rating) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if hovered || rating == .like {
                Button { rate(rating == .like ? .none : .like) } label: {
                    Image(systemName: Rating.likeSymbol(filled: rating == .like))
                        .foregroundStyle(rating == .like ? Color.primary : Color.secondary)
                }
                .help(rating == .like ? "Remove from Liked Songs" : "Like")
            }
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
        AsyncImage(url: Self.sized(url, points: size)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.secondary.opacity(0.2)
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
