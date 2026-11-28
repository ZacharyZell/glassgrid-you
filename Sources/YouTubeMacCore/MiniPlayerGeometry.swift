import CoreGraphics
import Foundation

/// Active presentation mode inside the always-on-top Floating Mini-Player panel.
public enum MiniPlayerMode: String, Codable, Equatable, Hashable, Sendable {
    case single
    case multiviewGrid
}

/// Curated 16:9 Floating Mini-Player size presets.
public enum MiniPlayerSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "Compact (360×203)"
        case .standard: return "Standard (480×270)"
        case .large: return "Large (640×360)"
        case .extraLarge: return "XL (880×495)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "XL"
        }
    }

    public var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 360, height: 203)
        case .standard: return CGSize(width: 480, height: 270)
        case .large: return CGSize(width: 640, height: 360)
        case .extraLarge: return CGSize(width: 880, height: 495)
        }
    }

    public static func closest(to size: CGSize) -> MiniPlayerSizePreset {
        Self.allCases.min { lhs, rhs in
            abs(lhs.size.width - size.width) < abs(rhs.size.width - size.width)
        } ?? .standard
    }

    public static func stepSmaller(from currentSize: CGSize, tolerance: CGFloat = 12) -> MiniPlayerSizePreset {
        let ordered = Self.allCases
        for candidate in ordered.reversed() {
            if candidate.size.width < currentSize.width - tolerance {
                return candidate
            }
        }
        return ordered.first ?? .compact
    }

    public static func stepLarger(from currentSize: CGSize, tolerance: CGFloat = 12) -> MiniPlayerSizePreset {
        let ordered = Self.allCases
        for candidate in ordered {
            if candidate.size.width > currentSize.width + tolerance {
                return candidate
            }
        }
        return ordered.last ?? .extraLarge
    }
}

/// Curated 16:9 Floating Multiview Grid Mini-Player size presets.
public enum MiniPlayerGridSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large
    case extraLarge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "Compact (540×304)"
        case .standard: return "Standard (680×383)"
        case .large: return "Large (880×495)"
        case .extraLarge: return "XL (1040×585)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .large: return "Large"
        case .extraLarge: return "XL"
        }
    }

    public var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 540, height: 304)
        case .standard: return CGSize(width: 680, height: 383)
        case .large: return CGSize(width: 880, height: 495)
        case .extraLarge: return CGSize(width: 1040, height: 585)
        }
    }

    public static func closest(to size: CGSize) -> MiniPlayerGridSizePreset {
        Self.allCases.min { lhs, rhs in
            abs(lhs.size.width - size.width) < abs(rhs.size.width - size.width)
        } ?? .standard
    }

    public static func stepSmaller(from currentSize: CGSize, tolerance: CGFloat = 12) -> MiniPlayerGridSizePreset {
        let ordered = Self.allCases
        for candidate in ordered.reversed() {
            if candidate.size.width < currentSize.width - tolerance {
                return candidate
            }
        }
        return ordered.first ?? .compact
    }

    public static func stepLarger(from currentSize: CGSize, tolerance: CGFloat = 12) -> MiniPlayerGridSizePreset {
        let ordered = Self.allCases
        for candidate in ordered {
            if candidate.size.width > currentSize.width + tolerance {
                return candidate
            }
        }
        return ordered.last ?? .extraLarge
    }
}

/// Edge or corner handle dragged to resize the Floating Mini-Player panel in screen coordinates.
public enum MiniPlayerResizeEdge: String, CaseIterable, Sendable {
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

/// Pure, deterministic AppKit-coordinate geometry helpers for Floating Mini-Player magnetic corner snapping
/// and edge-anchored size preset transitions.
public enum MiniPlayerGeometry {
    public static let defaultCornerInset: CGFloat = 20
    public static let defaultSnapThreshold: CGFloat = 48
    public static let gridMinimumSize = CGSize(width: 440, height: 248)

    /// Snaps `frame` to the nearest `visibleFrame` corner (at `inset`) ONLY when within `snapThreshold`
    /// points of that corner, preserving `frame.size` (16:9 aspect ratio) and never fighting mid-screen placements.
    public static func snappedFrame(
        _ frame: CGRect,
        in visibleFrame: CGRect,
        inset: CGFloat = defaultCornerInset,
        snapThreshold: CGFloat = defaultSnapThreshold
    ) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0, frame.width > 0, frame.height > 0 else {
            return frame
        }

        let leftX = visibleFrame.minX + inset
        let rightX = max(leftX, visibleFrame.maxX - frame.width - inset)
        let bottomY = visibleFrame.minY + inset
        let topY = max(bottomY, visibleFrame.maxY - frame.height - inset)

        let cornerOrigins: [CGPoint] = [
            CGPoint(x: leftX, y: bottomY),
            CGPoint(x: rightX, y: bottomY),
            CGPoint(x: leftX, y: topY),
            CGPoint(x: rightX, y: topY)
        ]

        var bestOrigin: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for origin in cornerOrigins {
            let dx = frame.origin.x - origin.x
            let dy = frame.origin.y - origin.y
            let distance = hypot(dx, dy)
            if distance <= snapThreshold && distance < bestDistance {
                bestDistance = distance
                bestOrigin = origin
            }
        }

        guard let snappedOrigin = bestOrigin else {
            return frame
        }
        return CGRect(origin: snappedOrigin, size: frame.size)
    }

    /// Resizes `current` to `preset` while anchoring to the nearest horizontal and vertical screen edges
    /// (so a bottom-right panel stays anchored at bottom-right) and clamping cleanly within `visibleFrame`
    /// while preserving a 16:9 aspect ratio on short screens.
    public static func resizedFrame(
        from current: CGRect,
        to preset: MiniPlayerSizePreset,
        in visibleFrame: CGRect,
        inset: CGFloat = defaultCornerInset
    ) -> CGRect {
        let maxW = max(300, visibleFrame.width - inset * 2)
        let maxH = max(169, visibleFrame.height - inset * 2)
        var targetW = min(preset.size.width, maxW)
        var targetH = (targetW * 9.0 / 16.0).rounded()
        if targetH > maxH {
            targetH = max(169, maxH)
            targetW = max(300, min(maxW, (targetH * 16.0 / 9.0).rounded()))
        }
        return anchoredFrame(from: current, targetSize: CGSize(width: targetW, height: targetH), in: visibleFrame)
    }

    /// Resizes `current` to a Floating Multiview Grid `preset` while anchoring to the nearest horizontal
    /// and vertical screen edges and clamping cleanly within `visibleFrame` at `gridMinimumSize` (`440×248`).
    public static func resizedGridFrame(
        from current: CGRect,
        to preset: MiniPlayerGridSizePreset,
        in visibleFrame: CGRect,
        inset: CGFloat = defaultCornerInset
    ) -> CGRect {
        let maxW = max(gridMinimumSize.width, visibleFrame.width - inset * 2)
        let maxH = max(gridMinimumSize.height, visibleFrame.height - inset * 2)
        var targetW = min(preset.size.width, maxW)
        var targetH = (targetW * 9.0 / 16.0).rounded()
        if targetH > maxH {
            targetH = max(gridMinimumSize.height, maxH)
            targetW = max(gridMinimumSize.width, min(maxW, (targetH * 16.0 / 9.0).rounded()))
        }
        return anchoredFrame(from: current, targetSize: CGSize(width: targetW, height: targetH), in: visibleFrame)
    }

    /// Computes a smooth live-drag resize frame in AppKit bottom-left screen coordinates while anchoring the
    /// opposite edge/corner, maintaining optional 16:9 aspect ratio, and clamping inside `visibleFrame`.
    public static func dragResizedFrame(
        initialFrame: CGRect,
        edge: MiniPlayerResizeEdge,
        delta: CGSize,
        maintainAspectRatio: Bool,
        minSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0,
              initialFrame.width > 0, initialFrame.height > 0,
              delta.width.isFinite, delta.height.isFinite else {
            return initialFrame
        }

        let screenMargin: CGFloat = 8
        let movesLeft = (edge == .left || edge == .topLeft || edge == .bottomLeft)
        let movesRight = (edge == .right || edge == .topRight || edge == .bottomRight)
        let movesBottom = (edge == .bottom || edge == .bottomLeft || edge == .bottomRight)
        let movesTop = (edge == .top || edge == .topLeft || edge == .topRight)

        let rawW: CGFloat
        if movesLeft {
            rawW = initialFrame.width - delta.width
        } else if movesRight {
            rawW = initialFrame.width + delta.width
        } else {
            rawW = initialFrame.width
        }

        let rawH: CGFloat
        if movesBottom {
            rawH = initialFrame.height - delta.height
        } else if movesTop {
            rawH = initialFrame.height + delta.height
        } else {
            rawH = initialFrame.height
        }

        let fullAvailW = max(minSize.width, visibleFrame.width - screenMargin * 2)
        let fullAvailH = max(minSize.height, visibleFrame.height - screenMargin * 2)

        let availW: CGFloat
        if movesLeft {
            availW = min(fullAvailW, max(minSize.width, initialFrame.maxX - (visibleFrame.minX + screenMargin)))
        } else if movesRight {
            availW = min(fullAvailW, max(minSize.width, (visibleFrame.maxX - screenMargin) - initialFrame.minX))
        } else {
            availW = fullAvailW
        }

        let availH: CGFloat
        if movesBottom {
            availH = min(fullAvailH, max(minSize.height, initialFrame.maxY - (visibleFrame.minY + screenMargin)))
        } else if movesTop {
            availH = min(fullAvailH, max(minSize.height, (visibleFrame.maxY - screenMargin) - initialFrame.minY))
        } else {
            availH = fullAvailH
        }

        var targetW: CGFloat
        var targetH: CGFloat

        if maintainAspectRatio {
            let verticalOnly = (edge == .top || edge == .bottom)
            let horizontalOnly = (edge == .left || edge == .right)
            let verticalDrives = verticalOnly || (!horizontalOnly && abs(delta.height * 16.0 / 9.0) > abs(delta.width))

            if verticalDrives {
                targetH = min(max(rawH, minSize.height), availH).rounded()
                targetW = (targetH * 16.0 / 9.0).rounded()
                if targetW > availW {
                    targetW = availW.rounded()
                    targetH = (targetW * 9.0 / 16.0).rounded()
                }
                if targetW < minSize.width {
                    targetW = minSize.width.rounded()
                    targetH = (targetW * 9.0 / 16.0).rounded()
                }
            } else {
                targetW = min(max(rawW, minSize.width), availW).rounded()
                targetH = (targetW * 9.0 / 16.0).rounded()
                if targetH > availH {
                    targetH = availH.rounded()
                    targetW = (targetH * 16.0 / 9.0).rounded()
                }
                if targetH < minSize.height {
                    targetH = minSize.height.rounded()
                    targetW = (targetH * 16.0 / 9.0).rounded()
                }
            }
        } else {
            targetW = min(max(rawW, minSize.width), availW).rounded()
            targetH = min(max(rawH, minSize.height), availH).rounded()
        }

        let rawX: CGFloat
        if movesLeft {
            rawX = initialFrame.maxX - targetW
        } else if movesRight {
            rawX = initialFrame.minX
        } else {
            rawX = initialFrame.midX - (targetW / 2.0)
        }

        let rawY: CGFloat
        if movesBottom {
            rawY = initialFrame.maxY - targetH
        } else if movesTop {
            rawY = initialFrame.minY
        } else {
            rawY = initialFrame.midY - (targetH / 2.0)
        }

        let minX = visibleFrame.minX + screenMargin
        let maxX = max(minX, visibleFrame.maxX - targetW - screenMargin)
        let minY = visibleFrame.minY + screenMargin
        let maxY = max(minY, visibleFrame.maxY - targetH - screenMargin)

        return CGRect(
            x: min(max(rawX, minX), maxX).rounded(),
            y: min(max(rawY, minY), maxY).rounded(),
            width: targetW,
            height: targetH
        )
    }

    private static func anchoredFrame(
        from current: CGRect,
        targetSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGRect {
        let targetW = targetSize.width.rounded()
        let targetH = targetSize.height.rounded()
        let closerToRight = (visibleFrame.maxX - current.maxX) <= (current.minX - visibleFrame.minX)
        let closerToTop = (visibleFrame.maxY - current.maxY) <= (current.minY - visibleFrame.minY)

        let rawX = closerToRight ? (current.maxX - targetW) : current.minX
        let rawY = closerToTop ? (current.maxY - targetH) : current.minY

        let minX = visibleFrame.minX + 8
        let maxX = max(minX, visibleFrame.maxX - targetW - 8)
        let minY = visibleFrame.minY + 8
        let maxY = max(minY, visibleFrame.maxY - targetH - 8)

        let clampedX = min(max(rawX, minX), maxX)
        let clampedY = min(max(rawY, minY), maxY)
        return CGRect(x: clampedX.rounded(), y: clampedY.rounded(), width: targetW, height: targetH)
    }
}

/// Resolved target placement for the opt-in Notch Media HUD pill.
public struct NotchMediaHUDPlacement: Equatable, Sendable {
    public let frame: CGRect
    public let hasNotch: Bool
    public let notchWidth: CGFloat

    public init(frame: CGRect, hasNotch: Bool, notchWidth: CGFloat) {
        self.frame = frame
        self.hasNotch = hasNotch
        self.notchWidth = notchWidth
    }
}

/// Pure AppKit-coordinate geometry calculator for placing the Notch Media HUD around MacBook hardware notches
/// or as a compact top-edge pill on notchless / external displays.
public enum NotchMediaHUDGeometry {
    public static let notchSideWingWidth: CGFloat = 98
    public static let minimumNotchHUDWidth: CGFloat = 360
    public static let minimumNotchHUDHeight: CGFloat = 32
    public static let fallbackWidth: CGFloat = 340
    public static let fallbackHeight: CGFloat = 36
    public static let fallbackTopInset: CGFloat = 6

    public static func targetFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> NotchMediaHUDPlacement {
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return NotchMediaHUDPlacement(frame: .zero, hasNotch: false, notchWidth: 0)
        }

        if safeAreaTop > 0,
           let left = auxiliaryTopLeft,
           let right = auxiliaryTopRight,
           right.minX > left.maxX {
            let notchWidth = (right.minX - left.maxX).rounded()
            let maxAllowedWidth = max(240, screenFrame.width - 16)
            let desiredWidth = max(minimumNotchHUDWidth, notchWidth + notchSideWingWidth * 2)
            let totalWidth = min(maxAllowedWidth, desiredWidth).rounded()
            let height = max(minimumNotchHUDHeight, safeAreaTop.rounded())
            let notchMidX = left.maxX + (notchWidth / 2.0)
            let rawX = (notchMidX - (totalWidth / 2.0)).rounded()
            let minX = screenFrame.minX + 8
            let maxX = max(minX, screenFrame.maxX - totalWidth - 8)
            let clampedX = min(max(rawX, minX), maxX)
            let y = (screenFrame.maxY - height).rounded()

            return NotchMediaHUDPlacement(
                frame: CGRect(x: clampedX, y: y, width: totalWidth, height: height),
                hasNotch: true,
                notchWidth: notchWidth
            )
        }

        let effectiveVisible = (visibleFrame.width > 0 && visibleFrame.height > 0) ? visibleFrame : screenFrame
        let maxAllowedWidth = max(240, effectiveVisible.width - 16)
        let width = min(fallbackWidth, maxAllowedWidth).rounded()
        let height = fallbackHeight
        let x = (effectiveVisible.midX - (width / 2.0)).rounded()
        let y = (effectiveVisible.maxY - height - fallbackTopInset).rounded()

        return NotchMediaHUDPlacement(
            frame: CGRect(x: x, y: y, width: width, height: height),
            hasNotch: false,
            notchWidth: 0
        )
    }

    /// Computes an expanded interactive Notch Media HUD frame anchored at `base.frame.maxY`,
    /// preserving `notchWidth` and clamping cleanly inside `screenFrame` / `visibleFrame`.
    public static func expandedFrame(
        from base: NotchMediaHUDPlacement,
        in screenFrame: CGRect,
        visibleFrame: CGRect,
        extraHeight: CGFloat = 86,
        extraHorizontalWing: CGFloat = 34
    ) -> NotchMediaHUDPlacement {
        guard base.frame.width > 0, base.frame.height > 0,
              screenFrame.width > 0, screenFrame.height > 0 else {
            return base
        }

        let safeExtraHeight = max(0, extraHeight.isFinite ? extraHeight : 0)
        let safeExtraWing = max(0, extraHorizontalWing.isFinite ? extraHorizontalWing : 0)
        let effectiveVisible = (visibleFrame.width > 0 && visibleFrame.height > 0) ? visibleFrame : screenFrame

        if base.hasNotch {
            let minX = screenFrame.minX + 8
            let maxAvailableWidth = max(base.frame.width, screenFrame.width - 16)
            let targetWidth = min(maxAvailableWidth, base.frame.width + safeExtraWing * 2).rounded()
            let rawX = (base.frame.midX - (targetWidth / 2.0)).rounded()
            let maxX = max(minX, screenFrame.maxX - targetWidth - 8)
            let clampedX = min(max(rawX, minX), maxX)

            let topY = min(base.frame.maxY, screenFrame.maxY)
            let maxHeight = max(base.frame.height, topY - (effectiveVisible.minY + 8))
            let targetHeight = min(maxHeight, base.frame.height + safeExtraHeight).rounded()
            let y = (topY - targetHeight).rounded()

            return NotchMediaHUDPlacement(
                frame: CGRect(x: clampedX, y: y, width: targetWidth, height: targetHeight),
                hasNotch: true,
                notchWidth: base.notchWidth
            )
        }

        let minX = effectiveVisible.minX + 8
        let maxAvailableWidth = max(base.frame.width, effectiveVisible.width - 16)
        let targetWidth = min(maxAvailableWidth, base.frame.width + safeExtraWing * 2).rounded()
        let rawX = (base.frame.midX - (targetWidth / 2.0)).rounded()
        let maxX = max(minX, effectiveVisible.maxX - targetWidth - 8)
        let clampedX = min(max(rawX, minX), maxX)

        let topY = min(base.frame.maxY, effectiveVisible.maxY)
        let maxHeight = max(base.frame.height, topY - (effectiveVisible.minY + 8))
        let targetHeight = min(maxHeight, base.frame.height + safeExtraHeight).rounded()
        let y = (topY - targetHeight).rounded()

        return NotchMediaHUDPlacement(
            frame: CGRect(x: clampedX, y: y, width: targetWidth, height: targetHeight),
            hasNotch: false,
            notchWidth: base.notchWidth
        )
    }
}
