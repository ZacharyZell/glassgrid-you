import CoreGraphics
import Foundation

/// Pure descriptor of a connected macOS display (built-in, external monitor, or AirPlay 2 / Apple TV display).
public struct ConnectedDisplayDescriptor: Identifiable, Equatable, Hashable, Sendable {
    public let id: UInt32
    public let name: String
    public let visibleFrame: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let isPrimary: Bool

    public init(
        id: UInt32,
        name: String,
        visibleFrame: CGRect,
        pixelWidth: Int,
        pixelHeight: Int,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.visibleFrame = visibleFrame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isPrimary = isPrimary
    }

    public var resolutionLabel: String {
        "\(pixelWidth)×\(pixelHeight)"
    }
}

/// Structured result returned by `EnhancementScript.showAirPlayPickerScript`.
public enum AirPlayPickerResult: String, Equatable, Sendable {
    case ok = "ok"
    case mseUnsupported = "mse_unsupported"
    case unavailable = "unavailable"
    case noVideo = "no_video"
}

/// Pure, deterministic window frame calculation for moving GlassGrid You (and full Multiview walls)
/// cleanly onto an external or AirPlay TV display across multi-monitor coordinate spaces (including negative origins).
public enum WindowDisplayRouter {
    public static func targetFrame(
        currentFrame: CGRect,
        targetVisibleFrame: CGRect,
        maximizeForTV: Bool
    ) -> CGRect {
        guard targetVisibleFrame.width > 0, targetVisibleFrame.height > 0 else {
            return currentFrame
        }
        if maximizeForTV {
            return targetVisibleFrame.integral
        }

        let width = min(max(currentFrame.width, 780), targetVisibleFrame.width)
        let height = min(max(currentFrame.height, 520), targetVisibleFrame.height)
        let originX = targetVisibleFrame.minX + ((targetVisibleFrame.width - width) / 2.0)
        let originY = targetVisibleFrame.minY + ((targetVisibleFrame.height - height) / 2.0)

        let clampedX = min(max(originX, targetVisibleFrame.minX), targetVisibleFrame.maxX - width)
        let clampedY = min(max(originY, targetVisibleFrame.minY), targetVisibleFrame.maxY - height)
        return CGRect(x: clampedX, y: clampedY, width: width, height: height).integral
    }
}
