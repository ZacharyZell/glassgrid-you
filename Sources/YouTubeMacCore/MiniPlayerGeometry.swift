import CoreGraphics
import Foundation

/// Curated 16:9 Floating Mini-Player size presets.
public enum MiniPlayerSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: return "Compact (360×203)"
        case .standard: return "Standard (480×270)"
        case .large: return "Large (640×360)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .large: return "Large"
        }
    }

    public var size: CGSize {
        switch self {
        case .compact: return CGSize(width: 360, height: 203)
        case .standard: return CGSize(width: 480, height: 270)
        case .large: return CGSize(width: 640, height: 360)
        }
    }

    public static func closest(to size: CGSize) -> MiniPlayerSizePreset {
        Self.allCases.min { lhs, rhs in
            abs(lhs.size.width - size.width) < abs(rhs.size.width - size.width)
        } ?? .standard
    }
}

/// Pure, deterministic AppKit-coordinate geometry helpers for Floating Mini-Player magnetic corner snapping
/// and edge-anchored size preset transitions.
public enum MiniPlayerGeometry {
    public static let defaultCornerInset: CGFloat = 20
    public static let defaultSnapThreshold: CGFloat = 48

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
    /// (so a bottom-right panel stays anchored at bottom-right) and clamping cleanly within `visibleFrame`.
    public static func resizedFrame(
        from current: CGRect,
        to preset: MiniPlayerSizePreset,
        in visibleFrame: CGRect,
        inset: CGFloat = defaultCornerInset
    ) -> CGRect {
        let maxW = max(300, visibleFrame.width - inset * 2)
        let maxH = max(169, visibleFrame.height - inset * 2)
        let targetW = min(preset.size.width, maxW)
        let targetH = min((targetW * 9.0 / 16.0).rounded(), maxH)

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
        return CGRect(x: clampedX.rounded(), y: clampedY.rounded(), width: targetW.rounded(), height: targetH.rounded())
    }
}
