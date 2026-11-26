import SwiftUI
import YouTubeMacCore

/// Trailing Liquid Glass Live Companion Drawer displaying fantasy matchups, active-in-stream players,
/// live scores with 1-click stream pinning, read-only prediction markets, and quick web-tile launchers.
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
    @State private var isPinEmptyStatePopoverPresented: Bool = false
    @State private var isSpoilerPopoverPresented: Bool = false

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
                    }
                }
                .padding(10)
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
        HStack(spacing: 4) {
            // Segmented Mode Picker
            HStack(spacing: 1) {
                ForEach(LivePulseDrawerTab.allCases) { tab in
                    let isSelected = store.selectedDrawerTab == tab
                    Button {
                        store.selectedDrawerTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(isSelected ? AppleTheme.accent : Color.primary.opacity(0.78))
                            .padding(.horizontal, 6)
                            .frame(height: 22)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? AppleTheme.accent.opacity(0.16) : .clear)
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 26)
            .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))

            Spacer(minLength: 2)

            LivePulseRefreshButton(
                isRefreshing: store.isRefreshing,
                lastUpdatedAt: snapshot.lastUpdatedAt,
                lastManualRefreshCompletedAt: store.lastManualRefreshCompletedAt,
                providerStatus: snapshot.providerStatus,
                isEnabled: controller.settings.livePulseEnabled,
                isFrozen: isFrozen,
                iconSize: 10.5
            ) {
                store.refreshNow()
            }

            Button {
                controller.toggleLivePulseDrawer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .help("Close Live Companion Drawer (⌘⌥I)")
        }
        .padding(.horizontal, 8)
        .frame(height: LivePulseLayout.drawerHeaderHeight)
    }

    // MARK: - Stream Context, Disambiguation & Filters

    @ViewBuilder
    private var contextAndFiltersBar: some View {
        let isFocused = controller.settings.livePulseStreamFocusOnly

        VStack(alignment: .leading, spacing: 7) {
            streamContextBanner

            HStack(spacing: 5) {
                Button {
                    controller.toggleLivePulseStreamFocus()
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "scope")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Focus")
                            .font(.system(size: 10, weight: isFocused ? .semibold : .medium))
                    }
                    .foregroundStyle(isFocused ? AppleTheme.accent : Color.primary.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isFocused ? AppleTheme.accent.opacity(0.16) : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isFrozen)
                .help(isFocused ? "Watched Stream Focus: On — Click to show all leagues" : "Watched Stream Focus — Filter Live Pulse to active stream(s)")

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        leagueFilterPill(title: "All", league: nil)
                        ForEach(controller.settings.orderedEnabledLivePulseLeagues) { league in
                            leagueFilterPill(title: league.displayName, league: league)
                                .contextMenu {
                                    Button("Move \(league.displayName) to #1 Priority") {
                                        controller.settings.moveLivePulseLeagueToTop(league)
                                    }
                                }
                        }
                    }
                }

                let isDelayActive = controller.settings.livePulseSpoilerDelay != .off
                Button {
                    isSpoilerPopoverPresented.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isDelayActive ? AppleTheme.accent : Color.secondary)
                        Text(controller.settings.livePulseSpoilerDelay.shortLabel)
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isDelayActive ? AppleTheme.accent : Color.primary.opacity(0.80))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isDelayActive ? AppleTheme.accent.opacity(0.14) : Color.primary.opacity(0.06))
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(isFrozen)
                .help("Spoiler Delay Buffer")
                .popover(isPresented: $isSpoilerPopoverPresented, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spoiler Delay Buffer")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        ForEach(SpoilerDelayOption.allCases) { option in
                            let isSelected = controller.settings.livePulseSpoilerDelay == option
                            Button {
                                controller.settings.livePulseSpoilerDelay = option
                                isSpoilerPopoverPresented = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isSelected ? "checkmark" : "clock")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(isSelected ? AppleTheme.accent : .secondary)
                                        .frame(width: 14)
                                    Text(option.displayName)
                                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? AppleTheme.accent.opacity(0.12) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .frame(width: 170)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var streamContextBanner: some View {
        let isFocused = controller.settings.livePulseStreamFocusOnly
        let bannerFill = isFocused ? AppleTheme.accent.opacity(0.12) : Color.primary.opacity(0.05)

        switch snapshot.primaryContext {
        case .networkCandidates(let network, _, let gameIDs):
            let candidates = snapshot.games.filter { gameIDs.contains($0.id) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "tv.and.mediabox")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppleTheme.accent)
                    Text("Multiple \(network) broadcasts — Pin your game:")
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
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
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(candidates) { game in
                                Button {
                                    pinGameToActiveTab(game)
                                } label: {
                                    Text("\(game.away.abbreviation) @ \(game.home.abbreviation)")
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppleTheme.accent)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(AppleTheme.accent.opacity(0.14), in: Capsule(style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(isFrozen)
                            }
                        }
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppleTheme.accent.opacity(isFocused ? 0.14 : 0.09),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )

        case .matchedGame(let gameID, _, let confidence, let sourceLabel):
            let game = snapshot.games.first(where: { $0.id == gameID })
            HStack(spacing: 6) {
                Image(systemName: confidence == .manual ? "pin.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(game.map { "\($0.away.abbreviation) \($0.away.score) – \($0.home.score) \($0.home.abbreviation)" } ?? sourceLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(confidence == .manual ? "Pinned to active stream" : "Auto-matched: \(sourceLabel)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                        FreshnessLabelView(
                            lastUpdatedAt: snapshot.lastUpdatedAt,
                            hasLiveGames: hasLiveGames,
                            isOffline: isOffline,
                            isFrozen: isFrozen,
                            style: .drawerInline
                        )
                    }
                }

                Spacer(minLength: 4)

                if confidence == .manual, let tabID = activeTargetTab?.id {
                    Button("Unpin") {
                        store.clearManualPin(tabID: tabID)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
                    .disabled(isFrozen)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bannerFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

        case .liveSlate(let league, let label):
            HStack(spacing: 6) {
                Image(systemName: league.symbolName)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("Whip-around slate")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
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
                    Button("Auto") {
                        store.clearManualPin(tabID: tabID)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
                    .disabled(isFrozen)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(bannerFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

        case .none:
            HStack(spacing: 6) {
                Image(systemName: "play.tv")
                    .font(.system(size: 10))
                    .foregroundStyle(isFocused ? AppleTheme.accent : .secondary)
                Text("Pin a game in Scores or play a live broadcast")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                FreshnessLabelView(
                    lastUpdatedAt: snapshot.lastUpdatedAt,
                    hasLiveGames: hasLiveGames,
                    isOffline: isOffline,
                    isFrozen: isFrozen,
                    style: .drawerInline
                )
            }
            .padding(.horizontal, isFocused ? 8 : 0)
            .padding(.vertical, isFocused ? 5 : 0)
            .background(
                isFocused ? AppleTheme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
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
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppleTheme.accent : Color.primary.opacity(0.76))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppleTheme.accent.opacity(0.16) : Color.primary.opacity(0.06))
                )
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
        }
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

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(matchup.league.displayName) · \(matchup.leagueName)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(matchup.weekLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(matchup.userTeamName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(String(format: "%.1f", matchup.userPoints))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(matchup.userPoints >= matchup.opponentPoints ? .primary : .secondary)
                        .liveNumericTransition(enabled: animationsEnabled, value: matchup.userPoints)
                    if let proj = matchup.userProjected {
                        Text(String(format: "Proj %.1f", proj))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("VS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(matchup.opponentTeamName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(String(format: "%.1f", matchup.opponentPoints))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(matchup.opponentPoints > matchup.userPoints ? .primary : .secondary)
                        .liveNumericTransition(enabled: animationsEnabled, value: matchup.opponentPoints)
                    if let proj = matchup.opponentProjected {
                        Text(String(format: "Proj %.1f", proj))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider().opacity(0.3)

            Text("Your Starters")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not counted in matchup total")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)

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
                    HStack(spacing: 6) {
                        Text(liveBenchCount > 0 ? "Bench (\(matchup.bench.count) · \(liveBenchCount) live)" : "Bench (\(matchup.bench.count))")
                        Spacer()
                        Text(String(format: "%.1f BN", benchTotal))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            }

            if !matchup.opponentStarters.isEmpty {
                DisclosureGroup("Opponent Starters (\(matchup.opponentStarters.count))", isExpanded: $showOpponentStarters) {
                    VStack(spacing: 4) {
                        ForEach(matchup.opponentStarters) { player in
                            FantasyPlayerRowView(
                                player: player,
                                showOpponentBadge: true,
                                isResolvedDark: isResolvedDark,
                                animationsEnabled: animationsEnabled
                            )
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(isResolvedDark ? 0.06 : 0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    benchFilterChip
                }
                .padding(.horizontal, 2)
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
                        HStack(spacing: 6) {
                            Text("Bench in stream")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                        }
                        .padding(.top, 2)
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
                        .padding(.top, 4)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
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
            HStack(spacing: 3.5) {
                Text("BN")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                Text("Bench")
                    .font(.system(size: 10, weight: showBenchInPlayers ? .semibold : .medium))
            }
            .foregroundStyle(showBenchInPlayers ? AppleTheme.accent : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                Capsule(style: .continuous)
                    .fill(showBenchInPlayers ? AppleTheme.accent.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        showBenchInPlayers ? AppleTheme.accent.opacity(0.32) : Color.secondary.opacity(0.25),
                        lineWidth: 0.75
                    )
            )
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
                    ? "Enable NFL, NBA, MLB, or NHL in Settings -> Live Pulse."
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

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(game.league.displayName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isStreamMatch ? AppleTheme.accent : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isStreamMatch ? AppleTheme.accent.opacity(0.15) : Color.primary.opacity(0.06))
                    )

                Text(game.clock ?? game.statusDetail)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(game.status == .live ? AppleTheme.accent : .secondary)
                    .lineLimit(1)

                if game.situation?.isRedZone == true {
                    Text("RED ZONE")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(AppleTheme.accent, in: Capsule(style: .continuous))
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
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(isPinnedToActive ? "Pinned" : "Pin")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(isPinnedToActive ? .white : Color.primary.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isPinnedToActive ? AppleTheme.accent : Color.primary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }

            teamScoreRow(game.away)
            teamScoreRow(game.home)

            if let sit = game.situation, let summary = situationSummary(sit), !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let spread = game.spreadSummary, !spread.isEmpty {
                    Text(spread)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
                if let ou = game.overUnder {
                    Text(String(format: "O/U %.1f", ou))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let awayWin = game.espnAwayWinProb, let homeWin = game.espnHomeWinProb {
                    let awayPct = Int((awayWin * 100).rounded())
                    let homePct = Int((homeWin * 100).rounded())
                    Text("Win \(game.away.abbreviation) \(awayPct)% / \(game.home.abbreviation) \(homePct)%")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let network = game.broadcasts.first {
                    Text(network)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isStreamMatch ? AppleTheme.accent.opacity(0.08) : Color.primary.opacity(isResolvedDark ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(isStreamMatch ? AppleTheme.accent.opacity(0.32) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func teamScoreRow(_ team: TeamScore) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(team.isPossession ? AppleTheme.accent : Color.clear)
                .frame(width: 5, height: 5)

            Text(team.abbreviation)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .frame(width: 38, alignment: .leading)

            Text(team.shortName)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)

            if let record = team.record, !record.isEmpty {
                Text(record)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(team.score)")
                .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                .liveNumericTransition(enabled: animationsEnabled, value: team.score)
        }
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
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func marketCard(_ quote: PredictionMarketQuote) -> some View {
        let isStreamMatch = quote.matchedGameID.map { snapshot.activeGameIDs.contains($0) } ?? false
        let pct = Int((quote.yesProbability * 100.0).rounded())

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(quote.provider.displayName)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(AppleTheme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(AppleTheme.accent.opacity(0.14), in: Capsule(style: .continuous))

                if let league = quote.league {
                    Text(league.displayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let urlStr = quote.externalURLString, let url = URL(string: urlStr) {
                    Button {
                        controller.openCompanionTile(url: url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFrozen)
                    .help("Open Market Page in Companion Tile")
                }
            }

            Text(quote.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(quote.outcomeLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if let d1 = quote.delta1m, abs(d1) >= 0.005 {
                    deltaPill(label: "1m", delta: d1)
                }
                if let d5 = quote.delta5m, abs(d5) >= 0.005 {
                    deltaPill(label: "5m", delta: d5)
                }

                Text("\(pct)%")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isStreamMatch ? AppleTheme.accent : .primary)
                    .liveNumericTransition(enabled: animationsEnabled, value: pct)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isStreamMatch ? AppleTheme.accent.opacity(0.08) : Color.primary.opacity(isResolvedDark ? 0.06 : 0.04))
        )
    }

    @ViewBuilder
    private func deltaPill(label: String, delta: Double) -> some View {
        let pct = Int((delta * 100.0).rounded())
        let sign = pct >= 0 ? "+" : ""
        let color: Color = pct >= 0 ? .green : AppleTheme.accent
        Text("\(label) \(sign)\(pct)%")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.14), in: Capsule(style: .continuous))
    }

    // MARK: - Footer: 1-Click "Open in Tile" Quick-Launcher

    @ViewBuilder
    private var quickLauncherFooter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Open in Tile")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink {
                    Text("Settings…")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppleTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(isFrozen)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 68), spacing: 4),
                    GridItem(.flexible(minimum: 68), spacing: 4),
                    GridItem(.flexible(minimum: 68), spacing: 4)
                ],
                spacing: 4
            ) {
                ForEach(CompanionQuickSite.livePulseSites) { site in
                    Button {
                        controller.openCompanionTile(url: site.url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: site.systemImage)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(AppleTheme.accent)
                            Text(shortLauncherTitle(for: site))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
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
        .padding(.vertical, 8)
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
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(AppleTheme.accent.opacity(0.85))
            Text("No matched stream")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Play a live sports broadcast, pin a game to this tab, or switch back to all leagues.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button("Pin game") {
                    isPinEmptyStatePopoverPresented = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(AppleTheme.accent, in: Capsule(style: .continuous))
                .disabled(isFrozen || snapshot.games.isEmpty)
                .popover(isPresented: $isPinEmptyStatePopoverPresented, arrowEdge: .leading) {
                    drawerPinPopover
                }

                Button("Show All") {
                    controller.toggleLivePulseStreamFocus()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppleTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(AppleTheme.accent.opacity(0.14), in: Capsule(style: .continuous))
                .disabled(isFrozen)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var drawerPinPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pin Game to Active Stream")
                .font(.system(size: 12, weight: .semibold))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(snapshot.games.prefix(12)) { game in
                        Button {
                            pinGameToActiveTab(game)
                            isPinEmptyStatePopoverPresented = false
                        } label: {
                            HStack(spacing: 6) {
                                Text(game.league.displayName)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .leading)
                                Text("\(game.away.abbreviation) \(game.away.score) – \(game.home.score) \(game.home.abbreviation)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                                Spacer()
                                Text(game.clock ?? game.statusDetail)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppleTheme.accent.opacity(0.85))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SettingsLink {
                Text("Open Live Pulse Settings")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppleTheme.accent, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isFrozen)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
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
    @State private var washColor: Color = .green

    private var isBench: Bool { !player.isStarter }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                slotBadge

                Text(player.name)
                    .font(.system(
                        size: isBench ? 11 : 11.5,
                        weight: isBench ? .medium : (player.isActiveInStream ? .semibold : .medium)
                    ))
                    .foregroundStyle(isBench ? Color.primary.opacity(0.76) : .primary)
                    .lineLimit(1)

                Text(isBench ? "\(player.position) · \(player.nflOrProTeam)" : player.nflOrProTeam)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showOpponentBadge && !player.isUserRoster {
                    Text("OPP")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
                }

                if player.isRedZone {
                    redZoneBadge
                }

                Spacer(minLength: 4)

                if let delta = player.lastDeltaPoints, abs(delta) >= 0.05 {
                    let isPositive = delta >= 0
                    Text(String(format: "%@%.1f", isPositive ? "+" : "", delta))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(
                            isBench
                                ? (isPositive ? Color.green.opacity(0.72) : AppleTheme.accent.opacity(0.78))
                                : (isPositive ? .green : AppleTheme.accent)
                        )
                }

                Text(String(format: "%.1f", player.points))
                    .font(.system(
                        size: isBench ? 11 : 11.5,
                        weight: isBench ? .medium : .semibold,
                        design: .rounded
                    ).monospacedDigit())
                    .foregroundStyle(isBench ? .secondary : .primary)
                    .liveNumericTransition(enabled: animationsEnabled, value: player.points)
            }

            if let statLine = player.liveStatLine, !statLine.isEmpty {
                Text(statLine)
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(isBench ? Color.secondary.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(surfaceFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(washColor.opacity(highlightWashOpacity))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 17)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.75)
                )
        } else {
            Text(player.position)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(player.isActiveInStream ? AppleTheme.accent : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 28, height: 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(player.isActiveInStream ? AppleTheme.accent.opacity(0.14) : Color.primary.opacity(0.07))
                )
        }
    }

    @ViewBuilder
    private var redZoneBadge: some View {
        if isBench {
            Text("RZ")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(AppleTheme.accent)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppleTheme.accent.opacity(0.45), lineWidth: 0.75)
                )
        } else {
            Text("RZ")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1)
                .background(AppleTheme.accent, in: Capsule(style: .continuous))
        }
    }

    private var surfaceFillColor: Color {
        if isBench {
            return player.isActiveInStream ? AppleTheme.accent.opacity(0.05) : Color.primary.opacity(0.015)
        }
        if player.isActiveInStream {
            return AppleTheme.accent.opacity(isResolvedDark ? 0.13 : 0.09)
        }
        return Color.primary.opacity(isResolvedDark ? 0.045 : 0.035)
    }

    private var surfaceStrokeColor: Color {
        guard isBench else { return .clear }
        return player.isActiveInStream ? AppleTheme.accent.opacity(0.20) : Color.primary.opacity(0.09)
    }

    private func triggerOneShotWash(isPositive: Bool) {
        guard animationsEnabled else { return }
        washColor = isPositive ? .green : AppleTheme.accent
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
