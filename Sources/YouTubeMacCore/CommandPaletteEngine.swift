import Foundation

/// Sections displayed inside the Liquid Glass Command Palette (`⌘K`).
public enum CommandPaletteSection: String, CaseIterable, Sendable {
    case openTabs
    case chapters
    case multiviewPresets
    case continueWatching
    case channelsAndPins
    case actions
    case suggestions
    case directSearch

    public var title: String {
        switch self {
        case .openTabs: return "Open Tabs"
        case .chapters: return "Video Chapters"
        case .multiviewPresets: return "Multiview Presets"
        case .continueWatching: return "Continue Watching"
        case .channelsAndPins: return "Channels & Pinned"
        case .actions: return "Actions"
        case .suggestions: return "YouTube Suggestions"
        case .directSearch: return "Search YouTube"
        }
    }
}

/// Built-in app actions executable from the Command Palette with discoverable shortcut hints.
public enum CommandPaletteAction: String, CaseIterable, Sendable {
    case toggleMultiview
    case openYouTubeTVInMultiview
    case toggleMiniPlayer
    case togglePictureInPicture
    case toggleFocusMode
    case toggleDayNightMode
    case toggleSidebar
    case findOnPage
    case newTab
    case newWindow
    case openClipboardURL
    case copyVideoFrame
    case saveVideoFrame
    case sleepTimer15
    case sleepTimer30
    case sleepTimerEndOfVideo
    case cancelSleepTimer
    case toggleAlwaysOnTop
}

/// Action payload executed when a Command Palette row is selected.
public enum CommandPalettePayload: Equatable, Sendable {
    case selectTab(UUID)
    case seekToChapter(Double)
    case launchPreset(UUID)
    case openPinnedFolder(UUID)
    case openCompanionURL(URL)
    case openURL(URL)
    case searchYouTube(String)
    case runAction(CommandPaletteAction)
}

/// Pure, unit-testable snapshot of an open tab for Command Palette indexing.
public struct CommandPaletteTabSnapshot: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let multiviewSlot: Int?
    public let isActiveAudio: Bool
    public let isPlaying: Bool
    public let isSelected: Bool

    public init(
        id: UUID,
        title: String,
        subtitle: String,
        multiviewSlot: Int? = nil,
        isActiveAudio: Bool = false,
        isPlaying: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.multiviewSlot = multiviewSlot
        self.isActiveAudio = isActiveAudio
        self.isPlaying = isPlaying
        self.isSelected = isSelected
    }
}

/// Pure, unit-testable descriptor for a Command Palette action entry.
public struct CommandPaletteActionDescriptor: Equatable, Sendable {
    public let action: CommandPaletteAction
    public let title: String
    public let keywords: String
    public let systemImage: String
    public let shortcutHint: String?
    public let isFeaturedWhenEmpty: Bool

    public init(
        action: CommandPaletteAction,
        title: String,
        keywords: String,
        systemImage: String,
        shortcutHint: String? = nil,
        isFeaturedWhenEmpty: Bool = false
    ) {
        self.action = action
        self.title = title
        self.keywords = keywords
        self.systemImage = systemImage
        self.shortcutHint = shortcutHint
        self.isFeaturedWhenEmpty = isFeaturedWhenEmpty
    }
}

/// A single rendered result row inside the Command Palette.
public struct CommandPaletteItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let section: CommandPaletteSection
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let shortcutHint: String?
    public let badgeText: String?
    public let isActiveAudio: Bool
    public let payload: CommandPalettePayload

    public init(
        id: String,
        section: CommandPaletteSection,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        shortcutHint: String? = nil,
        badgeText: String? = nil,
        isActiveAudio: Bool = false,
        payload: CommandPalettePayload
    ) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcutHint = shortcutHint
        self.badgeText = badgeText
        self.isActiveAudio = isActiveAudio
        self.payload = payload
    }
}

/// Pure fuzzy matching, privacy-safe autocomplete gating, and deterministic ranking for the Command Palette.
public enum CommandPaletteEngine {
    private static let domainSuffixes: [String] = [
        ".com", ".org", ".net", ".io", ".tv", ".be", ".gg", ".co", ".edu", ".gov", ".app", ".dev"
    ]

    /// Returns `false` for short inputs AND for any URL or domain-like string so pasted links are
    /// never sent over the network to `suggestqueries.google.com`.
    public static func shouldFetchSuggestions(for rawQuery: String) -> Bool {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        if YouTubeURLRouter.extractYouTubeURLFromString(trimmed) != nil {
            return false
        }

        let lower = trimmed.lowercased()
        if lower.contains("://")
            || lower.hasPrefix("http:")
            || lower.hasPrefix("https:")
            || lower.hasPrefix("www.")
            || lower.contains("youtube.com")
            || lower.contains("youtu.be")
            || lower.contains("tv.youtube.com") {
            return false
        }

        // Reject space-free strings that look like private URLs, domains, or paths (e.g. "internal.org/foo").
        if !lower.contains(where: \.isWhitespace) {
            if lower.contains("/") {
                return false
            }
            for suffix in domainSuffixes where lower.hasSuffix(suffix) || lower.contains("\(suffix)/") {
                return false
            }
        }

        return true
    }

    /// Deterministic case-insensitive fuzzy scorer: exact > prefix > word-boundary > substring > subsequence.
    public static func fuzzyScore(query rawQuery: String, in text: String) -> Int? {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let target = text.lowercased()
        guard !target.isEmpty else { return nil }

        if target == q {
            return 1000
        }
        if target.hasPrefix(q) {
            return 850 - min(target.count - q.count, 50)
        }
        if let range = target.range(of: q) {
            let startOffset = target.distance(from: target.startIndex, to: range.lowerBound)
            if startOffset > 0 {
                let prevIndex = target.index(before: range.lowerBound)
                let prevChar = target[prevIndex]
                if !prevChar.isLetter && !prevChar.isNumber {
                    return 680 - min(startOffset, 60)
                }
            }
            return 480 - min(startOffset, 80)
        }

        // Ordered subsequence fallback for power-user abbreviations (e.g. "mv" -> "Multiview", "ytv" -> "YouTube TV")
        var qIdx = q.startIndex
        var tIdx = target.startIndex
        var firstMatchOffset = -1
        var gaps = 0
        var offset = 0

        while qIdx < q.endIndex && tIdx < target.endIndex {
            if q[qIdx] == target[tIdx] {
                if firstMatchOffset < 0 {
                    firstMatchOffset = offset
                }
                qIdx = q.index(after: qIdx)
            } else if firstMatchOffset >= 0 {
                gaps += 1
            }
            tIdx = target.index(after: tIdx)
            offset += 1
        }

        guard qIdx == q.endIndex else {
            return nil
        }
        return max(100, 260 - min(gaps * 3, 140) - min(firstMatchOffset, 20))
    }

    /// Produces a deterministically ordered list of Command Palette items for both empty and active queries.
    public static func rank(
        query rawQuery: String,
        openTabs: [CommandPaletteTabSnapshot],
        chapters: [VideoChapter] = [],
        presets: [MultiviewPreset],
        continueWatching: [ContinueWatchingItem],
        pinnedItems: [PinnedItem],
        pinnedFolders: [PinnedFolder] = [],
        watchedChannels: [WatchedChannelStat],
        actions: [CommandPaletteActionDescriptor],
        suggestions: [String]
    ) -> [CommandPaletteItem] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return emptyQueryItems(
                openTabs: openTabs,
                presets: presets,
                continueWatching: continueWatching,
                actions: actions
            )
        }

        var results: [CommandPaletteItem] = []

        // 1. Direct YouTube / YouTube TV URL detection goes straight to #1
        let detectedYouTubeURL = YouTubeURLRouter.extractYouTubeURLFromString(trimmed)
        let detectedCompanionURL: URL?
        if let url = detectedYouTubeURL {
            detectedCompanionURL = nil
            results.append(
                CommandPaletteItem(
                    id: "direct-url-\(url.absoluteString)",
                    section: .directSearch,
                    title: "Open YouTube Link",
                    subtitle: url.absoluteString,
                    systemImage: YouTubeURLRouter.isYouTubeTVHost(url.host) ? "tv" : "link",
                    shortcutHint: "↩",
                    payload: .openURL(url)
                )
            )
        } else if let companionURL = YouTubeURLRouter.resolveCompanionURL(trimmed) {
            detectedCompanionURL = companionURL
            results.append(
                CommandPaletteItem(
                    id: "direct-companion-\(companionURL.absoluteString)",
                    section: .directSearch,
                    title: "Open Companion Tile",
                    subtitle: companionURL.absoluteString,
                    systemImage: "globe",
                    shortcutHint: "↩",
                    badgeText: "Web",
                    payload: .openCompanionURL(companionURL)
                )
            )
        } else {
            detectedCompanionURL = nil
        }

        // 2. Open Tabs
        let rankedTabs: [(score: Int, item: CommandPaletteItem)] = openTabs.compactMap { tab in
            let titleScore = fuzzyScore(query: trimmed, in: tab.title) ?? 0
            let subtitleScore = fuzzyScore(query: trimmed, in: tab.subtitle).map { $0 - 120 } ?? 0
            let best = max(titleScore, subtitleScore)
            guard best > 0 else { return nil }
            return (best + (tab.isPlaying ? 40 : 0), makeTabItem(tab))
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.item.title < rhs.item.title
        }
        results.append(contentsOf: rankedTabs.prefix(5).map(\.item))

        // 2b. Video Chapters (active video)
        if chapters.count >= 2 {
            let rankedChapters: [(score: Int, item: CommandPaletteItem)] = chapters.compactMap { chapter in
                let titleScore = fuzzyScore(query: trimmed, in: chapter.title) ?? 0
                let timeScore = fuzzyScore(query: trimmed, in: chapter.formattedStartTime).map { $0 - 100 } ?? 0
                let best = max(titleScore, timeScore)
                guard best > 0 else { return nil }
                return (
                    best,
                    CommandPaletteItem(
                        id: "chapter-\(chapter.id)",
                        section: .chapters,
                        title: chapter.title,
                        subtitle: "Jump to \(chapter.formattedStartTime)",
                        systemImage: "list.bullet.indent",
                        badgeText: chapter.formattedStartTime,
                        payload: .seekToChapter(chapter.startSeconds)
                    )
                )
            }
            .sorted { $0.score > $1.score }
            results.append(contentsOf: rankedChapters.prefix(5).map(\.item))
        }

        // 3. Saved Multiview Presets
        let rankedPresets: [(score: Int, item: CommandPaletteItem)] = presets.compactMap { preset in
            guard let score = fuzzyScore(query: trimmed, in: preset.name) else { return nil }
            return (score, makePresetItem(preset))
        }
        .sorted { $0.score > $1.score }
        results.append(contentsOf: rankedPresets.prefix(4).map(\.item))

        // 4. Continue Watching
        let rankedContinue: [(score: Int, item: CommandPaletteItem)] = continueWatching.compactMap { item in
            guard let resumeURL = item.resumeURL else { return nil }
            let titleScore = fuzzyScore(query: trimmed, in: item.title) ?? 0
            let channelScore = fuzzyScore(query: trimmed, in: item.channel).map { $0 - 60 } ?? 0
            let best = max(titleScore, channelScore)
            guard best > 0 else { return nil }
            return (best, makeContinueItem(item, url: resumeURL))
        }
        .sorted { $0.score > $1.score }
        results.append(contentsOf: rankedContinue.prefix(4).map(\.item))

        // 5. Pinned Folders, Pinned Items & Most Watched Channels
        let folderNameByID = Dictionary(uniqueKeysWithValues: pinnedFolders.map { ($0.id, $0.name) })
        let pinCountByFolderID = Dictionary(grouping: pinnedItems.compactMap(\.folderID), by: { $0 }).mapValues(\.count)

        var channelEntries: [(score: Int, item: CommandPaletteItem)] = []
        var seenChannelURLs = Set<String>()

        for folder in pinnedFolders {
            guard let score = fuzzyScore(query: trimmed, in: folder.name) else { continue }
            let count = pinCountByFolderID[folder.id] ?? 0
            let subtitle: String
            if (2...MultiviewGridLayout.maxTiles).contains(count) {
                subtitle = "Folder · Open \(count) pins in Multiview"
            } else if count > 0 {
                subtitle = "Folder · Open \(count) \(count == 1 ? "pin" : "pins")"
            } else {
                subtitle = "Empty Folder"
            }
            channelEntries.append((
                score + 30,
                CommandPaletteItem(
                    id: "folder-\(folder.id.uuidString)",
                    section: .channelsAndPins,
                    title: folder.name,
                    subtitle: subtitle,
                    systemImage: "folder.fill",
                    badgeText: count > 0 ? "\(count) \(count == 1 ? "pin" : "pins")" : nil,
                    payload: .openPinnedFolder(folder.id)
                )
            ))
        }

        for pin in pinnedItems {
            guard let url = pin.url, seenChannelURLs.insert(pin.urlString).inserted else { continue }
            let titleScore = fuzzyScore(query: trimmed, in: pin.title) ?? 0
            let folderName = pin.folderID.flatMap { folderNameByID[$0] }
            let folderScore = folderName.flatMap { fuzzyScore(query: trimmed, in: $0).map { $0 - 140 } } ?? 0
            let best = max(titleScore, folderScore)
            guard best > 0 else { continue }
            let subtitle = folderName.map { "Pinned • \($0)" } ?? "Pinned"
            let isCompanion = YouTubeURLRouter.preferredRoutingMode(for: url) == .companion
            channelEntries.append((
                best + 20,
                CommandPaletteItem(
                    id: "pin-\(pin.id.uuidString)",
                    section: .channelsAndPins,
                    title: pin.title,
                    subtitle: subtitle,
                    systemImage: YouTubeURLRouter.pinnedItemIcon(for: pin.urlString),
                    payload: isCompanion ? .openCompanionURL(url) : .openURL(url)
                )
            ))
        }
        for channel in watchedChannels {
            guard let url = channel.url, seenChannelURLs.insert(url.absoluteString).inserted else { continue }
            guard let score = fuzzyScore(query: trimmed, in: channel.name) else { continue }
            channelEntries.append((
                score,
                CommandPaletteItem(
                    id: "channel-\(channel.id)",
                    section: .channelsAndPins,
                    title: channel.name,
                    subtitle: channel.watchCount > 1 ? "Watched \(channel.watchCount)×" : "Channel",
                    systemImage: "person.crop.circle",
                    payload: .openURL(url)
                )
            ))
        }
        channelEntries.sort { $0.score > $1.score }
        results.append(contentsOf: channelEntries.prefix(5).map(\.item))

        // 6. App Actions
        let rankedActions: [(score: Int, item: CommandPaletteItem)] = actions.compactMap { desc in
            let titleScore = fuzzyScore(query: trimmed, in: desc.title) ?? 0
            let keywordScore = fuzzyScore(query: trimmed, in: desc.keywords).map { $0 - 80 } ?? 0
            let best = max(titleScore, keywordScore)
            guard best > 0 else { return nil }
            return (best, makeActionItem(desc))
        }
        .sorted { $0.score > $1.score }
        results.append(contentsOf: rankedActions.prefix(5).map(\.item))

        // 6b. Quick-launch Companion streaming/sports site matching (e.g. "Twitch", "ESPN", "Peacock")
        if detectedYouTubeURL == nil && detectedCompanionURL == nil {
            let matchingSites: [(score: Int, site: CompanionQuickSite)] = CompanionQuickSite.catalog.compactMap { site in
                guard site.routingMode == .companion else { return nil }
                let nameScore = fuzzyScore(query: trimmed, in: site.name) ?? 0
                let subScore = fuzzyScore(query: trimmed, in: site.subtitle).map { $0 - 150 } ?? 0
                let best = max(nameScore, subScore)
                guard best >= 450 else { return nil }
                return (best, site)
            }
            .sorted { $0.score > $1.score }

            for match in matchingSites.prefix(2) {
                results.append(
                    CommandPaletteItem(
                        id: "quick-companion-\(match.site.id)",
                        section: .directSearch,
                        title: "Open \(match.site.name) Companion Tile",
                        subtitle: match.site.urlString,
                        systemImage: match.site.systemImage,
                        badgeText: "Web",
                        payload: .openCompanionURL(match.site.url)
                    )
                )
            }
        }

        // 7. Live YouTube Search Suggestions (deduplicated against raw query)
        let normalizedQuery = trimmed.lowercased()
        var seenSuggestions = Set<String>([normalizedQuery])
        for suggestion in suggestions {
            let clean = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seenSuggestions.insert(clean.lowercased()).inserted else { continue }
            results.append(
                CommandPaletteItem(
                    id: "suggest-\(clean.lowercased())",
                    section: .suggestions,
                    title: clean,
                    subtitle: "YouTube Search",
                    systemImage: "magnifyingglass",
                    payload: .searchYouTube(clean)
                )
            )
        }

        // 8. Guaranteed offline direct-search fallback (when input isn't already a direct YouTube URL)
        if detectedYouTubeURL == nil {
            results.append(
                CommandPaletteItem(
                    id: "search-direct-\(normalizedQuery)",
                    section: .directSearch,
                    title: "Search YouTube for \"\(trimmed)\"",
                    subtitle: "Press Return to search",
                    systemImage: "magnifyingglass.circle.fill",
                    shortcutHint: "↩",
                    payload: .searchYouTube(trimmed)
                )
            )
        }

        return results
    }

    private static func emptyQueryItems(
        openTabs: [CommandPaletteTabSnapshot],
        presets: [MultiviewPreset],
        continueWatching: [ContinueWatchingItem],
        actions: [CommandPaletteActionDescriptor]
    ) -> [CommandPaletteItem] {
        var results: [CommandPaletteItem] = []

        for tab in openTabs.prefix(6) {
            results.append(makeTabItem(tab))
        }
        for preset in presets.prefix(4) {
            results.append(makePresetItem(preset))
        }
        for item in continueWatching.prefix(3) {
            if let url = item.resumeURL {
                results.append(makeContinueItem(item, url: url))
            }
        }
        let featuredActions = actions.filter(\.isFeaturedWhenEmpty)
        for desc in (featuredActions.isEmpty ? actions : featuredActions).prefix(8) {
            results.append(makeActionItem(desc))
        }

        return results
    }

    private static func makeTabItem(_ tab: CommandPaletteTabSnapshot) -> CommandPaletteItem {
        let icon: String
        if tab.isActiveAudio {
            icon = "waveform"
        } else if tab.isPlaying {
            icon = "play.fill"
        } else {
            icon = "macwindow"
        }
        let badge = tab.multiviewSlot.map { "Tile \($0)" }
        return CommandPaletteItem(
            id: "tab-\(tab.id.uuidString)",
            section: .openTabs,
            title: tab.title,
            subtitle: tab.subtitle,
            systemImage: icon,
            badgeText: badge,
            isActiveAudio: tab.isActiveAudio,
            payload: .selectTab(tab.id)
        )
    }

    private static func makePresetItem(_ preset: MultiviewPreset) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "preset-\(preset.id.uuidString)",
            section: .multiviewPresets,
            title: preset.name,
            subtitle: "\(preset.urlStrings.count) Streams · \(preset.layoutMode.title)",
            systemImage: "square.grid.2x2.fill",
            badgeText: "\(preset.urlStrings.count)×",
            payload: .launchPreset(preset.id)
        )
    }

    private static func makeContinueItem(_ item: ContinueWatchingItem, url: URL) -> CommandPaletteItem {
        let subtitleParts = [item.channel, item.remainingTimeText].filter { !$0.isEmpty }
        return CommandPaletteItem(
            id: "continue-\(item.videoID)",
            section: .continueWatching,
            title: item.title,
            subtitle: subtitleParts.isEmpty ? "Resume Video" : subtitleParts.joined(separator: " · "),
            systemImage: "play.circle.fill",
            payload: .openURL(url)
        )
    }

    private static func makeActionItem(_ desc: CommandPaletteActionDescriptor) -> CommandPaletteItem {
        CommandPaletteItem(
            id: "action-\(desc.action.rawValue)",
            section: .actions,
            title: desc.title,
            subtitle: nil,
            systemImage: desc.systemImage,
            shortcutHint: desc.shortcutHint,
            payload: .runAction(desc.action)
        )
    }
}
