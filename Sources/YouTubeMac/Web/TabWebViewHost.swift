import AppKit
import SwiftUI
import WebKit
import YouTubeMacCore

/// Lightweight AppKit gutter handle sitting strictly inside the `10pt` inter-tile gap above `WKWebView`s.
/// Drives crisp 120Hz `resizeLeftRight` / `resizeUpDown` dragging and double-click reset without
/// ever overlapping tiles, bottom 64pt scrubbers, or losing pointer tracking over out-of-process WebViews.
@MainActor
private final class MultiviewDividerNSView: NSView {
    var descriptor: MultiviewDividerDescriptor {
        didSet {
            if oldValue.axis != descriptor.axis {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    var onHoverChanged: ((MultiviewDividerID, Bool) -> Void)?
    var onDragStarted: ((MultiviewDividerID) -> Void)?
    var onDragMoved: ((MultiviewDividerID, CGPoint) -> Void)?
    var onDragEnded: ((MultiviewDividerID) -> Void)?
    var onDoubleClickReset: ((MultiviewDividerID) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isDragging = false

    // Stored as nonisolated(unsafe) strictly so `deinit` (nonisolated on Swift 6.0/6.1 macOS 15 SDK)
    // can unconditionally unregister any active monitor if torn down mid-drag.
    nonisolated(unsafe) private var dragMonitor: Any?

    init(descriptor: MultiviewDividerDescriptor) {
        self.descriptor = descriptor
        super.init(frame: descriptor.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private var desiredCursor: NSCursor {
        descriptor.axis == .vertical ? .resizeLeftRight : .resizeUpDown
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: desiredCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        desiredCursor.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            cancelActiveDrag()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        desiredCursor.set()
        onHoverChanged?(descriptor.id, true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            onHoverChanged?(descriptor.id, false)
        }
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            cancelActiveDrag()
            onDoubleClickReset?(descriptor.id)
            return
        }

        cancelActiveDrag()
        isDragging = true
        desiredCursor.push()
        onDragStarted?(descriptor.id)

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] monitored in
            let eventType = monitored.type
            let location = monitored.locationInWindow
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if eventType == .leftMouseUp {
                    self.cancelActiveDrag()
                    return true
                }
                self.onDragMoved?(self.descriptor.id, location)
                return true
            }
            return consumed ? nil : monitored
        }
    }

    func cancelActiveDrag() {
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        if isDragging {
            isDragging = false
            NSCursor.pop()
            onDragEnded?(descriptor.id)
        }
    }
}

/// Top-left-origin AppKit container that keeps all docked `WKWebView` instances permanently mounted
/// across single-tab mode and Native Multiview (2-Up / 3-Up / 2×2 Quad-Box) without ever detaching
/// WebViews or touching subviews/layers while any tab is in WebKit fullscreen.
final class FlippedTabHostContainerView: NSView {
    var tabs: [BrowserTab] = []
    var selectedTabID: UUID = UUID()
    var poppedOutTabID: UUID?
    var anyTabInFullscreen: Bool = false
    var multiviewTabIDs: [UUID] = []
    var soloMultiviewTabID: UUID?
    var multiviewLayoutMode: MultiviewLayoutMode = .auto
    var multiviewSplitRatios: MultiviewSplitRatios = .default

    var onHoveredTileChanged: ((UUID?) -> Void)?
    var onSplitRatiosChanged: ((MultiviewSplitRatios) -> Void)?
    var onDividerHoverChanged: ((MultiviewDividerID?) -> Void)?
    var onDividerDragStateChanged: ((MultiviewDividerID?) -> Void)?
    var onDividerDoubleClickReset: ((MultiviewDividerID) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var currentHoveredTileID: UUID?
    private var activeTileRects: [(UUID, CGRect)] = []
    private var dividerViews: [MultiviewDividerNSView] = []
    private var activeDividerDragID: MultiviewDividerID?
    private var hoveredDividerID: MultiviewDividerID?
    private var resignKeyObserver: (any NSObjectProtocol)?

    var isDraggingDivider: Bool {
        activeDividerDragID != nil
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        if let window {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelActiveDividerDrags()
                }
            }
        } else {
            cancelActiveDividerDrags()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(for: event)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(for: event)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        // When moving the cursor from a WKWebView onto a sibling SwiftUI hover pill above this container,
        // AppKit delivers mouseExited while the pointer is still inside `bounds`. Preserve hover state
        // so top-right Multiview action pills never flicker or vanish mid-click.
        let localPoint = convert(event.locationInWindow, from: nil)
        if bounds.contains(localPoint) {
            super.mouseExited(with: event)
            return
        }
        setHoveredTileID(nil)
        super.mouseExited(with: event)
    }

    override func layout() {
        super.layout()
        applyLayout()
    }

    func cancelActiveDividerDrags() {
        for divider in dividerViews {
            divider.cancelActiveDrag()
        }
        if activeDividerDragID != nil {
            activeDividerDragID = nil
            onDividerDragStateChanged?(nil)
        }
    }

    func applyLayout() {
        // Hard invariant: never mutate WKWebView subviews, frames, visibility, or layers while any WKWebView is
        // entering, in, or exiting WebKit fullscreen (WebKit swaps in WKFullScreenPlaceholderView).
        if anyTabInFullscreen || tabs.contains(where: { $0.webView.fullscreenState != .notInFullscreen }) {
            cancelActiveDividerDrags()
            for divider in dividerViews where !divider.isHidden {
                divider.isHidden = true
            }
            setHoveredDividerID(nil)
            return
        }

        let dockedTabs = tabs.filter { $0.id != poppedOutTabID }
        let dockedWebViews = Set(dockedTabs.map { ObjectIdentifier($0.webView) })

        // Only remove stale WKWebView subviews (never remove WebKit helper/placeholder or MultiviewDividerNSView subviews).
        for subview in subviews {
            if subview is WKWebView, !dockedWebViews.contains(ObjectIdentifier(subview)) {
                subview.removeFromSuperview()
            }
        }

        let dockedIDSet = Set(dockedTabs.map(\.id))
        let visibleMultiviewIDs = multiviewTabIDs.filter { dockedIDSet.contains($0) }
        let isMultiview = visibleMultiviewIDs.count >= 2
        let activeSoloID: UUID? = (isMultiview && soloMultiviewTabID.map { visibleMultiviewIDs.contains($0) } == true)
            ? soloMultiviewTabID
            : nil

        var tileFrameByTabID: [UUID: CGRect] = [:]
        var activeDividers: [MultiviewDividerDescriptor] = []

        if let activeSoloID {
            // Zero-latency Solo mode: fill 100% of container bounds with soloed tile while keeping
            // the other 1–3 Multiview WKWebViews permanently mounted (`isHidden = true`, 0 teardown).
            tileFrameByTabID[activeSoloID] = bounds
            activeTileRects = [(activeSoloID, bounds)]
            activeDividers = []
            cancelActiveDividerDrags()
            setHoveredDividerID(nil)
        } else if isMultiview {
            let frames = MultiviewGridLayout.frames(
                forCount: visibleMultiviewIDs.count,
                in: bounds.size,
                mode: multiviewLayoutMode,
                ratios: multiviewSplitRatios
            )
            activeDividers = MultiviewGridLayout.dividers(
                forCount: visibleMultiviewIDs.count,
                in: bounds.size,
                mode: multiviewLayoutMode,
                ratios: multiviewSplitRatios
            )
            var pairs: [(UUID, CGRect)] = []
            pairs.reserveCapacity(visibleMultiviewIDs.count)
            for (idx, tabID) in visibleMultiviewIDs.enumerated() where idx < frames.count {
                let rect = frames[idx]
                tileFrameByTabID[tabID] = rect
                pairs.append((tabID, rect))
            }
            activeTileRects = pairs
        } else {
            activeTileRects = []
            setHoveredTileID(nil)
            cancelActiveDividerDrags()
            setHoveredDividerID(nil)
        }

        for tab in dockedTabs {
            let webView = tab.webView
            guard webView.fullscreenState == .notInFullscreen else { continue }

            // Re-attach cleanly below any divider handles so gutter handles always stay on top.
            if webView.superview !== self {
                webView.removeFromSuperview()
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = []
                if let firstDivider = dividerViews.first, firstDivider.superview === self {
                    addSubview(webView, positioned: .below, relativeTo: firstDivider)
                } else {
                    addSubview(webView)
                }
            } else if !webView.translatesAutoresizingMaskIntoConstraints {
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = []
            }

            let tileRect = tileFrameByTabID[tab.id]
            let shouldHide: Bool
            let targetFrame: CGRect

            if isMultiview {
                if let tileRect {
                    shouldHide = false
                    targetFrame = tileRect
                } else {
                    shouldHide = true
                    targetFrame = bounds
                }
            } else {
                shouldHide = (tab.id != selectedTabID)
                targetFrame = bounds
            }

            if webView.isHidden != shouldHide {
                webView.isHidden = shouldHide
            }

            if !shouldHide,
               targetFrame.width > 0,
               targetFrame.height > 0,
               !webView.frame.equalTo(targetFrame) {
                webView.frame = targetFrame
            }

            // Clip video edges cleanly to the 12pt rounded Multiview card radius (0 in Solo or single-tab).
            let desiredRadius: CGFloat = (isMultiview && activeSoloID == nil && tileRect != nil) ? 12 : 0
            let desiredMasks = desiredRadius > 0
            if !webView.wantsLayer {
                webView.wantsLayer = true
            }
            if let layer = webView.layer {
                if layer.cornerRadius != desiredRadius {
                    layer.cornerRadius = desiredRadius
                }
                if layer.masksToBounds != desiredMasks {
                    layer.masksToBounds = desiredMasks
                }
            }

            if isMultiview && tileRect != nil && tab.needsPostAttachResize {
                tab.needsPostAttachResize = false
            }
        }

        syncDividerViews(with: activeDividers, tileCount: visibleMultiviewIDs.count)

        // Notify YouTube's player strictly AFTER re-attachment & full-size layout when returning to single-tab mode.
        if !isMultiview {
            for tab in dockedTabs where tab.needsPostAttachResize && tab.id == selectedTabID {
                let webView = tab.webView
                guard webView.superview === self,
                      !webView.isHidden,
                      webView.fullscreenState == .notInFullscreen else {
                    continue
                }
                tab.needsPostAttachResize = false
                tab.schedulePostAttachResize(in: self)
            }
        }
    }

    private func syncDividerViews(with descriptors: [MultiviewDividerDescriptor], tileCount: Int) {
        // Grow pool up to needed count (max 3 dividers for 4-row stacked).
        while dividerViews.count < descriptors.count {
            let handle = MultiviewDividerNSView(descriptor: descriptors[dividerViews.count])
            wireDividerHandle(handle)
            addSubview(handle)
            dividerViews.append(handle)
        }

        for idx in dividerViews.indices {
            let handle = dividerViews[idx]
            if idx < descriptors.count {
                let desc = descriptors[idx]
                handle.descriptor = desc
                if handle.superview !== self {
                    addSubview(handle)
                }
                if handle.isHidden {
                    handle.isHidden = false
                }
                if !handle.frame.equalTo(desc.frame) {
                    handle.frame = desc.frame
                }
            } else {
                handle.cancelActiveDrag()
                if !handle.isHidden {
                    handle.isHidden = true
                }
            }
        }
    }

    private func wireDividerHandle(_ handle: MultiviewDividerNSView) {
        handle.onHoverChanged = { [weak self] dividerID, isHovering in
            guard let self else { return }
            if isHovering {
                self.setHoveredDividerID(dividerID)
            } else if self.hoveredDividerID == dividerID {
                self.setHoveredDividerID(nil)
            }
        }
        handle.onDragStarted = { [weak self] dividerID in
            guard let self else { return }
            self.activeDividerDragID = dividerID
            self.setHoveredTileID(nil)
            self.setHoveredDividerID(dividerID)
            self.onDividerDragStateChanged?(dividerID)
        }
        handle.onDragMoved = { [weak self] dividerID, windowPoint in
            guard let self else { return }
            self.handleDividerDragMoved(dividerID: dividerID, locationInWindow: windowPoint)
        }
        handle.onDragEnded = { [weak self] dividerID in
            guard let self else { return }
            if self.activeDividerDragID == dividerID {
                self.activeDividerDragID = nil
                self.onDividerDragStateChanged?(nil)
            }
        }
        handle.onDoubleClickReset = { [weak self] dividerID in
            guard let self else { return }
            let tileCount = self.activeTileRects.count
            guard tileCount >= 2 else { return }
            self.multiviewSplitRatios = self.multiviewSplitRatios.resetting(divider: dividerID, tileCount: tileCount)
            self.applyLayout()
            self.onSplitRatiosChanged?(self.multiviewSplitRatios)
            self.onDividerDoubleClickReset?(dividerID)
        }
    }

    private func handleDividerDragMoved(dividerID: MultiviewDividerID, locationInWindow: CGPoint) {
        let tileCount = activeTileRects.count
        guard tileCount >= 2 else { return }

        let local = convert(locationInWindow, from: nil)
        let pad = MultiviewGridLayout.defaultPadding.rounded(.down)
        let gap = MultiviewGridLayout.defaultSpacing.rounded(.down)
        let innerWidth = max(1, bounds.width.rounded(.down) - pad * 2)
        let innerHeight = max(1, bounds.height.rounded(.down) - pad * 2)

        let activeDescriptor = dividerViews.first(where: { !$0.isHidden && $0.descriptor.id == dividerID })?.descriptor
        let isVertical = activeDescriptor?.axis == .vertical

        let normalized: CGFloat
        if isVertical {
            let usable = max(1, innerWidth - gap)
            normalized = (local.x - pad - gap / 2) / usable
        } else if case .stacked = dividerID {
            let usable = max(1, innerHeight - gap * CGFloat(tileCount - 1))
            let precedingGaps = CGFloat(dividerID.stackedIndex ?? 0) * gap
            normalized = (local.y - pad - precedingGaps - gap / 2) / usable
        } else {
            let usable = max(1, innerHeight - gap)
            normalized = (local.y - pad - gap / 2) / usable
        }

        let updated = multiviewSplitRatios.updating(divider: dividerID, to: normalized, tileCount: tileCount)
        guard updated != multiviewSplitRatios else { return }
        multiviewSplitRatios = updated
        // Direct 120Hz AppKit frame update with zero evaluateJavaScript.
        applyLayout()
        onSplitRatiosChanged?(updated)
    }

    private func updateHover(for event: NSEvent) {
        guard !isDraggingDivider, multiviewTabIDs.count >= 2, !anyTabInFullscreen, !activeTileRects.isEmpty else {
            setHoveredTileID(nil)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let matched = activeTileRects.first(where: { $0.1.contains(point) })?.0
        setHoveredTileID(matched)
    }

    private func setHoveredTileID(_ newID: UUID?) {
        guard currentHoveredTileID != newID else { return }
        currentHoveredTileID = newID
        onHoveredTileChanged?(newID)
    }

    private func setHoveredDividerID(_ newID: MultiviewDividerID?) {
        guard hoveredDividerID != newID else { return }
        hoveredDividerID = newID
        onDividerHoverChanged?(newID)
    }
}

private extension MultiviewDividerID {
    var stackedIndex: Int? {
        if case .stacked(let idx) = self {
            return idx
        }
        return nil
    }
}

/// Keeps all docked tabs' `WKWebView` instances mounted across single-tab and Multiview modes
/// while respecting WebKit fullscreen, 120Hz draggable gutter dividers, and floating pop-out ownership.
struct TabWebViewHost: NSViewRepresentable {
    let tabs: [BrowserTab]
    let selectedTabID: UUID
    let poppedOutTabID: UUID?
    let anyTabInFullscreen: Bool
    let multiviewTabIDs: [UUID]
    let soloMultiviewTabID: UUID?
    let multiviewLayoutMode: MultiviewLayoutMode
    let multiviewSplitRatios: MultiviewSplitRatios
    let onHoveredTileChanged: (UUID?) -> Void
    let onSplitRatiosChanged: (MultiviewSplitRatios) -> Void
    let onDividerHoverChanged: (MultiviewDividerID?) -> Void
    let onDividerDragStateChanged: (MultiviewDividerID?) -> Void
    let onDividerDoubleClickReset: (MultiviewDividerID) -> Void

    func makeNSView(context: Context) -> FlippedTabHostContainerView {
        let container = FlippedTabHostContainerView(frame: .zero)
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: FlippedTabHostContainerView, context: Context) {
        container.tabs = tabs
        container.selectedTabID = selectedTabID
        container.poppedOutTabID = poppedOutTabID
        container.anyTabInFullscreen = anyTabInFullscreen
        container.multiviewTabIDs = multiviewTabIDs
        container.soloMultiviewTabID = soloMultiviewTabID
        container.multiviewLayoutMode = multiviewLayoutMode
        // Never overwrite live 120Hz AppKit ratios from stale SwiftUI props while dragging a divider.
        if !container.isDraggingDivider {
            container.multiviewSplitRatios = multiviewSplitRatios
        }
        container.onHoveredTileChanged = onHoveredTileChanged
        container.onSplitRatiosChanged = onSplitRatiosChanged
        container.onDividerHoverChanged = onDividerHoverChanged
        container.onDividerDragStateChanged = onDividerDragStateChanged
        container.onDividerDoubleClickReset = onDividerDoubleClickReset
        container.applyLayout()
    }
}
