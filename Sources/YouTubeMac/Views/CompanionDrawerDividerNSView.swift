import AppKit
import SwiftUI
import YouTubeMacCore

/// Compact 6pt AppKit gutter divider between `TabWebViewHost` and `LiveCompanionDrawerView`.
/// Reuses `MultiviewDividerNSView`'s local `NSEvent` left-mouse drag monitor pattern for smooth
/// 120Hz resizing over out-of-process `WKWebView` layers, double-click width reset, and strict
/// fullscreen / resign-key / teardown cancellation.
struct CompanionDrawerDividerNSView: NSViewRepresentable {
    let currentWidth: CGFloat
    let isFrozen: Bool
    let onDragWidthChanged: (CGFloat) -> Void
    let onDoubleClickReset: () -> Void

    func makeNSView(context: Context) -> DrawerDividerHostNSView {
        let view = DrawerDividerHostNSView(frame: .zero)
        view.currentWidth = currentWidth
        view.isFrozen = isFrozen
        view.onDragWidthChanged = onDragWidthChanged
        view.onDoubleClickReset = onDoubleClickReset
        return view
    }

    func updateNSView(_ nsView: DrawerDividerHostNSView, context: Context) {
        nsView.currentWidth = currentWidth
        nsView.isFrozen = isFrozen
        nsView.onDragWidthChanged = onDragWidthChanged
        nsView.onDoubleClickReset = onDoubleClickReset
    }
}

@MainActor
final class DrawerDividerHostNSView: NSView {
    var currentWidth: CGFloat = LivePulseLayout.drawerDefaultWidth
    var isFrozen: Bool = false {
        didSet {
            if isFrozen {
                cancelActiveDrag()
                isHovered = false
                updatePillAppearance()
            }
            if oldValue != isFrozen {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    var onDragWidthChanged: ((CGFloat) -> Void)?
    var onDoubleClickReset: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isDragging = false
    private var dragStartWindowX: CGFloat = 0
    private var dragStartWidth: CGFloat = LivePulseLayout.drawerDefaultWidth
    private let pillLayer = CALayer()

    // Stored as nonisolated(unsafe) strictly so `deinit` can unconditionally remove any active
    // monitor/observer under Swift 6 strict concurrency.
    nonisolated(unsafe) private var dragMonitor: Any?
    nonisolated(unsafe) private var resignKeyObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        pillLayer.cornerRadius = 1.5
        pillLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(pillLayer)
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
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        !isFrozen
    }

    override func layout() {
        super.layout()
        let pillWidth: CGFloat = 3
        let pillHeight: CGFloat = min(44, max(20, bounds.height * 0.12))
        pillLayer.frame = CGRect(
            x: (bounds.width - pillWidth) / 2.0,
            y: (bounds.height - pillHeight) / 2.0,
            width: pillWidth,
            height: pillHeight
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isFrozen {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isFrozen {
            NSCursor.arrow.set()
        } else {
            NSCursor.resizeLeftRight.set()
        }
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
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            resignKeyObserver = nil
        }
        if newWindow == nil {
            cancelActiveDrag()
        } else if let newWindow {
            resignKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: newWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelActiveDrag()
                }
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isFrozen else { return }
        isHovered = true
        NSCursor.resizeLeftRight.set()
        updatePillAppearance()
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            updatePillAppearance()
        }
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isFrozen else { return }

        if event.clickCount >= 2 {
            cancelActiveDrag()
            onDoubleClickReset?()
            return
        }

        cancelActiveDrag()
        isDragging = true
        dragStartWindowX = event.locationInWindow.x
        dragStartWidth = currentWidth
        NSCursor.resizeLeftRight.push()
        updatePillAppearance()

        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] monitored in
            let eventType = monitored.type
            let locationX = monitored.locationInWindow.x
            let consumed = MainActor.assumeIsolated {
                guard let self, !self.isFrozen else {
                    self?.cancelActiveDrag()
                    return false
                }
                if eventType == .leftMouseUp {
                    self.cancelActiveDrag()
                    return true
                }
                // Trailing drawer: dragging left (smaller X) widens the drawer.
                let deltaX = self.dragStartWindowX - locationX
                self.onDragWidthChanged?(self.dragStartWidth + deltaX)
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
            updatePillAppearance()
        }
    }

    private func updatePillAppearance() {
        if isDragging {
            pillLayer.backgroundColor = AppleTheme.accentNSColor.cgColor
        } else if isHovered {
            pillLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.24).cgColor
        } else {
            pillLayer.backgroundColor = NSColor.clear.cgColor
        }
    }
}
