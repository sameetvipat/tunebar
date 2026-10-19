import Foundation

// Data passed between the page (bridge.js) and the UI. Everything here is decoded from the JSON the
// bridge returns, so property names match its keys.

/// YouTube Music page types, as they appear in browse links.
enum PageType {
    static let artist = "MUSIC_PAGE_TYPE_ARTIST"
    static let libraryArtist = "MUSIC_PAGE_TYPE_LIBRARY_ARTIST" // an artist's songs in your library
    static let album = "MUSIC_PAGE_TYPE_ALBUM"
    static let playlist = "MUSIC_PAGE_TYPE_PLAYLIST"
    static let creator = "MUSIC_PAGE_TYPE_USER_CHANNEL"
}

/// A song's rating, as YouTube Music names it.
enum Rating: String, Codable {
    case like = "LIKE"
    case dislike = "DISLIKE"
    case none = "INDIFFERENT"

    /// Thumbs up for a like, thumbs down for a dislike.
    static func likeSymbol(filled: Bool) -> String { filled ? "hand.thumbsup.fill" : "hand.thumbsup" }
    static func dislikeSymbol(filled: Bool) -> String { filled ? "hand.thumbsdown.fill" : "hand.thumbsdown" }
}

/// One row or card: a song, video, album, playlist or artist.
struct SearchItem: Codable, Identifiable, Hashable {
    var id: String
    var section: String
    var style: String?            // "card" for carousel/grid tiles, else a list row
    var title: String
    var subtitle: String
    var segments: [Segment]?      // the subtitle in pieces, some linking to an artist/album/creator
    var thumbnail: String?
    var explicit: Bool?

    // What it is and what it plays.
    var videoId: String?
    var playlistId: String?
    var browseId: String?
    var pageType: String?
    var playEndpoint: String?     // the web app's own requests (JSON), replayed verbatim
    var mixEndpoint: String?

    // Where it's from.
    var artistId: String?
    var artistName: String?
    var albumId: String?
    var creatorId: String?        // a playlist's creator (their channel)
    var creatorName: String?

    // Your account.
    var setVideoId: String?       // the entry's id within its playlist; needed to remove or move it
    var likeStatus: Rating?
    var inLibrary: Bool?          // nil when it has no "Save to library" toggle
    var libraryAdd: String?       // that toggle's two endpoints (JSON)
    var libraryRemove: String?

    var isArtist: Bool { pageType == PageType.artist || pageType == PageType.libraryArtist }
    var isCard: Bool { style == "card" }

    /// Its public YouTube Music link, for sharing.
    var shareURL: URL? {
        // An artist's playlist id is its shuffle mix; the artist itself is its channel.
        ShareLinks.url(videoId: videoId, playlistId: isArtist ? nil : playlistId, browseId: browseId, pageType: pageType)
    }
    /// Opens a page when tapped, rather than playing.
    var isBrowsable: Bool { videoId == nil && browseId != nil }
    /// Can be played, queued or added to the library.
    var hasActions: Bool { videoId != nil || playlistId != nil }
}

/// Public music.youtube.com links, which open for anyone (in a browser or the YouTube Music app).
enum ShareLinks {
    static func url(videoId: String?, playlistId: String?, browseId: String?, pageType: String?) -> URL? {
        var link = URLComponents(string: "https://music.youtube.com")!
        if let videoId {
            link.path = "/watch"
            link.queryItems = [URLQueryItem(name: "v", value: videoId)]
        } else if let list = playlistId ?? browseId.flatMap({ $0.hasPrefix("VL") ? String($0.dropFirst(2)) : nil }) {
            link.path = "/playlist" // albums share as their track list (OLAK…), playlists as theirs
            link.queryItems = [URLQueryItem(name: "list", value: list)]
        } else if let browseId {
            // Artists and creators are channels; anything else opens by its browse id.
            let isChannel = [PageType.artist, PageType.creator].contains(pageType) && browseId.hasPrefix("UC")
            link.path = (isChannel ? "/channel/" : "/browse/") + browseId
        } else {
            return nil
        }
        return link.url
    }
}

/// A piece of a subtitle; `id`/`type` are set when it links somewhere.
struct Segment: Codable, Hashable {
    var text: String
    var id: String?
    var type: String?

    var isLink: Bool {
        id != nil && [PageType.artist, PageType.album, PageType.creator].contains(type)
    }
}

/// An album's release date and label (see bridge.js `albumDetails`).
struct AlbumDetails: Codable {
    var released: String?
    var label: String?
}

/// A shelf's "See all" page.
struct MoreLink: Codable, Hashable {
    var browseId: String
    var params: String?
    var pageType: String?
}

/// One screen in the popover: the home feed, search results, a library tab, a "View all" list, or
/// an artist / album / playlist / creator page.
struct Page: Codable {
    var title: String?
    var subtitle: String?          // a short line under the title, e.g. "EP • 2009"
    var stats: String?             // e.g. "6 songs • 23 minutes", shown under the track list
    var thumbnail: String?
    var description: String?
    var items: [SearchItem]

    // Set by Swift after loading, to say what kind of page this is.
    var browseId: String?
    var pageType: String?
    var libraryTab: LibraryTab?
    var query: String?             // search pages: the query
    var filterName: String?        // a "View all" page: the category it lists

    var playlistId: String?        // what Play plays
    var filters: [String: String]? // search pages: section name → filter params for its "View all"
    var more: [String: MoreLink]?  // browse pages: section name → its "See all" page
    var ownerId: String?           // a playlist's creator or an album's artist
    var ownerName: String?
    var ownerType: String?
    var owned: Bool?               // a playlist you can edit
    var privacy: String?           // PUBLIC / UNLISTED / PRIVATE
    var inLibrary: Bool?
    var libraryAdd: String?
    var libraryRemove: String?
    var released: String?          // albums: release date, "yyyy-MM-dd" (loaded after the page)
    var label: String?             // albums: e.g. "2004 UMG Recordings, Inc."

    static let homeType = "home"

    var isHome: Bool { pageType == Self.homeType }
    var isArtist: Bool { pageType == PageType.artist }
    var isLibrary: Bool { libraryTab != nil }
    var isLikedSongs: Bool { libraryTab == .likedSongs }
    /// A library tab that plays as one list (Liked songs, or Songs shuffled).
    var playsAsList: Bool { libraryTab == .likedSongs || libraryTab == .songs }
    var isOwnedPlaylist: Bool { owned == true }

    /// Its public YouTube Music link, for sharing.
    var shareURL: URL? {
        ShareLinks.url(videoId: nil, playlistId: isArtist ? nil : playlistId, browseId: browseId, pageType: pageType)
    }

    /// The playlist id the edit API expects (browse ids carry a "VL" prefix).
    var editablePlaylistId: String? {
        guard isOwnedPlaylist, let browseId else { return nil }
        return browseId.hasPrefix("VL") ? String(browseId.dropFirst(2)) : browseId
    }

    /// The playlist's own entries (excludes suggestion shelves).
    var tracks: [SearchItem] { items.filter { $0.setVideoId != nil } }

    /// Items grouped by section, in the order the sections first appear.
    var sections: [(title: String, items: [SearchItem])] {
        var order: [String] = []
        var groups: [String: [SearchItem]] = [:]
        for item in items {
            if groups[item.section] == nil { order.append(item.section) }
            groups[item.section, default: []].append(item)
        }
        return order.map { ($0, groups[$0]!) }
    }
}

enum LibraryTab: String, CaseIterable, Codable {
    case playlists = "Playlists"
    case songs = "Songs"
    case likedSongs = "Liked songs"
    case albums = "Albums"
    case artists = "Artists"
    case history = "History"

    var browseId: String {
        switch self {
        case .playlists: "FEmusic_liked_playlists"
        case .songs: "FEmusic_liked_videos"
        case .likedSongs: "VLLM"
        case .albums: "FEmusic_liked_albums"
        case .artists: "FEmusic_library_corpus_track_artists"
        case .history: "FEmusic_history"
        }
    }

    var shortTitle: String { self == .likedSongs ? "Liked" : rawValue }

    /// Apple Music's library symbols.
    var symbol: String {
        switch self {
        case .playlists: "music.note.list"
        case .songs: "music.note"
        case .likedSongs: Rating.likeSymbol(filled: false)
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .history: "clock"
        }
    }
}

/// One of your playlists, as offered by "Add to Playlist".
struct PlaylistRef: Codable, Hashable, Identifiable {
    var id: String
    var title: String
}

/// An entry in "Up Next".
struct QueueItem: Codable, Identifiable, Hashable {
    var index: Int        // position in the list shown
    var storeIndex: Int   // position in the page's queue (or autoplay) list
    var autoplay: Bool    // part of YouTube Music's autoplay mix, after your queue
    var title: String
    var subtitle: String
    var length: String
    var thumbnail: String?
    var videoId: String
    var occurrence: Int   // nth time this video appears in the queue
    var selected: Bool    // now playing
    var explicit: Bool
    var likeStatus: Rating?

    /// As an item, for actions that take one.
    var asItem: SearchItem {
        SearchItem(id: videoId, section: "", title: title, subtitle: subtitle, thumbnail: thumbnail,
                   explicit: explicit, videoId: videoId, likeStatus: likeStatus)
    }

    var id: Int { index }
}
