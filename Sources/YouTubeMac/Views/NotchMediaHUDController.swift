import AppKit
import Observation
import SwiftUI
import YouTubeMacCore

@MainActor
@Observable
private final class NotchMediaHUDState {
    var status: MediaStatus = .empty
    var timeline: PlaybackTimeline?
    var scoreText: String?
    var placement: NotchMediaHUDPlacement = NotchMediaHUDPlacement(frame: .zero, hasNotch: false, notchWidth: 0)
    var onTogglePlayPause: (() -> Void)?
    var onSeekBy: ((Double) -> Void)?
    var onFocusWindow: (() -> Void)?
}

private struct NotchMediaHUDView: View {
    let state: NotchMediaHUDState

    @State private var isHovered = false

    private var hasScore: Bool {
        guard let score = state.scoreText else { return false }
        return !score.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var compactTitle: String {
        let raw = state.status.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Now Playing" : raw
    }

    var body: some View {
        Group {
            if state.placement.hasNotch {
                notchedWingLayout
            } else {
                floatingPillLayout
            }
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var notchedWingLayout: some View {
        let wingWidth = max(72, (state.placement.frame.width - state.placement.notchWidth) / 2.0)

        HStack(spacing: 0) {
            // Left Wing: Focus / Title or Live Score
            Button {
                state.onFocusWindow?()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: state.status.isPlaying ? "waveform" : "play.rectangle.fill")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(state.status.isPlaying ? AppleTheme.accentText : .white.opacity(0.84))

                    if hasScore, let scoreText = state.scoreText {
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
                .frame(width: wingWidth, height: state.placement.frame.height, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Focus GlassGrid You Window")

            // Center hardware notch cutout spacer (strictly non-interactive)
            Color.clear
                .frame(width: state.placement.notchWidth, height: state.placement.frame.height)
                .allowsHitTesting(false)

            // Right Wing: Transport Controls
            HStack(spacing: AppSpacing.xs) {
                if let onSeekBy = state.onSeekBy, isHovered {
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

                if let onSeekBy = state.onSeekBy, isHovered {
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
            .frame(width: wingWidth, height: state.placement.frame.height, alignment: .trailing)
        }
        .frame(width: state.placement.frame.width, height: state.placement.frame.height)
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
    private var floatingPillLayout: some View {
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

                    if hasScore, let scoreText = state.scoreText {
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

            if let onSeekBy = state.onSeekBy, isHovered {
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
        .padding(.horizontal, AppSpacing.md)
        .frame(width: state.placement.frame.width, height: state.placement.frame.height)
        .appleGlass(in: Capsule(style: .continuous), interactive: true)
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

/// Opt-in Notch Media HUD floating `NSPanel` anchored around the MacBook hardware notch
/// (or centered as a compact top-edge pill on external displays), strictly respecting fullscreen.
@MainActor
final class NotchMediaHUDController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let state = NotchMediaHUDState()

    private var lastStatus: MediaStatus = .empty
    private var lastTimeline: PlaybackTimeline?
    private var lastIsEnabled: Bool = false
    private var lastIsSuppressed: Bool = true
    private var lastScoreText: String?

    nonisolated(unsafe) private var screenParametersObserver: (any NSObjectProtocol)?

    init() {
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

        let placement = NotchMediaHUDGeometry.targetFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
        guard placement.frame.width > 0, placement.frame.height > 0 else {
            hide()
            return
        }

        state.placement = placement
        let panel = ensurePanel(frame: placement.frame)
        if !panel.frame.equalTo(placement.frame) {
            panel.setFrame(placement.frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func shutdown() {
        removeObservers()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingView = nil
    }

    private func repositionIfVisible() {
        guard lastIsEnabled, !lastIsSuppressed, lastStatus.hasVideo,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            hide()
            return
        }
        let placement = NotchMediaHUDGeometry.targetFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
        guard placement.frame.width > 0, placement.frame.height > 0 else {
            hide()
            return
        }
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

        let root = AnyView(
            NotchMediaHUDView(state: state)
                .environment(\.font, AppFont.body)
        )
        let host = NSHostingView(rootView: root)
        host.safeAreaRegions = []
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        self.hostingView = host
        return panel
    }
}
