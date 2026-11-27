import AppKit
import Observation
import QuartzCore
import SwiftUI
import WebKit
import YouTubeMacCore

/// Observable hover, mode, opacity, size-preset, and hosted Multiview state bridged from the floating panel.
@MainActor
@Observable
private final class MiniPlayerHoverState {
    var mode: MiniPlayerMode = .single
    var isHovered: Bool = false
    var isPopoverPresented: Bool = false
    var panelSize: CGSize = MiniPlayerSizePreset.standard.size
    var currentSizePreset: MiniPlayerSizePreset = .standard
    var currentGridSizePreset: MiniPlayerGridSizePreset = .standard
    var opacity: Double = 1.0
    var hostedTabs: [BrowserTab] = []
    var audioTabID: UUID?
    var layoutMode: MultiviewLayoutMode = .auto
    var splitRatios: MultiviewSplitRatios = .default
    var tileVolumes: [UUID: Int] = [:]
    var hasCustomMix: Bool = false

    var isHeaderVisible: Bool {
        isHovered || isPopoverPresented
    }

    func effectiveVolume(for tab: BrowserTab) -> Int {
        if let explicit = tileVolumes[tab.id] {
            return MultiviewAudioMixer.clampVolume(explicit)
        }
        if tab.mediaStatus.isMuted {
            return 0
        }
        return MultiviewAudioMixer.clampVolume(tab.mediaStatus.volumePercent)
    }

    var allMuted: Bool {
        !hostedTabs.isEmpty && hostedTabs.allSatisfy { !$0.mediaStatus.hasVideo || effectiveVolume(for: $0) == 0 }
    }

    var canShrinkSingle: Bool {
        panelSize.width > MiniPlayerSizePreset.compact.size.width + 12
    }

    var canExpandSingle: Bool {
        panelSize.width < MiniPlayerSizePreset.extraLarge.size.width - 12
    }

    var canShrinkGrid: Bool {
        panelSize.width > MiniPlayerGridSizePreset.compact.size.width + 12
    }

    var canExpandGrid: Bool {
        panelSize.width < MiniPlayerGridSizePreset.extraLarge.size.width - 12
    }
}

/// Topmost perimeter AppKit resize overlay that captures 8pt outer edges and 12–14pt corners even over
/// WKWebViews and `.nonactivatingPanel` drag areas without ever obstructing interior buttons or scrubbers.
@MainActor
private final class MiniPlayerEdgeResizeView: NSView {
    var isBlockedByFullscreen: () -> Bool = { false }
    var onDragStart: (() -> Void)?
    var onDragDelta: ((MiniPlayerResizeEdge, CGRect, CGSize) -> Void)?
    var onDragEnd: (() -> Void)?
    var isVisibleGrip: Bool = false {
        didSet {
            if oldValue != isVisibleGrip {
                needsDisplay = true
            }
        }
    }

    private var trackingArea: NSTrackingArea?
    private var activeEdge: MiniPlayerResizeEdge?
    private var initialFrame: CGRect = .zero
    private var initialMouseScreen: NSPoint = .zero
    private var isDragging = false
    private var hasPushedCursor = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

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
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func edge(at localPoint: NSPoint) -> MiniPlayerResizeEdge? {
        let w = bounds.width
        let h = bounds.height
        guard w > 40, h > 40 else { return nil }
        let edgeBand: CGFloat = 8
        let topCorner: CGFloat = 12
        let bottomCorner: CGFloat = 14
        let x = localPoint.x
        let y = localPoint.y

        if x <= topCorner && y <= topCorner { return .topLeft }
        if x >= (w - topCorner) && y <= topCorner { return .topRight }
        if x <= bottomCorner && y >= (h - bottomCorner) { return .bottomLeft }
        if x >= (w - bottomCorner) && y >= (h - bottomCorner) { return .bottomRight }

        if x <= edgeBand { return .left }
        if x >= (w - edgeBand) { return .right }
        if y <= edgeBand { return .top }
        if y >= (h - edgeBand) { return .bottom }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !isBlockedByFullscreen() else { return nil }
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint), edge(at: localPoint) != nil else {
            return nil
        }
        return self
    }

    private func resizeCursor(for edge: MiniPlayerResizeEdge) -> NSCursor {
        if #available(macOS 15.0, *) {
            switch edge {
            case .left: return .frameResize(position: .left, directions: .all)
            case .right: return .frameResize(position: .right, directions: .all)
            case .top: return .frameResize(position: .top, directions: .all)
            case .bottom: return .frameResize(position: .bottom, directions: .all)
            case .topLeft: return .frameResize(position: .topLeft, directions: .all)
            case .topRight: return .frameResize(position: .topRight, directions: .all)
            case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
            case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
            }
        }
        switch edge {
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .resizeLeftRight
        case .top, .bottom:
            return .resizeUpDown
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if !isBlockedByFullscreen(),
           let edge = edge(at: convert(event.locationInWindow, from: nil)) {
            resizeCursor(for: edge).set()
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            NSCursor.arrow.set()
        }
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard !isBlockedByFullscreen(),
              let edge = edge(at: localPoint),
              let window else {
            return
        }
        activeEdge = edge
        initialFrame = window.frame
        initialMouseScreen = NSEvent.mouseLocation
        isDragging = true
        if !hasPushedCursor {
            resizeCursor(for: edge).push()
            hasPushedCursor = true
        }
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let edge = activeEdge else { return }
        if isBlockedByFullscreen() {
            cancelDrag()
            return
        }
        let mouseScreen = NSEvent.mouseLocation
        let delta = CGSize(
            width: mouseScreen.x - initialMouseScreen.x,
            height: mouseScreen.y - initialMouseScreen.y
        )
        resizeCursor(for: edge).set()
        onDragDelta?(edge, initialFrame, delta)
    }

    override func mouseUp(with event: NSEvent) {
        endDragIfNeeded(notify: true)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            endDragIfNeeded(notify: true)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func cancelDrag() {
        endDragIfNeeded(notify: true)
    }

    private func endDragIfNeeded(notify: Bool) {
        if hasPushedCursor {
            NSCursor.pop()
            hasPushedCursor = false
        }
        let wasDragging = isDragging
        isDragging = false
        activeEdge = nil
        initialFrame = .zero
        if notify && wasDragging {
            onDragEnd?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isVisibleGrip, !isBlockedByFullscreen(), bounds.width > 40, bounds.height > 40 else {
            return
        }
        let w = bounds.width
        let h = bounds.height
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: w - 12, y: h - 5))
        path.line(to: NSPoint(x: w - 5, y: h - 12))
        path.move(to: NSPoint(x: w - 8, y: h - 5))
        path.line(to: NSPoint(x: w - 5, y: h - 8))
        path.stroke()
    }
}

/// `NSPanel` subclass supporting `Esc` (`cancelOperation`) to dock cleanly when not in WebKit fullscreen.
private final class MiniPlayerPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }
}

/// Strictly non-hit-tested container hosting the `2pt` bottom progress hairline so the underlying
/// video scrubber remains 100% unobstructed.
private final class PassThroughProgressHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Strictly non-hit-tested container hosting floating Multiview grid borders & compact corner badges
/// above `WKWebView`s so clicks and scrubs pass directly to any tile.
private final class PassThroughGridBorderHostView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Flipped AppKit container positioning either 1 full-bleed `WKWebView` or 2–4 Multiview `WKWebView` tiles
/// using `MultiviewGridLayout` top-left coordinates with zero Auto Layout thrash and strict fullscreen immutability.
@MainActor
private final class FlippedMiniPlayerContainerView: NSView {
    var mode: MiniPlayerMode = .single
    var hostedTabs: [BrowserTab] = []
    var layoutMode: MultiviewLayoutMode = .auto
    var splitRatios: MultiviewSplitRatios = .default

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        applyLayout()
    }

    func applyLayout() {
        if hostedTabs.contains(where: { $0.webView.fullscreenState != .notInFullscreen }) {
            return
        }

        let targetWebViews = Set(hostedTabs.map { ObjectIdentifier($0.webView) })
        for subview in subviews {
            if let wv = subview as? WKWebView,
               !targetWebViews.contains(ObjectIdentifier(wv)),
               wv.fullscreenState == .notInFullscreen {
                wv.removeFromSuperview()
            }
        }

        guard !hostedTabs.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        let frames: [CGRect]
        let tileRadius: CGFloat
        if mode == .multiviewGrid && hostedTabs.count >= 2 {
            frames = MultiviewGridLayout.frames(
                forCount: hostedTabs.count,
                in: bounds.size,
                mode: layoutMode,
                ratios: splitRatios,
                padding: MultiviewGridLayout.floatingMiniPlayerPadding,
                spacing: MultiviewGridLayout.floatingMiniPlayerSpacing
            )
            tileRadius = MultiviewGridLayout.floatingTileCornerRadius
        } else {
            frames = [bounds]
            tileRadius = 0
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (index, tab) in hostedTabs.enumerated() where index < frames.count {
            let webView = tab.webView
            guard webView.fullscreenState == .notInFullscreen else { continue }

            if webView.superview !== self {
                webView.removeFromSuperview()
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = []
                addSubview(webView)
            } else if !webView.translatesAutoresizingMaskIntoConstraints {
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = []
            }

            if webView.isHidden {
                webView.isHidden = false
            }

            let targetFrame = frames[index]
            if targetFrame.width > 0, targetFrame.height > 0, !webView.frame.equalTo(targetFrame) {
                webView.frame = targetFrame
            }

            if !webView.wantsLayer {
                webView.wantsLayer = true
            }
            if let layer = webView.layer {
                let allowLayerMask = tileRadius > 0
                    && MultiviewGridLayout.shouldMaskWebViewLayer(for: tab.webView.url ?? tab.url)
                let effectiveRadius: CGFloat = allowLayerMask ? tileRadius : 0
                if layer.cornerRadius != effectiveRadius {
                    layer.cornerRadius = effectiveRadius
                }
                if layer.masksToBounds != allowLayerMask {
                    layer.masksToBounds = allowLayerMask
                }
            }
        }
    }
}

/// Isolated `2pt` bottom progress hairline observing `PlaybackTimeline` (hidden on live streams).
private struct MiniPlayerProgressHairlineView: View {
    let timeline: PlaybackTimeline

    var body: some View {
        if timeline.duration.isFinite && timeline.duration > 0 && timeline.duration < 86400 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                    Rectangle()
                        .fill(AppleTheme.accentFill.opacity(0.92))
                        .frame(width: proxy.size.width * min(max(timeline.progressFraction, 0), 1))
                }
            }
            .frame(height: 2)
            .ignoresSafeArea(.all)
            .allowsHitTesting(false)
        }
    }
}

/// Non-blocking crimson audio focus borders & compact corner slot indicators for the Floating Multiview Grid.
private struct FloatingMultiviewGridOverlayView: View {
    let hoverState: MiniPlayerHoverState

    var body: some View {
        GeometryReader { proxy in
            let tabs = hoverState.hostedTabs
            let frames = MultiviewGridLayout.frames(
                forCount: tabs.count,
                in: proxy.size,
                mode: hoverState.layoutMode,
                ratios: hoverState.splitRatios,
                padding: MultiviewGridLayout.floatingMiniPlayerPadding,
                spacing: MultiviewGridLayout.floatingMiniPlayerSpacing
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    if index < frames.count {
                        let rect = frames[index]
                        let isAudioActive = (tab.id == hoverState.audioTabID)
                        let hideCornerBadgeForTopHeader = hoverState.isHeaderVisible && rect.minY < 46

                        RoundedRectangle(cornerRadius: MultiviewGridLayout.floatingTileCornerRadius, style: .continuous)
                            .strokeBorder(
                                isAudioActive ? AppleTheme.accentFill : Color.white.opacity(0.16),
                                lineWidth: isAudioActive ? 2.0 : 0.75
                            )
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)

                        if !hideCornerBadgeForTopHeader {
                            let effectiveVol = hoverState.effectiveVolume(for: tab)
                            let isSilent = effectiveVol == 0
                            let badgeIcon = isAudioActive
                                ? (isSilent ? "speaker.slash.fill" : "waveform")
                                : (isSilent ? "speaker.slash.fill" : "speaker.wave.1.fill")
                            HStack(spacing: AppSpacing.xs) {
                                Text("\(index + 1)")
                                    .font(AppFont.micro(weight: .bold, tabular: true))
                                Image(systemName: badgeIcon)
                                    .font(AppIconFont.xs(weight: .semibold))
                                if !isSilent && (!isAudioActive || effectiveVol < 100) {
                                    Text("\(effectiveVol)%")
                                        .font(AppFont.micro(weight: .semibold, tabular: true))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .frame(height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isAudioActive ? AppleTheme.accentFill.opacity(0.92) : Color.black.opacity(0.62))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(isAudioActive ? 0.28 : 0.16), lineWidth: 0.75)
                            )
                            .offset(x: rect.minX + AppSpacing.sm, y: rect.minY + AppSpacing.sm)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .ignoresSafeArea(.all)
        .allowsHitTesting(false)
    }
}

/// `NSHostingView` subclass accepting first-click events so Mini-Player drag & hover transport controls
/// respond immediately on the very first click even while another app is active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Panel root view that tracks mouse enter/exit across the entire floating video even while GlassGrid You is inactive.
private final class HoverTrackingRootView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

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

/// Apple TV / Liquid Glass top overlay bar for single-video floating mini-player mode.
private struct FloatingMiniPlayerOverlayView: View {
    let tab: BrowserTab
    let hoverState: MiniPlayerHoverState
    let onSeek: (Double) -> Void
    let onTogglePlay: () -> Void
    let onToggleMute: () -> Void
    let onSetPlaybackRate: (Double) -> Void
    let onSetOpacity: (Double) -> Void
    let onSelectSizePreset: (MiniPlayerSizePreset) -> Void
    let onStepSize: (Bool) -> Void
    let onPreparePopover: () -> Void
    let onAirPlayResult: (AirPlayPickerResult) -> Void
    let onOpenDisplaysSettings: () -> Void
    let onPopoverVisibilityChanged: (Bool) -> Void
    let onDragEnded: () -> Void
    let onDock: () -> Void
    let onClose: () -> Void

    @State private var isDisplayOptionsPresented = false
    @State private var airPlayFeedbackMessage: String?
    private let speedPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        let panelW = hoverState.panelSize.width
        let showTitle = panelW >= 420
        let showSkipButtons = panelW >= 360
        let showAirPlayButton = panelW >= 340

        ZStack(alignment: .top) {
            WindowDragArea(edgeResizeInset: 10, onDoubleClick: onDock, onDragEnded: onDragEnded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hoverState.isHeaderVisible {
                VStack(spacing: AppSpacing.xs) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.55))
                        .frame(width: 34, height: 4)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .allowsHitTesting(false)

                    LiquidGlassGroup(spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.md) {
                            if showTitle {
                                HStack(spacing: AppSpacing.sm) {
                                    if tab.mediaStatus.isHDR {
                                        AppleHDRBadge(onDarkMedia: true)
                                    }

                                    if let rateText = tab.mediaStatus.formattedPlaybackRate {
                                        AppleSpeedBadge(rateText: rateText, onDarkMedia: true)
                                    }

                                    Text(tab.displayTitle)
                                        .font(AppFont.caption(weight: .medium))
                                        .foregroundStyle(.white.opacity(0.94))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .frame(height: 26)
                                .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.42))
                                .allowsHitTesting(false)
                            }

                            Spacer(minLength: AppSpacing.md)

                            HStack(spacing: AppSpacing.xs) {
                                if showSkipButtons {
                                    Button {
                                        onSeek(-10)
                                    } label: {
                                        Image(systemName: "gobackward.10")
                                            .frame(width: 24, height: 24)
                                            .contentShape(Circle())
                                    }
                                    .help("Rewind 10s")
                                    .accessibilityLabel("Rewind 10 seconds")
                                }

                                Button {
                                    onTogglePlay()
                                } label: {
                                    Image(systemName: tab.mediaStatus.isPlaying ? "pause.fill" : "play.fill")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Play / Pause")
                                .accessibilityLabel(tab.mediaStatus.isPlaying ? "Pause" : "Play")

                                if showSkipButtons {
                                    Button {
                                        onSeek(10)
                                    } label: {
                                        Image(systemName: "goforward.10")
                                            .frame(width: 24, height: 24)
                                            .contentShape(Circle())
                                    }
                                    .help("Forward 10s")
                                    .accessibilityLabel("Forward 10 seconds")
                                }

                                Button {
                                    onToggleMute()
                                } label: {
                                    Image(systemName: tab.mediaStatus.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundStyle(tab.mediaStatus.isMuted ? AppleTheme.accentText : .white)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help(tab.mediaStatus.isMuted ? "Unmute" : "Mute")
                                .accessibilityLabel(tab.mediaStatus.isMuted ? "Unmute" : "Mute")

                                Rectangle()
                                    .fill(.white.opacity(0.28))
                                    .frame(width: 1, height: 12)

                                Button {
                                    onStepSize(true)
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(hoverState.canShrinkSingle ? .white : .white.opacity(0.35))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .disabled(!hoverState.canShrinkSingle)
                                .help("Shrink Mini-Player")
                                .accessibilityLabel("Shrink Mini-Player")

                                Button {
                                    onStepSize(false)
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundStyle(hoverState.canExpandSingle ? .white : .white.opacity(0.35))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .disabled(!hoverState.canExpandSingle)
                                .help("Expand Mini-Player")
                                .accessibilityLabel("Expand Mini-Player")

                                if showAirPlayButton {
                                    Button {
                                        Task { @MainActor in
                                            let result = await tab.showAirPlayPicker()
                                            onAirPlayResult(result)
                                            switch result {
                                            case .ok:
                                                airPlayFeedbackMessage = nil
                                            case .mseUnsupported:
                                                airPlayFeedbackMessage = "MSE streams cast best via AirPlay Display in macOS Displays."
                                            case .unavailable:
                                                airPlayFeedbackMessage = "Direct video AirPlay unavailable on this stream — use AirPlay Display."
                                            case .noVideo:
                                                airPlayFeedbackMessage = "Start a video to stream via AirPlay."
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "airplayvideo")
                                            .foregroundStyle(tab.mediaStatus.isAirPlayActive ? AppleTheme.accentText : .white)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Circle())
                                    }
                                    .help("AirPlay Video")
                                    .accessibilityLabel("AirPlay Video")
                                    .popover(
                                        isPresented: Binding(
                                            get: { airPlayFeedbackMessage != nil },
                                            set: { if !$0 { airPlayFeedbackMessage = nil } }
                                        ),
                                        arrowEdge: .bottom
                                    ) {
                                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                                            HStack(spacing: AppSpacing.sm) {
                                                Image(systemName: "airplayvideo")
                                                    .font(AppIconFont.md(weight: .semibold))
                                                    .foregroundStyle(AppleTheme.accentText)
                                                Text("AirPlay Video")
                                                    .font(AppFont.callout(weight: .semibold))
                                            }
                                            Text(airPlayFeedbackMessage ?? "")
                                                .font(AppFont.caption)
                                                .foregroundStyle(AppleTheme.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Button("Open Displays Settings…") {
                                                airPlayFeedbackMessage = nil
                                                onOpenDisplaysSettings()
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        .padding(AppSpacing.lg)
                                        .frame(width: 240)
                                        .background(DarkPopoverAppearanceSyncView())
                                        .foregroundStyle(Color.primary)
                                        .preferredColorScheme(.dark)
                                        .environment(\.font, AppFont.body)
                                    }
                                }

                                Button {
                                    if !isDisplayOptionsPresented {
                                        onPreparePopover()
                                    }
                                    isDisplayOptionsPresented.toggle()
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(isDisplayOptionsPresented || hoverState.opacity < 0.99 ? AppleTheme.accentText : .white)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Mini-Player Opacity, Speed & Size")
                                .accessibilityLabel("Mini-Player Display Options")
                                .popover(isPresented: $isDisplayOptionsPresented, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            HStack {
                                                Text("Opacity")
                                                    .font(AppFont.caption(weight: .semibold))
                                                Spacer()
                                                Text("\(Int((hoverState.opacity * 100).rounded()))%")
                                                    .font(AppFont.caption(weight: .medium, tabular: true))
                                                    .foregroundStyle(AppleTheme.textSecondary)
                                            }
                                            Slider(
                                                value: Binding(
                                                    get: { hoverState.opacity },
                                                    set: { onSetOpacity($0) }
                                                ),
                                                in: 0.40...1.0,
                                                step: 0.05
                                            )
                                            .controlSize(.small)
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            Text("Playback Speed")
                                                .font(AppFont.caption(weight: .semibold))
                                            HStack(spacing: AppSpacing.xs) {
                                                ForEach(speedPresets, id: \.self) { rate in
                                                    let isSelected = abs(tab.mediaStatus.playbackRate - rate) < 0.03
                                                    Button {
                                                        onSetPlaybackRate(rate)
                                                    } label: {
                                                        Text(MediaStatus.formatPlaybackRate(rate))
                                                            .font(AppFont.micro(weight: isSelected ? .semibold : .medium, tabular: true))
                                                            .padding(.horizontal, AppSpacing.sm)
                                                            .minHitTarget(24, shape: Capsule(style: .continuous))
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(isSelected ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                                                            )
                                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            HStack {
                                                Text("Window Size")
                                                    .font(AppFont.caption(weight: .semibold))
                                                Spacer()
                                                Text("\(Int(hoverState.panelSize.width.rounded()))×\(Int(hoverState.panelSize.height.rounded()))")
                                                    .font(AppFont.caption(weight: .medium, tabular: true))
                                                    .foregroundStyle(AppleTheme.textSecondary)
                                            }
                                            HStack(spacing: AppSpacing.sm) {
                                                ForEach(MiniPlayerSizePreset.allCases) { preset in
                                                    let isSelected = hoverState.currentSizePreset == preset
                                                    Button {
                                                        onSelectSizePreset(preset)
                                                    } label: {
                                                        Text(preset.shortTitle)
                                                            .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                                                            .lineLimit(1)
                                                            .frame(maxWidth: .infinity)
                                                            .minHitTarget(24, shape: Capsule(style: .continuous))
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(isSelected ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                                                            )
                                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help(preset.title)
                                                }
                                            }
                                        }
                                    }
                                    .padding(AppSpacing.lg)
                                    .frame(width: 304)
                                    .background(DarkPopoverAppearanceSyncView())
                                    .foregroundStyle(Color.primary)
                                    .preferredColorScheme(.dark)
                                    .environment(\.font, AppFont.body)
                                }

                                Button {
                                    onDock()
                                } label: {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Return to Main Window")
                                .accessibilityLabel("Return to Main Window")

                                Button {
                                    onClose()
                                } label: {
                                    Image(systemName: "xmark")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Close Mini-Player")
                                .accessibilityLabel("Close Mini-Player")
                            }
                            .buttonStyle(.plain)
                            .font(AppIconFont.md(weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .frame(height: 26)
                            .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.48), interactive: true)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .environment(\.colorScheme, .dark)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(height: 50, alignment: .top)
        .ignoresSafeArea(.all)
        .contentShape(Rectangle())
        .onChange(of: isDisplayOptionsPresented || airPlayFeedbackMessage != nil) { _, open in
            onPopoverVisibilityChanged(open)
        }
    }
}

/// Compact Liquid Glass hover top bar (`44pt` tall) for the Floating Multiview Grid Mini-Player.
private struct FloatingMultiviewHeaderOverlayView: View {
    let hoverState: MiniPlayerHoverState
    let onFocusAudio: (UUID) -> Void
    let onCycleLayout: () -> Void
    let onSelectLayout: (MultiviewLayoutMode) -> Void
    let onToggleMuteAll: () -> Void
    let onTogglePlayActive: () -> Void
    let onPlayAll: () -> Void
    let onPauseAll: () -> Void
    let onSetTileVolume: (UUID, Int) -> Void
    let onResetMixer: () -> Void
    let onSetOpacity: (Double) -> Void
    let onSelectGridPreset: (MiniPlayerGridSizePreset) -> Void
    let onStepSize: (Bool) -> Void
    let onPreparePopover: () -> Void
    let onPopoverVisibilityChanged: (Bool) -> Void
    let onDragEnded: () -> Void
    let onDock: () -> Void
    let onClose: () -> Void

    @State private var isDisplayOptionsPresented = false

    private var activeAudioTab: BrowserTab? {
        hoverState.hostedTabs.first(where: { $0.id == hoverState.audioTabID }) ?? hoverState.hostedTabs.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            WindowDragArea(edgeResizeInset: 10, onDoubleClick: onDock, onDragEnded: onDragEnded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hoverState.isHeaderVisible {
                VStack(spacing: AppSpacing.xs) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.55))
                        .frame(width: 34, height: 4)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .allowsHitTesting(false)

                    LiquidGlassGroup(spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.sm) {
                            // Leading clickable slot audio pills [1] [2] [3] [4]
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(Array(hoverState.hostedTabs.enumerated()), id: \.element.id) { index, tab in
                                    let isAudio = tab.id == hoverState.audioTabID
                                    Button {
                                        onFocusAudio(tab.id)
                                    } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            Text("\(index + 1)")
                                                .font(AppFont.micro(weight: .bold, tabular: true))
                                            if isAudio {
                                                Image(systemName: "waveform")
                                                    .font(AppIconFont.xs(weight: .semibold))
                                            }
                                        }
                                        .foregroundStyle(isAudio ? .white : .white.opacity(0.84))
                                        .padding(.horizontal, isAudio ? AppSpacing.md : AppSpacing.sm)
                                        .frame(height: 24)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(isAudio ? AppleTheme.accentFill : Color.white.opacity(0.14))
                                        )
                                        .contentShape(Capsule(style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Audio Focus: Stream \(index + 1) — \(tab.displayTitle)")
                                    .accessibilityLabel("Switch Audio to Stream \(index + 1)")
                                }
                            }
                            .padding(.horizontal, AppSpacing.xxs)
                            .frame(height: 26)
                            .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.48), interactive: true)

                            Spacer(minLength: AppSpacing.sm)

                            // Trailing Multiview Grid controls capsule
                            HStack(spacing: AppSpacing.xs) {
                                Button(action: onCycleLayout) {
                                    Image(systemName: hoverState.layoutMode.systemImage)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Layout: \(hoverState.layoutMode.title) (Click to Cycle)")
                                .accessibilityLabel("Cycle Grid Layout")

                                Button(action: onToggleMuteAll) {
                                    Image(systemName: hoverState.allMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundStyle(hoverState.allMuted ? AppleTheme.accentText : .white)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help(hoverState.allMuted ? "Unmute Active Stream" : "Mute All Streams")
                                .accessibilityLabel(hoverState.allMuted ? "Unmute Active Stream" : "Mute All Streams")

                                Button(action: onTogglePlayActive) {
                                    Image(systemName: (activeAudioTab?.mediaStatus.isPlaying ?? false) ? "pause.fill" : "play.fill")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help((activeAudioTab?.mediaStatus.isPlaying ?? false) ? "Pause Active Stream" : "Play Active Stream")
                                .accessibilityLabel((activeAudioTab?.mediaStatus.isPlaying ?? false) ? "Pause Active Stream" : "Play Active Stream")

                                Rectangle()
                                    .fill(.white.opacity(0.28))
                                    .frame(width: 1, height: 12)

                                Button {
                                    onStepSize(true)
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(hoverState.canShrinkGrid ? .white : .white.opacity(0.35))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .disabled(!hoverState.canShrinkGrid)
                                .help("Shrink Floating Grid")
                                .accessibilityLabel("Shrink Floating Grid")

                                Button {
                                    onStepSize(false)
                                } label: {
                                    Image(systemName: "plus")
                                        .foregroundStyle(hoverState.canExpandGrid ? .white : .white.opacity(0.35))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .disabled(!hoverState.canExpandGrid)
                                .help("Expand Floating Grid")
                                .accessibilityLabel("Expand Floating Grid")

                                Button {
                                    if !isDisplayOptionsPresented {
                                        onPreparePopover()
                                    }
                                    isDisplayOptionsPresented.toggle()
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundStyle(isDisplayOptionsPresented || hoverState.opacity < 0.99 || hoverState.hasCustomMix ? AppleTheme.accentText : .white)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Grid Opacity, Stream Volumes, Layout & Size Presets")
                                .accessibilityLabel("Floating Grid Options")
                                .popover(isPresented: $isDisplayOptionsPresented, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            HStack {
                                                Text("Opacity")
                                                    .font(AppFont.caption(weight: .semibold))
                                                Spacer()
                                                Text("\(Int((hoverState.opacity * 100).rounded()))%")
                                                    .font(AppFont.caption(weight: .medium, tabular: true))
                                                    .foregroundStyle(AppleTheme.textSecondary)
                                            }
                                            Slider(
                                                value: Binding(
                                                    get: { hoverState.opacity },
                                                    set: { onSetOpacity($0) }
                                                ),
                                                in: 0.40...1.0,
                                                step: 0.05
                                            )
                                            .controlSize(.small)
                                        }

                                        if !hoverState.hostedTabs.isEmpty {
                                            Divider()

                                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                                HStack {
                                                    Text("Stream Volumes")
                                                        .font(AppFont.caption(weight: .semibold))
                                                    Spacer()
                                                    if hoverState.hasCustomMix {
                                                        Button {
                                                            onResetMixer()
                                                        } label: {
                                                            HStack(spacing: AppSpacing.xs) {
                                                                Image(systemName: "arrow.counterclockwise")
                                                                    .font(AppIconFont.xs(weight: .semibold))
                                                                Text("Reset Mixer")
                                                                    .font(AppFont.micro(weight: .semibold))
                                                            }
                                                            .padding(.horizontal, AppSpacing.sm)
                                                            .minHitTarget(24, shape: Capsule(style: .continuous))
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(AppleTheme.accentText.opacity(0.18))
                                                            )
                                                            .foregroundStyle(AppleTheme.accentText)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Reset Stream Volume Mixer")
                                                    }
                                                }

                                                VStack(spacing: AppSpacing.xs) {
                                                    ForEach(Array(hoverState.hostedTabs.enumerated()), id: \.element.id) { index, tab in
                                                        let isFocused = (tab.id == hoverState.audioTabID)
                                                        let volume = hoverState.effectiveVolume(for: tab)
                                                        HStack(spacing: AppSpacing.sm) {
                                                            Text("\(index + 1)")
                                                                .font(AppFont.micro(weight: .bold, tabular: true))
                                                                .foregroundStyle(.white)
                                                                .frame(width: 16, height: 16)
                                                                .background(
                                                                    Circle()
                                                                        .fill(isFocused ? AppleTheme.accentFill : Color.white.opacity(0.20))
                                                                )

                                                            Text(tab.displayTitle)
                                                                .font(AppFont.caption(weight: .medium))
                                                                .foregroundStyle(Color.primary)
                                                                .lineLimit(1)
                                                                .truncationMode(.tail)
                                                                .frame(maxWidth: .infinity, alignment: .leading)

                                                            Slider(
                                                                value: Binding(
                                                                    get: { Double(hoverState.effectiveVolume(for: tab)) },
                                                                    set: { newVal in
                                                                        onSetTileVolume(tab.id, Int(newVal.rounded()))
                                                                    }
                                                                ),
                                                                in: 0...100,
                                                                step: 5
                                                            )
                                                            .controlSize(.small)
                                                            .frame(width: 90)
                                                            .tint(AppleTheme.accentFill)

                                                            Text("\(volume)%")
                                                                .font(AppFont.caption(weight: .semibold, tabular: true))
                                                                .foregroundStyle(volume == 0 ? AppleTheme.textSecondary : Color.primary)
                                                                .frame(width: 36, alignment: .trailing)
                                                        }
                                                        .frame(minHeight: 24)
                                                    }
                                                }
                                            }
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            Text("Layout Mode")
                                                .font(AppFont.caption(weight: .semibold))
                                            HStack(spacing: AppSpacing.sm) {
                                                ForEach(MultiviewLayoutMode.allCases) { mode in
                                                    let isSelected = hoverState.layoutMode == mode
                                                    Button {
                                                        onSelectLayout(mode)
                                                    } label: {
                                                        HStack(spacing: AppSpacing.xs) {
                                                            Image(systemName: mode.systemImage)
                                                                .font(AppIconFont.xs(weight: .semibold))
                                                            Text(mode.title)
                                                                .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                                                        }
                                                        .padding(.horizontal, AppSpacing.md)
                                                        .minHitTarget(24, shape: Capsule(style: .continuous))
                                                        .background(
                                                            Capsule(style: .continuous)
                                                                .fill(isSelected ? AppleTheme.accentFill : Color.primary.opacity(0.10))
                                                        )
                                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                            HStack {
                                                Text("Grid Size")
                                                    .font(AppFont.caption(weight: .semibold))
                                                Spacer()
                                                Text("\(Int(hoverState.panelSize.width.rounded()))×\(Int(hoverState.panelSize.height.rounded()))")
                                                    .font(AppFont.caption(weight: .medium, tabular: true))
                                                    .foregroundStyle(AppleTheme.textSecondary)
                                            }
                                            HStack(spacing: AppSpacing.sm) {
                                                ForEach(MiniPlayerGridSizePreset.allCases) { preset in
                                                    let isSelected = hoverState.currentGridSizePreset == preset
                                                    Button {
                                                        onSelectGridPreset(preset)
                                                    } label: {
                                                        Text(preset.shortTitle)
                                                            .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                                                            .lineLimit(1)
                                                            .frame(maxWidth: .infinity)
                                                            .minHitTarget(24, shape: Capsule(style: .continuous))
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(isSelected ? AppleTheme.accentFill : Color.primary.opacity(0.10))
                                                            )
                                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help(preset.title)
                                                }
                                            }
                                        }

                                        Divider()

                                        HStack(spacing: AppSpacing.md) {
                                            Button(action: onPlayAll) {
                                                HStack(spacing: AppSpacing.xs) {
                                                    Image(systemName: "play.fill")
                                                        .font(AppIconFont.xs(weight: .medium))
                                                    Text("Play All")
                                                        .font(AppFont.caption(weight: .medium))
                                                }
                                                .padding(.horizontal, AppSpacing.md)
                                                .minHitTarget(24, shape: Capsule(style: .continuous))
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(Color.primary.opacity(0.10))
                                                )
                                                .foregroundStyle(Color.primary)
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: onPauseAll) {
                                                HStack(spacing: AppSpacing.xs) {
                                                    Image(systemName: "pause.fill")
                                                        .font(AppIconFont.xs(weight: .medium))
                                                    Text("Pause All")
                                                        .font(AppFont.caption(weight: .medium))
                                                }
                                                .padding(.horizontal, AppSpacing.md)
                                                .minHitTarget(24, shape: Capsule(style: .continuous))
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(Color.primary.opacity(0.10))
                                                )
                                                .foregroundStyle(Color.primary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(AppSpacing.lg)
                                    .frame(width: 304)
                                    .background(DarkPopoverAppearanceSyncView())
                                    .foregroundStyle(Color.primary)
                                    .preferredColorScheme(.dark)
                                    .environment(\.font, AppFont.body)
                                }

                                Button(action: onDock) {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Dock Grid to Main Window")
                                .accessibilityLabel("Dock Grid to Main Window")

                                Button(action: onClose) {
                                    Image(systemName: "xmark")
                                        .frame(width: 24, height: 24)
                                        .contentShape(Circle())
                                }
                                .help("Close Floating Grid & Pause")
                                .accessibilityLabel("Close Floating Grid")
                            }
                            .buttonStyle(.plain)
                            .font(AppIconFont.md(weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .frame(height: 26)
                            .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.48), interactive: true)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xs)
                .environment(\.colorScheme, .dark)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(height: 44, alignment: .top)
        .ignoresSafeArea(.all)
        .contentShape(Rectangle())
        .onChange(of: isDisplayOptionsPresented) { _, open in
            onPopoverVisibilityChanged(open)
        }
    }
}

/// Dedicated always-on-top floating `NSPanel` hosting either a single detached `BrowserTab`
/// or the live 2–4 stream Multiview Grid with zero reload and strict fullscreen safety.
@MainActor
final class FloatingMiniPlayerController: NSObject, NSWindowDelegate {
    private var panel: MiniPlayerPanel?
    private var webContainer: FlippedMiniPlayerContainerView?
    private var gridBorderHostView: PassThroughGridBorderHostView?
    private var overlayHostingView: NSView?
    private var progressHostView: PassThroughProgressHostView?
    private var edgeResizeView: MiniPlayerEdgeResizeView?
    private let hoverState = MiniPlayerHoverState()
    private var savedFrame: NSRect?
    private var savedGridFrame: NSRect?
    private var isProgrammaticallyHiding = false
    private var isSnapping = false
    private var isLiveEdgeResizing = false
    private var onDockHandler: (() -> Void)?
    private var frameSaveTask: Task<Void, Never>?
    private var cornerSnapTask: Task<Void, Never>?
    private var hostedTabsResizeSyncTask: Task<Void, Never>?
    private var urlObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]

    var onFrameChanged: ((NSRect) -> Void)?
    var onGridFrameChanged: ((NSRect) -> Void)?
    var onWindowClosedExternally: (() -> Void)?
    var onOpacityChanged: ((Double) -> Void)?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var currentMode: MiniPlayerMode {
        hoverState.mode
    }

    var hasLiveFullscreenTab: Bool {
        hoverState.hostedTabs.contains {
            $0.isInFullscreen || $0.webView.fullscreenState != .notInFullscreen
        }
    }

    /// True when the user is interacting with or hovering the floating panel, edge-resizing, or interacting
    /// with any child popover window, preventing app-activation auto-dock mid-click, mid-scrub, or mid-resize.
    var isInteractingWithPanel: Bool {
        guard let panel, panel.isVisible else { return false }
        if isLiveEdgeResizing || hoverState.isPopoverPresented {
            return true
        }
        let mouse = NSEvent.mouseLocation
        if panel.isKeyWindow || panel.frame.contains(mouse) {
            return true
        }
        if let children = panel.childWindows {
            return children.contains { child in
                child.isVisible && (child.isKeyWindow || child.frame.contains(mouse))
            }
        }
        return false
    }

    init(
        initialSavedFrame: NSRect? = nil,
        initialSavedGridFrame: NSRect? = nil,
        initialOpacity: Double = 1.0
    ) {
        self.savedFrame = initialSavedFrame
        self.savedGridFrame = initialSavedGridFrame
        self.hoverState.opacity = min(max(initialOpacity.isFinite ? initialOpacity : 1.0, 0.40), 1.0)
        super.init()
    }

    func updateOpacity(_ opacity: Double) {
        let clamped = min(max(opacity.isFinite ? opacity : 1.0, 0.40), 1.0)
        hoverState.opacity = clamped
        panel?.alphaValue = CGFloat(clamped)
    }

    func show(
        tab: BrowserTab,
        allSpaces: Bool,
        opacity: Double = 1.0,
        onSeek: @escaping (Double) -> Void,
        onTogglePlay: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onSetPlaybackRate: @escaping (Double) -> Void,
        onAirPlayResult: @escaping (AirPlayPickerResult) -> Void,
        onOpenDisplaysSettings: @escaping () -> Void,
        onDock: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        guard tab.webView.fullscreenState == .notInFullscreen, !hasLiveFullscreenTab else { return }

        cancelPendingGeometryTasks()
        let panel = ensurePanel(for: .single, allSpaces: allSpaces)
        configurePanelConstraints(for: .single, on: panel)
        updateCollectionBehavior(allSpaces: allSpaces)
        updateOpacity(opacity)

        hostedTabsResizeSyncTask?.cancel()
        hostedTabsResizeSyncTask = nil
        gridBorderHostView?.removeFromSuperview()
        gridBorderHostView = nil

        hoverState.mode = .single
        hoverState.hostedTabs = [tab]
        hoverState.audioTabID = tab.id
        hoverState.tileVolumes = [:]
        hoverState.hasCustomMix = false
        hoverState.isHovered = false
        hoverState.isPopoverPresented = false
        hoverState.panelSize = panel.frame.size
        hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        edgeResizeView?.isVisibleGrip = false
        onDockHandler = onDock
        syncHostedTabURLObservations(for: [tab])

        if let webContainer {
            webContainer.mode = .single
            webContainer.hostedTabs = [tab]
            webContainer.applyLayout()
            webContainer.layoutSubtreeIfNeeded()
        }

        installSingleOverlay(
            in: panel,
            tab: tab,
            onSeek: onSeek,
            onTogglePlay: onTogglePlay,
            onToggleMute: onToggleMute,
            onSetPlaybackRate: onSetPlaybackRate,
            onAirPlayResult: onAirPlayResult,
            onOpenDisplaysSettings: onOpenDisplaysSettings,
            onDock: onDock,
            onClose: onClose
        )
        installProgressHairline(in: panel, tab: tab)
        panel.orderFrontRegardless()
        scheduleHostedTabsResizeSync()
    }

    func showGrid(
        tabs: [BrowserTab],
        audioTabID: UUID?,
        layoutMode: MultiviewLayoutMode,
        splitRatios: MultiviewSplitRatios,
        allSpaces: Bool,
        opacity: Double = 1.0,
        tileVolumes: [UUID: Int] = [:],
        hasCustomMix: Bool = false,
        onFocusAudio: @escaping (UUID) -> Void,
        onCycleLayout: @escaping () -> Void,
        onSelectLayout: @escaping (MultiviewLayoutMode) -> Void,
        onToggleMuteAll: @escaping () -> Void,
        onTogglePlayActive: @escaping () -> Void,
        onPlayAll: @escaping () -> Void,
        onPauseAll: @escaping () -> Void,
        onSetTileVolume: @escaping (UUID, Int) -> Void,
        onResetMixer: @escaping () -> Void,
        onDock: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        guard tabs.count >= 2,
              !hasLiveFullscreenTab,
              !tabs.contains(where: { $0.isInFullscreen || $0.webView.fullscreenState != .notInFullscreen }) else {
            return
        }

        cancelPendingGeometryTasks()
        let panel = ensurePanel(for: .multiviewGrid, allSpaces: allSpaces)
        configurePanelConstraints(for: .multiviewGrid, on: panel)
        updateCollectionBehavior(allSpaces: allSpaces)
        updateOpacity(opacity)

        progressHostView?.removeFromSuperview()
        progressHostView = nil

        hoverState.mode = .multiviewGrid
        hoverState.hostedTabs = tabs
        hoverState.audioTabID = audioTabID ?? tabs.first?.id
        hoverState.layoutMode = layoutMode
        hoverState.splitRatios = splitRatios
        hoverState.tileVolumes = tileVolumes
        hoverState.hasCustomMix = hasCustomMix
        hoverState.isHovered = false
        hoverState.isPopoverPresented = false
        hoverState.panelSize = panel.frame.size
        hoverState.currentGridSizePreset = MiniPlayerGridSizePreset.closest(to: panel.frame.size)
        edgeResizeView?.isVisibleGrip = false
        onDockHandler = onDock
        syncHostedTabURLObservations(for: tabs)

        if let webContainer {
            webContainer.mode = .multiviewGrid
            webContainer.hostedTabs = tabs
            webContainer.layoutMode = layoutMode
            webContainer.splitRatios = splitRatios
            webContainer.applyLayout()
            webContainer.layoutSubtreeIfNeeded()
        }

        installGridBorderOverlayIfNeeded(in: panel)
        installGridHeaderOverlay(
            in: panel,
            onFocusAudio: onFocusAudio,
            onCycleLayout: onCycleLayout,
            onSelectLayout: onSelectLayout,
            onToggleMuteAll: onToggleMuteAll,
            onTogglePlayActive: onTogglePlayActive,
            onPlayAll: onPlayAll,
            onPauseAll: onPauseAll,
            onSetTileVolume: onSetTileVolume,
            onResetMixer: onResetMixer,
            onDock: onDock,
            onClose: onClose
        )
        panel.orderFrontRegardless()
        scheduleHostedTabsResizeSync()
    }

    func syncGrid(
        tabs: [BrowserTab],
        audioTabID: UUID?,
        layoutMode: MultiviewLayoutMode,
        splitRatios: MultiviewSplitRatios,
        tileVolumes: [UUID: Int] = [:],
        hasCustomMix: Bool = false
    ) {
        guard hoverState.mode == .multiviewGrid,
              !hasLiveFullscreenTab,
              !tabs.contains(where: { $0.isInFullscreen || $0.webView.fullscreenState != .notInFullscreen }) else {
            return
        }

        hoverState.hostedTabs = tabs
        hoverState.audioTabID = audioTabID ?? tabs.first?.id
        hoverState.layoutMode = layoutMode
        hoverState.splitRatios = splitRatios
        hoverState.tileVolumes = tileVolumes
        hoverState.hasCustomMix = hasCustomMix
        syncHostedTabURLObservations(for: tabs)

        if let webContainer {
            webContainer.mode = .multiviewGrid
            webContainer.hostedTabs = tabs
            webContainer.layoutMode = layoutMode
            webContainer.splitRatios = splitRatios
            webContainer.applyLayout()
            webContainer.layoutSubtreeIfNeeded()
        }
    }

    func updateCollectionBehavior(allSpaces: Bool) {
        guard let panel else { return }
        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if allSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        panel.collectionBehavior = behavior
    }

    @discardableResult
    func detachAndHide() -> [BrowserTab] {
        guard !hasLiveFullscreenTab else {
            return []
        }

        cancelPendingGeometryTasks()
        edgeResizeView?.cancelDrag()
        edgeResizeView?.isVisibleGrip = false
        isLiveEdgeResizing = false
        hostedTabsResizeSyncTask?.cancel()
        hostedTabsResizeSyncTask = nil

        if let panel, panel.isVisible {
            flushPendingFrameSave(panel.frame, isGridMode: hoverState.mode == .multiviewGrid)
            isProgrammaticallyHiding = true
            panel.orderOut(nil)
            isProgrammaticallyHiding = false
        }

        let previous = hoverState.hostedTabs
        if let webContainer {
            for tab in previous where tab.webView.superview === webContainer {
                tab.webView.layer?.cornerRadius = 0
                tab.webView.layer?.masksToBounds = false
                tab.webView.removeFromSuperview()
            }
            webContainer.hostedTabs = []
        }

        gridBorderHostView?.removeFromSuperview()
        gridBorderHostView = nil
        overlayHostingView?.removeFromSuperview()
        overlayHostingView = nil
        progressHostView?.removeFromSuperview()
        progressHostView = nil
        onDockHandler = nil
        urlObservations.removeAll()
        hoverState.isHovered = false
        hoverState.isPopoverPresented = false
        hoverState.hostedTabs = []
        hoverState.audioTabID = nil
        hoverState.tileVolumes = [:]
        hoverState.hasCustomMix = false
        hoverState.mode = .single
        return previous
    }

    private func syncHostedTabURLObservations(for tabs: [BrowserTab]) {
        let activeIDs = Set(tabs.map { ObjectIdentifier($0.webView) })
        urlObservations = urlObservations.filter { activeIDs.contains($0.key) }
        for tab in tabs {
            let key = ObjectIdentifier(tab.webView)
            guard urlObservations[key] == nil else { continue }
            urlObservations[key] = tab.webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.hoverState.mode == .multiviewGrid,
                          !self.hasLiveFullscreenTab else {
                        return
                    }
                    self.webContainer?.applyLayout()
                }
            }
        }
    }

    func stepSize(smaller: Bool) {
        guard !hasLiveFullscreenTab, let panel, panel.isVisible else { return }
        if hoverState.mode == .multiviewGrid {
            let next = smaller
                ? MiniPlayerGridSizePreset.stepSmaller(from: panel.frame.size)
                : MiniPlayerGridSizePreset.stepLarger(from: panel.frame.size)
            if smaller && next.size.width >= panel.frame.width { return }
            if !smaller && next.size.width <= panel.frame.width { return }
            applyGridSizePreset(next)
        } else {
            let next = smaller
                ? MiniPlayerSizePreset.stepSmaller(from: panel.frame.size)
                : MiniPlayerSizePreset.stepLarger(from: panel.frame.size)
            if smaller && next.size.width >= panel.frame.width { return }
            if !smaller && next.size.width <= panel.frame.width { return }
            applySizePreset(next)
        }
    }

    func applySizePreset(_ preset: MiniPlayerSizePreset) {
        guard !hasLiveFullscreenTab, let panel, panel.isVisible, hoverState.mode == .single else { return }
        cornerSnapTask?.cancel()
        cornerSnapTask = nil
        let visibleFrame = visibleFrameContaining(panel.frame)
        let target = MiniPlayerGeometry.resizedFrame(from: panel.frame, to: preset, in: visibleFrame)
        hoverState.currentSizePreset = preset
        hoverState.panelSize = target.size
        isSnapping = true
        panel.setFrame(target, display: true, animate: true)
        isSnapping = false
        webContainer?.applyLayout()
        webContainer?.layoutSubtreeIfNeeded()
        flushPendingFrameSave(target, isGridMode: false)
        scheduleHostedTabsResizeSync()
    }

    func applyGridSizePreset(_ preset: MiniPlayerGridSizePreset) {
        guard !hasLiveFullscreenTab, let panel, panel.isVisible, hoverState.mode == .multiviewGrid else { return }
        cornerSnapTask?.cancel()
        cornerSnapTask = nil
        let visibleFrame = visibleFrameContaining(panel.frame)
        let target = MiniPlayerGeometry.resizedGridFrame(from: panel.frame, to: preset, in: visibleFrame)
        hoverState.currentGridSizePreset = preset
        hoverState.panelSize = target.size
        isSnapping = true
        panel.setFrame(target, display: true, animate: true)
        isSnapping = false
        webContainer?.applyLayout()
        webContainer?.layoutSubtreeIfNeeded()
        flushPendingFrameSave(target, isGridMode: true)
        scheduleHostedTabsResizeSync()
    }

    private func scheduleHostedTabsResizeSync() {
        hostedTabsResizeSyncTask?.cancel()
        hostedTabsResizeSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self, !self.hasLiveFullscreenTab else { return }
            for tab in self.hoverState.hostedTabs {
                tab.syncPlayerSize()
            }
            self.hostedTabsResizeSyncTask = nil
        }
    }

    private func cancelPendingGeometryTasks() {
        cornerSnapTask?.cancel()
        cornerSnapTask = nil
        frameSaveTask?.cancel()
        frameSaveTask = nil
    }

    private func scheduleCornerSnapAfterDrag(isGridMode: Bool) {
        cornerSnapTask?.cancel()
        cornerSnapTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if (NSEvent.pressedMouseButtons & 1) == 0 {
                    break
                }
                try? await Task.sleep(for: .milliseconds(35))
            }
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled, let self, !self.isLiveEdgeResizing, (NSEvent.pressedMouseButtons & 1) == 0 else { return }
            self.cornerSnapTask = nil
            self.snapToNearestCornerIfClose(isGridMode: isGridMode)
        }
    }

    private func snapToNearestCornerIfClose(isGridMode: Bool) {
        guard let panel, panel.isVisible, !isSnapping, !isLiveEdgeResizing, !hasLiveFullscreenTab else { return }
        let currentModeIsGrid = (hoverState.mode == .multiviewGrid)
        guard currentModeIsGrid == isGridMode else { return }
        let visibleFrame = visibleFrameContaining(panel.frame)
        let snapped = MiniPlayerGeometry.snappedFrame(panel.frame, in: visibleFrame)
        if !snapped.equalTo(panel.frame) {
            isSnapping = true
            panel.setFrame(snapped, display: true, animate: true)
            isSnapping = false
            flushPendingFrameSave(snapped, isGridMode: isGridMode)
        } else {
            flushPendingFrameSave(panel.frame, isGridMode: isGridMode)
        }
    }

    private func handleEdgeResizeStart() {
        guard !hasLiveFullscreenTab else {
            edgeResizeView?.cancelDrag()
            return
        }
        isLiveEdgeResizing = true
        cornerSnapTask?.cancel()
        cornerSnapTask = nil
    }

    private func handleEdgeResizeDelta(edge: MiniPlayerResizeEdge, initialFrame: CGRect, delta: CGSize) {
        guard let panel, panel.isVisible, !hasLiveFullscreenTab else { return }
        let isGrid = (hoverState.mode == .multiviewGrid)
        let minSize = isGrid ? MiniPlayerGeometry.gridMinimumSize : CGSize(width: 300, height: 169)
        let visibleFrame = visibleFrameContaining(initialFrame)
        let target = MiniPlayerGeometry.dragResizedFrame(
            initialFrame: initialFrame,
            edge: edge,
            delta: delta,
            maintainAspectRatio: !isGrid,
            minSize: minSize,
            in: visibleFrame
        )
        guard !panel.frame.equalTo(target) else { return }
        panel.setFrame(target, display: true)
    }

    private func handleEdgeResizeEnd() {
        let wasResizing = isLiveEdgeResizing
        isLiveEdgeResizing = false
        guard wasResizing, let panel, panel.isVisible else { return }
        let isGrid = (hoverState.mode == .multiviewGrid)
        hoverState.panelSize = panel.frame.size
        if isGrid {
            hoverState.currentGridSizePreset = MiniPlayerGridSizePreset.closest(to: panel.frame.size)
        } else {
            hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        }
        webContainer?.applyLayout()
        webContainer?.layoutSubtreeIfNeeded()
        flushPendingFrameSave(panel.frame, isGridMode: isGrid)
        scheduleHostedTabsResizeSync()
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel,
              !isSnapping,
              !isLiveEdgeResizing,
              !hasLiveFullscreenTab,
              hoverState.mode == .single else {
            return frameSize
        }

        let visibleFrame = visibleFrameContaining(sender.frame)
        let minW: CGFloat = 300
        let minH: CGFloat = 169
        let maxW = max(minW, visibleFrame.width - 16)
        let maxH = max(minH, visibleFrame.height - 16)

        let currentSize = sender.frame.size
        let dw = abs(frameSize.width - currentSize.width)
        let dh = abs(frameSize.height - currentSize.height)

        var targetW: CGFloat
        var targetH: CGFloat
        if dh * (16.0 / 9.0) > dw {
            targetH = min(max(frameSize.height, minH), maxH).rounded()
            targetW = (targetH * 16.0 / 9.0).rounded()
            if targetW > maxW {
                targetW = maxW.rounded()
                targetH = (targetW * 9.0 / 16.0).rounded()
            }
        } else {
            targetW = min(max(frameSize.width, minW), maxW).rounded()
            targetH = (targetW * 9.0 / 16.0).rounded()
            if targetH > maxH {
                targetH = maxH.rounded()
                targetW = (targetH * 16.0 / 9.0).rounded()
            }
        }
        return NSSize(width: max(targetW, minW), height: max(targetH, minH))
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible, !isSnapping, !isLiveEdgeResizing else { return }
        let isGrid = (hoverState.mode == .multiviewGrid)
        scheduleDebouncedFrameSave(panel.frame, isGridMode: isGrid)
        scheduleCornerSnapAfterDrag(isGridMode: isGrid)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible, !isSnapping else { return }
        let isGrid = (hoverState.mode == .multiviewGrid)
        hoverState.panelSize = panel.frame.size
        if isGrid {
            hoverState.currentGridSizePreset = MiniPlayerGridSizePreset.closest(to: panel.frame.size)
        } else {
            hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        }
        if isLiveEdgeResizing {
            webContainer?.applyLayout()
        }
        scheduleDebouncedFrameSave(panel.frame, isGridMode: isGrid)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        let isGrid = (hoverState.mode == .multiviewGrid)
        hoverState.panelSize = panel.frame.size
        if isGrid {
            hoverState.currentGridSizePreset = MiniPlayerGridSizePreset.closest(to: panel.frame.size)
        } else {
            hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        }
        webContainer?.applyLayout()
        flushPendingFrameSave(panel.frame, isGridMode: isGrid)
        scheduleHostedTabsResizeSync()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isProgrammaticallyHiding else { return }
        edgeResizeView?.cancelDrag()
        isLiveEdgeResizing = false
        if !hoverState.hostedTabs.isEmpty && !hasLiveFullscreenTab {
            onWindowClosedExternally?()
        }
    }

    private func scheduleDebouncedFrameSave(_ frame: NSRect, isGridMode: Bool) {
        if isGridMode {
            savedGridFrame = frame
        } else {
            savedFrame = frame
        }
        frameSaveTask?.cancel()
        frameSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.frameSaveTask = nil
            if isGridMode {
                if let latest = self.savedGridFrame {
                    self.onGridFrameChanged?(latest)
                }
            } else if let latest = self.savedFrame {
                self.onFrameChanged?(latest)
            }
        }
    }

    private func flushPendingFrameSave(_ frame: NSRect, isGridMode: Bool) {
        frameSaveTask?.cancel()
        frameSaveTask = nil
        if isGridMode {
            savedGridFrame = frame
            onGridFrameChanged?(frame)
        } else {
            savedFrame = frame
            onFrameChanged?(frame)
        }
    }

    // MARK: - Private

    private func ensurePanel(for mode: MiniPlayerMode, allSpaces: Bool) -> MiniPlayerPanel {
        if let panel {
            return panel
        }

        let isGrid = (mode == .multiviewGrid)
        let targetRaw = isGrid ? (savedGridFrame ?? defaultGridFrame()) : (savedFrame ?? defaultSingleFrame())
        let initialFrame = clampedFrame(targetRaw, forGridMode: isGrid)
        let panel = MiniPlayerPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscapePressed = { [weak self] in
            guard let self,
                  !self.hoverState.hostedTabs.isEmpty,
                  !self.hasLiveFullscreenTab else {
                return
            }
            self.onDockHandler?()
        }
        panel.delegate = self
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = true

        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }

        let rootView = HoverTrackingRootView(frame: NSRect(origin: .zero, size: initialFrame.size))
        // Keep rootView.layer unmasked (no cornerRadius / masksToBounds / borderWidth) so FairPlay DRM
        // protected video IOSurfaces rely strictly on WindowServer rounded corners without offscreen masking.
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor
        rootView.onHoverChanged = { [weak self] hovering in
            guard let self else { return }
            self.edgeResizeView?.isVisibleGrip = hovering
            withAnimation(.easeInOut(duration: 0.16)) {
                self.hoverState.isHovered = hovering
            }
        }

        let container = FlippedMiniPlayerContainerView(frame: rootView.bounds)
        container.autoresizingMask = [.width, .height]
        rootView.addSubview(container)

        let edgeResizer = MiniPlayerEdgeResizeView(frame: rootView.bounds)
        edgeResizer.autoresizingMask = [.width, .height]
        edgeResizer.isBlockedByFullscreen = { [weak self] in
            self?.hasLiveFullscreenTab ?? false
        }
        edgeResizer.onDragStart = { [weak self] in
            self?.handleEdgeResizeStart()
        }
        edgeResizer.onDragDelta = { [weak self] edge, initial, delta in
            self?.handleEdgeResizeDelta(edge: edge, initialFrame: initial, delta: delta)
        }
        edgeResizer.onDragEnd = { [weak self] in
            self?.handleEdgeResizeEnd()
        }
        rootView.addSubview(edgeResizer)

        panel.contentView = rootView
        self.panel = panel
        self.webContainer = container
        self.edgeResizeView = edgeResizer
        configurePanelConstraints(for: mode, on: panel)
        updateCollectionBehavior(allSpaces: allSpaces)
        return panel
    }

    private func bringEdgeResizeViewToFront() {
        guard let rootView = panel?.contentView, let edgeResizeView else { return }
        if edgeResizeView.superview !== rootView || rootView.subviews.last !== edgeResizeView {
            edgeResizeView.removeFromSuperview()
            rootView.addSubview(edgeResizeView, positioned: .above, relativeTo: nil)
        }
    }

    private func configurePanelConstraints(for mode: MiniPlayerMode, on panel: MiniPlayerPanel) {
        let isGrid = (mode == .multiviewGrid)
        isSnapping = true
        defer { isSnapping = false }

        // Keep resizeIncrements 1x1 always (AppKit treats aspectRatio and resizeIncrements as mutually exclusive;
        // 16:9 ratio is enforced via MiniPlayerEdgeResizeView & windowWillResize).
        panel.resizeIncrements = NSSize(width: 1, height: 1)

        if isGrid {
            panel.minSize = NSSize(
                width: MiniPlayerGeometry.gridMinimumSize.width,
                height: MiniPlayerGeometry.gridMinimumSize.height
            )
            let target = clampedFrame(savedGridFrame ?? defaultGridFrame(), forGridMode: true)
            if !panel.frame.equalTo(target) {
                panel.setFrame(target, display: true)
            }
        } else {
            panel.minSize = NSSize(width: 300, height: 169)
            let target = clampedFrame(savedFrame ?? defaultSingleFrame(), forGridMode: false)
            if !panel.frame.equalTo(target) {
                panel.setFrame(target, display: true)
            }
        }
        hoverState.panelSize = panel.frame.size
    }

    private func refreshHoverAfterPopoverDismissal(_ popoverOpen: Bool) {
        hoverState.isPopoverPresented = popoverOpen
        if !popoverOpen, let panel {
            let inside = panel.frame.contains(NSEvent.mouseLocation)
            edgeResizeView?.isVisibleGrip = inside
            withAnimation(.easeInOut(duration: 0.16)) {
                hoverState.isHovered = inside
            }
        }
    }

    private func prepareForPopoverPresentation() {
        hoverState.isPopoverPresented = true
        panel?.makeKey()
    }

    private func installSingleOverlay(
        in panel: NSPanel,
        tab: BrowserTab,
        onSeek: @escaping (Double) -> Void,
        onTogglePlay: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onSetPlaybackRate: @escaping (Double) -> Void,
        onAirPlayResult: @escaping (AirPlayPickerResult) -> Void,
        onOpenDisplaysSettings: @escaping () -> Void,
        onDock: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        guard let rootView = panel.contentView else { return }
        overlayHostingView?.removeFromSuperview()

        let overlay = FirstMouseHostingView(
            rootView: FloatingMiniPlayerOverlayView(
                tab: tab,
                hoverState: hoverState,
                onSeek: onSeek,
                onTogglePlay: onTogglePlay,
                onToggleMute: onToggleMute,
                onSetPlaybackRate: onSetPlaybackRate,
                onSetOpacity: { [weak self] newOpacity in
                    self?.updateOpacity(newOpacity)
                    self?.onOpacityChanged?(newOpacity)
                },
                onSelectSizePreset: { [weak self] preset in
                    self?.applySizePreset(preset)
                },
                onStepSize: { [weak self] smaller in
                    self?.stepSize(smaller: smaller)
                },
                onPreparePopover: { [weak self] in
                    self?.prepareForPopoverPresentation()
                },
                onAirPlayResult: onAirPlayResult,
                onOpenDisplaysSettings: onOpenDisplaysSettings,
                onPopoverVisibilityChanged: { [weak self] open in
                    self?.refreshHoverAfterPopoverDismissal(open)
                },
                onDragEnded: {},
                onDock: onDock,
                onClose: onClose
            )
            .environment(\.font, AppFont.body)
        )
        overlay.safeAreaRegions = []
        overlay.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 50)
        ])
        overlayHostingView = overlay
        bringEdgeResizeViewToFront()
    }

    private func installGridBorderOverlayIfNeeded(in panel: NSPanel) {
        guard let rootView = panel.contentView else { return }
        if gridBorderHostView?.superview === rootView {
            bringEdgeResizeViewToFront()
            return
        }
        gridBorderHostView?.removeFromSuperview()

        let host = PassThroughGridBorderHostView(frame: rootView.bounds)
        host.autoresizingMask = [.width, .height]
        let borderView = NSHostingView(
            rootView: FloatingMultiviewGridOverlayView(hoverState: hoverState)
                .environment(\.font, AppFont.body)
        )
        borderView.safeAreaRegions = []
        borderView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            borderView.topAnchor.constraint(equalTo: host.topAnchor),
            borderView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        if let overlayHostingView, overlayHostingView.superview === rootView {
            rootView.addSubview(host, positioned: .below, relativeTo: overlayHostingView)
        } else {
            rootView.addSubview(host)
        }
        gridBorderHostView = host
        bringEdgeResizeViewToFront()
    }

    private func installGridHeaderOverlay(
        in panel: NSPanel,
        onFocusAudio: @escaping (UUID) -> Void,
        onCycleLayout: @escaping () -> Void,
        onSelectLayout: @escaping (MultiviewLayoutMode) -> Void,
        onToggleMuteAll: @escaping () -> Void,
        onTogglePlayActive: @escaping () -> Void,
        onPlayAll: @escaping () -> Void,
        onPauseAll: @escaping () -> Void,
        onSetTileVolume: @escaping (UUID, Int) -> Void,
        onResetMixer: @escaping () -> Void,
        onDock: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        guard let rootView = panel.contentView else { return }
        overlayHostingView?.removeFromSuperview()

        let overlay = FirstMouseHostingView(
            rootView: FloatingMultiviewHeaderOverlayView(
                hoverState: hoverState,
                onFocusAudio: onFocusAudio,
                onCycleLayout: onCycleLayout,
                onSelectLayout: onSelectLayout,
                onToggleMuteAll: onToggleMuteAll,
                onTogglePlayActive: onTogglePlayActive,
                onPlayAll: onPlayAll,
                onPauseAll: onPauseAll,
                onSetTileVolume: onSetTileVolume,
                onResetMixer: onResetMixer,
                onSetOpacity: { [weak self] newOpacity in
                    self?.updateOpacity(newOpacity)
                    self?.onOpacityChanged?(newOpacity)
                },
                onSelectGridPreset: { [weak self] preset in
                    self?.applyGridSizePreset(preset)
                },
                onStepSize: { [weak self] smaller in
                    self?.stepSize(smaller: smaller)
                },
                onPreparePopover: { [weak self] in
                    self?.prepareForPopoverPresentation()
                },
                onPopoverVisibilityChanged: { [weak self] open in
                    self?.refreshHoverAfterPopoverDismissal(open)
                },
                onDragEnded: {},
                onDock: onDock,
                onClose: onClose
            )
            .environment(\.font, AppFont.body)
        )
        overlay.safeAreaRegions = []
        overlay.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 44)
        ])
        overlayHostingView = overlay
        bringEdgeResizeViewToFront()
    }

    private func installProgressHairline(in panel: NSPanel, tab: BrowserTab) {
        guard let rootView = panel.contentView else { return }
        progressHostView?.removeFromSuperview()

        let host = PassThroughProgressHostView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        let hairline = NSHostingView(
            rootView: MiniPlayerProgressHairlineView(timeline: tab.timeline)
                .environment(\.font, AppFont.body)
        )
        hairline.safeAreaRegions = []
        hairline.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: host.topAnchor),
            hairline.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        rootView.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            host.heightAnchor.constraint(equalToConstant: 2)
        ])
        progressHostView = host
        bringEdgeResizeViewToFront()
    }

    private func visibleFrameContaining(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSRect(x: 0, y: 0, width: 1280, height: 800)
        }
        return screens
            .map(\.visibleFrame)
            .first(where: { $0.intersects(frame) }) ?? (NSScreen.main?.visibleFrame ?? screens[0].visibleFrame)
    }

    private func clampedFrame(_ frame: NSRect, forGridMode isGrid: Bool) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return isGrid ? defaultGridFrame() : defaultSingleFrame()
        }

        let targetVisible = screens
            .map(\.visibleFrame)
            .first(where: { $0.intersects(frame) }) ?? (NSScreen.main?.visibleFrame ?? screens[0].visibleFrame)

        let minW: CGFloat = isGrid ? MiniPlayerGeometry.gridMinimumSize.width : 300
        let minH: CGFloat = isGrid ? MiniPlayerGeometry.gridMinimumSize.height : 169
        let width = min(max(frame.width, minW), targetVisible.width - 24)
        let height = min(max(frame.height, minH), targetVisible.height - 24)
        let x = min(max(frame.origin.x, targetVisible.minX + 8), targetVisible.maxX - width - 8)
        let y = min(max(frame.origin.y, targetVisible.minY + 8), targetVisible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func defaultSingleFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = 480
        let height: CGFloat = 270
        let margin: CGFloat = 24
        return NSRect(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin,
            width: width,
            height: height
        )
    }

    private func defaultGridFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = MiniPlayerGridSizePreset.standard.size
        let width = min(size.width, max(MiniPlayerGeometry.gridMinimumSize.width, visibleFrame.width - 48))
        let height = min(size.height, max(MiniPlayerGeometry.gridMinimumSize.height, visibleFrame.height - 48))
        let margin: CGFloat = 24
        return NSRect(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin,
            width: width,
            height: height
        )
    }
}
