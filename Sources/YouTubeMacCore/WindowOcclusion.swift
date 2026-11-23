import CoreGraphics
import Foundation

/// Lightweight metadata describing an on-screen window positioned above the target window in z-order.
public struct OccludingWindowDescriptor: Equatable, Sendable {
    public let ownerPID: Int32
    public let layer: Int
    public let alpha: Double
    public let isOnscreen: Bool
    public let bounds: CGRect

    public init(
        ownerPID: Int32,
        layer: Int,
        alpha: Double,
        isOnscreen: Bool = true,
        bounds: CGRect
    ) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.isOnscreen = isOnscreen
        self.bounds = bounds
    }
}

/// Pure, deterministic occlusion geometry calculator used to distinguish a visible Split Screen /
/// side-by-side YouTube window from one genuinely covered behind another app or on another Space.
public enum WindowOcclusionCalculator {
    /// Minimum covered fraction of the main window required to auto-pop-out the floating Mini-Player.
    public static let popOutOcclusionThreshold: Double = 0.35

    /// Maximum covered fraction at or below which an app-switch auto-popped Mini-Player docks back automatically.
    public static let autoDockOcclusionThreshold: Double = 0.15

    /// Minimum width and height (points) for an occluding window so tiny helper/tracking windows are ignored.
    public static let minimumOccludingDimension: CGFloat = 40

    /// Returns whether a window descriptor represents a normal-level app window that can obscure YouTube.
    public static func isOccludingWindow(
        _ window: OccludingWindowDescriptor,
        excludingPID ownPID: Int32
    ) -> Bool {
        guard window.ownerPID != ownPID else { return false }
        guard window.layer == 0 else { return false }
        guard window.isOnscreen else { return false }
        guard window.alpha > 0.05 else { return false }
        guard window.bounds.width >= minimumOccludingDimension,
              window.bounds.height >= minimumOccludingDimension else {
            return false
        }
        return true
    }

    /// Computes the exact fraction `[0.0, 1.0]` of `targetBounds` covered by the union of `occludingRects`.
    /// Uses an X-sweep with Y-interval merging so overlapping windows are never double-counted.
    public static func coveredFraction(
        of targetBounds: CGRect,
        by occludingRects: [CGRect]
    ) -> Double {
        let targetArea = Double(targetBounds.width * targetBounds.height)
        guard targetBounds.width > 0, targetBounds.height > 0, targetArea > 0 else {
            return 0
        }

        var clipped: [CGRect] = []
        clipped.reserveCapacity(occludingRects.count)
        for rect in occludingRects {
            let intersection = targetBounds.intersection(rect)
            if !intersection.isNull && intersection.width > 0 && intersection.height > 0 {
                clipped.append(intersection)
            }
        }
        guard !clipped.isEmpty else { return 0 }

        var xs: [CGFloat] = []
        xs.reserveCapacity(clipped.count * 2)
        for rect in clipped {
            xs.append(rect.minX)
            xs.append(rect.maxX)
        }
        xs.sort()

        var uniqueXs: [CGFloat] = []
        uniqueXs.reserveCapacity(xs.count)
        for x in xs {
            if let last = uniqueXs.last, abs(x - last) < 0.001 {
                continue
            }
            uniqueXs.append(x)
        }
        guard uniqueXs.count >= 2 else { return 0 }

        var coveredArea: Double = 0
        for i in 0..<(uniqueXs.count - 1) {
            let x0 = uniqueXs[i]
            let x1 = uniqueXs[i + 1]
            let dx = Double(x1 - x0)
            guard dx > 0 else { continue }
            let midX = (x0 + x1) * 0.5

            var yIntervals: [(CGFloat, CGFloat)] = []
            for rect in clipped where rect.minX <= midX && rect.maxX >= midX {
                yIntervals.append((rect.minY, rect.maxY))
            }
            guard !yIntervals.isEmpty else { continue }

            yIntervals.sort { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1 < rhs.1
            }

            var mergedHeight: Double = 0
            var currentStart = yIntervals[0].0
            var currentEnd = yIntervals[0].1
            for interval in yIntervals.dropFirst() {
                if interval.0 <= currentEnd {
                    currentEnd = max(currentEnd, interval.1)
                } else {
                    mergedHeight += Double(currentEnd - currentStart)
                    currentStart = interval.0
                    currentEnd = interval.1
                }
            }
            mergedHeight += Double(currentEnd - currentStart)
            coveredArea += dx * mergedHeight
        }

        return min(max(coveredArea / targetArea, 0.0), 1.0)
    }

    /// Decides whether the main YouTube window is behind another app or on another Space and should auto-pop-out.
    public static func shouldAutoPopOutWhenInactive(
        isWindowVisible: Bool,
        isOnActiveSpace: Bool,
        isOcclusionStateVisible: Bool,
        targetBounds: CGRect,
        aboveWindows: [OccludingWindowDescriptor],
        ownPID: Int32,
        threshold: Double = popOutOcclusionThreshold
    ) -> Bool {
        guard isWindowVisible else { return false }
        if !isOnActiveSpace || !isOcclusionStateVisible {
            return true
        }
        let occludingRects = aboveWindows
            .filter { isOccludingWindow($0, excludingPID: ownPID) }
            .map(\.bounds)
        let fraction = coveredFraction(of: targetBounds, by: occludingRects)
        return fraction >= threshold
    }

    /// Decides whether an app-switch auto-popped Mini-Player should dock back because the main window
    /// is visible and unobstructed on the active Space again (for example, returning to Split Screen).
    public static func shouldAutoDockWhenUncovered(
        isWindowVisible: Bool,
        isOnActiveSpace: Bool,
        isOcclusionStateVisible: Bool,
        targetBounds: CGRect,
        aboveWindows: [OccludingWindowDescriptor],
        ownPID: Int32,
        threshold: Double = autoDockOcclusionThreshold
    ) -> Bool {
        guard isWindowVisible, isOnActiveSpace, isOcclusionStateVisible else {
            return false
        }
        let occludingRects = aboveWindows
            .filter { isOccludingWindow($0, excludingPID: ownPID) }
            .map(\.bounds)
        let fraction = coveredFraction(of: targetBounds, by: occludingRects)
        return fraction <= threshold
    }
}
