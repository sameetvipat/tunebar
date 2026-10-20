import AppKit
import SwiftUI

/// Shown the first time Tunebar opens, with the popover pointing at its menu bar icon: a menu bar app
/// has no window or Dock icon, so this says where it lives and how to get back to it.
struct WelcomeCard: View {
    @ObservedObject var ui: UIState

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(nsImage: MenuBarIcon.image)
                        .resizable()
                        .frame(width: 30, height: 30)
                }
                Text("Tunebar lives in your menu bar")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Click its icon at the top of your screen to open it.", systemImage: "cursorarrow.click")
                    Label("Or press ⌃⌥M from any app.", systemImage: "keyboard")
                    Label("Right-click the icon for Sign In, Reload and Quit.", systemImage: "contextualmenu.and.cursorarrow")
                    Label("Music keeps playing when it's closed.", systemImage: "music.note")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Got It") { ui.finishWelcome() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(22)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(24)
        }
    }
}
