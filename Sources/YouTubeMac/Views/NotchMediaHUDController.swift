import AppKit
import Observation
import SwiftUI
import YouTubeMacCore

/// Shared visual tint mapping for SponsorBlock & Point-of-Interest Highlight segments across timelines.
@MainActor
enum SponsorSegmentVisual {
    static func color(for segment: SponsorSegment) -> Color {
        color(for: segment.categoryEnum)
    }

    static func color(for category: SponsorSegmentCategory?) -> Color {
        switch category {
        case .sponsor:
            return Color.green
        case .selfpromo:
            return Color.yellow
        case .intro:
            return Color.cyan
        case .outro:
            return Color.blue
        case .interaction:
            return Color.purple
        case .musicOfftopic:
            return Color.orange
        case .poiHighlight:
            return AppleTheme.accentFill
        case nil:
            return Color.white.opacity(0.6)
        }
    }
}

@MainActor
@Observable
private final class NotchMediaHUDState {
    var status: MediaStatus = .empty
    var timeline: PlaybackTimeline?
    var scoreText: String?
    var thumbnailURL: URL?
    var sponsorSegments: [SponsorSegment] = []
    var multiviewSlotCount: Int = 0
    var activeMultiviewSlot: Int = 0
    var isMaskScoresEnabled: Bool = false
    var placement: NotchMediaHUDPlacement = NotchMediaHUDPlacement(frame: .zero, hasNotch: false, notchWidth: 0)
    var safeAreaTop: CGFloat = 0
    var isExpanded: Bool = false
    var isScrubbing: Bool = false
    var onTogglePlayPause: (() -> Void)?
    var onSeekBy: ((Double) -> Void)?
    var onSeekToTime: ((Double) -> Void)?
    var onSelectMultiviewSlot: ((Int) -> Void)?
    var onFocusWindow: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onScrubbingChanged: ((Bool) -> Void)?
}

/// AppKit tracking view wrapping the SwiftUI host inside `.nonactivatingPanel` so pointer exits
/// to other macOS apps always fire reliably even when GlassGrid You is inactive.
@MainActor
private final class NotchTrackingRootView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}

private struct NotchMediaHUDView: View {
    let state: NotchMediaHUDState

    @State private var dragFraction: Double?
    @State private var lastSeekDispatchAt: Date = .distantPast

    private var hasScore: Bool {
        guard let score = state.scoreText else { return false }
        return !score.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedScoreText: String? {
        guard hasScore else { return nil }
        return state.isMaskScoresEnabled ? "• - •" : state.scoreText
    }

    private var compactTitle: String {
        let raw = state.status.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Now Playing" : raw
    }

    private var topBandHeight: CGFloat {
        if state.placement.hasNotch {
            return max(NotchMediaHUDGeometry.minimumNotchHUDHeight, state.safeAreaTop.rounded())
        }
        return NotchMediaHUDGeometry.fallbackHeight
    }

    private var isScrubbable: Bool {
        guard let timeline = state.timeline else { return false }
        return timeline.duration.isFinite && timeline.duration > 0 && timeline.duration < 86_400
    }

    private var displayedFraction: Double {
        if let dragFraction {
            return dragFraction
        }
        return state.timeline?.progressFraction ?? 0
    }

    private var displayedTime: Double {
        if let dragFraction, let timeline = state.timeline, isScrubbable {
            return dragFraction * timeline.duration
        }
        return state.timeline?.currentTime ?? 0
    }

    var body: some View {
        Group {
            if state.placement.hasNotch {
                notchedContainer
            } else {
                floatingPillContainer
            }
        }
        .onHover { hovering in
            state.onHoverChanged?(hovering)
        }
    }

    @ViewBuilder
    private var notchedContainer: some View {
        let wingWidth = max(72, (state.placement.frame.width - state.placement.notchWidth) / 2.0)

        VStack(spacing: 0) {
            // Top hardware-notch-aligned wing band (center cutout stays strictly empty and non-interactive)
            HStack(spacing: 0) {
                Button {
                    state.onFocusWindow?()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: state.status.isPlaying ? "waveform" : "play.rectangle.fill")
                            .font(AppIconFont.xs(weight: .semibold))
                            .foregroundStyle(state.status.isPlaying ? AppleTheme.accentText : .white.opacity(0.84))

                        if let scoreText = displayedScoreText {
                            Text(scoreText)
                                .font(AppFont.micro(weight: .semibold, tabular: true))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(compactTitle)
                                .font(AppFont.caption(weight: .medium))
                                .foregroundStyle(.white.opacity(0.94))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .frame(width: wingWidth, height: topBandHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Focus GlassGrid You Window")

                Color.clear
                    .frame(width: state.placement.notchWidth, height: topBandHeight)
                    .allowsHitTesting(false)

                HStack(spacing: AppSpacing.xs) {
                    if let onSeekBy = state.onSeekBy, state.isExpanded {
                        Button {
                            onSeekBy(-10)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rewind 10s")
                    }

                    Button {
                        state.onTogglePlayPause?()
                    } label: {
                        Image(systemName: state.status.isPlaying ? "pause.fill" : "play.fill")
                            .font(AppIconFont.sm(weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(AppleTheme.accentFill))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(state.status.isPlaying ? "Pause" : "Play")

                    if let onSeekBy = state.onSeekBy, state.isExpanded {
                        Button {
                            onSeekBy(10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Forward 10s")
                    } else {
                        Button {
                            state.onFocusWindow?()
                        } label: {
                            Image(systemName: "macwindow")
                                .font(AppIconFont.xs(weight: .medium))
                                .foregroundStyle(.white.opacity(0.84))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Focus GlassGrid You Window")
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .frame(width: wingWidth, height: topBandHeight, alignment: .trailing)
            }
            .frame(width: state.placement.frame.width, height: topBandHeight)

            // Lower expanded band strictly below safeAreaTop (never beneath hardware camera notch)
            if state.isExpanded {
                expandedLowerBand(isDarkSurface: true)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: state.placement.frame.width, height: state.placement.frame.height, alignment: .top)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: AppRadius.xl,
                bottomTrailingRadius: AppRadius.xl,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.94))
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: AppRadius.xl,
                bottomTrailingRadius: AppRadius.xl,
                topTrailingRadius: 0,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var floatingPillContainer: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    state.onTogglePlayPause?()
                } label: {
                    Image(systemName: state.status.isPlaying ? "pause.fill" : "play.fill")
                        .font(AppIconFont.xs(weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppleTheme.accentFill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(state.status.isPlaying ? "Pause" : "Play")

                Button {
                    state.onFocusWindow?()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(compactTitle)
                            .font(AppFont.caption(weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let scoreText = displayedScoreText {
                            Text(scoreText)
                                .font(AppFont.micro(weight: .semibold, tabular: true))
                                .foregroundStyle(AppleTheme.accentText)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, AppSpacing.xxs)
                                .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))
                                .fixedSize()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .minHitTarget(24)
                }
                .buttonStyle(.plain)
                .help("Focus GlassGrid You Window")

                if let onSeekBy = state.onSeekBy, state.isExpanded {
                    HStack(spacing: AppSpacing.xxs) {
                        Button {
                            onSeekBy(-10)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(AppleTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Rewind 10s")

                        Button {
                            onSeekBy(10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(AppleTheme.textSecondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Forward 10s")
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: topBandHeight)

            if state.isExpanded {
                expandedLowerBand(isDarkSurface: false)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: state.placement.frame.width, height: state.placement.frame.height, alignment: .top)
        .appleGlass(
            in: RoundedRectangle(
                cornerRadius: state.isExpanded ? AppRadius.xl : (topBandHeight / 2.0),
                style: .continuous
            ),
            interactive: true
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    @ViewBuilder
    private func expandedLowerBand(isDarkSurface: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                CachedThumbnailImage(
                    url: state.thumbnailURL,
                    fallbackURL: nil,
                    placeholderIconSize: 14
                )
                .frame(width: 48, height: 27)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .strokeBorder(
                            isDarkSurface ? Color.white.opacity(0.16) : Color.primary.opacity(0.12),
                            lineWidth: 0.6
                        )
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(compactTitle)
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(isDarkSurface ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: AppSpacing.xs) {
                        if !state.status.channel.isEmpty {
                            Text(state.status.channel)
                                .font(AppFont.micro(weight: .medium))
                                .foregroundStyle(isDarkSurface ? Color.white.opacity(0.72) : AppleTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if let scoreText = displayedScoreText {
                            Text(scoreText)
                                .font(AppFont.micro(weight: .semibold, tabular: true))
                                .foregroundStyle(AppleTheme.accentText)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 1)
                                .background(AppleTheme.accentText.opacity(0.16), in: Capsule(style: .continuous))
                                .fixedSize()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if state.multiviewSlotCount >= 2 {
                    HStack(spacing: AppSpacing.xxs) {
                        ForEach(1...min(state.multiviewSlotCount, MultiviewGridLayout.maxTiles), id: \.self) { slot in
                            let isActive = slot == state.activeMultiviewSlot
                            Button {
                                state.onSelectMultiviewSlot?(slot)
                            } label: {
                                Text("\(slot)")
                                    .font(AppFont.micro(weight: .bold, tabular: true))
                                    .foregroundStyle(isActive ? .white : (isDarkSurface ? .white.opacity(0.84) : .primary))
                                    .frame(width: 22, height: 22)
                                    .background(
                                        Circle()
                                            .fill(
                                                isActive
                                                    ? AppleTheme.accentFill
                                                    : (isDarkSurface ? Color.white.opacity(0.14) : Color.primary.opacity(0.10))
                                            )
                                    )
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Focus Multiview Stream \(slot) Audio")
                        }
                    }
                }
            }

            if let timeline = state.timeline, isScrubbable {
                VStack(spacing: 3) {
                    GeometryReader { proxy in
                        let width = max(1, proxy.size.width)
                        let clampedFraction = min(max(displayedFraction, 0), 1)
                        let filledWidth = width * clampedFraction
                        let trackHeight: CGFloat = state.isScrubbing ? 6.0 : 4.5

                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(isDarkSurface ? Color.white.opacity(0.20) : Color.primary.opacity(0.15))
                                .frame(height: trackHeight)

                            ForEach(Array(state.sponsorSegments.enumerated()), id: \.offset) { _, segment in
                                if let range = segment.normalizedRange(duration: timeline.duration) {
                                    let segX = width * range.lowerBound
                                    let segW = max(3, width * (range.upperBound - range.lowerBound))
                                    Capsule(style: .continuous)
                                        .fill(SponsorSegmentVisual.color(for: segment).opacity(0.88))
                                        .frame(width: segW, height: trackHeight)
                                        .offset(x: min(segX, max(0, width - segW)))
                                }
                            }

                            Capsule(style: .continuous)
                                .fill(AppleTheme.accentFill)
                                .frame(width: filledWidth, height: trackHeight)

                            Circle()
                                .fill(Color.white)
                                .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
                                .overlay(Circle().strokeBorder(AppleTheme.accentFill, lineWidth: 1.5))
                                .frame(width: 11, height: 11)
                                .offset(x: min(max(0, filledWidth - 5.5), width - 11))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !state.isScrubbing {
                                        state.onScrubbingChanged?(true)
                                    }
                                    let fraction = min(max(Double(value.location.x / width), 0), 1)
                                    dragFraction = fraction
                                    let now = Date()
                                    if now.timeIntervalSince(lastSeekDispatchAt) >= 0.15 {
                                        lastSeekDispatchAt = now
                                        dispatchSeek(to: fraction * timeline.duration, currentTime: timeline.currentTime)
                                    }
                                }
                                .onEnded { value in
                                    let fraction = min(max(Double(value.location.x / width), 0), 1)
                                    lastSeekDispatchAt = Date()
                                    dispatchSeek(to: fraction * timeline.duration, currentTime: timeline.currentTime)
                                    dragFraction = nil
                                    state.onScrubbingChanged?(false)
                                }
                        )
                    }
                    .frame(height: 14)

                    HStack {
                        Text(MediaState.formatTime(displayedTime))
                        Spacer()
                        Text(MediaState.formatTime(timeline.duration))
                    }
                    .font(AppFont.micro(weight: .medium, tabular: true))
                    .foregroundStyle(isDarkSurface ? Color.white.opacity(0.72) : AppleTheme.textSecondary)
                }
            } else {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(AppleTheme.accentFill)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(AppFont.micro(weight: .bold))
                        .foregroundStyle(isDarkSurface ? Color.white.opacity(0.84) : AppleTheme.textSecondary)
                    Spacer()
                }
                .padding(.top, AppSpacing.xxs)
            }
        }
    }

    private func dispatchSeek(to targetSeconds: Double, currentTime: Double) {
        if let onSeekToTime = state.onSeekToTime {
            onSeekToTime(targetSeconds)
        } else if let onSeekBy = state.onSeekBy {
            onSeekBy(targetSeconds - currentTime)
        }
    }
}

/// Opt-in Notch Media HUD floating `NSPanel` anchored around the MacBook hardware notch
/// (or centered as a compact top-edge pill on external displays), strictly respecting fullscreen.
@MainActor
final class NotchMediaHUDController {
    private var panel: NSPanel?
    private var rootTrackingView: NotchTrackingRootView?
    private var hostingView: NSHostingView<AnyView>?
    private let state = NotchMediaHUDState()

    private var lastStatus: MediaStatus = .empty
    private var lastTimeline: PlaybackTimeline?
    private var lastIsEnabled: Bool = false
    private var lastIsSuppressed: Bool = true
    private var lastScoreText: String?
    private var isPointerInside: Bool = false

    nonisolated(unsafe) private var hoverDebounceTask: Task<Void, Never>?
    nonisolated(unsafe) private var screenParametersObserver: (any NSObjectProtocol)?

    init() {
        state.onHoverChanged = { [weak self] hovering in
            self?.handleHoverChanged(hovering)
        }
        state.onScrubbingChanged = { [weak self] scrubbing in
            self?.handleScrubbingChanged(scrubbing)
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionIfVisible()
            }
        }
    }

    deinit {
        hoverDebounceTask?.cancel()
        hoverDebounceTask = nil
        removeObservers()
    }

    nonisolated private func removeObservers() {
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParametersObserver = nil
        }
    }

    func update(
        status: MediaStatus,
        timeline: PlaybackTimeline?,
        isEnabled: Bool,
        isSuppressed: Bool,
        scoreText: String? = nil,
        thumbnailURL: URL? = nil,
        sponsorSegments: [SponsorSegment] = [],
        multiviewSlotCount: Int = 0,
        activeMultiviewSlot: Int = 0,
        onSelectMultiviewSlot: ((Int) -> Void)? = nil,
        onSeekToTime: ((Double) -> Void)? = nil,
        isMaskScoresEnabled: Bool = false,
        onTogglePlayPause: @escaping () -> Void,
        onSeekBy: ((Double) -> Void)? = nil,
        onFocusWindow: @escaping () -> Void
    ) {
        lastStatus = status
        lastTimeline = timeline
        lastIsEnabled = isEnabled
        lastIsSuppressed = isSuppressed
        lastScoreText = scoreText

        state.status = status
        state.timeline = timeline
        state.scoreText = scoreText
        state.thumbnailURL = thumbnailURL
        state.sponsorSegments = sponsorSegments
        state.multiviewSlotCount = max(0, multiviewSlotCount)
        state.activeMultiviewSlot = max(0, activeMultiviewSlot)
        state.onSelectMultiviewSlot = onSelectMultiviewSlot
        state.onSeekToTime = onSeekToTime
        state.isMaskScoresEnabled = isMaskScoresEnabled
        state.onTogglePlayPause = onTogglePlayPause
        state.onSeekBy = onSeekBy
        state.onFocusWindow = onFocusWindow

        guard isEnabled, !isSuppressed, status.hasVideo else {
            hide()
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            hide()
            return
        }

        let placement = resolvedPlacement(for: screen, expanded: state.isExpanded)
        guard placement.frame.width > 0, placement.frame.height > 0 else {
            hide()
            return
        }

        state.safeAreaTop = screen.safeAreaInsets.top
        state.placement = placement
        let panel = ensurePanel(frame: placement.frame)
        if !panel.frame.equalTo(placement.frame) {
            panel.setFrame(placement.frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        cancelHoverDebounceAndResetExpansion()
        panel?.orderOut(nil)
    }

    func shutdown() {
        cancelHoverDebounceAndResetExpansion()
        removeObservers()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        rootTrackingView = nil
        hostingView = nil
    }

    private func handleHoverChanged(_ hovering: Bool) {
        isPointerInside = hovering
        hoverDebounceTask?.cancel()
        hoverDebounceTask = nil

        guard lastIsEnabled, !lastIsSuppressed, lastStatus.hasVideo else {
            return
        }

        if hovering {
            guard !state.isExpanded else { return }
            hoverDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled,
                      let self,
                      self.isPointerInside,
                      self.lastIsEnabled,
                      !self.lastIsSuppressed,
                      self.lastStatus.hasVideo else {
                    return
                }
                self.setExpanded(true)
            }
        } else {
            guard !state.isScrubbing, state.isExpanded else { return }
            scheduleDebouncedCollapse()
        }
    }

    private func handleScrubbingChanged(_ scrubbing: Bool) {
        state.isScrubbing = scrubbing
        if scrubbing {
            hoverDebounceTask?.cancel()
            hoverDebounceTask = nil
        } else if !isPointerInside && state.isExpanded {
            scheduleDebouncedCollapse()
        }
    }

    private func scheduleDebouncedCollapse() {
        hoverDebounceTask?.cancel()
        hoverDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let self,
                  !self.isPointerInside,
                  !self.state.isScrubbing else {
                return
            }
            self.setExpanded(false)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard lastIsEnabled, !lastIsSuppressed, lastStatus.hasVideo,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            cancelHoverDebounceAndResetExpansion()
            return
        }

        let targetPlacement = resolvedPlacement(for: screen, expanded: expanded)
        guard targetPlacement.frame.width > 0, targetPlacement.frame.height > 0 else {
            return
        }

        state.safeAreaTop = screen.safeAreaInsets.top
        state.isExpanded = expanded
        state.placement = targetPlacement

        let panel = ensurePanel(frame: targetPlacement.frame)
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.frame.equalTo(targetPlacement.frame) {
            panel.setFrame(targetPlacement.frame, display: true, animate: animate)
        }
    }

    private func cancelHoverDebounceAndResetExpansion() {
        hoverDebounceTask?.cancel()
        hoverDebounceTask = nil
        isPointerInside = false
        state.isScrubbing = false
        state.isExpanded = false
    }

    private func resolvedPlacement(for screen: NSScreen, expanded: Bool) -> NotchMediaHUDPlacement {
        let base = NotchMediaHUDGeometry.targetFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
        guard expanded else {
            return base
        }
        return NotchMediaHUDGeometry.expandedFrame(
            from: base,
            in: screen.frame,
            visibleFrame: screen.visibleFrame
        )
    }

    private func repositionIfVisible() {
        guard lastIsEnabled, !lastIsSuppressed, lastStatus.hasVideo,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            hide()
            return
        }
        let placement = resolvedPlacement(for: screen, expanded: state.isExpanded)
        guard placement.frame.width > 0, placement.frame.height > 0 else {
            hide()
            return
        }
        state.safeAreaTop = screen.safeAreaInsets.top
        state.placement = placement
        panel?.setFrame(placement.frame, display: true)
    }

    private func ensurePanel(frame: NSRect) -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let trackingRoot = NotchTrackingRootView(frame: NSRect(origin: .zero, size: frame.size))
        trackingRoot.autoresizingMask = [.width, .height]
        trackingRoot.onHoverChanged = { [weak self] hovering in
            self?.handleHoverChanged(hovering)
        }

        let root = AnyView(
            NotchMediaHUDView(state: state)
                .environment(\.font, AppFont.body)
        )
        let host = NSHostingView(rootView: root)
        host.safeAreaRegions = []
        host.frame = trackingRoot.bounds
        host.autoresizingMask = [.width, .height]
        trackingRoot.addSubview(host)
        panel.contentView = trackingRoot

        self.panel = panel
        self.rootTrackingView = trackingRoot
        self.hostingView = host
        return panel
    }
}
