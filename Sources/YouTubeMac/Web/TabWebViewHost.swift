import AppKit
import SwiftUI
import WebKit
import YouTubeMacCore

/// Top-left-origin AppKit container that keeps all docked `WKWebView` instances permanently mounted
/// across single-tab mode and Native Multiview (2-Up / 3-Up / 2×2 Quad-Box) without ever detaching
/// WebViews or touching subviews/layers while any tab is in WebKit fullscreen.
final class FlippedTabHostContainerView: NSView {
    var tabs: [BrowserTab] = []
    var selectedTabID: UUID = UUID()
    var poppedOutTabID: UUID?
    var anyTabInFullscreen: Bool = false
    var multiviewTabIDs: [UUID] = []
    var multiviewLayoutMode: MultiviewLayoutMode = .auto
    var onHoveredTileChanged: ((UUID?) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var currentHoveredTileID: UUID?
    private var activeTileRects: [(UUID, CGRect)] = []

    override var isFlipped: Bool { true }

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

    func applyLayout() {
        // Hard invariant: never mutate subviews, frames, visibility, or layers while any WKWebView is
        // entering, in, or exiting WebKit fullscreen (WebKit swaps in WKFullScreenPlaceholderView).
        if anyTabInFullscreen || tabs.contains(where: { $0.webView.fullscreenState != .notInFullscreen }) {
            return
        }

        let dockedTabs = tabs.filter { $0.id != poppedOutTabID }
        let dockedWebViews = Set(dockedTabs.map { ObjectIdentifier($0.webView) })

        // Only remove stale WKWebView subviews (never remove WebKit helper/placeholder subviews).
        for subview in subviews {
            if subview is WKWebView, !dockedWebViews.contains(ObjectIdentifier(subview)) {
                subview.removeFromSuperview()
            }
        }

        let dockedIDSet = Set(dockedTabs.map(\.id))
        let visibleMultiviewIDs = multiviewTabIDs.filter { dockedIDSet.contains($0) }
        let isMultiview = visibleMultiviewIDs.count >= 2

        var tileFrameByTabID: [UUID: CGRect] = [:]
        if isMultiview {
            let frames = MultiviewGridLayout.frames(
                forCount: visibleMultiviewIDs.count,
                in: bounds.size,
                mode: multiviewLayoutMode
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
        }

        for tab in dockedTabs {
            let webView = tab.webView
            guard webView.fullscreenState == .notInFullscreen else { continue }

            // Re-attach cleanly (e.g. first mount or docking back from Floating Mini-Player which uses Auto Layout).
            if webView.superview !== self {
                webView.removeFromSuperview()
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = []
                addSubview(webView)
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

            // Clip video edges cleanly to the 12pt rounded Multiview card radius (only outside fullscreen).
            let desiredRadius: CGFloat = (isMultiview && tileRect != nil) ? 12 : 0
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

    private func updateHover(for event: NSEvent) {
        guard multiviewTabIDs.count >= 2, !anyTabInFullscreen, !activeTileRects.isEmpty else {
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
}

/// Keeps all docked tabs' `WKWebView` instances mounted across single-tab and Multiview modes
/// while respecting WebKit fullscreen and floating pop-out ownership.
struct TabWebViewHost: NSViewRepresentable {
    let tabs: [BrowserTab]
    let selectedTabID: UUID
    let poppedOutTabID: UUID?
    let anyTabInFullscreen: Bool
    let multiviewTabIDs: [UUID]
    let multiviewLayoutMode: MultiviewLayoutMode
    let onHoveredTileChanged: (UUID?) -> Void

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
        container.multiviewLayoutMode = multiviewLayoutMode
        container.onHoveredTileChanged = onHoveredTileChanged
        container.applyLayout()
    }
}
