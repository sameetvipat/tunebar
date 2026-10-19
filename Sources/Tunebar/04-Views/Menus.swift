import AppKit
import SwiftUI

/// The actions for a song, album or playlist. Used by both the "…" menu and the right-click menu.
struct ItemMenuItems: View {
    let item: SearchItem
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        if let videoId = item.videoId {
            Button { player.select(item) } label: { Label("Play", systemImage: "play.fill") }
            QueueMenuItems(player: player, videoId: videoId, playlistId: nil)
            Button { player.startMix(videoId: videoId, endpoint: item.mixEndpoint) } label: {
                Label("Start Mix", systemImage: "dot.radiowaves.left.and.right")
            }
            Divider()
            RatingMenuItems(rating: item.likeStatus ?? .none) { player.setRating(videoId, $0, item: item) }
            AddToPlaylistMenu(videoId: videoId, player: player, ui: ui)
            if let inLibrary = item.inLibrary {
                LibraryMenuItem(inLibrary: inLibrary) { player.setInLibrary(item, $0) }
            }
            goToItems
            Divider()
            ShareItems(url: item.shareURL, title: item.title)
            if (page.isOwnedPlaylist && item.setVideoId != nil) || page.isLikedSongs {
                Divider()
                Button(role: .destructive) { player.removeFromPlaylist(item, on: page) } label: {
                    Label("Remove from \(page.isLikedSongs ? "Liked Songs" : "Playlist")", systemImage: "trash")
                }
            }
        } else if let playlistId = item.playlistId {
            Button { player.play(videoId: nil, playlistId: playlistId) } label: { Label("Play", systemImage: "play.fill") }
            QueueMenuItems(player: player, videoId: nil, playlistId: playlistId)
            Button { player.startMix(playlistId: playlistId, endpoint: item.mixEndpoint) } label: {
                Label("Start Mix", systemImage: "dot.radiowaves.left.and.right")
            }
            if let inLibrary = item.inLibrary {
                LibraryMenuItem(inLibrary: inLibrary) { player.setInLibrary(item, $0) }
            }
            if item.isBrowsable, let browseId = item.browseId {
                GoToItem(owner: item.pageType, id: browseId, name: item.title, player: player)
            }
            goToItems
            Divider()
            ShareItems(url: item.shareURL, title: item.title)
        } else if item.isArtist, let url = item.shareURL {
            ShareItems(url: url, title: item.title)
        }
    }

    /// The artist, album and creator this item links to.
    @ViewBuilder private var goToItems: some View {
        let creator = item.videoId == nil ? item.creatorId : nil
        let artist = item.isArtist ? nil : item.artistId
        let album = item.videoId != nil && page.browseId != item.albumId ? item.albumId : nil
        if creator != nil || artist != nil || album != nil { Divider() }
        if let creator { GoToItem(owner: PageType.creator, id: creator, name: item.creatorName, player: player) }
        if let artist { GoToItem(owner: PageType.artist, id: artist, name: item.artistName, player: player) }
        if let album { GoToItem(owner: PageType.album, id: album, name: nil, player: player) }
    }
}

/// Share… (the macOS share menu) and Copy Link.
struct ShareItems: View {
    let url: URL?
    let title: String

    var body: some View {
        if let url {
            ShareLink(item: url, subject: Text(title), message: Text(title)) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            } label: { Label("Copy Link", systemImage: "link") }
        }
    }
}

/// Play Next and Add to Queue, for a song or a whole album/playlist.
struct QueueMenuItems: View {
    let player: Player
    let videoId: String?
    let playlistId: String?

    var body: some View {
        Button { player.enqueue(videoId: videoId, playlistId: playlistId, playNext: true) } label: {
            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { player.enqueue(videoId: videoId, playlistId: playlistId, playNext: false) } label: {
            Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
    }
}

/// Like / Dislike, each turning into its undo when already set.
struct RatingMenuItems: View {
    let rating: Rating
    let rate: (Rating) -> Void

    var body: some View {
        Button { rate(rating == .like ? .none : .like) } label: {
            Label(rating == .like ? "Remove from Liked Songs" : "Like",
                  systemImage: Rating.likeSymbol(filled: rating == .like))
        }
        Button { rate(rating == .dislike ? .none : .dislike) } label: {
            Label(rating == .dislike ? "Remove Dislike" : "Dislike",
                  systemImage: Rating.dislikeSymbol(filled: rating == .dislike))
        }
    }
}

/// Add to Library, or Remove from Library when it's already saved. `set` receives the new state.
struct LibraryMenuItem: View {
    let inLibrary: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!inLibrary) } label: {
            Label(inLibrary ? "Remove from Library" : "Add to Library", systemImage: inLibrary ? "minus.circle" : "plus")
        }
    }
}

/// "Go to Artist / Album / Playlist / Creator", by page type.
struct GoToItem: View {
    let owner: String?
    let id: String
    let name: String?
    let player: Player

    var body: some View {
        let (label, symbol, fallback): (String, String, String) = switch owner {
        case PageType.artist, PageType.libraryArtist: ("Go to Artist", "music.mic", "Artist")
        case PageType.album: ("Go to Album", "square.stack", "Album")
        case PageType.creator: ("Go to Creator", "person.crop.circle", "Creator")
        default: ("Go to Playlist", "music.note.list", "Playlist")
        }
        Button { player.open(id: id, pageType: owner, title: name ?? fallback) } label: {
            Label(label, systemImage: symbol)
        }
    }
}

/// Your playlists, plus "New Playlist…" to start one with this song.
struct AddToPlaylistMenu: View {
    let videoId: String
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        Menu {
            ForEach(player.ownPlaylists) { playlist in
                Button { player.addToPlaylist(videoId: videoId, playlist) } label: {
                    Label(playlist.title, systemImage: "music.note.list")
                }
            }
            if !player.ownPlaylists.isEmpty { Divider() }
            Button { ui.beginCreating(with: videoId) } label: { Label("New Playlist…", systemImage: "plus") }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
    }
}
