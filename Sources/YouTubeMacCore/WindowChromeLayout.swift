import CoreGraphics
import Foundation

/// Top-left window-coordinate frames of macOS's three standard traffic-light buttons.
public struct TrafficLightFrames: Equatable, Sendable {
    public let close: CGRect
    public let miniaturize: CGRect
    public let zoom: CGRect

    public init(close: CGRect, miniaturize: CGRect, zoom: CGRect) {
        self.close = close
        self.miniaturize = miniaturize
        self.zoom = zoom
    }

    public var allButtons: [CGRect] {
        [close, miniaturize, zoom]
    }

    public var averageCenterY: CGFloat {
        (close.midY + miniaturize.midY + zoom.midY) / 3.0
    }

    public var maxX: CGFloat {
        max(close.maxX, max(miniaturize.maxX, zoom.maxX))
    }

    /// Reference unified 52pt titlebar metrics on macOS 26/27 (Tahoe) (`close=(19,19,14x14)`, `zoom.maxX=79`).
    public static let tahoeUnified = TrafficLightFrames(
        close: CGRect(x: 19, y: 19, width: 14, height: 14),
        miniaturize: CGRect(x: 42, y: 19, width: 14, height: 14),
        zoom: CGRect(x: 65, y: 19, width: 14, height: 14)
    )

    /// Reference unified 52pt titlebar metrics on macOS 15 (Sequoia) (`close=(20,19,12x12)`, `zoom.maxX=72`).
    public static let sequoiaUnified = TrafficLightFrames(
        close: CGRect(x: 20, y: 19, width: 12, height: 12),
        miniaturize: CGRect(x: 40, y: 19, width: 12, height: 12),
        zoom: CGRect(x: 60, y: 19, width: 12, height: 12)
    )

    /// Historical broken compact 32pt titlebar (no NSToolbar) on Tahoe where the close button clips the 16pt corner arc.
    public static let legacyCompact32 = TrafficLightFrames(
        close: CGRect(x: 9, y: 9, width: 14, height: 14),
        miniaturize: CGRect(x: 32, y: 9, width: 14, height: 14),
        zoom: CGRect(x: 55, y: 9, width: 14, height: 14)
    )
}

/// Structured output of a geometric window-chrome collision and alignment audit.
public struct WindowChromeAuditResult: Equatable, Sendable {
    public let minInwardClearance: CGFloat
    public let sidebarHeaderCenterDelta: CGFloat
    public let topHeaderBarCenterDelta: CGFloat
    public let expandedSidebarLeadingClearance: CGFloat
    public let collapsedNavLeadingClearance: CGFloat
    public let nativeFullScreenCollapsedPadding: CGFloat
    public let violations: [String]

    public var passed: Bool {
        violations.isEmpty
    }

    public init(
        minInwardClearance: CGFloat,
        sidebarHeaderCenterDelta: CGFloat,
        topHeaderBarCenterDelta: CGFloat,
        expandedSidebarLeadingClearance: CGFloat,
        collapsedNavLeadingClearance: CGFloat,
        nativeFullScreenCollapsedPadding: CGFloat,
        violations: [String]
    ) {
        self.minInwardClearance = minInwardClearance
        self.sidebarHeaderCenterDelta = sidebarHeaderCenterDelta
        self.topHeaderBarCenterDelta = topHeaderBarCenterDelta
        self.expandedSidebarLeadingClearance = expandedSidebarLeadingClearance
        self.collapsedNavLeadingClearance = collapsedNavLeadingClearance
        self.nativeFullScreenCollapsedPadding = nativeFullScreenCollapsedPadding
        self.violations = violations
    }
}

/// Single source of truth for GlassGrid You's floating sidebar, unified 52pt titlebar,
/// and traffic-light collision/alignment geometry.
public enum WindowChromeLayout {
    public static let sidebarWidth: CGFloat = 234
    public static let sidebarCardLeadingInset: CGFloat = 8
    public static let sidebarCardTrailingInset: CGFloat = 4
    public static let sidebarCardVerticalInset: CGFloat = 8
    public static let sidebarCardCornerRadius: CGFloat = 16
    public static let sidebarHeaderHeight: CGFloat = 36
    public static let topHeaderBarHeight: CGFloat = 52

    public static let minimumTrafficLightClearance: CGFloat = 6.0
    public static let maximumCenterlineDelta: CGFloat = 1.5
    public static let minimumExpandedSidebarLeadingClearance: CGFloat = 4.0
    public static let minimumCollapsedNavLeadingClearance: CGFloat = 8.0
    public static let maximumNativeFullScreenCollapsedPadding: CGFloat = 16.0

    /// Vertical centerline of the sidebar's top control row in window coordinates (`8 + 36 / 2 = 26pt`).
    public static var sidebarHeaderCenterY: CGFloat {
        sidebarCardVerticalInset + sidebarHeaderHeight / 2.0
    }

    /// Vertical centerline of the main header bar in window coordinates (`52 / 2 = 26pt`).
    public static var topHeaderBarCenterY: CGFloat {
        topHeaderBarHeight / 2.0
    }

    /// Leading padding inside the floating sidebar card's top control row (relative to card leading edge).
    public static func sidebarHeaderLeadingPadding(isNativeFullScreen: Bool) -> CGFloat {
        isNativeFullScreen ? 8 : 78
    }

    /// Leading padding of the main header bar's navigation capsule.
    public static func collapsedNavLeadingPadding(isSidebarVisible: Bool, isNativeFullScreen: Bool) -> CGFloat {
        if isSidebarVisible {
            return 8
        }
        return isNativeFullScreen ? 12 : 90
    }

    /// Bounding rectangle of the floating Liquid Glass sidebar card in top-left window coordinates.
    public static func sidebarCardRect(windowSize: CGSize) -> CGRect {
        let width = max(0, sidebarWidth - sidebarCardLeadingInset - sidebarCardTrailingInset)
        let height = max(0, windowSize.height - (sidebarCardVerticalInset * 2.0))
        return CGRect(
            x: sidebarCardLeadingInset,
            y: sidebarCardVerticalInset,
            width: width,
            height: height
        )
    }

    /// Exact signed-distance inward clearance (in points) of a circular button inside a rounded rectangle.
    ///
    /// Positive values indicate the entire circular button sits strictly inside both the straight edges
    /// and circular corner arcs with that many points of margin; negative values indicate border or
    /// corner-arc overlap/clipping.
    public static func inwardClearance(
        ofCircleIn buttonFrame: CGRect,
        insideRoundedRect rect: CGRect,
        cornerRadius: CGFloat
    ) -> CGFloat {
        let hx = max(0, rect.width / 2.0)
        let hy = max(0, rect.height / 2.0)
        let rc = max(0, min(cornerRadius, min(hx, hy)))
        let radius = max(0, min(buttonFrame.width, buttonFrame.height) / 2.0)

        let qx = abs(buttonFrame.midX - rect.midX) - (hx - rc)
        let qy = abs(buttonFrame.midY - rect.midY) - (hy - rc)
        let outsideDistance = hypot(max(qx, 0), max(qy, 0))
        let insideDistance = min(max(qx, qy), 0)
        let signedDistance = outsideDistance + insideDistance - rc
        return -signedDistance - radius
    }

    /// Audits traffic-light frames against all GlassGrid You window chrome invariants.
    public static func audit(
        trafficLights: TrafficLightFrames,
        windowSize: CGSize = CGSize(width: 1280, height: 800),
        collapsedLeadingPaddingOverride: CGFloat? = nil
    ) -> WindowChromeAuditResult {
        let cardRect = sidebarCardRect(windowSize: windowSize)
        let clearances = trafficLights.allButtons.map { button in
            inwardClearance(
                ofCircleIn: button,
                insideRoundedRect: cardRect,
                cornerRadius: sidebarCardCornerRadius
            )
        }
        let minInwardClearance = clearances.min() ?? -.greatestFiniteMagnitude

        let centerY = trafficLights.averageCenterY
        let sidebarHeaderCenterDelta = abs(centerY - sidebarHeaderCenterY)
        let topHeaderBarCenterDelta = abs(centerY - topHeaderBarCenterY)

        let expandedSidebarContentX = sidebarCardLeadingInset + sidebarHeaderLeadingPadding(isNativeFullScreen: false)
        let expandedSidebarLeadingClearance = expandedSidebarContentX - trafficLights.maxX

        let collapsedNavX = collapsedLeadingPaddingOverride
            ?? collapsedNavLeadingPadding(isSidebarVisible: false, isNativeFullScreen: false)
        let collapsedNavLeadingClearance = collapsedNavX - trafficLights.maxX

        let nativeFullScreenCollapsedPadding = collapsedNavLeadingPadding(
            isSidebarVisible: false,
            isNativeFullScreen: true
        )

        var violations: [String] = []
        if minInwardClearance < minimumTrafficLightClearance {
            violations.append(
                String(
                    format: "Traffic-light rounded-rect clearance %.2fpt < %.2fpt minimum",
                    minInwardClearance,
                    minimumTrafficLightClearance
                )
            )
        }
        if sidebarHeaderCenterDelta > maximumCenterlineDelta {
            violations.append(
                String(
                    format: "Sidebar header centerline delta %.2fpt > %.2fpt maximum",
                    sidebarHeaderCenterDelta,
                    maximumCenterlineDelta
                )
            )
        }
        if topHeaderBarCenterDelta > maximumCenterlineDelta {
            violations.append(
                String(
                    format: "Top header bar centerline delta %.2fpt > %.2fpt maximum",
                    topHeaderBarCenterDelta,
                    maximumCenterlineDelta
                )
            )
        }
        if expandedSidebarLeadingClearance < minimumExpandedSidebarLeadingClearance {
            violations.append(
                String(
                    format: "Expanded sidebar header clearance %.2fpt < %.2fpt minimum",
                    expandedSidebarLeadingClearance,
                    minimumExpandedSidebarLeadingClearance
                )
            )
        }
        if collapsedNavLeadingClearance < minimumCollapsedNavLeadingClearance {
            violations.append(
                String(
                    format: "Collapsed nav capsule clearance %.2fpt < %.2fpt minimum",
                    collapsedNavLeadingClearance,
                    minimumCollapsedNavLeadingClearance
                )
            )
        }
        if nativeFullScreenCollapsedPadding > maximumNativeFullScreenCollapsedPadding {
            violations.append(
                String(
                    format: "Native fullscreen collapsed nav padding %.2fpt > %.2fpt maximum",
                    nativeFullScreenCollapsedPadding,
                    maximumNativeFullScreenCollapsedPadding
                )
            )
        }

        return WindowChromeAuditResult(
            minInwardClearance: minInwardClearance,
            sidebarHeaderCenterDelta: sidebarHeaderCenterDelta,
            topHeaderBarCenterDelta: topHeaderBarCenterDelta,
            expandedSidebarLeadingClearance: expandedSidebarLeadingClearance,
            collapsedNavLeadingClearance: collapsedNavLeadingClearance,
            nativeFullScreenCollapsedPadding: nativeFullScreenCollapsedPadding,
            violations: violations
        )
    }
}

/// Pure geometry and responsive threshold helpers for Compact Single-Row Header (`52pt`) layout.
public enum CompactHeaderLayout {
    public static let headerHeight: CGFloat = WindowChromeLayout.topHeaderBarHeight
    public static let minDragGutterWidth: CGFloat = 16
    public static let narrowFoldThresholdWidth: CGFloat = 920
    public static let compactTabCollapseThresholdWidth: CGFloat = 880
    public static let compactTabHeight: CGFloat = 32
    public static let minActiveOmniboxWidth: CGFloat = 140
    public static let maxInactiveTabWidth: CGFloat = 124

    /// Returns `true` when secondary header controls (PiP & AirPlay) should fold into the `⋯` menu.
    public static func shouldFoldSecondaryControls(headerWidth: CGFloat) -> Bool {
        headerWidth < narrowFoldThresholdWidth
    }

    /// Returns `true` when inactive compact tabs should collapse into a compact `N Tabs` menu pill.
    public static func shouldCollapseInactiveTabs(headerWidth: CGFloat, tabCount: Int) -> Bool {
        headerWidth < compactTabCollapseThresholdWidth && tabCount > 2
    }

    /// Computes the available horizontal budget for the center tab/omnibox rail after subtracting
    /// sidebar width, traffic-light clearance, leading navigation capsule, trailing controls, and flanking drag gutters.
    public static func availableCenterRailWidth(
        windowWidth: CGFloat,
        isSidebarVisible: Bool,
        isNativeFullScreen: Bool,
        isMultiviewActive: Bool,
        hasLivePulseButton: Bool
    ) -> CGFloat {
        let headerWidth = max(0, windowWidth - (isSidebarVisible ? WindowChromeLayout.sidebarWidth : 0))
        let leadingPadding = WindowChromeLayout.collapsedNavLeadingPadding(
            isSidebarVisible: isSidebarVisible,
            isNativeFullScreen: isNativeFullScreen
        )
        // Leading capsule: sidebar toggle (when collapsed) + back + forward + reload (28pt each + 2pt gaps + 8pt padding)
        let leadingButtonCount: CGFloat = isSidebarVisible ? 3 : 4
        let leadingCapsuleWidth = leadingButtonCount * 28 + max(0, leadingButtonCount - 1) * 2 + 8

        let shouldFold = shouldFoldSecondaryControls(headerWidth: headerWidth)
        // Trailing capsule: Multiview, MiniPlayer, CompactToggle, ControlsMenu (+ PiP & AirPlay when not folded, + LivePulse when enabled)
        var trailingButtonCount: CGFloat = shouldFold ? 4 : 6
        if hasLivePulseButton {
            trailingButtonCount += 1
        }
        let trailingCapsuleWidth = trailingButtonCount * 28 + max(0, trailingButtonCount - 1) * 2 + 8
        let focusPillWidth: CGFloat = 32
        let multiviewPillWidth: CGFloat = isMultiviewActive ? 74 : 0
        let trailingStackSpacing: CGFloat = 6 + (isMultiviewActive ? 6 : 0)
        let trailingTotalWidth = focusPillWidth + multiviewPillWidth + trailingStackSpacing + trailingCapsuleWidth + 12

        let guttersWidth = 2 * minDragGutterWidth
        return max(0, headerWidth - leadingPadding - leadingCapsuleWidth - trailingTotalWidth - guttersWidth)
    }
}
