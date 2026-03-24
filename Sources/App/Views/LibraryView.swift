import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var historyStore: RecordingHistoryStore
    @State private var copiedId: UUID?
    @State private var expandedId: UUID?

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

            if historyStore.entries.isEmpty {
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
                        ForEach(historyStore.entries) { entry in
                            LibraryRow(
                                entry: entry,
                                isCopied: copiedId == entry.id,
                                isExpanded: expandedId == entry.id,
                                onCopy: { copyURL(entry) },
                                onOpen: { openURL(entry) },
                                onDelete: { deleteEntry(entry) },
                                onToggleExpand: { toggleExpand(entry) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            historyStore.reload()
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
        withAnimation(.easeOut(duration: 0.2)) {
            historyStore.delete(id: entry.id)
        }
    }

    private func toggleExpand(_ entry: RecordingEntry) {
        withAnimation(.easeOut(duration: 0.2)) {
            expandedId = expandedId == entry.id ? nil : entry.id
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let entry: RecordingEntry
    let isCopied: Bool
    let isExpanded: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onToggleExpand: () -> Void

    @State private var thumbnailImage: NSImage?
    @State private var isHovering = false

    private var hasSummary: Bool {
        entry.title != nil || entry.summary != nil || entry.tags != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button(action: onToggleExpand) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.displayTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        if entry.summarizing == true {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Summarizing...")
                                    .font(.system(size: 11))
                                    .foregroundColor(MuxTheme.orange)
                            }
                        } else if let summary = entry.summary {
                            Text(summary)
                                .font(.system(size: 11))
                                .foregroundColor(MuxTheme.textSecondary)
                                .lineLimit(isExpanded ? nil : 1)
                        }

                        Text(formattedDate(entry.createdAt))
                            .font(.system(size: 10))
                            .foregroundColor(MuxTheme.textSecondary.opacity(0.7))
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
            }
            .buttonStyle(.plain)
            .padding(10)

            // Expanded detail
            if isExpanded && hasSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(MuxTheme.border)

                    if let summary = entry.summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let tags = entry.tags, !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(MuxTheme.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(MuxTheme.orange.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Asset ID
                    HStack(spacing: 4) {
                        Text("ASSET")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundColor(MuxTheme.textSecondary)
                        Text(entry.assetId)
                            .font(MuxTheme.mono(size: 10))
                            .foregroundColor(MuxTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

// MARK: - Flow Layout for tags

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
