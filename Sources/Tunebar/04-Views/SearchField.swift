import SwiftUI

/// The top bar's search box: a magnifier, the text and a clear button, in the same 36 pt glass
/// capsule as the bar's buttons. Focused as soon as it appears; Esc calls `onCancel`.
struct SearchField: View {
    @Binding var text: String
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            FocusedTextField(text: $text, placeholder: "Search songs, artists, albums", onCancel: onCancel)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .glassEffect(.regular, in: Capsule())
    }
}
