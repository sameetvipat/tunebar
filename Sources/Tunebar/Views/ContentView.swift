import SwiftUI

/// The popover: a top bar and the now-playing card floating as Liquid Glass over the content, which
/// runs edge to edge and scrolls underneath them like a macOS toolbar.
struct ContentView: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The top bar and the card's room stay in the layout while Now Playing is open, so the page
            // underneath never shifts; the bar just fades out of the way.
            .safeAreaInset(edge: .top, spacing: 0) {
                TopBar(player: player, ui: ui)
                    .opacity(ui.showingNowPlaying ? 0 : 1)
                    .allowsHitTesting(!ui.showingNowPlaying)
            }
            // Room for the player card, which floats over the page's bottom edge in the overlay below.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: ui.cardHeight)
            }
            .overlay(alignment: .bottom) { PlayerSurface(player: player, ui: ui) }
            // The brand sits above everything, in the middle of the top bar's row, and stays put
            // while the top bar and Now Playing trade places. Hidden while the search box needs the room.
            .overlay(alignment: .top) {
                if !ui.isSearching || ui.showingNowPlaying {
                    Brand()
                        .frame(height: TopBar.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.move, value: ui.showingNowPlaying)
            .overlay(alignment: .top) {
                if ui.isCreatingPlaylist {
                    ZStack(alignment: .top) {
                        // Clicking anywhere outside the panel dismisses it.
                        Color.black.opacity(0.2)
                            .contentShape(Rectangle())
                            .onTapGesture { ui.isCreatingPlaylist = false }
                        CreatePlaylistPanel(player: player, ui: ui)
                            .padding(.top, 52)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.move, value: ui.isCreatingPlaylist)
            // Recent searches, while the search box is open and empty.
            .overlay(alignment: .top) {
                if ui.isSearching && ui.query.isEmpty && !ui.recentSearches.isEmpty && !ui.showingNowPlaying {
                    RecentSearches(ui: ui)
                        .padding(.top, TopBar.height)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.quick, value: ui.isSearching && ui.query.isEmpty)
            .overlay {
                if ui.showingWelcome {
                    WelcomeCard(ui: ui).transition(.opacity)
                }
            }
            .animation(.move, value: ui.showingWelcome)
            .onChange(of: player.navigation) { ui.resetForNavigation() }
            .onChange(of: player.navigationRequest) { ui.leavePlayer() }
            .font(.body)
            .frame(width: AppDelegate.popoverSize.width, height: AppDelegate.popoverSize.height)
    }

    /// The page, cross-fading to the next one on every navigation. In a ZStack so the two overlap
    /// while they fade, rather than being stacked one above the other for a moment.
    private var content: some View {
        ZStack {
            pageContent
                .id(player.navigation)
                .transition(.opacity)
        }
        .animation(.move, value: player.navigation)
    }

    @ViewBuilder private var pageContent: some View {
        if let page = player.current, page.isOwnedPlaylist, ui.editingBrowseId == page.browseId {
            PlaylistEditor(page: page, player: player, ui: ui)
        } else if let page = player.current {
            PageView(page: page, player: player, ui: ui)
        } else {
            VStack(spacing: 10) {
                if player.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "music.note").font(.system(size: 36))
                    Text(player.errorMessage ?? "Nothing here yet").multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.secondary)
            .padding()
        }
    }
}

/// Your recent searches, under the search box: click one to search it again.
private struct RecentSearches: View {
    @ObservedObject var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Recent Searches").font(.headline)
                Spacer()
                Button("Clear") { ui.forgetSearch(nil) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            ForEach(ui.recentSearches, id: \.self) { query in
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    Text(query).lineLimit(1)
                    Spacer()
                    Button { ui.forgetSearch(query) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                        .buttonStyle(.borderless)
                        .help("Remove from recent searches")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { ui.query = query }
            }
        }
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
    }
}
