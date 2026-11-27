import AppKit
import SwiftUI
import YouTubeMacCore

/// Isolated subview observing `PlaybackTimeline` so per-second updates only re-render the progress bar.
/// Supports smooth 60fps interactive dragging with >= 150ms throttled `seek(to:)` dispatch (never per-pixel JS),
/// and remains cleanly non-scrubbable on live streams (`duration <= 0` or `>= 86400`).
private struct MenuBarTimelineView: View {
    let timeline: PlaybackTimeline
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var lastSeekDispatchAt: Date = .distantPast
    @State private var isHovered = false

    private var isScrubbable: Bool {
        timeline.duration.isFinite && timeline.duration > 0 && timeline.duration < 86400
    }

    private var displayedFraction: Double {
        if let dragFraction {
            return dragFraction
        }
        return timeline.progressFraction
    }

    private var displayedTime: Double {
        if let dragFraction, isScrubbable {
            return dragFraction * timeline.duration
        }
        return timeline.currentTime
    }

    var body: some View {
        if isScrubbable {
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    let width = max(1, proxy.size.width)
                    let filledWidth = width * min(max(displayedFraction, 0), 1)
                    let trackHeight: CGFloat = (isHovered || dragFraction != nil) ? 5.5 : 4.0

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.14))
                            .frame(height: trackHeight)

                        Capsule(style: .continuous)
                            .fill(AppleTheme.accentFill)
                            .frame(width: filledWidth, height: trackHeight)

                        if isHovered || dragFraction != nil {
                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                                .overlay(Circle().strokeBorder(AppleTheme.accentFill, lineWidth: 1.5))
                                .frame(width: 11, height: 11)
                                .offset(x: min(max(0, filledWidth - 5.5), width - 11))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = min(max(Double(value.location.x / width), 0), 1)
                                dragFraction = fraction
                                let now = Date()
                                if now.timeIntervalSince(lastSeekDispatchAt) >= 0.15 {
                                    lastSeekDispatchAt = now
                                    onSeek(fraction * timeline.duration)
                                }
                            }
                            .onEnded { value in
                                let fraction = min(max(Double(value.location.x / width), 0), 1)
                                lastSeekDispatchAt = Date()
                                onSeek(fraction * timeline.duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 14)
                .onHover { isHovered = $0 }

                HStack {
                    Text(MediaState.formatTime(displayedTime))
                    Spacer()
                    Text(MediaState.formatTime(timeline.duration))
                }
                .font(AppFont.caption(tabular: true))
                .foregroundStyle(AppleTheme.textSecondary)
            }
            .padding(.top, AppSpacing.xxs)
        } else {
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(AppleTheme.accentFill)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(AppFont.micro(weight: .bold))
                    .foregroundStyle(AppleTheme.textSecondary)
                Spacer()
            }
            .padding(.top, AppSpacing.xxs)
        }
    }
}

private struct MenuBarActionRow: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: systemImage)
                    .font(AppIconFont.md(weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isActive ? AppleTheme.accentText : AppleTheme.textSecondary)
                Text(title)
                    .font(AppFont.callout(weight: isActive ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Apple Control Center & Liquid Glass menu bar Now Playing popover with multi-window transport & window controls.
struct MenuBarView: View {
    @Bindable var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var isSettingsHovered = false
    @State private var isQuitHovered = false

    var body: some View {
        Group {
            if let controller = coordinator.nowPlayingController {
                MenuBarActiveControllerView(coordinator: coordinator, controller: controller)
            } else {
                emptyWindowsPopover
            }
        }
        .task {
            coordinator.openWindowHandler = { id in
                openWindow(id: "main", value: id)
            }
        }
    }

    @ViewBuilder
    private var emptyWindowsPopover: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.md) {
                BrandMarkBadge(size: 32, cornerRadius: AppRadius.md)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("GlassGrid You")
                        .font(AppFont.body(weight: .semibold))
                    Text("No open windows")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                Spacer()
            }

            Divider()
                .opacity(0.6)

            VStack(spacing: AppSpacing.xxs) {
                MenuBarActionRow(title: "New GlassGrid You Window", systemImage: "macwindow.badge.plus") {
                    coordinator.openNewWindow()
                }
                MenuBarActionRow(title: "Open Copied YouTube URL", systemImage: "link.badge.plus") {
                    coordinator.openURLFromClipboard()
                }
            }

            Divider()
                .opacity(0.6)

            HStack {
                SettingsLink {
                    Text("Settings…")
                        .font(AppFont.callout(weight: .medium))
                        .foregroundStyle(isSettingsHovered ? Color.primary : AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSettingsHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule(style: .continuous))
                .onHover { isSettingsHovered = $0 }

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit GlassGrid You")
                        .font(AppFont.callout(weight: .medium))
                        .foregroundStyle(isQuitHovered ? Color.primary : AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                        .background(
                            Capsule(style: .continuous)
                                .fill(isQuitHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule(style: .continuous))
                .onHover { isQuitHovered = $0 }
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 318)
    }
}

private struct MenuBarActiveControllerView: View {
    @Bindable var coordinator: AppCoordinator
    @Bindable var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSettingsHovered = false
    @State private var isQuitHovered = false
    @State private var isChaptersExpanded = false
    @State private var isTranscriptExpanded = false

    private var nowPlaying: MediaStatus {
        controller.nowPlayingStatus
    }

    private var isResolvedDark: Bool {
        switch controller.settings.appearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var nowPlayingVideoID: String? {
        guard nowPlaying.hasVideo,
              let tab = controller.activeMediaTab,
              !YouTubeURLRouter.isYouTubeTVHost(tab.url.host) else {
            return nil
        }
        return YouTubeURLRouter.extractVideoID(from: tab.url)
    }

    private var nowPlayingFallbackThumbnailURL: URL? {
        guard let videoID = nowPlayingVideoID else {
            return nil
        }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
    }

    private var nowPlayingThumbnailURL: URL? {
        guard let fallbackURL = nowPlayingFallbackThumbnailURL else {
            return nil
        }
        return controller.effectiveThumbnailURL(for: controller.activeMediaTab?.url, fallback: fallbackURL)
    }

    private var nowPlayingBrandingTaskID: String {
        "\(nowPlayingVideoID ?? "")-\(controller.settings.deArrowEnabled)-\(controller.settings.deArrowThumbnailsEnabled)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            nowPlayingSection

            transportControls

            if controller.isMultiviewActive {
                multiviewAudioSwitcher
            }

            if controller.activeChapters.count >= 2 {
                chaptersSection
            }

            if isTranscriptExpanded {
                transcriptSection
            }

            Divider()
                .opacity(0.6)

            quickActionsSection

            Divider()
                .opacity(0.6)

            footerRow
        }
        .padding(14)
        .frame(width: 318)
    }

    @ViewBuilder
    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                if let thumbURL = nowPlayingThumbnailURL {
                    ZStack(alignment: .bottomTrailing) {
                        CachedThumbnailImage(
                            url: thumbURL,
                            fallbackURL: nowPlayingFallbackThumbnailURL,
                            placeholderIconSize: 16
                        )
                            .frame(width: 64, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
                            )

                        if nowPlaying.isPlaying {
                            Image(systemName: "waveform")
                                .font(AppIconFont.xs(weight: .bold))
                                .foregroundStyle(.white)
                                .padding(AppSpacing.xxs)
                                .background(AppleTheme.accentFill, in: Circle())
                                .padding(AppSpacing.xxs)
                        }
                    }
                    .frame(width: 64, height: 36)
                } else if nowPlaying.hasVideo {
                    BrandMarkBadge(size: 32, cornerRadius: AppRadius.md)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 32, height: 32)

                        Image(systemName: "play.fill")
                            .font(AppIconFont.nav(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if nowPlaying.hasVideo, let activeTab = controller.activeMediaTab {
                Text(controller.effectiveTitle(for: activeTab))
                    .font(AppFont.body(weight: .semibold))
                    .lineLimit(2)
            } else {
                Text(nowPlaying.title.isEmpty ? "YouTube" : nowPlaying.title)
                    .font(AppFont.body(weight: .semibold))
                    .lineLimit(2)
            }

                    HStack(spacing: AppSpacing.sm) {
                        Text(
                            nowPlaying.channel.isEmpty
                                ? (nowPlaying.hasVideo ? "Ready to play" : "No video playing")
                                : nowPlaying.channel
                        )
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)

                        if nowPlaying.isHDR {
                            AppleHDRBadge()
                        }

                        if let rateText = nowPlaying.formattedPlaybackRate {
                            AppleSpeedBadge(rateText: rateText)
                        }
                    }
                }
            }

            if nowPlaying.hasVideo, let timeline = controller.activeTimeline {
                MenuBarTimelineView(timeline: timeline) { targetSeconds in
                    controller.seek(to: targetSeconds)
                }
            }

            if let sleepOption = controller.sleepTimerOption {
                sleepTimerCountdownPill(option: sleepOption)
            }
        }
        .task(id: nowPlayingBrandingTaskID) {
            if let videoID = nowPlayingVideoID {
                controller.ensureDeArrowBrandingLoaded(forVideoID: videoID)
            }
        }
    }

    @ViewBuilder
    private var multiviewAudioSwitcher: some View {
        LiquidGlassGroup(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)

                ForEach(Array(controller.multiviewTabs.enumerated()), id: \.element.id) { index, tab in
                    let isAudio = controller.multiviewAudioTab?.id == tab.id
                    Button {
                        controller.focusMultiviewAudio(tabID: tab.id, showFeedback: false)
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Text("\(index + 1)")
                                .font(AppFont.micro(weight: .bold, tabular: true))
                            Image(systemName: isAudio && !tab.mediaStatus.isMuted ? "waveform" : "speaker.slash.fill")
                                .font(AppIconFont.xs(weight: .semibold))
                        }
                        .foregroundStyle(isAudio ? .white : Color.primary.opacity(0.84))
                        .padding(.horizontal, AppSpacing.md)
                        .frame(height: 24)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isAudio ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Stream \(index + 1): \(tab.displayTitle)")
                }

                Spacer(minLength: AppSpacing.xs)

                if controller.isFloatingMultiviewGrid {
                    Text("Floating")
                        .font(AppFont.micro(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.sm)
                        .frame(height: 24)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppleTheme.accentText.opacity(0.14))
                        )
                }

                Button {
                    controller.muteAllMultiviewTiles()
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Mute All Multiview Streams")
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .appleGlass(in: Capsule(style: .continuous), interactive: true)
        }
    }

    @ViewBuilder
    private func sleepTimerCountdownPill(option: SleepTimerOption) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "moon.zzz.fill")
                .font(AppIconFont.sm(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)

            if let endDate = controller.sleepTimerEndDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endDate.timeIntervalSince(context.date))
                    Text("Sleep in \(SleepTimerOption.formatRemaining(remaining))")
                        .font(AppFont.caption(weight: .medium, tabular: true))
                        .foregroundStyle(.primary)
                }
            } else {
                Text("Sleep at \(option.shortTitle)")
                    .font(AppFont.caption(weight: .medium, tabular: true))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                controller.setSleepTimer(nil)
            } label: {
                Text("Cancel")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                    .padding(.horizontal, AppSpacing.sm)
                    .minHitTarget(24, shape: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accentText.opacity(0.12))
    }

    @ViewBuilder
    private var chaptersSection: some View {
        let chapters = controller.activeChapters
        let activeChapter = controller.activeTimeline.flatMap {
            VideoChapterParser.activeChapter(at: $0.currentTime, in: chapters)
        }

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    isChaptersExpanded.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "list.bullet.indent")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                    Text("Chapters (\(chapters.count))")
                        .font(AppFont.callout(weight: .semibold, tabular: true))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isChaptersExpanded ? "chevron.up" : "chevron.down")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            if isChaptersExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        ForEach(chapters) { chapter in
                            let isCurrent = activeChapter?.id == chapter.id
                            Button {
                                controller.seek(to: chapter.startSeconds)
                            } label: {
                                HStack(spacing: AppSpacing.md) {
                                    Text(chapter.formattedStartTime)
                                        .font(AppFont.caption(weight: .semibold, tabular: true))
                                        .foregroundStyle(isCurrent ? AppleTheme.accentText : AppleTheme.textSecondary)
                                        .frame(width: 44, alignment: .leading)

                                    Text(chapter.title)
                                        .font(AppFont.callout(weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.84))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.xs)
                                .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(isCurrent ? AppleTheme.accentText.opacity(0.12) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "captions.bubble")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                Text("Transcript")
                    .font(AppFont.callout(weight: .semibold))
                Spacer()
                if controller.isFetchingTranscript {
                    ProgressView()
                        .controlSize(.mini)
                } else if let cues = controller.currentTranscript?.cues, !cues.isEmpty {
                    Button("Copy") {
                        if let text = controller.currentTranscript?.formattedPlainText() {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(text, forType: .string)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(AppleTheme.accentText)
                    .minHitTarget(24)
                }
            }

            if let cues = controller.currentTranscript?.cues, !cues.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        ForEach(cues.prefix(80)) { cue in
                            Button {
                                controller.seek(to: cue.startSeconds)
                            } label: {
                                HStack(alignment: .top, spacing: AppSpacing.sm) {
                                    Text(cue.formattedTimestamp)
                                        .font(AppFont.caption(weight: .semibold, tabular: true))
                                        .foregroundStyle(AppleTheme.accentText)
                                        .frame(width: 44, alignment: .leading)
                                    Text(cue.text)
                                        .font(AppFont.caption)
                                        .foregroundStyle(.primary.opacity(0.88))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xs)
                                .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            } else if !controller.isFetchingTranscript {
                Text("No captions found for the active video.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var transportControls: some View {
        LiquidGlassGroup(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xxs) {
                    AppleIconButton(
                        systemImage: "gobackward.10",
                        isDisabled: !nowPlaying.hasVideo,
                        helpText: "Rewind 10s"
                    ) {
                        controller.seek(by: -10)
                    }

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(AppIconFont.toolbar(weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 28)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(nowPlaying.hasVideo ? AppleTheme.accentFill : Color.primary.opacity(0.18))
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!nowPlaying.hasVideo)
                    .help("Play / Pause")

                    AppleIconButton(
                        systemImage: "goforward.10",
                        isDisabled: !nowPlaying.hasVideo,
                        helpText: "Forward 10s"
                    ) {
                        controller.seek(by: 10)
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
                .frame(height: 34)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)

                Spacer()

                HStack(spacing: AppSpacing.xxs) {
                    AppleIconButton(
                        systemImage: nowPlaying.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        isActive: nowPlaying.isMuted,
                        isDisabled: !nowPlaying.hasVideo,
                        helpText: "Mute / Unmute"
                    ) {
                        controller.toggleMute()
                    }

                    AppleIconButton(
                        systemImage: nowPlaying.isPiP ? "pip.exit" : "pip.enter",
                        isActive: nowPlaying.isPiP,
                        isDisabled: !nowPlaying.hasVideo,
                        helpText: "Picture in Picture"
                    ) {
                        controller.togglePictureInPicture()
                    }

                    AppleIconButton(
                        systemImage: controller.isMiniPlayer ? "arrow.down.right.and.arrow.up.left" : "rectangle.inset.bottomright.filled",
                        isActive: controller.isMiniPlayer,
                        isDisabled: !controller.isMiniPlayer && !controller.canPopOutActiveContent,
                        helpText: controller.isMiniPlayer
                            ? (controller.isFloatingMultiviewGrid ? "Return Floating Grid to Window" : "Return to Full Window")
                            : (controller.isMultiviewActive ? "Float Multiview Grid" : "Mini-Player")
                    ) {
                        if controller.isMiniPlayer {
                            openOrFocusMainWindow()
                            controller.dockMiniPlayer(selectTab: true, focusMain: true)
                        } else {
                            controller.toggleMiniPlayer()
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
                .frame(height: 34)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)
            }
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(spacing: 2) {
            MenuBarActionRow(
                title: controller.isMainWindowVisible ? "Hide GlassGrid You Window" : "Show GlassGrid You Window",
                systemImage: controller.isMainWindowVisible ? "minus.rectangle" : "macwindow"
            ) {
                if controller.isMainWindowVisible {
                    controller.hideMainWindow()
                } else {
                    openOrFocusMainWindow()
                }
            }

            MenuBarActionRow(
                title: "New Window",
                systemImage: "macwindow.badge.plus"
            ) {
                coordinator.openNewWindow()
            }

            if coordinator.hasMultipleWindows {
                MenuBarActionRow(
                    title: "Bring All Windows to Front",
                    systemImage: "macwindow.on.rectangle"
                ) {
                    coordinator.bringAllWindowsToFront()
                }
            }

            MenuBarActionRow(
                title: "Open Copied YouTube URL",
                systemImage: "link.badge.plus"
            ) {
                openOrFocusMainWindow()
                controller.openURLFromClipboard()
            }

            MenuBarActionRow(
                title: controller.alwaysOnTop ? "Always on Top: On" : "Always on Top",
                systemImage: controller.alwaysOnTop ? "pin.fill" : "pin",
                isActive: controller.alwaysOnTop
            ) {
                controller.toggleAlwaysOnTop()
            }

            MenuBarActionRow(
                title: controller.focusModeActive ? "Focus Mode: On" : "Focus Mode",
                systemImage: controller.focusModeActive ? "eye.slash.fill" : "sparkles",
                isActive: controller.focusModeActive
            ) {
                controller.toggleFocusMode()
            }

            if controller.isMiniPlayer {
                MenuBarActionRow(
                    title: coordinator.floatingMiniPlayer.isGhostMode ? "Ghost Mode: On (⌘⌥O)" : "Ghost Mode (⌘⌥O)",
                    systemImage: coordinator.floatingMiniPlayer.isGhostMode ? "eye.slash.fill" : "eye.slash",
                    isActive: coordinator.floatingMiniPlayer.isGhostMode
                ) {
                    _ = controller.toggleMiniPlayerGhostMode()
                }
            }

            if nowPlaying.hasVideo {
                MenuBarActionRow(
                    title: "Add Timestamp Bookmark (⌘⇧K)",
                    systemImage: "bookmark.badge.plus"
                ) {
                    _ = controller.addCurrentTimestampBookmark(note: "")
                }

                MenuBarActionRow(
                    title: isTranscriptExpanded ? "Hide Transcript" : "Transcripts",
                    systemImage: "captions.bubble",
                    isActive: isTranscriptExpanded
                ) {
                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                        isTranscriptExpanded.toggle()
                    }
                    if isTranscriptExpanded {
                        Task { @MainActor in
                            _ = await controller.fetchCurrentTabTranscript()
                        }
                    }
                }
            }

            MenuBarActionRow(
                title: controller.isAirPlayActive ? "AirPlay Active — Manage…" : "Stream to AirPlay & TV Displays…",
                systemImage: "airplayvideo",
                isActive: controller.isAirPlayActive
            ) {
                controller.focusMainWindow()
                controller.openAirPlayPopover()
            }

            MenuBarActionRow(
                title: isResolvedDark ? "Night Mode (Switch to Day)" : "Day Mode (Switch to Night)",
                systemImage: isResolvedDark ? "moon" : "sun.max"
            ) {
                controller.toggleDayNightMode(currentColorScheme: colorScheme)
            }

            Menu {
                ForEach(SleepTimerOption.allCases) { option in
                    Button {
                        controller.setSleepTimer(option)
                    } label: {
                        if controller.sleepTimerOption == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
                if controller.isSleepTimerActive {
                    Divider()
                    Button("Turn Off Sleep Timer") {
                        controller.setSleepTimer(nil)
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: controller.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(AppIconFont.md(weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(controller.isSleepTimerActive ? AppleTheme.accentText : AppleTheme.textSecondary)
                    Text(controller.sleepTimerOption.map { "Sleep Timer: \($0.shortTitle)" } ?? "Sleep Timer…")
                        .font(AppFont.callout(weight: controller.isSleepTimerActive ? .medium : .regular, tabular: true))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.textMuted)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        HStack {
            SettingsLink {
                Text("Settings…")
                    .font(AppFont.callout(weight: .medium))
                    .foregroundStyle(isSettingsHovered ? Color.primary : AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(24, shape: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSettingsHovered ? Color.primary.opacity(0.08) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule(style: .continuous))
            .onHover { isSettingsHovered = $0 }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit GlassGrid You")
                    .font(AppFont.callout(weight: .medium))
                    .foregroundStyle(isQuitHovered ? Color.primary : AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(24, shape: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isQuitHovered ? Color.primary.opacity(0.08) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule(style: .continuous))
            .onHover { isQuitHovered = $0 }
        }
    }

    private func openOrFocusMainWindow() {
        if controller.mainWindow == nil {
            coordinator.openNewWindow()
        } else {
            controller.focusMainWindow()
        }
    }
}
