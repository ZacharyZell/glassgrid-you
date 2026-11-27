import SwiftUI
import YouTubeMacCore

/// Native macOS Settings tab for opt-in Live Pulse live sports scoreboards, Sleeper & ESPN Public
/// fantasy matchups, spoiler-delay buffering, and strictly read-only Kalshi/Polymarket feeds.
struct LivePulseSettingsTabView: View {
    @Bindable var coordinator: AppCoordinator

    @State private var sleeperUsernameDraft: String = ""
    @State private var espnLeagueSelection: SportsLeague = .nfl
    @State private var espnLeagueIDDraft: String = ""
    @State private var espnSeasonDraft: String = ""
    @State private var espnOwnerHintDraft: String = ""
    @State private var isLookingUpSleeper: Bool = false

    private var store: LivePulseStore {
        coordinator.livePulseStore
    }

    var body: some View {
        @Bindable var settings = coordinator.settings

        Form {
            Section("Live Pulse Surfaces") {
                Toggle("Enable Live Pulse (Opt-In)", isOn: $settings.livePulseEnabled)
                    .onChange(of: settings.livePulseEnabled) { _, isEnabled in
                        if isEnabled && !settings.livePulseShowTicker && !settings.livePulseShowDrawer {
                            settings.livePulseShowTicker = true
                            settings.livePulseShowDrawer = true
                        }
                    }
                Text("Off by default. When disabled, zero background requests, caches, or WebSockets run.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Toggle("Show Live Pulse Ticker Bar (⌘⌥B)", isOn: $settings.livePulseShowTicker)
                    .disabled(!settings.livePulseEnabled)

                Toggle("Show Live Companion Drawer (⌘⌥I)", isOn: $settings.livePulseShowDrawer)
                    .disabled(!settings.livePulseEnabled)

                Toggle("Pin Live Score in macOS Menu Bar", isOn: $settings.livePulseMenuBarPin)
                    .disabled(!settings.livePulseEnabled)
                Text("Shows your pinned game's spoiler-delayed score beside the GlassGrid You menu bar icon.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Toggle("Spoiler-Delayed Fantasy Scoring Flashes", isOn: $settings.livePulseScoringFlashes)
                    .disabled(!settings.livePulseEnabled)
                Text("Briefly highlights scoring plays and fantasy roster point spikes after your configured spoiler delay.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Picker("Spoiler Delay Buffer", selection: $settings.livePulseSpoilerDelay) {
                    ForEach(SpoilerDelayOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .disabled(!settings.livePulseEnabled)
            }

            Section("Primary Leagues") {
                ForEach(SportsLeague.primaryLeagues) { league in
                    leagueToggleRow(league: league, settings: settings)
                }
            }

            Section("Secondary Leagues (College, Soccer & F1)") {
                let secondaryLeagues = SportsLeague.allCases.filter { !SportsLeague.primaryLeagues.contains($0) }
                ForEach(secondaryLeagues) { league in
                    leagueToggleRow(league: league, settings: settings)
                }
                Text("Disabled by default to keep background scoreboard polling minimal. Enable only the leagues you follow.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }

            Section("Sport Priority & Stream Focus") {
                let enabledPriorityLeagues = settings.orderedEnabledLivePulseLeagues
                if enabledPriorityLeagues.isEmpty {
                    Text("Enable at least one league above to configure sport priority.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                } else {
                    ForEach(Array(enabledPriorityLeagues.enumerated()), id: \.element) { index, league in
                        HStack(spacing: AppSpacing.md) {
                            Text("#\(index + 1)")
                                .font(AppFont.micro(weight: .bold, tabular: true))
                                .foregroundStyle(index == 0 ? AppleTheme.accentText : AppleTheme.textSecondary)
                                .frame(width: 24, height: 20)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(index == 0 ? AppleTheme.accentText.opacity(0.14) : Color.primary.opacity(0.06))
                                )

                            Image(systemName: league.symbolName)
                                .font(AppIconFont.md(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                                .frame(width: 16)

                            Text(league.displayName)
                                .font(AppFont.body(weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(Color.primary)

                            Spacer()

                            HStack(spacing: AppSpacing.xxs) {
                                Button {
                                    moveEnabledLeague(league, direction: -1, in: enabledPriorityLeagues, settings: settings)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(AppIconFont.xs(weight: .semibold))
                                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .accessibilityLabel("Move \(league.displayName) up in priority")
                                .help("Move \(league.displayName) up")

                                Button {
                                    moveEnabledLeague(league, direction: 1, in: enabledPriorityLeagues, settings: settings)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(AppIconFont.xs(weight: .semibold))
                                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == enabledPriorityLeagues.count - 1)
                                .accessibilityLabel("Move \(league.displayName) down in priority")
                                .help("Move \(league.displayName) down")
                            }
                        }
                    }
                }

                Text("Smart Priority ranks your watched stream first, then orders live scores, fantasy players, and markets by priority.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Toggle("Watched Stream Focus Only", isOn: $settings.livePulseStreamFocusOnly)
                    .disabled(!settings.livePulseEnabled)

                Text("When enabled, hides scores, players, and markets outside your active or pinned stream(s).")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Toggle("Show Kalshi & Polymarket Probabilities (Read-Only)", isOn: $settings.livePulseShowMarkets)
            }

            Section("Sleeper Fantasy Lookup") {
                HStack(spacing: AppSpacing.md) {
                    TextField("Sleeper @username", text: $sleeperUsernameDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            triggerSleeperLookup()
                        }

                    Button(isLookingUpSleeper ? "Searching…" : "Find Leagues") {
                        triggerSleeperLookup()
                    }
                    .disabled(!settings.livePulseEnabled || isLookingUpSleeper || sleeperUsernameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let status = store.sleeperLookupStatus {
                    Text(status)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }

                if !store.discoveredSleeperLeagues.isEmpty {
                    ForEach(store.discoveredSleeperLeagues) { league in
                        let isAdded = settings.livePulseFantasyLeagues.contains(where: { $0.id == league.id })
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(league.leagueName)
                                    .font(AppFont.body)
                                Text("\(league.league.displayName) · Season \(String(league.season))")
                                    .font(AppFont.caption(tabular: true))
                                    .foregroundStyle(AppleTheme.textSecondary)
                            }
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { isAdded },
                                    set: { shouldInclude in
                                        if shouldInclude {
                                            store.addFantasyLeague(league)
                                        } else {
                                            store.removeFantasyLeague(id: league.id)
                                        }
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("24h Sleeper Player Directory Cache")
                            .font(AppFont.body)
                        Text(sleeperCacheCaption)
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Clear Sleeper Cache") {
                        Task {
                            await store.clearSleeperCache()
                        }
                    }
                }
            }

            Section("ESPN Public Fantasy League") {
                Picker("League", selection: $espnLeagueSelection) {
                    ForEach(SportsLeague.primaryLeagues) { league in
                        Text(league.displayName).tag(league)
                    }
                }

                HStack(spacing: AppSpacing.md) {
                    TextField("League ID (e.g. 123456)", text: $espnLeagueIDDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Season", text: $espnSeasonDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                }

                HStack(spacing: AppSpacing.md) {
                    TextField("Optional Team / Owner Hint", text: $espnOwnerHintDraft)
                        .textFieldStyle(.roundedBorder)

                    Button("Add ESPN League") {
                        let year = Int(espnSeasonDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            ?? Calendar.current.component(.year, from: Date())
                        store.addESPNPublicLeague(
                            league: espnLeagueSelection,
                            leagueID: espnLeagueIDDraft,
                            season: year,
                            teamOwnerHint: espnOwnerHintDraft
                        )
                        espnLeagueIDDraft = ""
                        espnOwnerHintDraft = ""
                    }
                    .disabled(espnLeagueIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("Public ESPN leagues sync directly; private leagues can be opened 1-click inside a Multiview Companion Tile.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }

            if !settings.livePulseFantasyLeagues.isEmpty {
                Section("Configured Fantasy Leagues") {
                    ForEach(settings.livePulseFantasyLeagues) { config in
                        HStack(spacing: AppSpacing.md) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { config.isEnabled },
                                    set: { nextEnabled in
                                        let updated = FantasyLeagueConfig(
                                            id: config.id,
                                            provider: config.provider,
                                            league: config.league,
                                            leagueID: config.leagueID,
                                            leagueName: config.leagueName,
                                            season: config.season,
                                            teamOwnerHint: config.teamOwnerHint,
                                            isEnabled: nextEnabled
                                        )
                                        store.addFantasyLeague(updated)
                                    }
                                )
                            )
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 1) {
                                Text(config.leagueName)
                                    .font(AppFont.body)
                                Text("\(config.provider.displayName) · \(config.league.displayName) · \(String(config.season))")
                                    .font(AppFont.caption(tabular: true))
                                    .foregroundStyle(AppleTheme.textSecondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                store.removeFantasyLeague(id: config.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(AppIconFont.md)
                                    .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(config.leagueName)")
                        }
                    }
                }
            }

            Section("Privacy & Compliance") {
                Text("All Live Pulse requests use ephemeral, cookieless URLSession sessions and never access WebKit or browser cookies. Prediction market feeds from Kalshi and Polymarket are strictly read-only and informational — GlassGrid You provides zero wagering, order routing, trading, or wallet signing.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, AppSpacing.xs)
        .onAppear {
            if sleeperUsernameDraft.isEmpty {
                sleeperUsernameDraft = coordinator.settings.livePulseSleeperUsername
            }
            if espnSeasonDraft.isEmpty {
                espnSeasonDraft = String(Calendar.current.component(.year, from: Date()))
            }
        }
    }

    @ViewBuilder
    private func leagueToggleRow(league: SportsLeague, settings: AppSettings) -> some View {
        let isLeagueEnabled = settings.livePulseEnabledLeagues.contains(league)
        HStack(spacing: AppSpacing.md) {
            Image(systemName: league.symbolName)
                .font(AppIconFont.md(weight: .semibold))
                .foregroundStyle(isLeagueEnabled ? AppleTheme.accentText : AppleTheme.textSecondary)
                .frame(width: 18)

            Toggle(
                league.displayName,
                isOn: Binding(
                    get: { settings.livePulseEnabledLeagues.contains(league) },
                    set: { enabled in
                        var updated = settings.livePulseEnabledLeagues
                        if enabled {
                            if !updated.contains(league) {
                                updated.append(league)
                            }
                        } else {
                            updated.removeAll { $0 == league }
                        }
                        settings.livePulseEnabledLeagues = updated
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(AppFont.body(weight: isLeagueEnabled ? .medium : .regular))
        }
    }

    private func moveEnabledLeague(
        _ league: SportsLeague,
        direction: Int,
        in enabledOrdered: [SportsLeague],
        settings: AppSettings
    ) {
        guard let currentEnabledIdx = enabledOrdered.firstIndex(of: league) else { return }
        let targetEnabledIdx = currentEnabledIdx + direction
        guard targetEnabledIdx >= 0 && targetEnabledIdx < enabledOrdered.count else { return }
        let neighbor = enabledOrdered[targetEnabledIdx]

        var full = SportsLeague.normalizedPriority(settings.livePulseLeaguePriority)
        guard let fromFullIdx = full.firstIndex(of: league),
              let neighborFullIdx = full.firstIndex(of: neighbor) else { return }
        full.swapAt(fromFullIdx, neighborFullIdx)
        settings.livePulseLeaguePriority = full
    }

    private var sleeperCacheCaption: String {
        if let updated = store.sleeperCacheLastUpdated {
            let formatted = updated.formatted(date: .abbreviated, time: .shortened)
            return "Cached locally · Updated \(formatted)"
        }
        return "Refreshes at most once every 24 hours on demand."
    }

    private func triggerSleeperLookup() {
        let username = sleeperUsernameDraft
        isLookingUpSleeper = true
        Task {
            await store.lookupSleeperUsername(username)
            isLookingUpSleeper = false
        }
    }
}
