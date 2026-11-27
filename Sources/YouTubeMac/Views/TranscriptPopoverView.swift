import AppKit
import SwiftUI
import YouTubeMacCore

/// Dark-HUD Liquid Glass popover for on-demand YouTube transcripts with instant search & click-to-seek cues.
struct TranscriptPopoverView: View {
    let transcript: YouTubeTranscript?
    let isLoading: Bool
    let currentTime: Double
    let onRefresh: () -> Void
    let onSeek: (Double) -> Void

    @State private var searchQuery = ""
    @State private var copiedFeedback = false

    private var filteredCues: [TranscriptCue] {
        transcript?.matching(query: searchQuery) ?? []
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
                    copyTranscript()
                } label: {
                    Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(copiedFeedback ? AppleTheme.positive : .primary.opacity(0.84))
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
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ForEach(filteredCues) { cue in
                            let nextBoundary = cue.startSeconds + max(cue.durationSeconds, 4.0)
                            let isCurrent = currentTime >= cue.startSeconds && currentTime < nextBoundary
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
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .fill(isCurrent ? AppleTheme.accentText.opacity(0.16) : Color.primary.opacity(0.04))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 340)
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
        copiedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            copiedFeedback = false
        }
    }
}
