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
                            .fill(AppleTheme.accent)
                            .frame(width: filledWidth, height: trackHeight)

                        if isHovered || dragFraction != nil {
                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                                .overlay(Circle().strokeBorder(AppleTheme.accent, lineWidth: 1.5))
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
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 5) {
                Circle()
                    .fill(AppleTheme.accent)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)
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
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isActive ? AppleTheme.accent : .secondary)
                Text(title)
                    .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppleTheme.accent.opacity(0.14))
                    .frame(width: 44, height: 32)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppleTheme.accent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("GlassGrid You")
                        .font(.system(size: 13, weight: .semibold))
                    Text("No open windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()
                .opacity(0.6)

            VStack(spacing: 2) {
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSettingsHovered ? Color.primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSettingsHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isSettingsHovered = $0 }

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit GlassGrid You")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isQuitHovered ? Color.primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isQuitHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isQuitHovered = $0 }
            }
        }
        .padding(14)
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

    private var nowPlayingThumbnailURL: URL? {
        guard nowPlaying.hasVideo,
              let tab = controller.activeMediaTab,
              !YouTubeURLRouter.isYouTubeTVHost(tab.url.host),
              let videoID = YouTubeURLRouter.extractVideoID(from: tab.url) else {
            return nil
        }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let thumbURL = nowPlayingThumbnailURL {
                    ZStack(alignment: .bottomTrailing) {
                        CachedThumbnailImage(url: thumbURL, placeholderIconSize: 16)
                            .frame(width: 64, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
                            )

                        if nowPlaying.isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(AppleTheme.accent, in: Circle())
                                .padding(3)
                        }
                    }
                    .frame(width: 64, height: 36)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                nowPlaying.hasVideo
                                    ? LinearGradient(
                                        colors: [
                                            Color(red: 1.0, green: 0.24, blue: 0.26),
                                            Color(red: 0.82, green: 0.06, blue: 0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    : LinearGradient(
                                        colors: [Color.primary.opacity(0.12), Color.primary.opacity(0.08)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                            .frame(width: 38, height: 38)

                        Image(systemName: nowPlaying.isPlaying ? "waveform" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(nowPlaying.hasVideo ? .white : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title.isEmpty ? "YouTube" : nowPlaying.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(
                            nowPlaying.channel.isEmpty
                                ? (nowPlaying.hasVideo ? "Ready to play" : "No video playing")
                                : nowPlaying.channel
                        )
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private var multiviewAudioSwitcher: some View {
        LiquidGlassGroup(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)

                ForEach(Array(controller.multiviewTabs.enumerated()), id: \.element.id) { index, tab in
                    let isAudio = controller.multiviewAudioTab?.id == tab.id
                    Button {
                        controller.focusMultiviewAudio(tabID: tab.id, showFeedback: false)
                    } label: {
                        HStack(spacing: 3.5) {
                            Text("\(index + 1)")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                            Image(systemName: isAudio && !tab.mediaStatus.isMuted ? "waveform" : "speaker.slash.fill")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(isAudio ? .white : Color.primary.opacity(0.8))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isAudio ? AppleTheme.accent : Color.primary.opacity(0.08))
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Stream \(index + 1): \(tab.displayTitle)")
                }

                Spacer(minLength: 4)

                if controller.isFloatingMultiviewGrid {
                    Text("Floating")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppleTheme.accent)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppleTheme.accent.opacity(0.14))
                        )
                }

                Button {
                    controller.muteAllMultiviewTiles()
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Mute All Multiview Streams")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .appleGlass(in: Capsule(style: .continuous), interactive: true)
        }
    }

    @ViewBuilder
    private func sleepTimerCountdownPill(option: SleepTimerOption) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppleTheme.accent)

            if let endDate = controller.sleepTimerEndDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endDate.timeIntervalSince(context.date))
                    Text("Sleep in \(SleepTimerOption.formatRemaining(remaining))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            } else {
                Text("Sleep at \(option.shortTitle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                controller.setSleepTimer(nil)
            } label: {
                Text("Cancel")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accent.opacity(0.12))
    }

    @ViewBuilder
    private var chaptersSection: some View {
        let chapters = controller.activeChapters
        let activeChapter = controller.activeTimeline.flatMap {
            VideoChapterParser.activeChapter(at: $0.currentTime, in: chapters)
        }

        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    isChaptersExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppleTheme.accent)
                    Text("Chapters (\(chapters.count))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isChaptersExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if isChaptersExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(chapters) { chapter in
                            let isCurrent = activeChapter?.id == chapter.id
                            Button {
                                controller.seek(to: chapter.startSeconds)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(chapter.formattedStartTime)
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(isCurrent ? AppleTheme.accent : .secondary)
                                        .frame(width: 42, alignment: .leading)

                                    Text(chapter.title)
                                        .font(.system(size: 11.5, weight: isCurrent ? .semibold : .regular))
                                        .foregroundStyle(isCurrent ? Color.primary : Color.primary.opacity(0.84))
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isCurrent ? AppleTheme.accent.opacity(0.12) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    private var transportControls: some View {
        LiquidGlassGroup(spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 28)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(nowPlaying.hasVideo ? AppleTheme.accent : Color.primary.opacity(0.18))
                            )
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
                .padding(.horizontal, 4)
                .frame(height: 34)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)

                Spacer()

                HStack(spacing: 2) {
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
                        systemImage: controller.isMiniPlayer ? "arrow.up.left.and.arrow.down.right" : "rectangle.inset.bottomright.filled",
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
                .padding(.horizontal, 4)
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
                systemImage: isResolvedDark ? "moon.fill" : "sun.max.fill"
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
                HStack(spacing: 9) {
                    Image(systemName: controller.isSleepTimerActive ? "moon.zzz.fill" : "moon.zzz")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(controller.isSleepTimerActive ? AppleTheme.accent : .secondary)
                    Text(controller.sleepTimerOption.map { "Sleep Timer: \($0.shortTitle)" } ?? "Sleep Timer…")
                        .font(.system(size: 12.5, weight: controller.isSleepTimerActive ? .medium : .regular))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSettingsHovered ? Color.primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSettingsHovered ? Color.primary.opacity(0.08) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isSettingsHovered = $0 }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit GlassGrid You")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isQuitHovered ? Color.primary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isQuitHovered ? Color.primary.opacity(0.08) : .clear)
                    )
            }
            .buttonStyle(.plain)
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
