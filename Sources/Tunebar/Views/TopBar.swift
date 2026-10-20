import SwiftUI

/// Back and Home on the left, the YouTube Music brand in the middle, Library and Search on the right.
/// Every button is the same 36 pt glass circle.
struct TopBar: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    /// Its 36 pt buttons plus 8 pt above and below. Now Playing's header matches it.
    static let height: CGFloat = 52

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                BarButton(symbol: "chevron.left", help: "Back", action: back)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(!player.canGoBack && ui.cardPanel == nil && !ui.showingNowPlaying)
                // On home, Home reloads it (the spinner shows meanwhile, then the fresh feed fades in).
                BarButton(symbol: player.current?.isHome == true ? "house.fill" : "house",
                          help: player.current?.isHome == true ? "Refresh Home" : "Home",
                          action: player.goHome)
                    .glassEffect(.regular.interactive(), in: Circle())
                BarButton(symbol: player.current?.isExplore == true ? "square.grid.2x2.fill" : "square.grid.2x2",
                          help: "Explore") {
                    Task { await player.openExplore() }
                }
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

                ProfileButton(player: player, ui: ui)
                    .glassEffect(.regular.interactive(), in: Circle())

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
        if ui.showingNowPlaying {
            ui.showingNowPlaying = false
        } else if ui.cardPanel != nil {
            ui.cardPanel = nil
        } else {
            player.goBack()
        }
    }

    private func toggleSearch() {
        if ui.isSearching {
            closeSearch()
        } else {
            withAnimation(.quick) { ui.isSearching = true }
        }
    }

    private func closeSearch() {
        ui.rememberSearch(ui.query)
        withAnimation(.quick) {
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
            .animation(.quick, value: visible)
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

/// Your photo in the top bar. Opens a card with your name and handle, and Sign Out; signed out, it
/// signs in.
struct ProfileButton: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        Button {
            if player.signedIn == true { ui.showingProfile.toggle() } else { player.requestSignIn() }
        } label: {
            Group {
                if let photo = player.account?.photo {
                    Artwork(url: photo, size: 26, circle: true)
                } else {
                    Image(systemName: player.signedIn == true ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 17, weight: .medium))
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(player.signedIn == true ? (player.account?.name ?? "Account") : "Sign In")
        .popover(isPresented: $ui.showingProfile, arrowEdge: .bottom) { ProfileCard(player: player, ui: ui) }
    }
}

/// Who's signed in, a link to your profile, and Sign Out.
private struct ProfileCard: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    var body: some View {
        VStack(spacing: 10) {
            if let photo = player.account?.photo {
                Artwork(url: photo, size: 56, circle: true)
            } else {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                Text(player.account?.name ?? "Signed in").font(.headline)
                if let handle = player.account?.handle {
                    Text(handle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                if let account = player.account, let channelId = account.channelId {
                    Button {
                        ui.showingProfile = false
                        player.open(id: channelId, pageType: PageType.creator, title: account.name)
                    } label: {
                        Label("View Profile", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                Button(role: .destructive) {
                    ui.showingProfile = false
                    Task { await player.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(18)
        .frame(minWidth: 200)
    }
}
