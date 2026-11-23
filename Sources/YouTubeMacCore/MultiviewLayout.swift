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

/// Orientation of an interactive Multiview tile divider gutter.
public enum MultiviewDividerAxis: String, Codable, Hashable, Sendable {
    /// Vertical bar dividing left and right tiles (`resizeLeftRight` cursor).
    case vertical
    /// Horizontal bar dividing top and bottom tiles (`resizeUpDown` cursor).
    case horizontal
}

/// Stable identifier for a draggable Multiview divider axis.
public enum MultiviewDividerID: Equatable, Hashable, Codable, Sendable {
    case column
    case row
    case spotlight
    case stacked(Int)
}

/// Pixel-exact descriptor shared between AppKit gutter hit handles and SwiftUI Liquid Glass pill visuals.
public struct MultiviewDividerDescriptor: Equatable, Hashable, Identifiable, Sendable {
    public let id: MultiviewDividerID
    public let axis: MultiviewDividerAxis
    public let frame: CGRect
    public let ratio: CGFloat
    public let leadingPercent: Int
    public let trailingPercent: Int

    public init(
        id: MultiviewDividerID,
        axis: MultiviewDividerAxis,
        frame: CGRect,
        ratio: CGFloat,
        leadingPercent: Int,
        trailingPercent: Int
    ) {
        self.id = id
        self.axis = axis
        self.frame = frame
        self.ratio = ratio
        self.leadingPercent = leadingPercent
        self.trailingPercent = trailingPercent
    }
}

/// Custom user-dragged split ratios for Multiview layouts with safe clamping and backward-compatible `Codable`.
public struct MultiviewSplitRatios: Equatable, Hashable, Codable, Sendable {
    public static let minRatio: CGFloat = 0.22
    public static let maxRatio: CGFloat = 0.78
    public static let minStackedWeight: CGFloat = 0.15

    public var columnRatio: CGFloat
    public var rowRatio: CGFloat
    public var spotlightRatio: CGFloat?
    public var stackedWeights: [CGFloat]?

    public static let `default` = MultiviewSplitRatios()

    public init(
        columnRatio: CGFloat = 0.50,
        rowRatio: CGFloat = 0.50,
        spotlightRatio: CGFloat? = nil,
        stackedWeights: [CGFloat]? = nil
    ) {
        self.columnRatio = Self.clampRatio(columnRatio)
        self.rowRatio = Self.clampRatio(rowRatio)
        self.spotlightRatio = spotlightRatio.map(Self.clampRatio)
        self.stackedWeights = stackedWeights.map(Self.normalizeStackedWeights)
    }

    public static func clampRatio(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0.50 }
        return min(max(value, minRatio), maxRatio)
    }

    /// Normalizes row weights for `Stacked` mode so they sum to `1.0` with a per-row floor of `0.15`.
    public static func normalizeStackedWeights(_ raw: [CGFloat]) -> [CGFloat] {
        guard raw.count >= 2 else { return [] }
        let safe = raw.map { ($0.isFinite && $0 > 0) ? $0 : 1.0 }
        let total = safe.reduce(0, +)
        guard total > 0 else {
            return Array(repeating: 1.0 / CGFloat(raw.count), count: raw.count)
        }
        var weights = safe.map { $0 / total }
        let floor = min(minStackedWeight, 1.0 / CGFloat(weights.count))

        // Iteratively enforce per-row floor while preserving unit sum.
        for _ in 0..<4 {
            var deficit: CGFloat = 0
            var surplusTotal: CGFloat = 0
            for i in weights.indices {
                if weights[i] < floor {
                    deficit += (floor - weights[i])
                    weights[i] = floor
                } else {
                    surplusTotal += (weights[i] - floor)
                }
            }
            guard deficit > 0.0001, surplusTotal > 0.0001 else { break }
            let scale = max(0, (surplusTotal - deficit) / surplusTotal)
            for i in weights.indices where weights[i] > floor {
                weights[i] = floor + (weights[i] - floor) * scale
            }
        }

        let finalSum = weights.reduce(0, +)
        return finalSum > 0 ? weights.map { $0 / finalSum } : Array(repeating: 1.0 / CGFloat(raw.count), count: raw.count)
    }

    public func resolvedStackedWeights(for count: Int) -> [CGFloat] {
        guard count >= 2 else { return count == 1 ? [1.0] : [] }
        if count == 2 {
            let top = Self.clampRatio(rowRatio)
            return [top, 1.0 - top]
        }
        if let existing = stackedWeights, existing.count == count {
            return Self.normalizeStackedWeights(existing)
        }
        return Array(repeating: 1.0 / CGFloat(count), count: count)
    }

    public func resolvedSpotlightRatio(defaultRatio: CGFloat) -> CGFloat {
        if let spotlightRatio {
            return Self.clampRatio(spotlightRatio)
        }
        return Self.clampRatio(defaultRatio)
    }

    /// Returns a copy with `divider` updated to a new normalized position (`0...1` along the active axis).
    public func updating(divider: MultiviewDividerID, to normalizedPosition: CGFloat, tileCount: Int) -> MultiviewSplitRatios {
        var next = self
        switch divider {
        case .column:
            next.columnRatio = Self.clampRatio(normalizedPosition)
        case .row:
            next.rowRatio = Self.clampRatio(normalizedPosition)
        case .spotlight:
            next.spotlightRatio = Self.clampRatio(normalizedPosition)
        case .stacked(let index):
            guard tileCount >= 2, index >= 0, index < tileCount - 1 else { return next }
            if tileCount == 2 {
                next.rowRatio = Self.clampRatio(normalizedPosition)
                return next
            }
            var weights = resolvedStackedWeights(for: tileCount)
            let prefixSum = weights.prefix(index).reduce(0, +)
            let pairTotal = weights[index] + weights[index + 1]
            let floor = min(Self.minStackedWeight, pairTotal / 2)
            let desiredFirst = normalizedPosition - prefixSum
            let clampedFirst = min(max(desiredFirst, floor), pairTotal - floor)
            weights[index] = clampedFirst
            weights[index + 1] = pairTotal - clampedFirst
            next.stackedWeights = Self.normalizeStackedWeights(weights)
        }
        return next
    }

    /// Returns a copy with `divider` reset to its default proportion.
    public func resetting(divider: MultiviewDividerID, tileCount: Int) -> MultiviewSplitRatios {
        var next = self
        switch divider {
        case .column:
            next.columnRatio = 0.50
        case .row:
            next.rowRatio = 0.50
        case .spotlight:
            next.spotlightRatio = nil
        case .stacked:
            if tileCount == 2 {
                next.rowRatio = 0.50
            } else {
                next.stackedWeights = nil
            }
        }
        return next
    }
}

/// Forward-compatible preset model for saving and restoring custom Multiview layouts (e.g., Sunday Ticket Quad-Box).
public struct MultiviewPreset: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var urlStrings: [String]
    public var layoutMode: MultiviewLayoutMode
    public var splitRatios: MultiviewSplitRatios?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlStrings
        case layoutMode
        case splitRatios
    }

    public init(
        id: UUID = UUID(),
        name: String,
        urlStrings: [String],
        layoutMode: MultiviewLayoutMode = .auto,
        splitRatios: MultiviewSplitRatios? = nil
    ) {
        self.id = id
        self.name = name
        self.urlStrings = Array(urlStrings.prefix(MultiviewGridLayout.maxTiles))
        self.layoutMode = layoutMode
        self.splitRatios = splitRatios
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let urls = try container.decode([String].self, forKey: .urlStrings)
        urlStrings = Array(urls.prefix(MultiviewGridLayout.maxTiles))
        layoutMode = try container.decodeIfPresent(MultiviewLayoutMode.self, forKey: .layoutMode) ?? .auto
        splitRatios = try container.decodeIfPresent(MultiviewSplitRatios.self, forKey: .splitRatios)
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
/// `TabWebViewHost` and SwiftUI `MultiviewOverlayView` so video tiles, gutter dividers, and Liquid Glass borders align to the pixel.
public enum MultiviewGridLayout {
    public static let maxTiles: Int = 4
    public static let defaultPadding: CGFloat = 10
    public static let defaultSpacing: CGFloat = 10

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
        ratios: MultiviewSplitRatios = .default,
        padding: CGFloat = defaultPadding,
        spacing: CGFloat = defaultSpacing
    ) -> [CGRect] {
        computeLayout(
            forCount: count,
            in: containerSize,
            mode: mode,
            ratios: ratios,
            padding: padding,
            spacing: spacing
        ).frames
    }

    /// Computes exact non-overlapping inter-tile gutter rects matching `frames(...)` pixel-for-pixel.
    public static func dividers(
        forCount count: Int,
        in containerSize: CGSize,
        mode: MultiviewLayoutMode = .auto,
        ratios: MultiviewSplitRatios = .default,
        padding: CGFloat = defaultPadding,
        spacing: CGFloat = defaultSpacing
    ) -> [MultiviewDividerDescriptor] {
        computeLayout(
            forCount: count,
            in: containerSize,
            mode: mode,
            ratios: ratios,
            padding: padding,
            spacing: spacing
        ).dividers
    }

    private static func computeLayout(
        forCount count: Int,
        in containerSize: CGSize,
        mode: MultiviewLayoutMode,
        ratios: MultiviewSplitRatios,
        padding: CGFloat,
        spacing: CGFloat
    ) -> (frames: [CGRect], dividers: [MultiviewDividerDescriptor]) {
        let clampedCount = min(max(count, 0), maxTiles)
        guard clampedCount > 0, containerSize.width > 0, containerSize.height > 0 else {
            return ([], [])
        }

        let pad = padding.rounded(.down)
        let gap = spacing.rounded(.down)
        let innerX = pad
        let innerY = pad
        let innerWidth = max(0, containerSize.width.rounded(.down) - pad * 2)
        let innerHeight = max(0, containerSize.height.rounded(.down) - pad * 2)
        guard innerWidth > 0, innerHeight > 0 else {
            return (Array(repeating: .zero, count: clampedCount), [])
        }

        if clampedCount == 1 {
            return ([CGRect(x: innerX, y: innerY, width: innerWidth, height: innerHeight)], [])
        }

        switch mode {
        case .stacked:
            return stackedLayout(
                count: clampedCount,
                x: innerX,
                y: innerY,
                width: innerWidth,
                height: innerHeight,
                spacing: gap,
                ratios: ratios
            )

        case .spotlight:
            return spotlightLayout(
                count: clampedCount,
                x: innerX,
                y: innerY,
                width: innerWidth,
                height: innerHeight,
                spacing: gap,
                ratios: ratios,
                defaultPrimaryRatio: 0.64
            )

        case .auto:
            switch clampedCount {
            case 2:
                // In tall/narrow half-screen Split Screen windows, stack 2 streams vertically so 16:9 video fills cleanly.
                if innerWidth < innerHeight * 1.05 {
                    let rowRatio = MultiviewSplitRatios.clampRatio(ratios.rowRatio)
                    let rows = splitTwoWeighted(total: innerHeight, ratio: rowRatio, spacing: gap)
                    let row2Y = innerY + rows.0 + gap
                    let frames = [
                        CGRect(x: innerX, y: innerY, width: innerWidth, height: rows.0),
                        CGRect(x: innerX, y: row2Y, width: innerWidth, height: rows.1)
                    ]
                    let leadingPct = Int((rowRatio * 100).rounded())
                    let divider = MultiviewDividerDescriptor(
                        id: .row,
                        axis: .horizontal,
                        frame: CGRect(x: innerX, y: innerY + rows.0, width: innerWidth, height: gap),
                        ratio: rowRatio,
                        leadingPercent: leadingPct,
                        trailingPercent: 100 - leadingPct
                    )
                    return (frames, gap > 0 ? [divider] : [])
                }

                let colRatio = MultiviewSplitRatios.clampRatio(ratios.columnRatio)
                let cols = splitTwoWeighted(total: innerWidth, ratio: colRatio, spacing: gap)
                let col2X = innerX + cols.0 + gap
                let frames = [
                    CGRect(x: innerX, y: innerY, width: cols.0, height: innerHeight),
                    CGRect(x: col2X, y: innerY, width: cols.1, height: innerHeight)
                ]
                let leadingPct = Int((colRatio * 100).rounded())
                let divider = MultiviewDividerDescriptor(
                    id: .column,
                    axis: .vertical,
                    frame: CGRect(x: innerX + cols.0, y: innerY, width: gap, height: innerHeight),
                    ratio: colRatio,
                    leadingPercent: leadingPct,
                    trailingPercent: 100 - leadingPct
                )
                return (frames, gap > 0 ? [divider] : [])

            case 3:
                return spotlightLayout(
                    count: 3,
                    x: innerX,
                    y: innerY,
                    width: innerWidth,
                    height: innerHeight,
                    spacing: gap,
                    ratios: ratios,
                    defaultPrimaryRatio: 0.58
                )

            default:
                // 2×2 Quad-Box with independent vertical column and horizontal row dividers
                let colRatio = MultiviewSplitRatios.clampRatio(ratios.columnRatio)
                let rowRatio = MultiviewSplitRatios.clampRatio(ratios.rowRatio)
                let cols = splitTwoWeighted(total: innerWidth, ratio: colRatio, spacing: gap)
                let rows = splitTwoWeighted(total: innerHeight, ratio: rowRatio, spacing: gap)
                let col2X = innerX + cols.0 + gap
                let row2Y = innerY + rows.0 + gap
                let frames = [
                    CGRect(x: innerX, y: innerY, width: cols.0, height: rows.0),
                    CGRect(x: col2X, y: innerY, width: cols.1, height: rows.0),
                    CGRect(x: innerX, y: row2Y, width: cols.0, height: rows.1),
                    CGRect(x: col2X, y: row2Y, width: cols.1, height: rows.1)
                ]
                var dividers: [MultiviewDividerDescriptor] = []
                if gap > 0 {
                    let colPct = Int((colRatio * 100).rounded())
                    let rowPct = Int((rowRatio * 100).rounded())
                    dividers.append(
                        MultiviewDividerDescriptor(
                            id: .column,
                            axis: .vertical,
                            frame: CGRect(x: innerX + cols.0, y: innerY, width: gap, height: innerHeight),
                            ratio: colRatio,
                            leadingPercent: colPct,
                            trailingPercent: 100 - colPct
                        )
                    )
                    dividers.append(
                        MultiviewDividerDescriptor(
                            id: .row,
                            axis: .horizontal,
                            frame: CGRect(x: innerX, y: innerY + rows.0, width: innerWidth, height: gap),
                            ratio: rowRatio,
                            leadingPercent: rowPct,
                            trailingPercent: 100 - rowPct
                        )
                    )
                }
                return (frames, dividers)
            }
        }
    }

    /// Splits `total` into `parts` equal integral lengths separated by `spacing`, absorbing remainder pixels cleanly with zero overlap.
    private static func splitIntegral(total: CGFloat, parts: Int, spacing: CGFloat) -> [CGFloat] {
        guard parts > 0 else { return [] }
        let available = max(0, Int(total.rounded(.down)) - Int(spacing) * (parts - 1))
        let base = available / parts
        let remainder = available % parts
        return (0..<parts).map { idx in
            CGFloat(base + (idx < remainder ? 1 : 0))
        }
    }

    /// Splits `total` into two integral lengths using `ratio` (`0.22...0.78`) with zero overlap.
    private static func splitTwoWeighted(total: CGFloat, ratio: CGFloat, spacing: CGFloat) -> (CGFloat, CGFloat) {
        let available = max(0, Int(total.rounded(.down)) - Int(spacing))
        if available == 0 {
            return (0, 0)
        }
        // Keep exact half-remainder convention when ratio == 0.50 (matches legacy splitIntegral).
        if abs(ratio - 0.50) < 0.0001 {
            let first = available / 2 + (available % 2)
            return (CGFloat(first), CGFloat(available - first))
        }
        let first = min(max(0, Int((CGFloat(available) * ratio).rounded())), available)
        return (CGFloat(first), CGFloat(available - first))
    }

    /// Splits `total` into `weights.count` integral lengths matching normalized `weights` with zero overlap.
    private static func splitWeighted(total: CGFloat, weights: [CGFloat], spacing: CGFloat) -> [CGFloat] {
        guard !weights.isEmpty else { return [] }
        let parts = weights.count
        let available = max(0, Int(total.rounded(.down)) - Int(spacing) * (parts - 1))
        guard available > 0 else { return Array(repeating: 0, count: parts) }

        var lengths = weights.map { Int((CGFloat(available) * $0).rounded(.down)) }
        let assigned = lengths.reduce(0, +)
        var remainder = available - assigned
        var idx = 0
        while remainder > 0 {
            lengths[idx % parts] += 1
            remainder -= 1
            idx += 1
        }
        return lengths.map(CGFloat.init)
    }

    private static func stackedLayout(
        count: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        ratios: MultiviewSplitRatios
    ) -> (frames: [CGRect], dividers: [MultiviewDividerDescriptor]) {
        let weights = ratios.resolvedStackedWeights(for: count)
        let heights: [CGFloat]
        if count == 2 {
            let pair = splitTwoWeighted(total: height, ratio: weights[0], spacing: spacing)
            heights = [pair.0, pair.1]
        } else {
            heights = splitWeighted(total: height, weights: weights, spacing: spacing)
        }

        var frames: [CGRect] = []
        var dividers: [MultiviewDividerDescriptor] = []
        var cursorY = y
        var cumulativeWeight: CGFloat = 0

        for idx in 0..<count {
            let h = heights[idx]
            frames.append(CGRect(x: x, y: cursorY, width: width, height: h))
            cumulativeWeight += weights[idx]
            if idx < count - 1 {
                if spacing > 0 {
                    let dividerID: MultiviewDividerID = (count == 2) ? .row : .stacked(idx)
                    let leadingPct = Int((weights[idx] * 100).rounded())
                    let trailingPct = Int((weights[idx + 1] * 100).rounded())
                    dividers.append(
                        MultiviewDividerDescriptor(
                            id: dividerID,
                            axis: .horizontal,
                            frame: CGRect(x: x, y: cursorY + h, width: width, height: spacing),
                            ratio: cumulativeWeight,
                            leadingPercent: leadingPct,
                            trailingPercent: trailingPct
                        )
                    )
                }
                cursorY += h + spacing
            }
        }
        return (frames, dividers)
    }

    private static func spotlightLayout(
        count: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        spacing: CGFloat,
        ratios: MultiviewSplitRatios,
        defaultPrimaryRatio: CGFloat
    ) -> (frames: [CGRect], dividers: [MultiviewDividerDescriptor]) {
        let sideCount = count - 1
        let primaryRatio = ratios.resolvedSpotlightRatio(defaultRatio: defaultPrimaryRatio)
        let leadingPct = Int((primaryRatio * 100).rounded())

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
            let divider = MultiviewDividerDescriptor(
                id: .spotlight,
                axis: .horizontal,
                frame: CGRect(x: x, y: y + topHeight, width: width, height: spacing),
                ratio: primaryRatio,
                leadingPercent: leadingPct,
                trailingPercent: 100 - leadingPct
            )
            return (result, spacing > 0 ? [divider] : [])
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
        let divider = MultiviewDividerDescriptor(
            id: .spotlight,
            axis: .vertical,
            frame: CGRect(x: x + mainWidth, y: y, width: spacing, height: height),
            ratio: primaryRatio,
            leadingPercent: leadingPct,
            trailingPercent: 100 - leadingPct
        )
        return (result, spacing > 0 ? [divider] : [])
    }
}
