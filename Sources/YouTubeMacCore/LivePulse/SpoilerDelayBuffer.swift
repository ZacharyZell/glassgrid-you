import Foundation

/// Bounded timestamped ring buffer delaying live deltas and market ticks to prevent HLS/DASH broadcast spoilers.
public struct SpoilerDelayBuffer<Value: Sendable>: Sendable {
    public struct Entry: Sendable {
        public let value: Value
        public let timestamp: Date

        public init(value: Value, timestamp: Date) {
            self.value = value
            self.timestamp = timestamp
        }
    }

    public static var defaultMaxEntries: Int { 512 }

    public let maxEntries: Int
    private var entries: [Entry] = []

    public init(maxEntries: Int = 512) {
        self.maxEntries = max(1, maxEntries)
    }

    public var count: Int {
        entries.count
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Appends a timestamped value, evicting the oldest entry if `maxEntries` (default 512) is exceeded.
    public mutating func enqueue(_ value: Value, at timestamp: Date = Date()) {
        if entries.count >= maxEntries {
            entries.removeFirst(entries.count - maxEntries + 1)
        }
        entries.append(Entry(value: value, timestamp: timestamp))
    }

    /// Drains and returns all entries whose configured spoiler delay has elapsed as of `now`.
    public mutating func drainReady(at now: Date = Date(), delay: SpoilerDelayOption) -> [Value] {
        guard !entries.isEmpty else { return [] }
        if delay == .off {
            let values = entries.map(\.value)
            entries.removeAll(keepingCapacity: true)
            return values
        }

        let requiredLag = Double(delay.rawValue)
        var ready: [Value] = []
        var remaining: [Entry] = []
        remaining.reserveCapacity(entries.count)

        for entry in entries {
            if now.timeIntervalSince(entry.timestamp) >= requiredLag {
                ready.append(entry.value)
            } else {
                remaining.append(entry)
            }
        }
        entries = remaining
        return ready
    }

    /// Returns the most recent entry ready as of `now` without mutating the buffer.
    public func latestReady(at now: Date = Date(), delay: SpoilerDelayOption) -> Value? {
        if delay == .off {
            return entries.last?.value
        }
        let requiredLag = Double(delay.rawValue)
        return entries.last(where: { now.timeIntervalSince($0.timestamp) >= requiredLag })?.value
    }

    public mutating func clear() {
        entries.removeAll(keepingCapacity: false)
    }
}
