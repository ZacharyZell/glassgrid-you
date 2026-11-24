import AppKit
import Observation
import SwiftUI
import WebKit
import YouTubeMacCore

/// Observable hover, opacity & size-preset state bridged from the floating Mini-Player panel.
@MainActor
@Observable
private final class MiniPlayerHoverState {
    var isHovered: Bool = false
    var currentSizePreset: MiniPlayerSizePreset = .standard
    var opacity: Double = 1.0
}

/// `NSPanel` subclass supporting `Esc` (`cancelOperation`) to dock cleanly when not in WebKit fullscreen.
private final class MiniPlayerPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }
}

/// Strictly non-hit-tested container hosting the `2pt` bottom progress hairline so the underlying
/// YouTube video scrubber remains 100% unobstructed.
private final class PassThroughProgressHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
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
                        .fill(AppleTheme.accent.opacity(0.92))
                        .frame(width: proxy.size.width * min(max(timeline.progressFraction, 0), 1))
                }
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
    }
}

/// `NSHostingView` subclass accepting first-click events so Mini-Player drag & hover transport controls
/// respond immediately on the very first click even while another app is active.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Panel root view that tracks mouse enter/exit across the entire floating video even while YouTube.app is inactive.
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

/// Apple TV / Liquid Glass top overlay bar for the floating mini-player pop-up panel.
private struct FloatingMiniPlayerOverlayView: View {
    let tab: BrowserTab
    let hoverState: MiniPlayerHoverState
    let onSeek: (Double) -> Void
    let onTogglePlay: () -> Void
    let onToggleMute: () -> Void
    let onSetPlaybackRate: (Double) -> Void
    let onSetOpacity: (Double) -> Void
    let onSelectSizePreset: (MiniPlayerSizePreset) -> Void
    let onAirPlayResult: (AirPlayPickerResult) -> Void
    let onOpenDisplaysSettings: () -> Void
    let onDragEnded: () -> Void
    let onDock: () -> Void
    let onClose: () -> Void

    @State private var isDisplayOptionsPresented = false
    @State private var airPlayFeedbackMessage: String?
    private let speedPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        ZStack(alignment: .top) {
            // Top draggable strip: click-drag moves the floating panel anywhere on screen; release snaps near corners; double-click docks back.
            WindowDragArea(onDoubleClick: onDock, onDragEnded: onDragEnded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hoverState.isHovered {
                VStack(spacing: 4) {
                    // Subtle centered grabber indicator so dragging the Mini-Player is unmistakable
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.55))
                        .frame(width: 34, height: 3.5)
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .allowsHitTesting(false)

                    LiquidGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                if tab.mediaStatus.isHDR {
                                    Text("HDR")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.88))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
                                        )
                                }

                                if let rateText = tab.mediaStatus.formattedPlaybackRate {
                                    Text(rateText)
                                        .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.92))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }

                                Text(tab.displayTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.94))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.42))
                            .allowsHitTesting(false)

                            Spacer(minLength: 8)

                            HStack(spacing: 9) {
                                Button {
                                    onSeek(-10)
                                } label: {
                                    Image(systemName: "gobackward.10")
                                }
                                .help("Rewind 10s")

                                Button {
                                    onTogglePlay()
                                } label: {
                                    Image(systemName: tab.mediaStatus.isPlaying ? "pause.fill" : "play.fill")
                                }
                                .help("Play / Pause")

                                Button {
                                    onSeek(10)
                                } label: {
                                    Image(systemName: "goforward.10")
                                }
                                .help("Forward 10s")

                                Button {
                                    onToggleMute()
                                } label: {
                                    Image(systemName: tab.mediaStatus.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .foregroundStyle(tab.mediaStatus.isMuted ? AppleTheme.accent : .white)
                                }
                                .help(tab.mediaStatus.isMuted ? "Unmute" : "Mute")

                                Rectangle()
                                    .fill(.white.opacity(0.28))
                                    .frame(width: 1, height: 12)

                                Button {
                                    Task { @MainActor in
                                        let result = await tab.showAirPlayPicker()
                                        onAirPlayResult(result)
                                        switch result {
                                        case .ok:
                                            airPlayFeedbackMessage = nil
                                        case .mseUnsupported:
                                            airPlayFeedbackMessage = "YouTube MSE streams cast best via AirPlay Display in macOS Displays."
                                        case .unavailable:
                                            airPlayFeedbackMessage = "Direct video AirPlay unavailable on this stream — use AirPlay Display."
                                        case .noVideo:
                                            airPlayFeedbackMessage = "Start a video to stream via AirPlay."
                                        }
                                    }
                                } label: {
                                    Image(systemName: "airplayvideo")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(tab.mediaStatus.isAirPlayActive ? AppleTheme.accent : .white)
                                }
                                .help("AirPlay Video")
                                .popover(
                                    isPresented: Binding(
                                        get: { airPlayFeedbackMessage != nil },
                                        set: { if !$0 { airPlayFeedbackMessage = nil } }
                                    ),
                                    arrowEdge: .bottom
                                ) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "airplayvideo")
                                                .foregroundStyle(AppleTheme.accent)
                                            Text("AirPlay Video")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        Text(airPlayFeedbackMessage ?? "")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Button("Open Displays Settings…") {
                                            airPlayFeedbackMessage = nil
                                            onOpenDisplaysSettings()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(12)
                                    .frame(width: 240)
                                }

                                Button {
                                    isDisplayOptionsPresented.toggle()
                                } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isDisplayOptionsPresented || hoverState.opacity < 0.99 ? AppleTheme.accent : .white)
                                }
                                .help("Mini-Player Opacity, Speed & Size")
                                .popover(isPresented: $isDisplayOptionsPresented, arrowEdge: .bottom) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // GPU-composited Window Opacity (40%–100%, FairPlay DRM & HDR10 safe)
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text("Opacity")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Spacer()
                                                Text("\(Int((hoverState.opacity * 100).rounded()))%")
                                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                                    .foregroundStyle(.secondary)
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

                                        // Universal HTML5 / Shadow DOM Playback Speed
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Playback Speed")
                                                .font(.system(size: 11, weight: .semibold))
                                            HStack(spacing: 4) {
                                                ForEach(speedPresets, id: \.self) { rate in
                                                    let isSelected = abs(tab.mediaStatus.playbackRate - rate) < 0.03
                                                    Button {
                                                        onSetPlaybackRate(rate)
                                                    } label: {
                                                        Text(rate == 1.0 ? "1×" : (rate.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(rate))×" : String(format: "%.2g×", rate)))
                                                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium).monospacedDigit())
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 3)
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(isSelected ? AppleTheme.accent : Color.primary.opacity(0.08))
                                                            )
                                                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }

                                        Divider()

                                        // Size Presets
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Window Size")
                                                .font(.system(size: 11, weight: .semibold))
                                            HStack(spacing: 6) {
                                                ForEach(MiniPlayerSizePreset.allCases) { preset in
                                                    let isSelected = hoverState.currentSizePreset == preset
                                                    Button {
                                                        onSelectSizePreset(preset)
                                                    } label: {
                                                        Text(preset.title)
                                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                                            .padding(.horizontal, 9)
                                                            .padding(.vertical, 4)
                                                            .background(
                                                                Capsule(style: .continuous)
                                                                    .fill(isSelected ? AppleTheme.accent.opacity(0.22) : Color.primary.opacity(0.07))
                                                            )
                                                            .foregroundStyle(isSelected ? AppleTheme.accent : Color.primary)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .frame(width: 278)
                                }

                                Button {
                                    onDock()
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                }
                                .help("Return to Main Window")

                                Button {
                                    onClose()
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .help("Close Mini-Player")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .appleGlass(in: Capsule(style: .continuous), tint: .black.opacity(0.48), interactive: true)
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .environment(\.colorScheme, .dark)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(height: 50, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// Dedicated always-on-top floating `NSPanel` hosting a detached playing `BrowserTab` pop-up.
@MainActor
final class FloatingMiniPlayerController: NSObject, NSWindowDelegate {
    private var panel: MiniPlayerPanel?
    private var webContainer: NSView?
    private var overlayHostingView: NSView?
    private var progressHostView: PassThroughProgressHostView?
    private let hoverState = MiniPlayerHoverState()
    private var savedFrame: NSRect?
    private weak var hostedTab: BrowserTab?
    private var isProgrammaticallyHiding = false
    private var isSnapping = false
    private var onDockHandler: (() -> Void)?
    private var frameSaveTask: Task<Void, Never>?
    private var cornerSnapTask: Task<Void, Never>?

    var onFrameChanged: ((NSRect) -> Void)?
    var onWindowClosedExternally: (() -> Void)?
    var onOpacityChanged: ((Double) -> Void)?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    /// True when the user is actively interacting with or hovering over the floating panel,
    /// preventing app-activation auto-dock from yanking the `WKWebView` mid-scrub or mid-drag.
    var isInteractingWithPanel: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.isKeyWindow || panel.frame.contains(NSEvent.mouseLocation)
    }

    init(initialSavedFrame: NSRect? = nil, initialOpacity: Double = 1.0) {
        self.savedFrame = initialSavedFrame
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
        guard tab.webView.fullscreenState == .notInFullscreen else { return }

        let panel = ensurePanel(allSpaces: allSpaces)
        updateCollectionBehavior(allSpaces: allSpaces)
        updateOpacity(opacity)

        if let existing = hostedTab, existing.id != tab.id {
            if existing.webView.fullscreenState == .notInFullscreen {
                existing.webView.removeFromSuperview()
            }
        }
        hostedTab = tab
        onDockHandler = onDock
        hoverState.isHovered = false
        hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)

        if let webContainer {
            let webView = tab.webView
            if webView.superview !== webContainer {
                webView.removeFromSuperview()
                webView.translatesAutoresizingMaskIntoConstraints = false
                webContainer.addSubview(webView)
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
                    webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor)
                ])
            }
            webView.isHidden = false
            webContainer.layoutSubtreeIfNeeded()
            webView.needsLayout = true
            webView.needsDisplay = true
        }

        installOverlay(
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

        // Stay on top across apps without stealing keyboard focus from the app the user switched to.
        panel.orderFrontRegardless()
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
    func detachAndHide() -> BrowserTab? {
        // Never yank a WKWebView out of the panel while it is in or transitioning fullscreen.
        if let hosted = hostedTab, hosted.webView.fullscreenState != .notInFullscreen {
            return nil
        }

        cornerSnapTask?.cancel()
        cornerSnapTask = nil
        if let panel, panel.isVisible {
            flushPendingFrameSave(panel.frame)
            isProgrammaticallyHiding = true
            panel.orderOut(nil)
            isProgrammaticallyHiding = false
        }
        let previous = hostedTab
        if let webView = previous?.webView, webView.superview === webContainer {
            webView.removeFromSuperview()
        }
        overlayHostingView?.removeFromSuperview()
        overlayHostingView = nil
        progressHostView?.removeFromSuperview()
        progressHostView = nil
        onDockHandler = nil
        hoverState.isHovered = false
        hostedTab = nil
        return previous
    }

    func applySizePreset(_ preset: MiniPlayerSizePreset) {
        guard let panel, panel.isVisible else { return }
        cornerSnapTask?.cancel()
        cornerSnapTask = nil
        let visibleFrame = visibleFrameContaining(panel.frame)
        let target = MiniPlayerGeometry.resizedFrame(from: panel.frame, to: preset, in: visibleFrame)
        hoverState.currentSizePreset = preset
        isSnapping = true
        panel.setFrame(target, display: true, animate: true)
        isSnapping = false
        flushPendingFrameSave(target)
    }

    private func scheduleCornerSnapAfterDrag() {
        cornerSnapTask?.cancel()
        cornerSnapTask = Task { @MainActor [weak self] in
            // Wait until the left mouse button is released so we never fight an active WindowServer drag.
            while !Task.isCancelled {
                if (NSEvent.pressedMouseButtons & 1) == 0 {
                    break
                }
                try? await Task.sleep(for: .milliseconds(35))
            }
            try? await Task.sleep(for: .milliseconds(65))
            guard !Task.isCancelled, let self, (NSEvent.pressedMouseButtons & 1) == 0 else { return }
            self.cornerSnapTask = nil
            self.snapToNearestCornerIfClose()
        }
    }

    private func snapToNearestCornerIfClose() {
        guard let panel, panel.isVisible, !isSnapping else { return }
        let visibleFrame = visibleFrameContaining(panel.frame)
        let snapped = MiniPlayerGeometry.snappedFrame(panel.frame, in: visibleFrame)
        if !snapped.equalTo(panel.frame) {
            isSnapping = true
            panel.setFrame(snapped, display: true, animate: true)
            isSnapping = false
            flushPendingFrameSave(snapped)
        } else {
            flushPendingFrameSave(panel.frame)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible, !isSnapping else { return }
        scheduleDebouncedFrameSave(panel.frame)
        scheduleCornerSnapAfterDrag()
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible, !isSnapping else { return }
        hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        scheduleDebouncedFrameSave(panel.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        hoverState.currentSizePreset = MiniPlayerSizePreset.closest(to: panel.frame.size)
        flushPendingFrameSave(panel.frame)
    }

    func windowWillClose(_ notification: Notification) {
        guard !isProgrammaticallyHiding else { return }
        if hostedTab != nil {
            onWindowClosedExternally?()
        }
    }

    private func scheduleDebouncedFrameSave(_ frame: NSRect) {
        savedFrame = frame
        frameSaveTask?.cancel()
        frameSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let latest = self.savedFrame else { return }
            self.frameSaveTask = nil
            self.onFrameChanged?(latest)
        }
    }

    private func flushPendingFrameSave(_ frame: NSRect) {
        frameSaveTask?.cancel()
        frameSaveTask = nil
        savedFrame = frame
        onFrameChanged?(frame)
    }

    // MARK: - Private

    private func ensurePanel(allSpaces: Bool) -> MiniPlayerPanel {
        if let panel {
            let clamped = clampedFrame(panel.frame)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: false)
            }
            return panel
        }

        let initialFrame = clampedFrame(savedFrame ?? defaultFrame())
        let panel = MiniPlayerPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onEscapePressed = { [weak self] in
            guard let self,
                  let hosted = self.hostedTab,
                  !hosted.isInFullscreen,
                  hosted.webView.fullscreenState == .notInFullscreen else {
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
        panel.hasShadow = true
        panel.minSize = NSSize(width: 300, height: 169)
        panel.aspectRatio = NSSize(width: 16, height: 9)

        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(buttonType)?.isHidden = true
        }

        let rootView = HoverTrackingRootView(frame: NSRect(origin: .zero, size: initialFrame.size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.black.cgColor
        rootView.layer?.cornerRadius = 16
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        rootView.layer?.borderWidth = 0.75
        rootView.onHoverChanged = { [weak self] hovering in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                self.hoverState.isHovered = hovering
            }
        }

        let container = NSView(frame: rootView.bounds)
        container.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            container.topAnchor.constraint(equalTo: rootView.topAnchor),
            container.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        panel.contentView = rootView
        self.panel = panel
        self.webContainer = container
        updateCollectionBehavior(allSpaces: allSpaces)
        return panel
    }

    private func installOverlay(
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
                onAirPlayResult: onAirPlayResult,
                onOpenDisplaysSettings: onOpenDisplaysSettings,
                onDragEnded: {},
                onDock: onDock,
                onClose: onClose
            )
        )
        overlay.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: rootView.topAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 50)
        ])
        overlayHostingView = overlay
    }

    private func installProgressHairline(in panel: NSPanel, tab: BrowserTab) {
        guard let rootView = panel.contentView else { return }
        progressHostView?.removeFromSuperview()

        let host = PassThroughProgressHostView(frame: .zero)
        host.translatesAutoresizingMaskIntoConstraints = false
        let hairline = NSHostingView(rootView: MiniPlayerProgressHairlineView(timeline: tab.timeline))
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

    private func clampedFrame(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return defaultFrame() }

        let targetVisible = screens
            .map(\.visibleFrame)
            .first(where: { $0.intersects(frame) }) ?? (NSScreen.main?.visibleFrame ?? screens[0].visibleFrame)

        let width = min(max(frame.width, 300), targetVisible.width - 24)
        let height = min(max(frame.height, 169), targetVisible.height - 24)
        let x = min(max(frame.origin.x, targetVisible.minX + 8), targetVisible.maxX - width - 8)
        let y = min(max(frame.origin.y, targetVisible.minY + 8), targetVisible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let width: CGFloat = 440
        let height: CGFloat = 248
        let margin: CGFloat = 24
        return NSRect(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin,
            width: width,
            height: height
        )
    }
}
