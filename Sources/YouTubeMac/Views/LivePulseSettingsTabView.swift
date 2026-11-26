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
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Live Pulse Ticker Bar (⌘⌥B)", isOn: $settings.livePulseShowTicker)
                    .disabled(!settings.livePulseEnabled)

                Toggle("Show Live Companion Drawer (⌘⌥I)", isOn: $settings.livePulseShowDrawer)
                    .disabled(!settings.livePulseEnabled)

                Picker("Spoiler Delay Buffer", selection: $settings.livePulseSpoilerDelay) {
                    ForEach(SpoilerDelayOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .disabled(!settings.livePulseEnabled)
            }

            Section("Sport Priority & Leagues") {
                let orderedLeagues = settings.livePulseLeaguePriority
                ForEach(Array(orderedLeagues.enumerated()), id: \.element) { index, league in
                    let isLeagueEnabled = settings.livePulseEnabledLeagues.contains(league)
                    HStack(spacing: 10) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(index == 0 ? AppleTheme.accent : .secondary)
                            .frame(width: 24, height: 20)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(index == 0 ? AppleTheme.accent.opacity(0.14) : Color.primary.opacity(0.06))
                            )

                        Image(systemName: league.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isLeagueEnabled ? AppleTheme.accent : .secondary)
                            .frame(width: 16)

                        Text(league.displayName)
                            .font(.body.weight(index == 0 ? .semibold : .regular))
                            .foregroundStyle(isLeagueEnabled ? .primary : .secondary)

                        Spacer()

                        HStack(spacing: 2) {
                            Button {
                                settings.moveLivePulseLeague(league, direction: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(league.displayName) up in priority")
                            .help("Move \(league.displayName) up")

                            Button {
                                settings.moveLivePulseLeague(league, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == orderedLeagues.count - 1)
                            .accessibilityLabel("Move \(league.displayName) down in priority")
                            .help("Move \(league.displayName) down")
                        }

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
                        .labelsHidden()
                    }
                }

                Text("Smart Priority ranks your watched stream first, then orders live scores, fantasy players, and markets by #1–#4 Sport Priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Watched Stream Focus Only", isOn: $settings.livePulseStreamFocusOnly)
                    .disabled(!settings.livePulseEnabled)

                Text("When enabled, hides scores, players, and markets outside your active or pinned stream(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Kalshi & Polymarket Probabilities (Read-Only)", isOn: $settings.livePulseShowMarkets)
            }

            Section("Sleeper Fantasy Lookup") {
                HStack(spacing: 8) {
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.discoveredSleeperLeagues.isEmpty {
                    ForEach(store.discoveredSleeperLeagues) { league in
                        let isAdded = settings.livePulseFantasyLeagues.contains(where: { $0.id == league.id })
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(league.leagueName)
                                    .font(.body)
                                Text("\(league.league.displayName) · Season \(String(league.season))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("24h Sleeper Player Directory Cache")
                        Text(sleeperCacheCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    ForEach(SportsLeague.allCases) { league in
                        Text(league.displayName).tag(league)
                    }
                }

                HStack(spacing: 8) {
                    TextField("League ID (e.g. 123456)", text: $espnLeagueIDDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Season", text: $espnSeasonDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                }

                HStack(spacing: 8) {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !settings.livePulseFantasyLeagues.isEmpty {
                Section("Configured Fantasy Leagues") {
                    ForEach(settings.livePulseFantasyLeagues) { config in
                        HStack(spacing: 8) {
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
                                    .font(.body)
                                Text("\(config.provider.displayName) · \(config.league.displayName) · \(String(config.season))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                store.removeFantasyLeague(id: config.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(config.leagueName)")
                        }
                    }
                }
            }

            Section("Privacy & Compliance") {
                Text("All Live Pulse requests use ephemeral, cookieless URLSession sessions and never access WebKit or browser cookies. Prediction market feeds from Kalshi and Polymarket are strictly read-only and informational — GlassGrid You provides zero wagering, order routing, trading, or wallet signing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
        .onAppear {
            if sleeperUsernameDraft.isEmpty {
                sleeperUsernameDraft = coordinator.settings.livePulseSleeperUsername
            }
            if espnSeasonDraft.isEmpty {
                espnSeasonDraft = String(Calendar.current.component(.year, from: Date()))
            }
        }
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
