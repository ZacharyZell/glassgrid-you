import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

/// Dark-HUD Liquid Glass popover for on-demand YouTube transcripts with Follow Playback,
/// instant search, 1-click cue bookmarking, Obsidian Markdown export, and AI study packet copy.
struct TranscriptPopoverView: View {
    let transcript: YouTubeTranscript?
    let isLoading: Bool
    let currentTime: Double
    let onRefresh: () -> Void
    let onSeek: (Double) -> Void
    var videoTitle: String = ""
    var videoID: String = ""
    var urlString: String? = nil
    var bookmarks: [VideoBookmark] = []
    var chapters: [VideoChapter] = []
    var noteMarkdown: String = ""
    var onBookmarkCue: ((TranscriptCue) -> Void)? = nil

    @State private var searchQuery = ""
    @State private var followPlayback = true
    @State private var copiedPlainFeedback = false
    @State private var copiedStudyPacketFeedback = false
    @State private var bookmarkedCueID: Int?

    private var filteredCues: [TranscriptCue] {
        transcript?.matching(query: searchQuery) ?? []
    }

    private var activeCueID: Int? {
        guard let cues = transcript?.cues, !cues.isEmpty else { return nil }
        if let exact = cues.first(where: { cue in
            let nextBoundary = cue.startSeconds + max(cue.durationSeconds, 4.0)
            return currentTime >= cue.startSeconds && currentTime < nextBoundary
        }) {
            return exact.id
        }
        return cues.last(where: { $0.startSeconds <= currentTime })?.id
    }

    private var resolvedTitle: String {
        let trimmed = videoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let transcriptTitle = transcript?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !transcriptTitle.isEmpty {
            return transcriptTitle
        }
        return "YouTube Video"
    }

    private var resolvedVideoID: String {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (transcript?.videoID ?? "") : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "captions.bubble")
                    .font(AppIconFont.toolbar(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)

                Text("Transcript")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.primary)

                if let transcript, !transcript.cues.isEmpty {
                    Text("\(transcript.cues.count)")
                        .font(AppFont.micro(weight: .semibold, tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(Color.primary.opacity(0.10), in: Capsule(style: .continuous))
                }

                Spacer()

                Button {
                    followPlayback.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: followPlayback ? "scope" : "pause.circle")
                            .font(AppIconFont.xs(weight: .semibold))
                        Text("Follow")
                            .font(AppFont.micro(weight: .semibold))
                    }
                    .foregroundStyle(followPlayback ? AppleTheme.accentText : AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .minHitTarget(24, shape: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(followPlayback ? AppleTheme.accentText.opacity(0.16) : Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Follow Playback — Auto-scroll transcript to current video timestamp")

                Button {
                    copyTranscript()
                } label: {
                    Image(systemName: copiedPlainFeedback ? "checkmark" : "doc.on.doc")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(copiedPlainFeedback ? AppleTheme.positive : .primary.opacity(0.84))
                        .minHitTarget(24, shape: Circle())
                }
                .buttonStyle(.plain)
                .disabled(transcript?.cues.isEmpty ?? true)
                .help("Copy Transcript Plain Text")

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.84))
                        .minHitTarget(24, shape: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help("Refresh Transcript")
            }

            // Search bar
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppIconFont.sm(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)

                TextField("Search transcript…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppFont.callout)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppIconFont.sm)
                            .foregroundStyle(AppleTheme.textMuted)
                            .minHitTarget(24, shape: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: 28)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            Divider()

            if isLoading {
                VStack(spacing: AppSpacing.md) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading captions on demand…")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else if filteredCues.isEmpty {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "captions.bubble")
                        .font(AppIconFont.lg(weight: .medium))
                        .foregroundStyle(AppleTheme.textMuted)
                    Text(transcript == nil || transcript?.cues.isEmpty == true
                         ? "No captions available for this video."
                         : "No transcript lines match \"\(searchQuery)\".")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    if transcript == nil || transcript?.cues.isEmpty == true {
                        Button("Try Reading Captions") {
                            onRefresh()
                        }
                        .font(AppFont.caption(weight: .semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(filteredCues) { cue in
                                let isCurrent = activeCueID == cue.id
                                let isJustBookmarked = bookmarkedCueID == cue.id
                                HStack(alignment: .top, spacing: AppSpacing.xs) {
                                    Button {
                                        onSeek(cue.startSeconds)
                                    } label: {
                                        HStack(alignment: .top, spacing: AppSpacing.md) {
                                            Text(cue.formattedTimestamp)
                                                .font(AppFont.caption(weight: .semibold, tabular: true))
                                                .foregroundStyle(isCurrent ? AppleTheme.accentText : AppleTheme.textSecondary)
                                                .frame(width: 48, alignment: .leading)

                                            Text(cue.text)
                                                .font(AppFont.callout(weight: isCurrent ? .medium : .regular))
                                                .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.88))
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.vertical, AppSpacing.sm)
                                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    if let onBookmarkCue {
                                        Button {
                                            onBookmarkCue(cue)
                                            bookmarkedCueID = cue.id
                                            Task { @MainActor in
                                                try? await Task.sleep(for: .milliseconds(1200))
                                                if bookmarkedCueID == cue.id {
                                                    bookmarkedCueID = nil
                                                }
                                            }
                                        } label: {
                                            Image(systemName: isJustBookmarked ? "bookmark.fill" : "bookmark")
                                                .font(AppIconFont.xs(weight: .semibold))
                                                .foregroundStyle(isJustBookmarked ? AppleTheme.positive : AppleTheme.textSecondary)
                                                .minHitTarget(24, shape: Circle())
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, AppSpacing.xxs)
                                        .padding(.trailing, AppSpacing.xs)
                                        .help("Bookmark Cue at \(cue.formattedTimestamp)")
                                    }
                                }
                                .id(cue.id)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .fill(isCurrent ? AppleTheme.accentText.opacity(0.16) : Color.primary.opacity(0.04))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .onChange(of: activeCueID) { _, newCueID in
                        guard followPlayback,
                              searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let newCueID else {
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newCueID, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Export & AI Study Packet Footer
            HStack(spacing: AppSpacing.sm) {
                Button {
                    exportMarkdownFile()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppIconFont.xs(weight: .semibold))
                        Text("Export Markdown (.md)…")
                            .font(AppFont.caption(weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(26, shape: Capsule(style: .continuous))
                    .background(Color.primary.opacity(0.09), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(transcript?.cues.isEmpty ?? true && bookmarks.isEmpty && noteMarkdown.isEmpty)

                Spacer(minLength: AppSpacing.xs)

                Button {
                    copyAIStudyPacket()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: copiedStudyPacketFeedback ? "checkmark" : "sparkles")
                            .font(AppIconFont.xs(weight: .semibold))
                        Text(copiedStudyPacketFeedback ? "Copied Packet" : "Copy AI Study Packet")
                            .font(AppFont.caption(weight: .semibold))
                    }
                    .foregroundStyle(copiedStudyPacketFeedback ? AppleTheme.positive : AppleTheme.accentText)
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(26, shape: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(copiedStudyPacketFeedback ? AppleTheme.positive.opacity(0.16) : AppleTheme.accentText.opacity(0.14))
                    )
                }
                .buttonStyle(.plain)
                .disabled(transcript?.cues.isEmpty ?? true && bookmarks.isEmpty && chapters.isEmpty)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 360)
        .background(DarkPopoverAppearanceSyncView())
        .foregroundStyle(Color.primary)
        .preferredColorScheme(.dark)
        .environment(\.font, AppFont.body)
    }

    private func copyTranscript() {
        guard let transcript, !transcript.cues.isEmpty else { return }
        let text = transcript.formattedPlainText()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copiedPlainFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            copiedPlainFeedback = false
        }
    }

    private func copyAIStudyPacket() {
        let packet = TranscriptMarkdownExporter.formatAIStudyPacket(
            title: resolvedTitle,
            videoID: resolvedVideoID,
            urlString: urlString,
            transcript: transcript,
            bookmarks: bookmarks,
            chapters: chapters
        )
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(packet, forType: .string)
        copiedStudyPacketFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            copiedStudyPacketFeedback = false
        }
    }

    private func exportMarkdownFile() {
        let markdown = TranscriptMarkdownExporter.exportMarkdown(
            title: resolvedTitle,
            videoID: resolvedVideoID,
            urlString: urlString,
            transcript: transcript,
            bookmarks: bookmarks,
            chapters: chapters,
            noteMarkdown: noteMarkdown
        )
        let safePrefix = resolvedTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = safePrefix.isEmpty ? "YouTube-Transcript" : String(safePrefix.prefix(48))

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(baseName).md"
        panel.title = "Export Transcript & Notes"
        panel.message = "Save Obsidian-ready Markdown with frontmatter, bookmarks, chapters, and transcript."
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        try? markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
    }
}
