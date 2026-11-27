import SwiftUI
import YouTubeMacCore

/// Dark-HUD Liquid Glass popover for creating, browsing, and jumping to saved timestamped video bookmarks (`⌘⇧K`).
struct BookmarksPopoverView: View {
    let bookmarks: [VideoBookmark]
    let currentVideoTitle: String
    let currentTime: Double
    let hasVideo: Bool
    let onAddBookmark: (String) -> Void
    let onJump: (VideoBookmark) -> Void
    let onDelete: (UUID) -> Void

    @State private var noteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "bookmark.fill")
                    .font(AppIconFont.toolbar(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)

                Text("Timestamp Bookmarks")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("⌘⇧K")
                    .font(AppFont.micro(weight: .medium, tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
            }

            // Quick add at current playback time
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                if hasVideo {
                    Text(currentVideoTitle)
                        .font(AppFont.caption(weight: .medium))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: AppSpacing.sm) {
                    TextField("Add note (optional)…", text: $noteText)
                        .textFieldStyle(.roundedBorder)
                        .font(AppFont.callout)
                        .disabled(!hasVideo)
                        .onSubmit {
                            submitBookmark()
                        }

                    Button {
                        submitBookmark()
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "plus")
                                .font(AppIconFont.xs(weight: .bold))
                            Text(hasVideo ? MediaState.formatTime(currentTime) : "Add")
                                .font(AppFont.caption(weight: .semibold, tabular: true))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.md)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                        .background(
                            Capsule(style: .continuous)
                                .fill(hasVideo ? AppleTheme.accentFill : Color.primary.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasVideo)
                    .help("Save bookmark at current timestamp (⌘⇧K)")
                }
            }

            Divider()

            if bookmarks.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "bookmark")
                        .font(AppIconFont.lg(weight: .medium))
                        .foregroundStyle(AppleTheme.textMuted)
                    Text("No saved bookmarks yet. Press ⌘⇧K while watching to save a timestamp.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: AppSpacing.xs) {
                        ForEach(bookmarks) { bookmark in
                            HStack(spacing: AppSpacing.sm) {
                                Button {
                                    onJump(bookmark)
                                } label: {
                                    HStack(spacing: AppSpacing.md) {
                                        Text(bookmark.formattedTimestamp)
                                            .font(AppFont.micro(weight: .bold, tabular: true))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, AppSpacing.sm)
                                            .padding(.vertical, AppSpacing.xs)
                                            .background(AppleTheme.accentFill, in: Capsule(style: .continuous))

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(bookmark.title)
                                                .font(AppFont.callout(weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)

                                            if !bookmark.note.isEmpty {
                                                Text(bookmark.note)
                                                    .font(AppFont.caption)
                                                    .foregroundStyle(AppleTheme.textSecondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }

                                        Spacer(minLength: AppSpacing.xs)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onDelete(bookmark.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(AppIconFont.xs(weight: .medium))
                                        .foregroundStyle(AppleTheme.textSecondary)
                                        .minHitTarget(24, shape: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Delete Bookmark")
                            }
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 340)
        .background(DarkPopoverAppearanceSyncView())
        .foregroundStyle(Color.primary)
        .preferredColorScheme(.dark)
        .environment(\.font, AppFont.body)
    }

    private func submitBookmark() {
        guard hasVideo else { return }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        onAddBookmark(trimmed)
        noteText = ""
    }
}
