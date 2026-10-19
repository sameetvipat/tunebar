import SwiftUI

/// Editor for a playlist you own: details at the top (applied on Save; Cancel discards them), and the
/// tracks below, which can be dragged to reorder or removed (applied immediately, like the web app).
struct PlaylistEditor: View {
    let page: Page
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    private var title: String { ui.editTitle.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit Playlist").font(.headline)
                FocusedTextField(text: $ui.editTitle, placeholder: "Title", bordered: true,
                                 onSubmit: save, onCancel: { ui.editingBrowseId = nil })
                TextField("Description", text: $ui.editDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                PrivacyPicker(selection: $ui.editPrivacy)
                HStack {
                    if ui.confirmDelete {
                        Text("Delete for good?").font(.callout)
                        Button("Delete", role: .destructive) {
                            ui.editingBrowseId = nil
                            player.deletePlaylist(page)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                        Button("Keep") { ui.confirmDelete = false }
                    } else {
                        Button(role: .destructive) { ui.confirmDelete = true } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    }
                    Spacer()
                    Button("Cancel") { ui.editingBrowseId = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .disabled(title.isEmpty)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
            .padding(16)

            Divider()
            HStack {
                Text("\(page.tracks.count) songs").font(.subheadline.bold())
                Spacer()
                Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach(page.tracks) { track in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Artwork(url: track.thumbnail, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title).lineLimit(1)
                            HStack(spacing: 4) {
                                if track.explicit == true { ExplicitBadge() }
                                Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button { player.removeFromPlaylist(track, on: page) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from playlist")
                    }
                    .padding(.vertical, 2)
                }
                .onMove { player.moveTrack(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func save() {
        guard !title.isEmpty else { return }
        player.savePlaylistDetails(page, title: title, description: ui.editDescription, privacy: ui.editPrivacy)
        ui.editingBrowseId = nil
    }
}

/// The New Playlist panel, optionally starting the playlist with a song.
struct CreatePlaylistPanel: View {
    @ObservedObject var player: Player
    @ObservedObject var ui: UIState

    private var title: String { ui.newTitle.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui.pendingVideoId == nil ? "New Playlist" : "New Playlist with This Song").font(.headline)
            FocusedTextField(text: $ui.newTitle, placeholder: "Title", bordered: true,
                             onSubmit: create, onCancel: { ui.isCreatingPlaylist = false })
            PrivacyPicker(selection: $ui.newPrivacy)
            HStack {
                Spacer()
                Button("Cancel") { ui.isCreatingPlaylist = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .buttonStyle(.glassProminent)
                    .disabled(title.isEmpty)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(12)
    }

    private func create() {
        guard !title.isEmpty else { return }
        player.createPlaylist(title: title, privacy: ui.newPrivacy, videoId: ui.pendingVideoId)
        ui.isCreatingPlaylist = false
    }
}

/// Public / Unlisted / Private.
struct PrivacyPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Privacy", selection: $selection) {
            Text("Public").tag("PUBLIC")
            Text("Unlisted").tag("UNLISTED")
            Text("Private").tag("PRIVATE")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
