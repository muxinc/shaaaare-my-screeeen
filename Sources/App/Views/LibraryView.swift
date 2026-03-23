import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var entries: [RecordingEntry] = []
    @State private var copiedId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.screen = .sourcePicker }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(MuxTheme.orange)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Library")
                    .font(MuxTheme.display(size: 22))

                Spacer()

                // Balance the back button width
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 40))
                        .foregroundColor(MuxTheme.textSecondary.opacity(0.5))

                    Text("No recordings yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(MuxTheme.textSecondary)

                    Text("Recordings you upload will appear here.")
                        .font(.system(size: 13))
                        .foregroundColor(MuxTheme.textSecondary.opacity(0.7))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            LibraryRow(
                                entry: entry,
                                isCopied: copiedId == entry.id,
                                onCopy: { copyURL(entry) },
                                onOpen: { openURL(entry) },
                                onDelete: { deleteEntry(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            entries = appState.historyStore.load()
        }
    }

    private func copyURL(_ entry: RecordingEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.playbackURL, forType: .string)
        copiedId = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedId == entry.id { copiedId = nil }
        }
    }

    private func openURL(_ entry: RecordingEntry) {
        if let url = URL(string: entry.playbackURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func deleteEntry(_ entry: RecordingEntry) {
        appState.historyStore.delete(id: entry.id)
        withAnimation(.easeOut(duration: 0.2)) {
            entries.removeAll { $0.id == entry.id }
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let entry: RecordingEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailImage: NSImage?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    MuxTheme.backgroundSecondary
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(MuxTheme.textSecondary.opacity(0.3))
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MuxTheme.border, lineWidth: 1)
            )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.assetId)
                    .font(MuxTheme.mono(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(formattedDate(entry.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(MuxTheme.textSecondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isCopied ? MuxTheme.green : MuxTheme.orange)
                        .frame(width: 28, height: 28)
                        .background(
                            isCopied
                                ? MuxTheme.green.opacity(0.1)
                                : MuxTheme.orange.opacity(0.1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy playback URL")

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MuxTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(MuxTheme.backgroundSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open in browser")

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(MuxTheme.red)
                            .frame(width: 28, height: 28)
                            .background(MuxTheme.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove from library")
                    .transition(.opacity)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MuxTheme.backgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(MuxTheme.border, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .task {
            guard thumbnailImage == nil, let url = entry.thumbnailURL else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    thumbnailImage = image
                }
            } catch {
                // Thumbnail fetch failed — placeholder stays
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
