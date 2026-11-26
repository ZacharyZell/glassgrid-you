import SwiftUI
import YouTubeMacCore

/// Compact 30pt Liquid Glass strip surfacing pinned matchup/game scores, watched-stream focus,
/// spoiler-delay controls, freshness telemetry, and 7-tier smart-priority player/score/market ticks.
struct LivePulseTickerBar: View {
    @Bindable var controller: AppController
    @Bindable var store: LivePulseStore
    let isFrozen: Bool

    @State private var currentPageIndex: Int = 0
    @State private var isRailHovered: Bool = false
    @State private var isPinPopoverPresented: Bool = false
    @State private var isSpoilerPopoverPresented: Bool = false
    @State private var lockPinAcrossNavigations: Bool = true

    private struct TickerRailItem: Identifiable, Equatable {
        let id: String
        let kind: Kind
        let badge: String
        let isBench: Bool
        let text: String
        let detail: String?
        let isPositive: Bool?
        let targetTab: LivePulseDrawerTab

        enum Kind: Equatable {
            case playerDelta
            case activeGame
            case marketTick
            case liveGame
        }
    }

    private var activeTargetTab: BrowserTab? {
        if controller.isMultiviewActive {
            return controller.multiviewAudioTab ?? controller.selectedTab
        }
        return controller.selectedTab
    }

    private var snapshot: LivePulseSnapshot {
        store.snapshot
    }

    private var hasLiveGames: Bool {
        LivePulseFreshnessHelpers.hasLiveGames(in: snapshot)
    }

    private var isOffline: Bool {
        LivePulseFreshnessHelpers.isOffline(providerStatus: snapshot.providerStatus)
    }

    private var watchedStreamLeague: SportsLeague? {
        switch snapshot.primaryContext {
        case .matchedGame(_, let league, _, _): return league
        case .liveSlate(let league, _): return league
        case .networkCandidates(_, let league, _): return league
        case .none: return nil
        }
    }

    private func isPlayerLive(_ player: FantasyPlayerLine) -> Bool {
        store.isGameLive(player.matchedGameID)
            || player.isRedZone
            || (player.lastDeltaPoints.map { abs($0) >= 0.05 } ?? false)
    }

    private func makePlayerRailItem(
        _ player: FantasyPlayerLine,
        isBench: Bool,
        idPrefix: String
    ) -> TickerRailItem {
        let deltaText: String
        let isPos: Bool?
        if let delta = player.lastDeltaPoints, abs(delta) >= 0.05 {
            let arrow = delta >= 0 ? "▲" : "▼"
            deltaText = String(format: "%@%.1f %@", delta >= 0 ? "+" : "", delta, arrow)
            isPos = delta >= 0
        } else {
            deltaText = String(format: "%.1f pts", player.points)
            isPos = nil
        }
        return TickerRailItem(
            id: "\(idPrefix):\(player.id)",
            kind: .playerDelta,
            badge: isBench ? "BN" : (player.isRedZone ? "RZ" : player.position),
            isBench: isBench,
            text: "\(abbreviatedPlayerName(player.name)) \(deltaText)",
            detail: player.liveStatLine,
            isPositive: isPos,
            targetTab: .players
        )
    }

    private var railItems: [TickerRailItem] {
        var items: [TickerRailItem] = []
        let focusOnly = controller.settings.livePulseStreamFocusOnly

        let starterEntries = snapshot.matchups.flatMap { matchup in
            matchup.starters.map { (league: matchup.league, player: $0) }
        }
        let benchEntries = snapshot.matchups.flatMap { matchup in
            matchup.bench.map { (league: matchup.league, player: $0) }
        }

        // Tier 1: In-stream Starter deltas / RZ / live (<= 4)
        let inStreamStarters = starterEntries
            .filter { $0.player.isActiveInStream }
            .sorted { lhs, rhs in
                let lHasDelta = abs(lhs.player.lastDeltaPoints ?? 0) >= 0.05
                let rHasDelta = abs(rhs.player.lastDeltaPoints ?? 0) >= 0.05
                if lHasDelta != rHasDelta { return lHasDelta }
                if lhs.player.isRedZone != rhs.player.isRedZone { return lhs.player.isRedZone }
                let lDelta = abs(lhs.player.lastDeltaPoints ?? 0)
                let rDelta = abs(rhs.player.lastDeltaPoints ?? 0)
                if abs(lDelta - rDelta) >= 0.05 { return lDelta > rDelta }
                let lLive = isPlayerLive(lhs.player)
                let rLive = isPlayerLive(rhs.player)
                if lLive != rLive { return lLive }
                let lRank = store.leaguePriorityRank(for: lhs.league)
                let rRank = store.leaguePriorityRank(for: rhs.league)
                if lRank != rRank { return lRank < rRank }
                return lhs.player.points > rhs.player.points
            }
        for entry in inStreamStarters.prefix(4) {
            items.append(makePlayerRailItem(entry.player, isBench: false, idPrefix: "starter-in"))
        }

        // Tier 2: In-stream Bench live / deltas (<= 2)
        let inStreamBench = benchEntries
            .filter { $0.player.isActiveInStream && isPlayerLive($0.player) }
            .sorted { lhs, rhs in
                let lDelta = abs(lhs.player.lastDeltaPoints ?? 0)
                let rDelta = abs(rhs.player.lastDeltaPoints ?? 0)
                if abs(lDelta - rDelta) >= 0.05 { return lDelta > rDelta }
                let lRank = store.leaguePriorityRank(for: lhs.league)
                let rRank = store.leaguePriorityRank(for: rhs.league)
                if lRank != rRank { return lRank < rRank }
                return lhs.player.points > rhs.player.points
            }
        for entry in inStreamBench.prefix(2) {
            items.append(makePlayerRailItem(entry.player, isBench: true, idPrefix: "bench-in"))
        }

        // Tier 3: In-stream Game scores
        let inStreamGames = snapshot.games
            .filter { snapshot.activeGameIDs.contains($0.id) }
            .sorted { store.leaguePriorityRank(for: $0.league) < store.leaguePriorityRank(for: $1.league) }
        for game in inStreamGames {
            let scoreText = "\(game.away.abbreviation) \(game.away.score) – \(game.home.abbreviation) \(game.home.score)"
            let detail = game.clock ?? game.statusDetail
            items.append(
                TickerRailItem(
                    id: "game-in:\(game.id)",
                    kind: .activeGame,
                    badge: game.league.displayName,
                    isBench: false,
                    text: scoreText,
                    detail: detail.isEmpty ? nil : detail,
                    isPositive: nil,
                    targetTab: .scores
                )
            )
        }

        if !focusOnly {
            // Tier 4: Other Live Starters by Sport Priority (<= 3)
            let otherLiveStarters = starterEntries
                .filter { !$0.player.isActiveInStream && isPlayerLive($0.player) }
                .sorted { lhs, rhs in
                    let lRank = store.leaguePriorityRank(for: lhs.league)
                    let rRank = store.leaguePriorityRank(for: rhs.league)
                    if lRank != rRank { return lRank < rRank }
                    if lhs.player.isRedZone != rhs.player.isRedZone { return lhs.player.isRedZone }
                    let lDelta = abs(lhs.player.lastDeltaPoints ?? 0)
                    let rDelta = abs(rhs.player.lastDeltaPoints ?? 0)
                    if abs(lDelta - rDelta) >= 0.05 { return lDelta > rDelta }
                    return lhs.player.points > rhs.player.points
                }
            for entry in otherLiveStarters.prefix(3) {
                items.append(makePlayerRailItem(entry.player, isBench: false, idPrefix: "starter-live"))
            }

            // Tier 5: Other Live Games by Sport Priority (<= 5)
            let otherLiveGames = snapshot.games
                .filter { !snapshot.activeGameIDs.contains($0.id) && ($0.status == .live || $0.status == .halftime) }
                .sorted { store.leaguePriorityRank(for: $0.league) < store.leaguePriorityRank(for: $1.league) }
            for game in otherLiveGames.prefix(5) {
                let scoreText = "\(game.away.abbreviation) \(game.away.score) – \(game.home.abbreviation) \(game.home.score)"
                let detail = game.clock ?? game.statusDetail
                items.append(
                    TickerRailItem(
                        id: "game-live:\(game.id)",
                        kind: .liveGame,
                        badge: game.league.displayName,
                        isBench: false,
                        text: scoreText,
                        detail: detail.isEmpty ? nil : detail,
                        isPositive: nil,
                        targetTab: .scores
                    )
                )
            }

            // Tier 6: Other Live Bench big plays (abs(delta) >= 4.0, <= 1)
            let otherBenchBigPlays = benchEntries
                .filter {
                    !$0.player.isActiveInStream
                        && isPlayerLive($0.player)
                        && abs($0.player.lastDeltaPoints ?? 0) >= 4.0
                }
                .sorted { lhs, rhs in
                    let lDelta = abs(lhs.player.lastDeltaPoints ?? 0)
                    let rDelta = abs(rhs.player.lastDeltaPoints ?? 0)
                    if abs(lDelta - rDelta) >= 0.05 { return lDelta > rDelta }
                    return store.leaguePriorityRank(for: lhs.league) < store.leaguePriorityRank(for: rhs.league)
                }
            for entry in otherBenchBigPlays.prefix(1) {
                items.append(makePlayerRailItem(entry.player, isBench: true, idPrefix: "bench-big"))
            }
        }

        // Tier 7: Markets (in-stream first, then Sport Priority, <= 4)
        if controller.settings.livePulseShowMarkets {
            let marketPool = focusOnly
                ? snapshot.markets.filter { $0.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false }
                : snapshot.markets

            let prioritizedMarkets = marketPool.sorted { lhs, rhs in
                let lhsActive = lhs.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
                let rhsActive = rhs.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
                if lhsActive != rhsActive { return lhsActive }
                let lRank = lhs.league.map { store.leaguePriorityRank(for: $0) } ?? 99
                let rRank = rhs.league.map { store.leaguePriorityRank(for: $0) } ?? 99
                if lRank != rRank { return lRank < rRank }
                return abs(lhs.delta5m ?? lhs.delta1m ?? 0) > abs(rhs.delta5m ?? rhs.delta1m ?? 0)
            }

            for quote in prioritizedMarkets.prefix(4) {
                let pct = Int((quote.yesProbability * 100.0).rounded())
                let delta = quote.delta1m ?? quote.delta5m
                let deltaSuffix: String
                let isPos: Bool?
                if let delta, abs(delta) >= 0.005 {
                    let deltaPct = Int((delta * 100.0).rounded())
                    let arrow = deltaPct >= 0 ? "▲" : "▼"
                    let sign = deltaPct >= 0 ? "+" : ""
                    deltaSuffix = " \(arrow)\(sign)\(deltaPct)%"
                    isPos = deltaPct >= 0
                } else {
                    deltaSuffix = ""
                    isPos = nil
                }
                items.append(
                    TickerRailItem(
                        id: "mkt:\(quote.id)",
                        kind: .marketTick,
                        badge: quote.provider == .kalshi ? "KALSHI" : "POLY",
                        isBench: false,
                        text: "\(quote.outcomeLabel) \(pct)%\(deltaSuffix)",
                        detail: quote.title,
                        isPositive: isPos,
                        targetTab: .markets
                    )
                )
            }
        }

        return items
    }

    private var activeRailItem: TickerRailItem? {
        guard !railItems.isEmpty else { return nil }
        return railItems[currentPageIndex % railItems.count]
    }

    private var pinnedSummaryText: String {
        let watchedLeague = watchedStreamLeague
        let prioritizedMatchup: FantasyMatchup? = {
            if let watchedLeague,
               let matched = snapshot.matchups.first(where: { $0.league == watchedLeague }) {
                return matched
            }
            if controller.settings.livePulseStreamFocusOnly, watchedLeague != nil {
                return nil
            }
            return snapshot.matchups.min {
                store.leaguePriorityRank(for: $0.league) < store.leaguePriorityRank(for: $1.league)
            }
        }()

        if let matchup = prioritizedMatchup {
            return String(
                format: "%@ %.1f–%.1f",
                matchup.league.displayName,
                matchup.userPoints,
                matchup.opponentPoints
            )
        }
        if case .matchedGame(let gameID, _, _, let sourceLabel) = snapshot.primaryContext {
            if let game = snapshot.games.first(where: { $0.id == gameID }) {
                return "\(game.away.abbreviation) \(game.away.score)–\(game.home.score) \(game.home.abbreviation)"
            }
            return sourceLabel
        }
        if case .liveSlate(_, let label) = snapshot.primaryContext {
            return label
        }
        if case .networkCandidates(let network, _, _) = snapshot.primaryContext {
            return "\(network) Slate"
        }
        if !controller.settings.livePulseEnabled {
            return "Live Pulse Off"
        }
        return "Auto-Detect"
    }

    private var hasManualPinOnActiveTab: Bool {
        guard let tabID = activeTargetTab?.id else { return false }
        return store.manualPinsByTab[tabID] != nil
    }

    private var needsInitialSetup: Bool {
        !controller.settings.livePulseEnabled
            || (controller.settings.livePulseEnabledLeagues.isEmpty
                && controller.settings.livePulseFantasyLeagues.isEmpty)
    }

    var body: some View {
        LiquidGlassGroup(spacing: 5) {
            HStack(spacing: 5) {
                leadingPinnedPill
                    .layoutPriority(1)

                focusTogglePill
                    .layoutPriority(0)

                spoilerDelayPill
                    .layoutPriority(1)

                Spacer(minLength: 2)

                centerReactiveRail
                    .layoutPriority(0.2)

                Spacer(minLength: 2)

                trailingControlPill
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: LivePulseLayout.tickerHeight)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
        .task(id: pagingTaskKey) {
            guard !isFrozen, !store.isTickerPaused, !isRailHovered, railItems.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5.5))
                guard !Task.isCancelled, !isFrozen, !store.isTickerPaused, !isRailHovered else { break }
                let count = railItems.count
                guard count > 1 else { break }
                withAnimation(.easeInOut(duration: 0.28)) {
                    currentPageIndex = (currentPageIndex + 1) % count
                }
            }
        }
        .onChange(of: railItems.count) { _, newCount in
            if newCount == 0 {
                currentPageIndex = 0
            } else if currentPageIndex >= newCount {
                currentPageIndex = 0
            }
        }
    }

    private var pagingTaskKey: String {
        "\(isFrozen)-\(store.isTickerPaused)-\(isRailHovered)-\(railItems.count)"
    }

    // MARK: - Leading Pinned, Stream Focus & Spoiler Delay Pills

    @ViewBuilder
    private var leadingPinnedPill: some View {
        Button {
            isPinPopoverPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)

                Text(pinnedSummaryText)
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if hasManualPinOnActiveTab {
                    Image(systemName: "pin.fill")
                        .font(AppIconFont.xs(weight: .bold))
                        .foregroundStyle(AppleTheme.accentText)
                }

                Image(systemName: "chevron.down")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: hasManualPinOnActiveTab ? AppleTheme.accentText.opacity(0.14) : nil,
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(isFrozen)
        .help("Pin Game or Live Slate to Active Stream")
        .popover(isPresented: $isPinPopoverPresented, arrowEdge: .bottom) {
            manualGamePinPopover
        }
    }

    @ViewBuilder
    private var focusTogglePill: some View {
        let isFocused = controller.settings.livePulseStreamFocusOnly
        Button {
            controller.toggleLivePulseStreamFocus()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "scope")
                        .font(AppIconFont.xs(weight: .semibold))
                    Text("Focus")
                        .font(AppFont.caption(weight: .semibold))
                }
                .padding(.horizontal, AppSpacing.md)
                .frame(minHeight: 24)
                .fixedSize()

                Image(systemName: "scope")
                    .font(AppIconFont.xs(weight: .semibold))
                    .frame(width: 24, height: 24)
                    .fixedSize()
            }
            .foregroundStyle(isFocused ? AppleTheme.accentText : Color.primary.opacity(0.82))
            .frame(height: 24)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: isFocused ? AppleTheme.accentText.opacity(0.18) : nil,
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isFrozen)
        .help(isFocused ? "Watched Stream Focus: On — Click to show all leagues" : "Watched Stream Focus — Filter Live Pulse to active stream(s)")
    }

    private var statusDotColor: Color {
        if !controller.settings.livePulseEnabled || isFrozen {
            return AppleTheme.textMuted
        }
        if store.isTickerPaused {
            return AppleTheme.warning
        }
        return AppleTheme.accentFill
    }

    @ViewBuilder
    private var spoilerDelayPill: some View {
        @Bindable var settings = controller.settings
        let isDelayActive = settings.livePulseSpoilerDelay != .off

        Button {
            isSpoilerPopoverPresented.toggle()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "clock.badge.checkmark")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(isDelayActive ? AppleTheme.accentText : AppleTheme.textSecondary)
                Text(settings.livePulseSpoilerDelay.shortLabel)
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(isDelayActive ? AppleTheme.accentText : Color.primary.opacity(0.86))
            }
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 24)
            .frame(minWidth: 24)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: isDelayActive ? AppleTheme.accentText.opacity(0.12) : nil,
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(isFrozen)
        .help("Spoiler Delay Buffer — Delay live scores & plays to match your stream")
        .popover(isPresented: $isSpoilerPopoverPresented, arrowEdge: .bottom) {
            SpoilerDelayPopover(
                selectedDelay: $settings.livePulseSpoilerDelay,
                isPresented: $isSpoilerPopoverPresented
            )
        }
    }

    // MARK: - Center Reactive Rail

    @ViewBuilder
    private var centerReactiveRail: some View {
        if needsInitialSetup {
            SettingsLink {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "sportscourt")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                    Text("Configure Live Pulse")
                        .font(AppFont.caption(weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
        } else if let item = activeRailItem {
            Button {
                controller.openLivePulseDrawer(tab: item.targetTab)
            } label: {
                HStack(spacing: 5) {
                    if item.isBench {
                        Text(item.badge)
                            .font(AppFont.micro(weight: .bold, tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, AppSpacing.xxs)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(AppleTheme.textSecondary.opacity(0.35), lineWidth: 0.75)
                            )
                            .fixedSize()
                            .layoutPriority(1)
                    } else {
                        Text(item.badge)
                            .font(AppFont.micro(weight: .bold, tabular: true))
                            .foregroundStyle(item.badge == "RZ" ? Color.white : AppleTheme.accentText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(item.badge == "RZ" ? AppleTheme.accentFill : AppleTheme.accentText.opacity(0.14))
                            )
                            .fixedSize()
                            .layoutPriority(1)
                    }

                    Text(item.text)
                        .font(AppFont.caption(weight: item.isBench ? .medium : .semibold, tabular: true))
                        .foregroundStyle(tickerTextColor(for: item.isPositive, isBench: item.isBench))
                        .lineLimit(1)
                        .layoutPriority(0.8)

                    if let detail = item.detail, !detail.isEmpty {
                        Text("· \(detail)")
                            .font(AppFont.caption(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                    }

                    if railItems.count > 1 {
                        Text("\((currentPageIndex % railItems.count) + 1)/\(railItems.count)")
                            .font(AppFont.micro(weight: .medium, tabular: true))
                            .foregroundStyle(AppleTheme.textMuted)
                            .fixedSize()
                            .layoutPriority(1)
                    }
                }
                .id(item.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
                .padding(.horizontal, AppSpacing.md)
                .frame(height: 24)
                .frame(minWidth: 180, maxWidth: 480)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .onHover { isRailHovered = $0 }
            .help("Click to open \(item.targetTab.title) in Live Companion Drawer")
        } else if controller.settings.livePulseStreamFocusOnly {
            HStack(spacing: AppSpacing.xs) {
                Text("No matched stream")
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)

                Button {
                    isPinPopoverPresented = true
                } label: {
                    Text("Pin")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.xs)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)

                Text("·")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textMuted)

                Button {
                    controller.toggleLivePulseStreamFocus()
                } label: {
                    Text("Show All")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.xs)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .frame(minWidth: 180)
            .appleGlass(in: Capsule(style: .continuous))
        } else {
            HStack(spacing: AppSpacing.sm) {
                Text(store.isRefreshing ? "Syncing live sports…" : "Live Pulse Ready — No active games")
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)

                if controller.settings.livePulseFantasyLeagues.isEmpty {
                    SettingsLink {
                        Text("Setup")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(AppleTheme.accentText)
                            .padding(.horizontal, AppSpacing.xs)
                            .frame(minWidth: 24, minHeight: 24)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(minWidth: 180)
            .appleGlass(in: Capsule(style: .continuous))
        }
    }

    private func tickerTextColor(for isPositive: Bool?, isBench: Bool) -> Color {
        if isBench {
            guard let isPositive else { return AppleTheme.textSecondary }
            return isPositive ? AppleTheme.positive : AppleTheme.accentText
        }
        guard let isPositive else { return .primary }
        return isPositive ? AppleTheme.positive : AppleTheme.accentText
    }

    // MARK: - Trailing Controls Pill

    @ViewBuilder
    private var trailingControlPill: some View {
        HStack(spacing: AppSpacing.xxs) {
            FreshnessLabelView(
                lastUpdatedAt: snapshot.lastUpdatedAt,
                hasLiveGames: hasLiveGames,
                isOffline: isOffline,
                isFrozen: isFrozen,
                style: .tickerProgressive
            )

            LivePulseRefreshButton(
                isRefreshing: store.isRefreshing,
                lastUpdatedAt: snapshot.lastUpdatedAt,
                lastManualRefreshCompletedAt: store.lastManualRefreshCompletedAt,
                providerStatus: snapshot.providerStatus,
                isEnabled: controller.settings.livePulseEnabled,
                isFrozen: isFrozen,
                iconFont: AppIconFont.xs(weight: .semibold),
                checkmarkFont: AppIconFont.xs(weight: .bold)
            ) {
                store.refreshNow()
            }

            Button {
                store.toggleTickerPaused()
            } label: {
                Image(systemName: store.isTickerPaused ? "play.fill" : "pause.fill")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(store.isTickerPaused ? AppleTheme.accentText : Color.primary.opacity(0.82))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .help(store.isTickerPaused ? "Resume Ticker Paging" : "Pause Ticker Paging")

            Button {
                controller.toggleLivePulseDrawer()
            } label: {
                Image(systemName: controller.isLivePulseDrawerVisible ? "sidebar.right" : "rectangle.trailinghalf.inset.filled")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(controller.isLivePulseDrawerVisible ? AppleTheme.accentText : Color.primary.opacity(0.82))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .help(controller.isLivePulseDrawerVisible ? "Hide Companion Drawer (⌘⌥I)" : "Open Companion Drawer (⌘⌥I)")

            Button {
                controller.toggleLivePulseTicker()
            } label: {
                Image(systemName: "xmark")
                    .font(AppIconFont.xs(weight: .bold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .help("Hide Live Pulse Ticker (⌘⌥B)")
        }
        .padding(.horizontal, AppSpacing.xs)
        .frame(height: 24)
        .fixedSize()
        .appleGlass(in: Capsule(style: .continuous), interactive: true)
    }

    // MARK: - Manual Game Pin Popover

    @ViewBuilder
    private var manualGamePinPopover: some View {
        let fantasyTeamCodesByLeague: [SportsLeague: Set<String>] = Dictionary(
            grouping: snapshot.matchups,
            by: \.league
        ).mapValues { matchups in
            Set(
                matchups.flatMap { $0.starters + $0.bench }
                    .map { SportsEntityMatcher.canonicalESPNCode($0.nflOrProTeam, league: matchups.first?.league ?? .nfl) }
            )
        }
        let fantasyGameIDs = Set(snapshot.matchups.flatMap { $0.starters + $0.bench }.compactMap(\.matchedGameID))
        let myFantasyGames = snapshot.games.filter { game in
            let teamCodes = fantasyTeamCodesByLeague[game.league] ?? []
            return fantasyGameIDs.contains(game.id)
                || teamCodes.contains(SportsEntityMatcher.canonicalESPNCode(game.away.abbreviation, league: game.league))
                || teamCodes.contains(SportsEntityMatcher.canonicalESPNCode(game.home.abbreviation, league: game.league))
        }
        let groupedByLeague = Dictionary(grouping: snapshot.games, by: \.league)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pin Stream Context")
                    .font(AppFont.callout(weight: .semibold))
                Spacer()
                Toggle("Lock Pin", isOn: $lockPinAcrossNavigations)
                    .toggleStyle(.checkbox)
                    .font(AppFont.caption)
                    .help("Keep pin locked across channel/URL changes in this tab")
            }

            Toggle(
                "Watched Stream Focus",
                isOn: Binding(
                    get: { controller.settings.livePulseStreamFocusOnly },
                    set: { nextValue in
                        if nextValue != controller.settings.livePulseStreamFocusOnly {
                            controller.toggleLivePulseStreamFocus()
                        }
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(AppFont.caption(weight: .medium))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if let tabID = activeTargetTab?.id {
                            store.clearManualPin(tabID: tabID)
                        }
                        isPinPopoverPresented = false
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                                .font(AppIconFont.sm(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                                .frame(width: 16)
                            Text("Auto-Detect from Stream")
                                .font(AppFont.callout(weight: .medium))
                            Spacer()
                            if !hasManualPinOnActiveTab {
                                Image(systemName: "checkmark")
                                    .font(AppIconFont.xs(weight: .bold))
                                    .foregroundStyle(AppleTheme.accentText)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 5)
                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !myFantasyGames.isEmpty {
                        Text("My Fantasy Games")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                        ForEach(myFantasyGames) { game in
                            pinGameRow(game)
                        }
                    }

                    ForEach(controller.settings.livePulseLeaguePriority) { league in
                        if let leagueGames = groupedByLeague[league], !leagueGames.isEmpty {
                            Text("Live \(league.displayName)")
                                .font(AppFont.caption(weight: .semibold))
                                .foregroundStyle(AppleTheme.textSecondary)
                            ForEach(leagueGames.prefix(8)) { game in
                                pinGameRow(game)
                            }
                        }
                    }

                    Text("Live Whip-Around Slates")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)

                    ForEach(controller.settings.livePulseLeaguePriority) { league in
                        let slateLabel = liveSlateTitle(for: league)
                        Button {
                            pinSlate(league: league, label: slateLabel)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: league.symbolName)
                                    .font(AppIconFont.sm)
                                    .foregroundStyle(AppleTheme.accentText)
                                    .frame(width: 16)
                                Text(slateLabel)
                                    .font(AppFont.callout)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 5)
                            .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(AppSpacing.lg)
        .frame(width: 286)
    }

    @ViewBuilder
    private func pinGameRow(_ game: LiveGame) -> some View {
        let isPinned: Bool = {
            guard let tabID = activeTargetTab?.id,
                  let pin = store.manualPinsByTab[tabID],
                  case .game(let gid, _) = pin.mode else {
                return false
            }
            return gid == game.id
        }()

        Button {
            pinGame(game)
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(game.league.displayName)
                    .font(AppFont.micro(weight: .bold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Text("\(game.away.abbreviation) \(game.away.score) – \(game.home.score) \(game.home.abbreviation)")
                    .font(AppFont.callout(weight: .medium, tabular: true))
                Spacer()
                Text(game.clock ?? game.statusDetail)
                    .font(AppFont.caption(tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(AppIconFont.xs)
                        .foregroundStyle(AppleTheme.accentText)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 5)
            .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isPinned ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private func pinGame(_ game: LiveGame) {
        guard let tab = activeTargetTab else { return }
        store.setManualPin(
            ManualGamePin(
                tabID: tab.id,
                scopeKey: controller.activeTabScopeKey(for: tab),
                mode: .game(gameID: game.id, league: game.league),
                isLocked: lockPinAcrossNavigations
            )
        )
        isPinPopoverPresented = false
    }

    private func pinSlate(league: SportsLeague, label: String) {
        guard let tab = activeTargetTab else { return }
        store.setManualPin(
            ManualGamePin(
                tabID: tab.id,
                scopeKey: controller.activeTabScopeKey(for: tab),
                mode: .liveSlate(league: league, label: label),
                isLocked: lockPinAcrossNavigations
            )
        )
        isPinPopoverPresented = false
    }

    private func liveSlateTitle(for league: SportsLeague) -> String {
        switch league {
        case .nfl: return "NFL RedZone / Live Slate"
        case .nba: return "NBA Live Whip-Around"
        case .mlb: return "MLB Big Inning Slate"
        case .nhl: return "NHL Frozen Frenzy Slate"
        }
    }

    private func abbreviatedPlayerName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let firstChar = parts.first?.first else {
            return fullName
        }
        let rest = parts.dropFirst().joined(separator: " ")
        return "\(firstChar). \(rest)"
    }
}
