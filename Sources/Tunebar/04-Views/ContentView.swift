import SwiftUI

/// The popover: a top bar and the now-playing card floating as Liquid Glass over the content, which
/// runs edge to edge and scrolls underneath them like a macOS toolbar.
struct ContentView: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { TopBar(player: player, ui: ui) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let toast = player.toast {
                        Text(toast)
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    NowPlayingBar(player: player, ui: ui)
                }
                .animation(.snappy, value: player.toast)
            }
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
            .animation(.snappy, value: ui.isCreatingPlaylist)
            .onChange(of: player.navigation) { ui.resetForNavigation() }
            .font(.body)
            .frame(width: AppDelegate.popoverSize.width, height: AppDelegate.popoverSize.height)
    }

    @ViewBuilder private var content: some View {
        if ui.showingQueue {
            QueueView(player: player, ui: ui)
        } else if let page = player.current, page.isOwnedPlaylist, ui.editingBrowseId == page.browseId {
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

/// Back and Home on the left, the YouTube Music brand in the middle, Library and Search on the right.
/// Every button is the same 36 pt glass circle.
struct TopBar: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                BarButton(symbol: "chevron.left", help: "Back", action: back)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(!player.canGoBack && !ui.showingQueue)
                BarButton(symbol: player.current?.isHome == true ? "house.fill" : "house", help: "Home",
                          action: player.goHome)
                    .glassEffect(.regular.interactive(), in: Circle())

                if ui.isSearching {
                    SearchField(text: $ui.query, onCancel: closeSearch)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Spacer()
                }
                if player.isLoading {
                    ProgressView().controlSize(.small)
                }

                BarButton(symbol: player.current?.isLibrary == true ? "square.stack.fill" : "square.stack",
                          help: "Library") {
                    Task { await player.openLibrary() }
                }
                .glassEffect(.regular.interactive(), in: Circle())

                BarButton(symbol: ui.isSearching ? "xmark" : "magnifyingglass",
                          help: ui.isSearching ? "Close Search" : "Search (⌘F)", action: toggleSearch)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
        // Centered on the bar itself (not between its neighbours); hidden while the search box needs the room.
        .overlay {
            if !ui.isSearching {
                Brand()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(alignment: .top) { ScrollBlur(visible: ui.contentScrolled) }
        .task(id: ui.query) {
            try? await Task.sleep(for: .milliseconds(350)) // debounce typing
            guard !Task.isCancelled else { return }
            await player.search(ui.query)
        }
    }

    private func back() {
        if ui.showingQueue { ui.showingQueue = false } else { player.goBack() }
    }

    private func toggleSearch() {
        if ui.isSearching {
            closeSearch()
        } else {
            withAnimation(.snappy) { ui.isSearching = true }
        }
    }

    private func closeSearch() {
        withAnimation(.snappy) {
            ui.isSearching = false
            ui.query = ""
        }
    }
}

/// A frosted band behind the top bar that fades out downwards, shown once the page has scrolled, so
/// content passing under the bar is softly blurred rather than colliding with it.
private struct ScrollBlur: View {
    let visible: Bool

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .padding(.bottom, -14) // fade out just below the bar
            .ignoresSafeArea(edges: .top)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: visible)
            .allowsHitTesting(false)
    }
}

/// A 36 pt icon button for the top bar; the caller gives it its glass shape.
struct BarButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }
}
