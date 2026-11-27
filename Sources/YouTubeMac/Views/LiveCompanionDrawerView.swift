import AppKit
import SwiftUI
import WebKit
import YouTubeMacCore

/// Trailing Liquid Glass Live Companion Drawer displaying fantasy matchups, active-in-stream players,
/// live scores with 1-click stream pinning, read-only prediction markets, lazy live chat, and quick web-tile launchers.
struct LiveCompanionDrawerView: View {
    @Bindable var controller: AppController
    @Bindable var store: LivePulseStore
    let isFrozen: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var showBenchPlayers: Bool = false
    @State private var showOpponentStarters: Bool = false
    @State private var showBenchInPlayers: Bool = true
    @State private var showUpcomingPlayers: Bool = false
    @State private var showRosterPlaysInMatchup: Bool = true
    @State private var showRosterPlaysInScores: Bool = false
    @State private var expandedPlayGameIDs: Set<String> = []
    @State private var isPinEmptyStatePopoverPresented: Bool = false
    @State private var isSpoilerPopoverPresented: Bool = false
    @State private var manualChatTabID: UUID?

    private var isResolvedDark: Bool {
        switch controller.settings.appearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var animationsEnabled: Bool {
        !isFrozen && !accessibilityReduceMotion
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

    private var watchedStreamLeagues: Set<SportsLeague> {
        var result: Set<SportsLeague> = []
        func insert(from ctx: StreamSportContext) {
            switch ctx {
            case .matchedGame(_, let league, _, _): result.insert(league)
            case .liveSlate(let league, _): result.insert(league)
            case .networkCandidates(_, let league, _):
                if let league { result.insert(league) }
            case .none: break
            }
        }
        insert(from: snapshot.primaryContext)
        for game in snapshot.games where snapshot.activeGameIDs.contains(game.id) {
            result.insert(game.league)
        }
        return result
    }

    private var isFocusMissingStream: Bool {
        controller.settings.livePulseStreamFocusOnly && snapshot.activeGameIDs.isEmpty
    }

    private var filteredMatchups: [FantasyMatchup] {
        var base = store.selectedLeagueFilter.map { filter in
            snapshot.matchups.filter { $0.league == filter }
        } ?? snapshot.matchups

        if controller.settings.livePulseStreamFocusOnly, !watchedStreamLeagues.isEmpty {
            base = base.filter { watchedStreamLeagues.contains($0.league) }
        }

        return base.sorted { lhs, rhs in
            let lWatched = watchedStreamLeagues.contains(lhs.league) ? 0 : 1
            let rWatched = watchedStreamLeagues.contains(rhs.league) ? 0 : 1
            if lWatched != rWatched { return lWatched < rWatched }
            return store.leaguePriorityRank(for: lhs.league) < store.leaguePriorityRank(for: rhs.league)
        }
    }

    private var filteredGames: [LiveGame] {
        var base = store.selectedLeagueFilter.map { filter in
            snapshot.games.filter { $0.league == filter }
        } ?? snapshot.games

        if controller.settings.livePulseStreamFocusOnly {
            base = base.filter { snapshot.activeGameIDs.contains($0.id) }
        }

        return base.sorted { lhs, rhs in
            let lhsActive = snapshot.activeGameIDs.contains(lhs.id)
            let rhsActive = snapshot.activeGameIDs.contains(rhs.id)
            if lhsActive != rhsActive { return lhsActive }
            let lRank = store.leaguePriorityRank(for: lhs.league)
            let rRank = store.leaguePriorityRank(for: rhs.league)
            if lRank != rRank { return lRank < rRank }
            let lStatus = gameStatusOrder(lhs.status)
            let rStatus = gameStatusOrder(rhs.status)
            if lStatus != rStatus { return lStatus < rStatus }
            return (lhs.startTime ?? .distantFuture) < (rhs.startTime ?? .distantFuture)
        }
    }

    private var filteredMarkets: [PredictionMarketQuote] {
        var base = store.selectedLeagueFilter.map { filter in
            snapshot.markets.filter { $0.league == filter }
        } ?? snapshot.markets

        if controller.settings.livePulseStreamFocusOnly {
            base = base.filter { quote in
                quote.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
            }
        }

        return base.sorted { lhs, rhs in
            let lhsActive = lhs.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
            let rhsActive = rhs.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
            if lhsActive != rhsActive { return lhsActive }
            let lRank = lhs.league.map { store.leaguePriorityRank(for: $0) } ?? 99
            let rRank = rhs.league.map { store.leaguePriorityRank(for: $0) } ?? 99
            if lRank != rRank { return lRank < rRank }
            return (lhs.volumeUSD ?? 0) > (rhs.volumeUSD ?? 0)
        }
    }

    private func gameStatusOrder(_ status: GameStatus) -> Int {
        switch status {
        case .live: return 0
        case .halftime: return 1
        case .pregame: return 2
        case .final: return 3
        case .postponed: return 4
        }
    }

    var body: some View {
        let cardShape = RoundedRectangle(
            cornerRadius: LivePulseLayout.drawerCardCornerRadius,
            style: .continuous
        )

        VStack(spacing: 0) {
            drawerHeader
            Divider().opacity(0.35)

            contextAndFiltersBar
            Divider().opacity(0.28)

            if store.selectedDrawerTab == .chat {
                chatTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        switch store.selectedDrawerTab {
                        case .matchup:
                            matchupTabContent
                        case .players:
                            playersTabContent
                        case .scores:
                            scoresTabContent
                        case .markets:
                            marketsTabContent
                        case .chat:
                            EmptyView()
                        }
                    }
                    .padding(10)
                }
            }

            Divider().opacity(0.35)
            quickLauncherFooter
        }
        .background(
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .clipShape(cardShape)
        )
        .clipShape(cardShape)
        .appleGlass(in: cardShape)
        .shadow(color: .black.opacity(isResolvedDark ? 0.28 : 0.08), radius: 10, y: 2)
        .padding(.top, LivePulseLayout.drawerCardTopInset)
        .padding(.bottom, LivePulseLayout.drawerCardBottomInset)
        .padding(.leading, LivePulseLayout.drawerCardLeadingInset)
        .padding(.trailing, LivePulseLayout.drawerCardTrailingInset)
    }

    // MARK: - 36pt Drawer Header (Omit WindowDragArea — topHeaderBar owns window drag)

    @ViewBuilder
    private var drawerHeader: some View {
        HStack(spacing: AppSpacing.xxs) {
            // Segmented Mode Picker (overflow-safe at 280–440pt across 5 tabs)
            ViewThatFits(in: .horizontal) {
                drawerTabSegmentedStrip(compactIcons: false)
                drawerTabSegmentedStrip(compactIcons: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    drawerTabSegmentedStrip(compactIcons: false)
                }
            }

            Spacer(minLength: AppSpacing.xxs)

            HStack(spacing: 0) {
                LivePulseRefreshButton(
                    isRefreshing: store.isRefreshing,
                    lastUpdatedAt: snapshot.lastUpdatedAt,
                    lastManualRefreshCompletedAt: store.lastManualRefreshCompletedAt,
                    providerStatus: snapshot.providerStatus,
                    isEnabled: controller.settings.livePulseEnabled,
                    isFrozen: isFrozen,
                    iconFont: AppIconFont.sm(weight: .semibold),
                    checkmarkFont: AppIconFont.sm(weight: .bold)
                ) {
                    store.refreshNow()
                }

                Button {
                    controller.toggleLivePulseDrawer()
                } label: {
                    Image(systemName: "xmark")
                        .font(AppIconFont.xs(weight: .bold))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
                .help("Close Live Companion Drawer (⌘⌥I)")
            }
            .fixedSize()
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(height: LivePulseLayout.drawerHeaderHeight)
    }

    @ViewBuilder
    private func drawerTabSegmentedStrip(compactIcons: Bool) -> some View {
        HStack(spacing: compactIcons ? 1 : 0) {
            ForEach(LivePulseDrawerTab.allCases) { tab in
                let isSelected = store.selectedDrawerTab == tab
                Button {
                    store.selectedDrawerTab = tab
                } label: {
                    Group {
                        if compactIcons {
                            HStack(spacing: 3) {
                                Image(systemName: tab.symbolName)
                                    .font(AppIconFont.xs(weight: isSelected ? .semibold : .medium))
                                if isSelected {
                                    Text(tab.title)
                                        .font(AppFont.caption(weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .padding(.horizontal, isSelected ? AppSpacing.sm : AppSpacing.xs)
                            .frame(minWidth: 24, minHeight: 24)
                        } else {
                            Text(tab.title)
                                .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, AppSpacing.xs)
                                .frame(minWidth: 24, minHeight: 24)
                        }
                    }
                    .foregroundStyle(isSelected ? AppleTheme.accentText : Color.primary.opacity(0.78))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? AppleTheme.accentText.opacity(0.16) : .clear)
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, AppSpacing.xxs)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
    }

    // MARK: - Stream Context, Disambiguation & Filters

    @ViewBuilder
    private var contextAndFiltersBar: some View {
        @Bindable var settings = controller.settings
        let isFocused = settings.livePulseStreamFocusOnly

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            streamContextBanner

            HStack(spacing: AppSpacing.xs) {
                Button {
                    controller.toggleLivePulseStreamFocus()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "scope")
                            .font(AppIconFont.xs(weight: .semibold))
                        Text("Focus")
                            .font(AppFont.micro(weight: isFocused ? .bold : .semibold))
                    }
                    .foregroundStyle(isFocused ? AppleTheme.accentText : Color.primary.opacity(0.78))
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isFocused ? AppleTheme.accentText.opacity(0.16) : Color.primary.opacity(0.06))
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isFrozen)
                .help(isFocused ? "Watched Stream Focus: On — Click to show all leagues" : "Watched Stream Focus — Filter Live Pulse to active stream(s)")

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        leagueFilterPill(title: "All", league: nil)
                        ForEach(settings.orderedEnabledLivePulseLeagues) { league in
                            leagueFilterPill(title: league.displayName, league: league)
                                .contextMenu {
                                    Button("Move \(league.displayName) to #1 Priority") {
                                        settings.moveLivePulseLeagueToTop(league)
                                    }
                                }
                        }
                    }
                }
                .clipped()

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
                            .foregroundStyle(isDelayActive ? AppleTheme.accentText : Color.primary.opacity(0.80))
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isDelayActive ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isFrozen)
                .help("Spoiler Delay Buffer")
                .popover(isPresented: $isSpoilerPopoverPresented, arrowEdge: .bottom) {
                    SpoilerDelayPopover(
                        selectedDelay: $settings.livePulseSpoilerDelay,
                        isPresented: $isSpoilerPopoverPresented
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, AppSpacing.md)
    }

    @ViewBuilder
    private var streamContextBanner: some View {
        let isFocused = controller.settings.livePulseStreamFocusOnly
        let bannerFill = isFocused ? AppleTheme.accentText.opacity(0.12) : Color.primary.opacity(0.05)

        switch snapshot.primaryContext {
        case .networkCandidates(let network, _, let gameIDs):
            let candidates = snapshot.games.filter { gameIDs.contains($0.id) }
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: 5) {
                    Image(systemName: "tv.and.mediabox")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                    Text("Multiple \(network) broadcasts — Pin your game:")
                        .font(AppFont.caption(weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.xs)
                    FreshnessLabelView(
                        lastUpdatedAt: snapshot.lastUpdatedAt,
                        hasLiveGames: hasLiveGames,
                        isOffline: isOffline,
                        isFrozen: isFrozen,
                        style: .drawerInline
                    )
                }

                if candidates.isEmpty {
                    Text("Select a game in Scores to pin it to this stream.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(candidates) { game in
                                Button {
                                    pinGameToActiveTab(game)
                                } label: {
                                    Text("\(game.away.abbreviation) @ \(game.home.abbreviation)")
                                        .font(AppFont.caption(weight: .semibold))
                                        .foregroundStyle(AppleTheme.accentText)
                                        .padding(.horizontal, AppSpacing.md)
                                        .frame(minWidth: 24, minHeight: 24)
                                        .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))
                                        .contentShape(Capsule(style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isFrozen)
                            }
                        }
                    }
                }
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppleTheme.accentText.opacity(isFocused ? 0.14 : 0.09),
                in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
            )

        case .matchedGame(let gameID, _, let confidence, let sourceLabel):
            let game = snapshot.games.first(where: { $0.id == gameID })
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: confidence == .manual ? "pin.fill" : "dot.radiowaves.left.and.right")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)

                VStack(alignment: .leading, spacing: 1) {
                    Text(game.map { "\($0.away.abbreviation) \($0.away.score) – \($0.home.score) \($0.home.abbreviation)" } ?? sourceLabel)
                        .font(AppFont.caption(weight: .semibold, tabular: true))
                        .lineLimit(1)
                    HStack(spacing: AppSpacing.xs) {
                        Text(confidence == .manual ? "Pinned to active stream" : "Auto-matched: \(sourceLabel)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                            .lineLimit(1)
                        Text("·")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textMuted)
                        FreshnessLabelView(
                            lastUpdatedAt: snapshot.lastUpdatedAt,
                            hasLiveGames: hasLiveGames,
                            isOffline: isOffline,
                            isFrozen: isFrozen,
                            style: .drawerInline
                        )
                    }
                }

                Spacer(minLength: AppSpacing.xs)

                if confidence == .manual, let tabID = activeTargetTab?.id {
                    Button {
                        store.clearManualPin(tabID: tabID)
                    } label: {
                        Text("Unpin")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(AppleTheme.accentText)
                            .padding(.horizontal, AppSpacing.xs)
                            .minHitTarget(24, shape: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(bannerFill, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

        case .liveSlate(let league, let label):
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: league.symbolName)
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFont.caption(weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: AppSpacing.xs) {
                        Text("Whip-around slate")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                        Text("·")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textMuted)
                        FreshnessLabelView(
                            lastUpdatedAt: snapshot.lastUpdatedAt,
                            hasLiveGames: hasLiveGames,
                            isOffline: isOffline,
                            isFrozen: isFrozen,
                            style: .drawerInline
                        )
                    }
                }
                Spacer()
                if let tabID = activeTargetTab?.id, store.manualPinsByTab[tabID] != nil {
                    Button {
                        store.clearManualPin(tabID: tabID)
                    } label: {
                        Text("Auto")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(AppleTheme.accentText)
                            .padding(.horizontal, AppSpacing.xs)
                            .minHitTarget(24, shape: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(bannerFill, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

        case .none:
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "play.tv")
                    .font(AppIconFont.xs)
                    .foregroundStyle(isFocused ? AppleTheme.accentText : AppleTheme.textSecondary)
                Text("Pin a game in Scores or play a live broadcast")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.xs)
                FreshnessLabelView(
                    lastUpdatedAt: snapshot.lastUpdatedAt,
                    hasLiveGames: hasLiveGames,
                    isOffline: isOffline,
                    isFrozen: isFrozen,
                    style: .drawerInline
                )
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                isFocused ? AppleTheme.accentText.opacity(0.12) : Color.primary.opacity(0.03),
                in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func leagueFilterPill(title: String, league: SportsLeague?) -> some View {
        let isSelected = store.selectedLeagueFilter == league
        Button {
            store.selectedLeagueFilter = league
        } label: {
            Text(title)
                .font(AppFont.micro(weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? AppleTheme.accentText : Color.primary.opacity(0.78))
                .padding(.horizontal, AppSpacing.sm)
                .frame(minWidth: 24, minHeight: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppleTheme.accentText.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Matchup

    @ViewBuilder
    private var matchupTabContent: some View {
        if filteredMatchups.isEmpty {
            emptyStateCard(
                icon: "trophy",
                title: controller.settings.livePulseFantasyLeagues.isEmpty
                    ? "Connect Your Fantasy League"
                    : "No Matchup Data Yet",
                subtitle: controller.settings.livePulseFantasyLeagues.isEmpty
                    ? "Add your Sleeper username or an ESPN Public league ID in Settings -> Live Pulse, or launch your league in a Multiview tile below."
                    : (snapshot.providerStatus["espnFantasy"] ?? "Waiting for next fantasy sync cycle.")
            )
        } else {
            ForEach(filteredMatchups) { matchup in
                matchupCard(matchup)
            }

            let targetGameID: String? = {
                if case .matchedGame(let gid, _, _, _) = snapshot.primaryContext,
                   snapshot.playsByGameID[gid]?.isEmpty == false {
                    return gid
                }
                return nil
            }()
            let allAvailablePlays = store.filteredPlays(for: targetGameID, rosterOnly: false)
            if !allAvailablePlays.isEmpty {
                let displayedPlays = store.filteredPlays(for: targetGameID, rosterOnly: showRosterPlaysInMatchup)
                matchupPlayByPlayCard(
                    gameID: targetGameID,
                    plays: displayedPlays,
                    hasAnyPlays: !allAvailablePlays.isEmpty
                )
            }
        }
    }

    @ViewBuilder
    private func matchupPlayByPlayCard(
        gameID: String?,
        plays: [PlayByPlayEvent],
        hasAnyPlays: Bool
    ) -> some View {
        let gameLabel: String = {
            if let gameID, let g = snapshot.games.first(where: { $0.id == gameID }) {
                return "\(g.away.abbreviation) @ \(g.home.abbreviation)"
            }
            return "Active Games"
        }()

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Text("Play-by-Play · \(gameLabel)")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                rosterPlaysToggleChip(isOn: $showRosterPlaysInMatchup)
            }

            if plays.isEmpty && hasAnyPlays && showRosterPlaysInMatchup {
                Text("No recent plays involving your fantasy roster.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textMuted)
                    .padding(.vertical, AppSpacing.xs)
            } else {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(plays.prefix(8)) { play in
                        playByPlayRow(play)
                    }
                }
            }
        }
        .padding(10)
        .background(
            Color.primary.opacity(isResolvedDark ? 0.06 : 0.04),
            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        )
    }

    @ViewBuilder
    private func matchupCard(_ matchup: FantasyMatchup) -> some View {
        let sortedStarters = matchup.starters.enumerated().sorted { lhs, rhs in
            if lhs.element.isActiveInStream != rhs.element.isActiveInStream {
                return lhs.element.isActiveInStream
            }
            let lLive = store.isGameLive(lhs.element.matchedGameID)
            let rLive = store.isGameLive(rhs.element.matchedGameID)
            if lLive != rLive { return lLive }
            return lhs.offset < rhs.offset
        }.map(\.element)

        let liveBenchCount = matchup.bench.filter {
            store.isGameLive($0.matchedGameID) || $0.isRedZone || abs($0.lastDeltaPoints ?? 0) >= 0.05
        }.count
        let benchTotal = matchup.bench.reduce(0.0) { $0 + $1.points }

        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("\(matchup.league.displayName) · \(matchup.leagueName)")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(matchup.weekLabel)
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(AppleTheme.accentText)
            }

            HStack(alignment: .center, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(matchup.userTeamName)
                        .font(AppFont.callout(weight: .semibold))
                        .lineLimit(1)
                    Text(String(format: "%.1f", matchup.userPoints))
                        .font(AppFont.largeTitle(weight: .bold, tabular: true))
                        .foregroundStyle(matchup.userPoints >= matchup.opponentPoints ? Color.primary : AppleTheme.textSecondary)
                        .liveNumericTransition(enabled: animationsEnabled, value: matchup.userPoints)
                    if let proj = matchup.userProjected {
                        Text(String(format: "Proj %.1f", proj))
                            .font(AppFont.caption(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("VS")
                    .font(AppFont.caption(weight: .bold))
                    .foregroundStyle(AppleTheme.textMuted)

                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text(matchup.opponentTeamName)
                        .font(AppFont.callout(weight: .medium))
                        .lineLimit(1)
                    Text(String(format: "%.1f", matchup.opponentPoints))
                        .font(AppFont.largeTitle(weight: .bold, tabular: true))
                        .foregroundStyle(matchup.opponentPoints > matchup.userPoints ? Color.primary : AppleTheme.textSecondary)
                        .liveNumericTransition(enabled: animationsEnabled, value: matchup.opponentPoints)
                    if let proj = matchup.opponentProjected {
                        Text(String(format: "Proj %.1f", proj))
                            .font(AppFont.caption(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider().opacity(0.3)

            Text("Your Starters")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)

            VStack(spacing: AppSpacing.xs) {
                ForEach(sortedStarters) { player in
                    FantasyPlayerRowView(
                        player: player,
                        showOpponentBadge: false,
                        isResolvedDark: isResolvedDark,
                        animationsEnabled: animationsEnabled
                    )
                }
            }

            if !matchup.bench.isEmpty {
                DisclosureGroup(isExpanded: $showBenchPlayers) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Not counted in matchup total")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textMuted)
                            .padding(.top, AppSpacing.xxs)

                        ForEach(matchup.bench) { player in
                            FantasyPlayerRowView(
                                player: player,
                                showOpponentBadge: false,
                                isResolvedDark: isResolvedDark,
                                animationsEnabled: animationsEnabled
                            )
                        }
                    }
                    .padding(.top, 3)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Text(liveBenchCount > 0 ? "Bench (\(matchup.bench.count) · \(liveBenchCount) live)" : "Bench (\(matchup.bench.count))")
                        Spacer()
                        Text(String(format: "%.1f BN", benchTotal))
                            .font(AppFont.caption(weight: .medium, tabular: true))
                            .foregroundStyle(AppleTheme.textMuted)
                    }
                }
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)
            }

            if !matchup.opponentStarters.isEmpty {
                DisclosureGroup("Opponent Starters (\(matchup.opponentStarters.count))", isExpanded: $showOpponentStarters) {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(matchup.opponentStarters) { player in
                            FantasyPlayerRowView(
                                player: player,
                                showOpponentBadge: true,
                                isResolvedDark: isResolvedDark,
                                animationsEnabled: animationsEnabled
                            )
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(isResolvedDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    // MARK: - Tab 2: Players

    private struct RankedPlayerEntry: Identifiable {
        let league: SportsLeague
        let player: FantasyPlayerLine
        var id: String { "\(league.rawValue):\(player.id)" }
    }

    @ViewBuilder
    private var playersTabContent: some View {
        let baseMatchups = store.selectedLeagueFilter.map { filter in
            snapshot.matchups.filter { $0.league == filter }
        } ?? snapshot.matchups

        let allEntries: [RankedPlayerEntry] = baseMatchups.flatMap { matchup in
            let roster = matchup.starters
                + (showBenchInPlayers ? matchup.bench : [])
                + matchup.opponentStarters
            return roster.map { RankedPlayerEntry(league: matchup.league, player: $0) }
        }

        let hasAnyBench = baseMatchups.contains { !$0.bench.isEmpty }
        let focusOnly = controller.settings.livePulseStreamFocusOnly

        if isFocusMissingStream {
            noMatchedStreamCard
        } else if allEntries.isEmpty {
            emptyStateCard(
                icon: "person.2",
                title: "No Active Fantasy Players",
                subtitle: "Configure Sleeper or ESPN Public leagues in Settings -> Live Pulse to highlight players currently in your stream."
            )
        } else {
            let inStream = allEntries.filter { $0.player.isActiveInStream }
            let inStreamStarters = inStream
                .filter { $0.player.isStarter }
                .sorted(by: compareTier1Players)
            let inStreamBench = inStream
                .filter { !$0.player.isStarter }
                .sorted(by: compareTier1Players)

            let playingLive = focusOnly ? [] : allEntries
                .filter { !$0.player.isActiveInStream && isPlayerLive($0.player) }
                .sorted(by: compareTier2Players)

            let upcomingOrFinal = focusOnly ? [] : allEntries
                .filter { !$0.player.isActiveInStream && !isPlayerLive($0.player) }
                .sorted(by: compareTier2Players)

            if hasAnyBench {
                HStack {
                    Text("Roster Feed")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                    Spacer()
                    benchFilterChip
                }
                .padding(.horizontal, AppSpacing.xxs)
            }

            if !inStream.isEmpty {
                sectionHeader("In Watched Stream")
                VStack(spacing: 5) {
                    ForEach(inStreamStarters) { entry in
                        FantasyPlayerRowView(
                            player: entry.player,
                            showOpponentBadge: !entry.player.isUserRoster,
                            isResolvedDark: isResolvedDark,
                            animationsEnabled: animationsEnabled
                        )
                    }

                    if !inStreamStarters.isEmpty && !inStreamBench.isEmpty {
                        HStack(spacing: AppSpacing.sm) {
                            Text("Bench in stream")
                                .font(AppFont.caption(weight: .medium))
                                .foregroundStyle(AppleTheme.textMuted)
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                        }
                        .padding(.top, AppSpacing.xxs)
                    }

                    ForEach(inStreamBench) { entry in
                        FantasyPlayerRowView(
                            player: entry.player,
                            showOpponentBadge: !entry.player.isUserRoster,
                            isResolvedDark: isResolvedDark,
                            animationsEnabled: animationsEnabled
                        )
                    }
                }
            }

            if !playingLive.isEmpty {
                sectionHeader("Playing Live")
                VStack(spacing: 5) {
                    ForEach(playingLive) { entry in
                        FantasyPlayerRowView(
                            player: entry.player,
                            showOpponentBadge: !entry.player.isUserRoster,
                            isResolvedDark: isResolvedDark,
                            animationsEnabled: animationsEnabled
                        )
                    }
                }
            }

            if !upcomingOrFinal.isEmpty {
                let hasLivePlayers = !inStream.isEmpty || !playingLive.isEmpty
                if hasLivePlayers {
                    DisclosureGroup("Upcoming & Final (\(upcomingOrFinal.count))", isExpanded: $showUpcomingPlayers) {
                        VStack(spacing: 5) {
                            ForEach(upcomingOrFinal) { entry in
                                FantasyPlayerRowView(
                                    player: entry.player,
                                    showOpponentBadge: !entry.player.isUserRoster,
                                    isResolvedDark: isResolvedDark,
                                    animationsEnabled: animationsEnabled
                                )
                            }
                        }
                        .padding(.top, AppSpacing.xs)
                    }
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.xxs)
                } else {
                    sectionHeader("Upcoming & Final")
                    VStack(spacing: 5) {
                        ForEach(upcomingOrFinal) { entry in
                            FantasyPlayerRowView(
                                player: entry.player,
                                showOpponentBadge: !entry.player.isUserRoster,
                                isResolvedDark: isResolvedDark,
                                animationsEnabled: animationsEnabled
                            )
                        }
                    }
                }
            } else if inStream.isEmpty && playingLive.isEmpty {
                emptyStateCard(
                    icon: "person.2",
                    title: "No Players in Matched Stream",
                    subtitle: "Pin another game or switch off Watched Stream Focus to view all live players."
                )
            }
        }
    }

    @ViewBuilder
    private var benchFilterChip: some View {
        Button {
            showBenchInPlayers.toggle()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Text("BN")
                    .font(AppFont.micro(weight: .bold))
                Text("Bench")
                    .font(AppFont.caption(weight: showBenchInPlayers ? .semibold : .medium))
            }
            .foregroundStyle(showBenchInPlayers ? AppleTheme.accentText : AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.md)
            .frame(minWidth: 24, minHeight: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(showBenchInPlayers ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        showBenchInPlayers ? AppleTheme.accentText.opacity(0.32) : AppleTheme.textSecondary.opacity(0.25),
                        lineWidth: 0.75
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(showBenchInPlayers ? "Hide bench players in Players feed" : "Show bench players in Players feed")
    }

    private func isPlayerLive(_ player: FantasyPlayerLine) -> Bool {
        store.isGameLive(player.matchedGameID)
            || player.isRedZone
            || (player.lastDeltaPoints.map { abs($0) >= 0.05 } ?? false)
    }

    private func compareTier1Players(_ lhs: RankedPlayerEntry, _ rhs: RankedPlayerEntry) -> Bool {
        if lhs.player.isUserRoster != rhs.player.isUserRoster { return lhs.player.isUserRoster }
        if lhs.player.isRedZone != rhs.player.isRedZone { return lhs.player.isRedZone }
        if abs(lhs.player.points - rhs.player.points) >= 0.05 { return lhs.player.points > rhs.player.points }
        return store.leaguePriorityRank(for: lhs.league) < store.leaguePriorityRank(for: rhs.league)
    }

    private func compareTier2Players(_ lhs: RankedPlayerEntry, _ rhs: RankedPlayerEntry) -> Bool {
        let lRank = store.leaguePriorityRank(for: lhs.league)
        let rRank = store.leaguePriorityRank(for: rhs.league)
        if lRank != rRank { return lRank < rRank }
        if lhs.player.isStarter != rhs.player.isStarter { return lhs.player.isStarter }
        if lhs.player.isUserRoster != rhs.player.isUserRoster { return lhs.player.isUserRoster }
        if lhs.player.isRedZone != rhs.player.isRedZone { return lhs.player.isRedZone }
        return lhs.player.points > rhs.player.points
    }

    // MARK: - Tab 3: Scores

    @ViewBuilder
    private var scoresTabContent: some View {
        if isFocusMissingStream {
            noMatchedStreamCard
        } else if filteredGames.isEmpty {
            emptyStateCard(
                icon: "sportscourt",
                title: "No Scoreboard Games",
                subtitle: controller.settings.livePulseEnabledLeagues.isEmpty
                    ? "Enable sports leagues in Settings -> Live Pulse."
                    : "No games returned for the selected league filter right now."
            )
        } else {
            ForEach(filteredGames) { game in
                scoreCard(game)
            }
        }
    }

    @ViewBuilder
    private func scoreCard(_ game: LiveGame) -> some View {
        let isPinnedToActive = isGamePinned(game)
        let isStreamMatch = snapshot.activeGameIDs.contains(game.id)
        let isFlashing = controller.settings.livePulseScoringFlashes && snapshot.scoringFlashGameIDs.contains(game.id)
        let allGamePlays = store.filteredPlays(for: game.id, rosterOnly: false)
        let displayedPlays = store.filteredPlays(for: game.id, rosterOnly: showRosterPlaysInScores)
        let isPlaysExpanded = expandedPlayGameIDs.contains(game.id)

        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: 5) {
                Text(game.league.displayName)
                    .font(AppFont.micro(weight: .bold))
                    .foregroundStyle(isStreamMatch ? AppleTheme.accentText : AppleTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isStreamMatch ? AppleTheme.accentText.opacity(0.15) : Color.primary.opacity(0.06))
                    )

                Text(game.clock ?? game.statusDetail)
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(game.status == .live ? AppleTheme.accentText : AppleTheme.textSecondary)
                    .lineLimit(1)

                if game.situation?.isRedZone == true {
                    Text("RED ZONE")
                        .font(AppFont.micro(weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                }

                Spacer()

                Button {
                    if isPinnedToActive, let tabID = activeTargetTab?.id {
                        store.clearManualPin(tabID: tabID)
                    } else {
                        pinGameToActiveTab(game)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isPinnedToActive ? "pin.fill" : "pin")
                            .font(AppIconFont.xs(weight: .semibold))
                        Text(isPinnedToActive ? "Pinned" : "Pin")
                            .font(AppFont.caption(weight: .semibold))
                    }
                    .foregroundStyle(isPinnedToActive ? Color.white : Color.primary.opacity(0.84))
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(24, shape: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(isPinnedToActive ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }

            teamScoreRow(game.away, league: game.league)
            teamScoreRow(game.home, league: game.league)

            if let sit = game.situation, let summary = situationSummary(sit), !summary.isEmpty {
                Text(summary)
                    .font(AppFont.caption(weight: .medium, tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
            }

            if let awayWin = game.espnAwayWinProb, let homeWin = game.espnHomeWinProb {
                winProbabilityBar(
                    awayAbbreviation: game.away.abbreviation,
                    homeAbbreviation: game.home.abbreviation,
                    awayProb: awayWin,
                    homeProb: homeWin
                )
            }

            HStack(spacing: AppSpacing.md) {
                if let spread = game.spreadSummary, !spread.isEmpty {
                    Text(spread)
                        .font(AppFont.caption(tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                if let ou = game.overUnder {
                    Text(String(format: "O/U %.1f", ou))
                        .font(AppFont.caption(tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                Spacer()
                if !allGamePlays.isEmpty {
                    Button {
                        if isPlaysExpanded {
                            expandedPlayGameIDs.remove(game.id)
                        } else {
                            expandedPlayGameIDs.insert(game.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isPlaysExpanded ? "chevron.up" : "list.bullet")
                                .font(AppIconFont.xs(weight: .semibold))
                            Text("Plays (\(allGamePlays.count))")
                                .font(AppFont.caption(weight: .semibold, tabular: true))
                        }
                        .foregroundStyle(isPlaysExpanded ? AppleTheme.accentText : AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                        .background(
                            Capsule(style: .continuous)
                                .fill(isPlaysExpanded ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                }
                if let network = game.broadcasts.first {
                    Text(network)
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textMuted)
                }
            }

            if isPlaysExpanded && !allGamePlays.isEmpty {
                Divider().opacity(0.25)
                HStack(spacing: AppSpacing.sm) {
                    Text("Play-by-Play")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                    Spacer()
                    rosterPlaysToggleChip(isOn: $showRosterPlaysInScores)
                }

                if displayedPlays.isEmpty && showRosterPlaysInScores {
                    Text("No recent plays involving your fantasy roster.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textMuted)
                        .padding(.vertical, AppSpacing.xxs)
                } else {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(displayedPlays.prefix(6)) { play in
                            playByPlayRow(play)
                        }
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(
                    isFlashing
                        ? AppleTheme.positive.opacity(0.14)
                        : (isStreamMatch ? AppleTheme.accentText.opacity(0.08) : Color.primary.opacity(isResolvedDark ? 0.06 : 0.04))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(
                    isFlashing
                        ? AppleTheme.positive.opacity(0.55)
                        : (isStreamMatch ? AppleTheme.accentText.opacity(0.32) : Color.clear),
                    lineWidth: 1
                )
        )
        .contextMenu {
            Button {
                if isPinnedToActive, let tabID = activeTargetTab?.id {
                    store.clearManualPin(tabID: tabID)
                } else {
                    pinGameToActiveTab(game)
                }
            } label: {
                Label(isPinnedToActive ? "Unpin from Stream" : "Pin to Stream", systemImage: isPinnedToActive ? "pin.slash" : "pin")
            }

            let isMenuBarPinned = store.menuBarPinnedGame?.id == game.id
            Button {
                if isMenuBarPinned {
                    store.pinGameToMenuBar(nil)
                } else {
                    controller.settings.livePulseMenuBarPin = true
                    store.pinGameToMenuBar(game.id)
                }
            } label: {
                Label(
                    isMenuBarPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar",
                    systemImage: isMenuBarPinned ? "pin.slash" : "menubar.rectangle"
                )
            }
        }
    }

    @ViewBuilder
    private func teamScoreRow(_ team: TeamScore, league: SportsLeague) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(team.isPossession ? AppleTheme.accentFill : Color.clear)
                .frame(width: 5, height: 5)

            Text(team.abbreviation)
                .font(AppFont.callout(weight: .bold))
                .frame(width: 40, alignment: .leading)

            if let rank = team.rank, rank > 0 {
                Text("#\(rank)")
                    .font(AppFont.micro(weight: .bold, tabular: true))
                    .foregroundStyle(AppleTheme.accentText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppleTheme.accentText.opacity(0.12), in: Capsule(style: .continuous))
            }

            Text(team.shortName)
                .font(AppFont.callout(weight: .medium))
                .lineLimit(1)

            if let record = team.record, !record.isEmpty, league != .f1 {
                Text(record)
                    .font(AppFont.caption(tabular: true))
                    .foregroundStyle(AppleTheme.textMuted)
            }

            Spacer()

            Text(league == .f1 ? "P\(team.score)" : "\(team.score)")
                .font(AppFont.subhead(weight: .bold, tabular: true))
                .liveNumericTransition(enabled: animationsEnabled, value: team.score)
        }
    }

    @ViewBuilder
    private func winProbabilityBar(
        awayAbbreviation: String,
        homeAbbreviation: String,
        awayProb: Double,
        homeProb: Double
    ) -> some View {
        let clampedAway = max(0.0, min(1.0, awayProb))
        let clampedHome = max(0.0, min(1.0, homeProb))
        let total = clampedAway + clampedHome
        let normalizedAway = total > 0 ? clampedAway / total : 0.5
        let awayPct = Int((normalizedAway * 100.0).rounded())
        let homePct = max(0, 100 - awayPct)
        let awayFavored = awayPct >= homePct

        VStack(spacing: 3) {
            HStack(spacing: AppSpacing.xs) {
                Text("\(awayAbbreviation) \(awayPct)%")
                    .font(AppFont.micro(weight: awayFavored ? .bold : .medium, tabular: true))
                    .foregroundStyle(awayFavored ? Color.primary : AppleTheme.textSecondary)
                Spacer()
                Text("Win Prob")
                    .font(AppFont.micro(weight: .medium))
                    .foregroundStyle(AppleTheme.textMuted)
                Spacer()
                Text("\(homePct)% \(homeAbbreviation)")
                    .font(AppFont.micro(weight: awayFavored ? .medium : .bold, tabular: true))
                    .foregroundStyle(awayFavored ? AppleTheme.textSecondary : Color.primary)
            }

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let awayWidth = max(2, width * normalizedAway)
                HStack(spacing: 1) {
                    Capsule(style: .continuous)
                        .fill(awayFavored ? AppleTheme.accentFill : Color.primary.opacity(0.20))
                        .frame(width: awayWidth, height: 4)
                    Capsule(style: .continuous)
                        .fill(awayFavored ? Color.primary.opacity(0.20) : AppleTheme.positive)
                        .frame(maxWidth: .infinity, maxHeight: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func rosterPlaysToggleChip(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isOn.wrappedValue ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    .font(AppIconFont.xs(weight: .semibold))
                Text("My Roster Plays")
                    .font(AppFont.micro(weight: .semibold))
            }
            .foregroundStyle(isOn.wrappedValue ? AppleTheme.accentText : AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .minHitTarget(24, shape: Capsule(style: .continuous))
            .background(
                Capsule(style: .continuous)
                    .fill(isOn.wrappedValue ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .help("Filter play-by-play to players on your fantasy roster")
    }

    @ViewBuilder
    private func playByPlayRow(_ play: PlayByPlayEvent) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                let clockLabel = [play.periodText, play.clock ?? ""]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                HStack(spacing: AppSpacing.xs) {
                    if !clockLabel.isEmpty {
                        Text(clockLabel)
                            .font(AppFont.micro(weight: .semibold, tabular: true))
                            .foregroundStyle(play.isScoringPlay ? AppleTheme.positive : AppleTheme.textMuted)
                    }
                    if let abbr = play.teamAbbreviation, !abbr.isEmpty {
                        Text(abbr)
                            .font(AppFont.micro(weight: .bold))
                            .foregroundStyle(play.isScoringPlay ? AppleTheme.positive : AppleTheme.accentText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((play.isScoringPlay ? AppleTheme.positive : AppleTheme.accentText).opacity(0.12))
                            )
                    }
                    if play.isScoringPlay {
                        Text("SCORE")
                            .font(AppFont.micro(weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppleTheme.positive, in: Capsule(style: .continuous))
                    }
                    Spacer(minLength: 0)
                    if let away = play.awayScore, let home = play.homeScore {
                        Text("\(away)–\(home)")
                            .font(AppFont.micro(weight: .semibold, tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }

                Text(play.text)
                    .font(AppFont.caption(weight: play.isScoringPlay ? .medium : .regular))
                    .foregroundStyle(play.isScoringPlay ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(play.isScoringPlay ? AppleTheme.positive.opacity(0.08) : Color.primary.opacity(0.035))
        )
    }

    // MARK: - Tab 4: Markets (Strictly Read-Only Informational)

    @ViewBuilder
    private var marketsTabContent: some View {
        if !controller.settings.livePulseShowMarkets {
            emptyStateCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Prediction Markets Disabled",
                subtitle: "Enable \"Show Kalshi & Polymarket Probabilities\" in Settings -> Live Pulse to view live implied odds."
            )
        } else if isFocusMissingStream {
            noMatchedStreamCard
        } else if filteredMarkets.isEmpty {
            emptyStateCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "No Active Sports Markets",
                subtitle: "Waiting for live Kalshi or Polymarket sports markets matching your enabled leagues."
            )
        } else {
            ForEach(filteredMarkets.prefix(24)) { quote in
                marketCard(quote)
            }

            Text("Read-only informational probabilities from Kalshi and Polymarket public market feeds. GlassGrid You does not execute trades, place wagers, or connect wallets.")
                .font(AppFont.caption)
                .foregroundStyle(AppleTheme.textSecondary)
                .padding(.top, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.xs)
        }
    }

    @ViewBuilder
    private func marketCard(_ quote: PredictionMarketQuote) -> some View {
        let isStreamMatch = quote.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
        let pct = Int((quote.yesProbability * 100.0).rounded())

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(quote.provider.displayName)
                    .font(AppFont.micro(weight: .bold))
                    .foregroundStyle(AppleTheme.accentText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))

                if let league = quote.league {
                    Text(league.displayName)
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                }

                Spacer()

                if let urlStr = quote.externalURLString, let url = URL(string: urlStr) {
                    Button {
                        controller.openCompanionTile(url: url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(AppIconFont.sm)
                            .foregroundStyle(AppleTheme.textSecondary)
                            .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                    .help("Open Market Page in Companion Tile")
                }
            }

            Text(quote.title)
                .font(AppFont.caption(weight: .medium))
                .lineLimit(2)

            HStack(spacing: AppSpacing.sm) {
                Text(quote.outcomeLabel)
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)

                Spacer()

                if let d1 = quote.delta1m, abs(d1) >= 0.005 {
                    deltaPill(label: "1m", delta: d1)
                }
                if let d5 = quote.delta5m, abs(d5) >= 0.005 {
                    deltaPill(label: "5m", delta: d5)
                }

                Text("\(pct)%")
                    .font(AppFont.subhead(weight: .bold, tabular: true))
                    .foregroundStyle(isStreamMatch ? AppleTheme.accentText : Color.primary)
                    .liveNumericTransition(enabled: animationsEnabled, value: pct)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(isStreamMatch ? AppleTheme.accentText.opacity(0.08) : Color.primary.opacity(isResolvedDark ? 0.06 : 0.04))
        )
    }

    @ViewBuilder
    private func deltaPill(label: String, delta: Double) -> some View {
        let pct = Int((delta * 100.0).rounded())
        let sign = pct >= 0 ? "+" : ""
        let color: Color = pct >= 0 ? AppleTheme.positive : AppleTheme.accentText
        Text("\(label) \(sign)\(pct)%")
            .font(AppFont.caption(weight: .semibold, tabular: true))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
    }

    // MARK: - Tab 5: Chat (Strictly Lazy & HTTPS Allowlisted)

    @ViewBuilder
    private var chatTabContent: some View {
        let tab = activeTargetTab
        let streamURL = tab.map { $0.pendingLazyURL ?? $0.url }
        let chatURL = streamURL.flatMap {
            CompanionChatURLValidator.chatURL(forStreamURL: $0, darkMode: isResolvedDark)
        }
        let isLiveOrTwitch: Bool = {
            guard let tab, let streamURL else { return false }
            let host = (streamURL.host ?? "").lowercased()
            let isTwitch = host == "twitch.tv" || host == "www.twitch.tv" || host.hasSuffix(".twitch.tv")
            let isYouTubeLive = streamURL.path.hasPrefix("/live/")
                || (tab.mediaStatus.hasVideo && tab.timeline.duration == 0 && !tab.isLoading)
            return isTwitch || isYouTubeLive
        }()

        if let tab,
           let chatURL,
           CompanionChatURLValidator.isAllowedChatURL(chatURL),
           (isLiveOrTwitch || manualChatTabID == tab.id) {
            LazyCompanionChatWebView(url: chatURL, isResolvedDark: isResolvedDark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isFrozen ? 0.7 : 1.0)
                .allowsHitTesting(!isFrozen)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(AppIconFont.hero(weight: .medium))
                        .foregroundStyle(AppleTheme.accentText)
                    Text("Live Chat Unavailable")
                        .font(AppFont.callout(weight: .semibold))
                        .multilineTextAlignment(.center)
                    Text("Focus an active YouTube live stream or Twitch channel to load its popout chat here.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    if let tab,
                       let chatURL,
                       CompanionChatURLValidator.isAllowedChatURL(chatURL) {
                        Button("Load YouTube Live Chat") {
                            manualChatTabID = tab.id
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.xl)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .padding(10)
            }
        }
    }

    // MARK: - Footer: 1-Click "Open in Tile" Quick-Launcher

    @ViewBuilder
    private var quickLauncherFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Open in Tile")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                Spacer()
                SettingsLink {
                    Text("Settings…")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.xs)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 68), spacing: AppSpacing.xs),
                    GridItem(.flexible(minimum: 68), spacing: AppSpacing.xs),
                    GridItem(.flexible(minimum: 68), spacing: AppSpacing.xs)
                ],
                spacing: AppSpacing.xs
            ) {
                ForEach(CompanionQuickSite.livePulseSites) { site in
                    Button {
                        controller.openCompanionTile(url: site.url)
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: site.systemImage)
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                            Text(shortLauncherTitle(for: site))
                                .font(AppFont.caption(weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .padding(.horizontal, AppSpacing.sm)
                        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                    .help("Open \(site.name) in Multiview Tile")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, AppSpacing.md)
    }

    private func shortLauncherTitle(for site: CompanionQuickSite) -> String {
        switch site.id {
        case "espn-fantasy": return "ESPN"
        case "yahoo-fantasy": return "Yahoo"
        case "nfl-fantasy": return "NFL.com"
        default: return site.name
        }
    }

    // MARK: - Empty States & Helpers

    @ViewBuilder
    private var noMatchedStreamCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "scope")
                .font(AppIconFont.xl(weight: .medium))
                .foregroundStyle(AppleTheme.accentText)
            Text("No matched stream")
                .font(AppFont.callout(weight: .semibold))
            Text("Play a live sports broadcast, pin a game to this tab, or switch back to all leagues.")
                .font(AppFont.caption)
                .foregroundStyle(AppleTheme.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppSpacing.md) {
                Button {
                    isPinEmptyStatePopoverPresented = true
                } label: {
                    Text("Pin game")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .minHitTarget(26, shape: Capsule(style: .continuous))
                        .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFrozen || snapshot.games.isEmpty)
                .popover(isPresented: $isPinEmptyStatePopoverPresented, arrowEdge: .leading) {
                    drawerPinPopover
                }

                Button {
                    controller.toggleLivePulseStreamFocus()
                } label: {
                    Text("Show All")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.lg)
                        .minHitTarget(26, shape: Capsule(style: .continuous))
                        .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }
            .padding(.top, AppSpacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private var drawerPinPopover: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Pin Game to Active Stream")
                .font(AppFont.callout(weight: .semibold))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.games.prefix(12)) { game in
                        Button {
                            pinGameToActiveTab(game)
                            isPinEmptyStatePopoverPresented = false
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Text(game.league.displayName)
                                    .font(AppFont.micro(weight: .bold))
                                    .foregroundStyle(AppleTheme.textSecondary)
                                    .frame(width: 28, alignment: .leading)
                                Text("\(game.away.abbreviation) \(game.away.score) – \(game.home.score) \(game.home.abbreviation)")
                                    .font(AppFont.caption(weight: .medium, tabular: true))
                                Spacer()
                                Text(game.clock ?? game.statusDetail)
                                    .font(AppFont.caption(tabular: true))
                                    .foregroundStyle(AppleTheme.textSecondary)
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 5)
                            .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .frame(width: 250)
    }

    @ViewBuilder
    private func emptyStateCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppIconFont.hero(weight: .medium))
                .foregroundStyle(AppleTheme.accentText)
            Text(title)
                .font(AppFont.callout(weight: .semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(AppFont.caption)
                .foregroundStyle(AppleTheme.textSecondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Text("Open Live Pulse Settings")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.lg)
                    .minHitTarget(28, shape: Capsule(style: .continuous))
                    .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .padding(.top, AppSpacing.xxs)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.xxs)
    }

    private func isGamePinned(_ game: LiveGame) -> Bool {
        guard let tabID = activeTargetTab?.id,
              let pin = store.manualPinsByTab[tabID],
              case .game(let gid, _) = pin.mode else {
            return false
        }
        return gid == game.id
    }

    private func pinGameToActiveTab(_ game: LiveGame) {
        guard let tab = activeTargetTab else { return }
        store.setManualPin(
            ManualGamePin(
                tabID: tab.id,
                scopeKey: controller.activeTabScopeKey(for: tab),
                mode: .game(gameID: game.id, league: game.league),
                isLocked: true
            )
        )
    }

    private func situationSummary(_ sit: GameSituation) -> String? {
        if let downDist = sit.downDistanceText, !downDist.isEmpty {
            if let yard = sit.yardLineText, !yard.isEmpty {
                return "\(downDist) · \(yard)"
            }
            return downDist
        }
        var parts: [String] = []
        if let balls = sit.balls, let strikes = sit.strikes {
            parts.append("\(balls)-\(strikes)")
        }
        if let outs = sit.outs {
            parts.append("\(outs) Out\(outs == 1 ? "" : "s")")
        }
        if let runners = sit.runnersOnBaseText, !runners.isEmpty {
            parts.append(runners)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Dedicated Fantasy Player Row (1-Shot Delta Wash + Starter/Bench Cues)

private struct FantasyPlayerRowView: View {
    let player: FantasyPlayerLine
    let showOpponentBadge: Bool
    let isResolvedDark: Bool
    let animationsEnabled: Bool

    @State private var highlightWashOpacity: Double = 0
    @State private var washColor: Color = AppleTheme.positive

    private var isBench: Bool { !player.isStarter }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.sm) {
                slotBadge

                Text(player.name)
                    .font(
                        isBench
                            ? AppFont.caption(weight: .medium)
                            : AppFont.callout(weight: player.isActiveInStream ? .semibold : .medium)
                    )
                    .foregroundStyle(isBench ? Color.primary.opacity(0.76) : Color.primary)
                    .lineLimit(1)

                Text(isBench ? "\(player.position) · \(player.nflOrProTeam)" : player.nflOrProTeam)
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)

                if showOpponentBadge && !player.isUserRoster {
                    Text("OPP")
                        .font(AppFont.micro(weight: .bold))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
                }

                if player.isRedZone {
                    redZoneBadge
                }

                Spacer(minLength: AppSpacing.xs)

                if let delta = player.lastDeltaPoints, abs(delta) >= 0.05 {
                    let isPositive = delta >= 0
                    Text(String(format: "%@%.1f", isPositive ? "+" : "", delta))
                        .font(AppFont.caption(weight: .bold, tabular: true))
                        .foregroundStyle(isPositive ? AppleTheme.positive : AppleTheme.accentText)
                }

                Text(String(format: "%.1f", player.points))
                    .font(
                        isBench
                            ? AppFont.caption(weight: .medium, tabular: true)
                            : AppFont.callout(weight: .semibold, tabular: true)
                    )
                    .foregroundStyle(isBench ? AppleTheme.textSecondary : Color.primary)
                    .liveNumericTransition(enabled: animationsEnabled, value: player.points)
            }

            if let statLine = player.liveStatLine, !statLine.isEmpty {
                Text(statLine)
                    .font(AppFont.caption(tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(surfaceFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(washColor.opacity(highlightWashOpacity))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .strokeBorder(surfaceStrokeColor, lineWidth: isBench ? 0.5 : 0)
        )
        .onChange(of: player.points) { oldPoints, newPoints in
            let diff = newPoints - oldPoints
            guard abs(diff) >= 0.05 else { return }
            triggerOneShotWash(isPositive: diff >= 0)
        }
        .onChange(of: player.lastDeltaPoints) { oldDelta, newDelta in
            guard let newDelta, abs(newDelta) >= 0.05, newDelta != oldDelta else { return }
            triggerOneShotWash(isPositive: newDelta >= 0)
        }
    }

    @ViewBuilder
    private var slotBadge: some View {
        if isBench {
            Text("BN")
                .font(AppFont.micro(weight: .bold))
                .foregroundStyle(AppleTheme.textSecondary)
                .frame(width: 30, height: 18)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppleTheme.textSecondary.opacity(0.35), lineWidth: 0.75)
                )
        } else {
            Text(player.position)
                .font(AppFont.micro(weight: .bold))
                .foregroundStyle(player.isActiveInStream ? AppleTheme.accentText : AppleTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 30, height: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(player.isActiveInStream ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.07))
                )
        }
    }

    @ViewBuilder
    private var redZoneBadge: some View {
        if isBench {
            Text("RZ")
                .font(AppFont.micro(weight: .bold))
                .foregroundStyle(AppleTheme.accentText)
                .padding(.horizontal, 5)
                .padding(.vertical, AppSpacing.xxs)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppleTheme.accentText.opacity(0.45), lineWidth: 0.75)
                )
        } else {
            Text("RZ")
                .font(AppFont.micro(weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
        }
    }

    private var surfaceFillColor: Color {
        if isBench {
            return player.isActiveInStream ? AppleTheme.accentText.opacity(0.05) : Color.primary.opacity(0.015)
        }
        if player.isActiveInStream {
            return AppleTheme.accentText.opacity(isResolvedDark ? 0.13 : 0.09)
        }
        return Color.primary.opacity(isResolvedDark ? 0.045 : 0.035)
    }

    private var surfaceStrokeColor: Color {
        guard isBench else { return .clear }
        return player.isActiveInStream ? AppleTheme.accentText.opacity(0.20) : Color.primary.opacity(0.09)
    }

    private func triggerOneShotWash(isPositive: Bool) {
        guard animationsEnabled else { return }
        washColor = isPositive ? AppleTheme.positive : AppleTheme.accentText
        highlightWashOpacity = 0.16
        withAnimation(.easeOut(duration: 1.4)) {
            highlightWashOpacity = 0
        }
    }
}

private extension View {
    @ViewBuilder
    func liveNumericTransition<V: Equatable>(enabled: Bool, value: V) -> some View {
        if enabled {
            self
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.28), value: value)
        } else {
            self
        }
    }
}

// MARK: - Strictly Lazy Companion Live Chat WebView

/// Isolated `WKWebView` for YouTube Live Chat and Twitch Popout Chat.
/// Strictly lazy (mounts only when `.chat` is active), enforces `CompanionChatURLValidator`,
/// never touches `TabWebViewHost`, and tears down navigation delegates and content on dismantle.
private struct LazyCompanionChatWebView: NSViewRepresentable {
    let url: URL
    let isResolvedDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = BrowserTab.safariUserAgentSuffix
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        applyUnderPageColor(to: webView, isDark: isResolvedDark)

        if CompanionChatURLValidator.isAllowedChatURL(url) {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        applyUnderPageColor(to: webView, isDark: isResolvedDark)
        guard CompanionChatURLValidator.isAllowedChatURL(url) else { return }
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        coordinator.loadedURL = nil
    }

    private func applyUnderPageColor(to webView: WKWebView, isDark: Bool) {
        webView.underPageBackgroundColor = isDark
            ? NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
            : .white
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame == true {
                if CompanionChatURLValidator.isAllowedChatURL(targetURL)
                    || targetURL.absoluteString == "about:blank" {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.cancel)
                }
                return
            }

            let scheme = targetURL.scheme?.lowercased() ?? ""
            if scheme == "https" || scheme == "about" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
