import CoreGraphics
import Foundation

/// Layout styles for the native Multiview grid inside the main window.
public enum MultiviewLayoutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto
    case spotlight
    case stacked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Grid"
        case .spotlight: return "Spotlight"
        case .stacked: return "Stacked"
        }
    }

    public var systemImage: String {
        switch self {
        case .auto: return "square.grid.2x2"
        case .spotlight: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        }
    }

    public var nextMode: MultiviewLayoutMode {
        let all = Self.allCases
        guard let idx = all.firstIndex(of: self) else { return .auto }
        return all[(idx + 1) % all.count]
    }
}

/// Forward-compatible preset model for saving and restoring custom Multiview layouts (e.g., Sunday Ticket Quad-Box).
public struct MultiviewPreset: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var urlStrings: [String]
    public var layoutMode: MultiviewLayoutMode

    public init(
        id: UUID = UUID(),
        name: String,
        urlStrings: [String],
        layoutMode: MultiviewLayoutMode = .auto
    ) {
        self.id = id
        self.name = name
        self.urlStrings = Array(urlStrings.prefix(MultiviewGridLayout.maxTiles))
        self.layoutMode = layoutMode
    }
}

/// Pure, unit-testable state representation for Native Multiview Mode.
public struct MultiviewState: Equatable, Sendable {
    public var tabIDs: [UUID]
    public var audioTabID: UUID?
    public var layoutMode: MultiviewLayoutMode

    public static let inactive = MultiviewState(tabIDs: [], audioTabID: nil, layoutMode: .auto)

    public init(
        tabIDs: [UUID] = [],
        audioTabID: UUID? = nil,
        layoutMode: MultiviewLayoutMode = .auto
    ) {
        self.tabIDs = tabIDs
        self.audioTabID = audioTabID
        self.layoutMode = layoutMode
    }

    public var isActive: Bool {
        tabIDs.count >= 2
    }
}

/// Pure state transitions for Multiview tile membership, ordering, and exclusive audio focus.
public enum MultiviewReducer {
    /// Enters Multiview with up to 4 deduplicated tabs starting with `primaryTabID`.
    public static func enter(
        primaryTabID: UUID,
        candidateTabIDs: [UUID],
        preferredAudioTabID: UUID? = nil,
        layoutMode: MultiviewLayoutMode = .auto
    ) -> MultiviewState {
        var ordered: [UUID] = [primaryTabID]
        for id in candidateTabIDs where id != primaryTabID && !ordered.contains(id) {
            ordered.append(id)
            if ordered.count >= MultiviewGridLayout.maxTiles {
                break
            }
        }
        guard ordered.count >= 2 else {
            return MultiviewState(tabIDs: [], audioTabID: nil, layoutMode: layoutMode)
        }
        let audioID: UUID
        if let preferred = preferredAudioTabID, ordered.contains(preferred) {
            audioID = preferred
        } else {
            audioID = primaryTabID
        }
        return MultiviewState(tabIDs: ordered, audioTabID: audioID, layoutMode: layoutMode)
    }

    /// Appends a tile if space remains (`< maxTiles`) and not already present.
    public static func addTile(_ tabID: UUID, to state: MultiviewState) -> MultiviewState {
        guard !state.tabIDs.contains(tabID), state.tabIDs.count < MultiviewGridLayout.maxTiles else {
            return state
        }
        var next = state
        next.tabIDs.append(tabID)
        if next.audioTabID == nil {
            next.audioTabID = next.tabIDs.first
        }
        return next
    }

    /// Removes a tile, transferring audio focus if needed, and auto-exits when `< 2` tiles remain.
    /// Returns the next state and the surviving tab ID to select when exiting.
    public static func removeTile(
        _ tabID: UUID,
        from state: MultiviewState
    ) -> (state: MultiviewState, remainingSingleTabID: UUID?) {
        guard let removedIndex = state.tabIDs.firstIndex(of: tabID) else {
            return (state, nil)
        }
        var remaining = state.tabIDs
        remaining.remove(at: removedIndex)

        if remaining.count < 2 {
            return (
                MultiviewState(tabIDs: [], audioTabID: nil, layoutMode: state.layoutMode),
                remaining.first
            )
        }

        var nextAudio = state.audioTabID
        if nextAudio == tabID || nextAudio.map({ !remaining.contains($0) }) == true {
            let fallbackIndex = min(removedIndex, remaining.count - 1)
            nextAudio = remaining[fallbackIndex]
        }
        return (
            MultiviewState(tabIDs: remaining, audioTabID: nextAudio, layoutMode: state.layoutMode),
            nil
        )
    }

    /// Promotes a tile to slot 0 (primary position in Grid/Spotlight) and optionally gives it audio focus.
    public static func promoteToPrimary(
        _ tabID: UUID,
        in state: MultiviewState,
        transferAudio: Bool = true
    ) -> MultiviewState {
        guard let idx = state.tabIDs.firstIndex(of: tabID) else {
            return state
        }
        var next = state
        if idx != 0 {
            next.tabIDs.remove(at: idx)
            next.tabIDs.insert(tabID, at: 0)
        }
        if transferAudio {
            next.audioTabID = tabID
        }
        return next
    }

    /// Sets exclusive audio focus to `tabID` (must be in `state.tabIDs`).
    public static func focusAudio(_ tabID: UUID, in state: MultiviewState) -> MultiviewState {
        guard state.tabIDs.contains(tabID) else { return state }
        var next = state
        next.audioTabID = tabID
        return next
    }

    /// Cycles audio focus forward (`delta = +1`) or backward (`delta = -1`).
    public static func cycleAudioFocus(by delta: Int, in state: MultiviewState) -> MultiviewState {
        guard !state.tabIDs.isEmpty else { return state }
        let currentIndex = state.audioTabID.flatMap { state.tabIDs.firstIndex(of: $0) } ?? 0
        let count = state.tabIDs.count
        let nextIndex = ((currentIndex + delta) % count + count) % count
        var next = state
        next.audioTabID = state.tabIDs[nextIndex]
        return next
    }

    /// Moves `tabID` left (`delta = -1`) or right (`delta = +1`) in the Multiview grid while preserving audio focus & layout mode.
    public static func moveTile(
        _ tabID: UUID,
        by delta: Int,
        in state: MultiviewState
    ) -> MultiviewState {
        guard let idx = state.tabIDs.firstIndex(of: tabID) else { return state }
        let targetIdx = idx + delta
        guard state.tabIDs.indices.contains(targetIdx), targetIdx != idx else { return state }
        return swapTiles(at: idx, and: targetIdx, in: state)
    }

    /// Swaps two tiles by slot index while preserving `audioTabID` and `layoutMode`.
    public static func swapTiles(
        at firstIndex: Int,
        and secondIndex: Int,
        in state: MultiviewState
    ) -> MultiviewState {
        guard state.tabIDs.indices.contains(firstIndex),
              state.tabIDs.indices.contains(secondIndex),
              firstIndex != secondIndex else {
            return state
        }
        var next = state
        next.tabIDs.swapAt(firstIndex, secondIndex)
        return next
    }
}

/// Pure, deterministic top-left-origin integral pixel layout geometry shared identically by both AppKit
/// `TabWebViewHost` and SwiftUI `MultiviewOverlayView` so video tiles and Liquid Glass borders align to the pixel.
public enum MultiviewGridLayout {
    public static let maxTiles: Int = 4
    public static let defaultPadding: CGFloat = 10
    public static let defaultSpacing: CGFloat = 8

    /// Returns true if tile `index` is a large primary / 2-up slot eligible for up to 1080p quality.
    public static func isPrimarySlot(index: Int, count: Int, mode: MultiviewLayoutMode) -> Bool {
        guard count > 0, index >= 0, index < count else { return false }
        if count <= 2 {
            return true
        }
        switch mode {
        case .spotlight:
            return index == 0
        case .auto:
            return count == 3 && index == 0
        case .stacked:
            return false
        }
    }

    /// Computes non-overlapping integral-point tile frames in top-left-origin coordinates for `count` (`1...4`) tiles inside `containerSize`.
    public static func frames(
        forCount count: Int,
        in containerSize: CGSize,
        mode: MultiviewLayoutMode = .auto,
        padding: CGFloat = defaultPadding,
        spacing: CGFloat = defaultSpacing
    ) -> [CGRect] {
        let clampedCount = min(max(count, 0), maxTiles)
        guard clampedCount > 0, containerSize.width > 0, containerSize.height > 0 else {
            return []
        }

        let pad = padding.rounded(.down)
        let gap = spacing.rounded(.down)
        let innerX = pad
        let innerY = pad
        let innerWidth = max(0, containerSize.width.rounded(.down) - pad * 2)
        let innerHeight = max(0, containerSize.height.rounded(.down) - pad * 2)
        guard innerWidth > 0, innerHeight > 0 else {
            return Array(repeating: .zero, count: clampedCount)
        }

        if clampedCount == 1 {
            return [CGRect(x: innerX, y: innerY, width: innerWidth, height: innerHeight)]
        }

        switch mode {
        case .stacked:
            return stackedFrames(
                count: clampedCount,
                x: innerX,
                y: innerY,
                width: innerWidth,
                height: innerHeight,
                spacing: gap
            )

        case .spotlight:
            return spotlightFrames(
                count: clampedCount,
                x: innerX,
                y: innerY,
                width: innerWidth,
                height: innerHeight,
                spacing: gap
            )

        case .auto:
            switch clampedCount {
            case 2:
                // In tall/narrow half-screen Split Screen windows, stack 2 streams vertically so 16:9 video fills cleanly.
                if innerWidth < innerHeight * 1.05 {
                    return stackedFrames(
                        count: 2,
                        x: innerX,
                        y: innerY,
                        width: innerWidth,
                        height: innerHeight,
                        spacing: gap
                    )
                }
                let cols = splitIntegral(total: innerWidth, parts: 2, spacing: gap)
                return [
                    CGRect(x: innerX, y: innerY, width: cols[0], height: innerHeight),
                    CGRect(x: innerX + cols[0] + gap, y: innerY, width: cols[1], height: innerHeight)
                ]

            case 3:
                return spotlightFrames(
                    count: 3,
                    x: innerX,
                    y: innerY,
                    width: innerWidth,
                    height: innerHeight,
                    spacing: gap,
                    primaryRatio: 0.58
                )

            default:
                // 2×2 equal Quad-Box with exact integral remainder absorption
                let cols = splitIntegral(total: innerWidth, parts: 2, spacing: gap)
                let rows = splitIntegral(total: innerHeight, parts: 2, spacing: gap)
                let col2X = innerX + cols[0] + gap
                let row2Y = innerY + rows[0] + gap
                return [
                    CGRect(x: innerX, y: innerY, width: cols[0], height: rows[0]),
                    CGRect(x: col2X, y: innerY, width: cols[1], height: rows[0]),
                    CGRect(x: innerX, y: row2Y, width: cols[0], height: rows[1]),
                    CGRect(x: col2X, y: row2Y, width: cols[1], height: rows[1])
                ]
            }
        }
    }

    /// Splits `total` into `parts` integral lengths separated by `spacing`, absorbing remainder pixels cleanly with zero overlap.
    private static func splitIntegral(total: CGFloat, parts: Int, spacing: CGFloat) -> [CGFloat] {
        guard parts > 0 else { return [] }
        let available = max(0, Int(total.rounded(.down)) - Int(spacing) * (parts - 1))
        let base = available / parts
        let remainder = available % parts
        return (0..<parts).map { idx in
            CGFloat(base + (idx < remainder ? 1 : 0))
        }
    }

    private static func stackedFrames(
        count: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat
    ) -> [CGRect] {
        let heights = splitIntegral(total: height, parts: count, spacing: spacing)
        var cursorY = y
        return heights.map { h in
            let rect = CGRect(x: x, y: cursorY, width: width, height: h)
            cursorY += h + spacing
            return rect
        }
    }

    private static func spotlightFrames(
        count: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        primaryRatio: CGFloat = 0.64
    ) -> [CGRect] {
        let sideCount = count - 1
        // On narrow portrait-ish windows, put primary on top and secondary tiles in a bottom row.
        if width < height * 0.95 {
            let topHeight = max(0, ((height - spacing) * primaryRatio).rounded())
            let bottomHeight = max(0, height - topHeight - spacing)
            let bottomY = y + topHeight + spacing
            let sideWidths = splitIntegral(total: width, parts: sideCount, spacing: spacing)
            var result = [CGRect(x: x, y: y, width: width, height: topHeight)]
            var cursorX = x
            for w in sideWidths {
                result.append(CGRect(x: cursorX, y: bottomY, width: w, height: bottomHeight))
                cursorX += w + spacing
            }
            return result
        }

        let mainWidth = max(0, ((width - spacing) * primaryRatio).rounded())
        let sideWidth = max(0, width - mainWidth - spacing)
        let sideX = x + mainWidth + spacing
        let sideHeights = splitIntegral(total: height, parts: sideCount, spacing: spacing)

        var result = [CGRect(x: x, y: y, width: mainWidth, height: height)]
        var cursorY = y
        for h in sideHeights {
            result.append(CGRect(x: sideX, y: cursorY, width: sideWidth, height: h))
            cursorY += h + spacing
        }
        return result
    }
}
