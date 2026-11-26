import SwiftUI
import YouTubeMacCore

/// Native macOS Preferences window organized per Apple HIG: General, Playback, Distraction-Free, and Account & Data.
struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var showClearDataConfirm = false
    @State private var servicePendingReset: StreamingService?
    @State private var statusMessage: String?
    @State private var statusClearTask: Task<Void, Never>?

    private static let speedPresets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            playbackTab
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }

            distractionFreeTab
                .tabItem {
                    Label("Distraction-Free", systemImage: "eye.slash")
                }

            accountTab
                .tabItem {
                    Label("Account & Data", systemImage: "person.crop.circle")
                }

            AgentSettingsTabView(coordinator: coordinator)
                .tabItem {
                    Label("AI & Automation", systemImage: "sparkles")
                }

            LivePulseSettingsTabView(coordinator: coordinator)
                .tabItem {
                    Label("Live Pulse", systemImage: "sportscourt")
                }
        }
        .frame(width: 660, height: 560)
        .alert("Sign Out & Clear All Site Data?", isPresented: $showClearDataConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                Task {
                    await coordinator.clearAllWebsiteData()
                    showTransientStatus("Cleared cookies, cache, and signed-out all windows.")
                }
            }
        } message: {
            Text("This removes YouTube and Google cookies and signs you out of your account in this app.")
        }
        .confirmationDialog(
            "Reset \(servicePendingReset?.name ?? "Service") Login & Site Data?",
            isPresented: Binding(
                get: { servicePendingReset != nil },
                set: { if !$0 { servicePendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let service = servicePendingReset {
                Button("Reset \(service.name) Login & Data", role: .destructive) {
                    servicePendingReset = nil
                    Task {
                        await coordinator.resetServiceData(for: service)
                        showTransientStatus("Reset login & site data for \(service.name).")
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                servicePendingReset = nil
            }
        } message: {
            if let service = servicePendingReset {
                if let ssoNote = StreamingServiceCatalog.sharedSSOWarning(for: service) {
                    Text("Clears cookies and site storage for \(service.name) only. \(ssoNote)")
                } else {
                    Text("Clears cookies and site storage for \(service.name) only without signing out of your other services.")
                }
            }
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        @Bindable var settings = coordinator.settings
        @Bindable var updater = coordinator.updater

        Form {
            Section("Startup & Appearance") {
                Toggle("Restore open tabs on launch", isOn: $settings.restoreTabsOnLaunch)

                Picker("Open on launch", selection: $settings.startupDestination) {
                    ForEach(StartupDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }

                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Picker("Holiday Theme", selection: $settings.holidayThemeSelection) {
                        ForEach(HolidayThemeSelection.allCases) { selection in
                            Text(selection.title).tag(selection)
                        }
                    }

                    if settings.holidayThemeSelection == .auto {
                        let autoCaption = settings.calendarHolidayThemeID == .classic
                            ? "Following seasonal calendar (Classic Crimson today)"
                            : "Currently active for today: \(settings.activeHolidayPalette.displayName)"
                        Text(autoCaption)
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Picker("Holiday Effects", selection: $settings.holidayEffectsIntensity) {
                        ForEach(HolidayEffectsIntensity.allCases) { intensity in
                            Text(intensity.title).tag(intensity)
                        }
                    }

                    Text("Subtle Core Animation chrome effects pause automatically in Fullscreen, Focus Mode, and Reduce Motion.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }

            Section("Streaming Services") {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Streaming Services & Sign-In Hub")
                        Text("\(coordinator.settings.enabledStreamingServices.count) enabled · Appears in Sidebar & \"Add Screen\" picker.")
                            .font(AppFont.caption(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Manage Services…") {
                        coordinator.commandTarget?.openStreamingServicesSetup(step: 1)
                    }
                    .disabled(coordinator.commandTarget == nil)
                }
            }

            Section("Mini-Player & Window") {
                Toggle("Auto pop-out Mini-Player or Multiview Grid when leaving or covered by another app", isOn: $settings.autoMiniPlayerOnLeave)
                Toggle("Keep Mini-Player visible across all Spaces", isOn: $settings.miniPlayerAllSpaces)
            }

            Section("Home, Tabs & Menu Bar") {
                Toggle("Show Home Shelf (Continue Watching, Subscriptions & Suggested)", isOn: $settings.showHomeShelf)
                Toggle("Show live YouTube search suggestions in Command Palette (⌘K)", isOn: $settings.searchAutocompleteEnabled)
                Toggle("Open non-YouTube links in default browser", isOn: $settings.openExternalLinksInBrowser)
                Toggle("Compact single-row header (⌘⌥\\)", isOn: $settings.compactHeaderMode)
                Toggle("Always show tab bar", isOn: $settings.alwaysShowTabBar)
                Toggle("Show menu bar quick-controls", isOn: $settings.showMenuBarControls)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)

                HStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("GlassGrid You v\(updater.currentAppVersion)")
                            .font(AppFont.body(tabular: true))
                        Text(updateStatusCaption)
                            .font(AppFont.caption(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    if !updater.isSparkleConfigured,
                       case .updateAvailable(_, let latest) = updater.lastUpdateCheckResult {
                        Button("Download \(latest.tagName)") {
                            updater.openTrustedGitHubURL(latest.preferredDownloadURL)
                        }
                    }
                    Button(updater.isCheckingForUpdates ? "Checking…" : "Check Now…") {
                        updater.checkForUpdates(presentAlert: updater.isSparkleConfigured)
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var playbackTab: some View {
        @Bindable var settings = coordinator.settings

        Form {
            Section("Video Quality & Speed") {
                Picker("Preferred video quality", selection: $settings.preferredQuality) {
                    ForEach(PreferredVideoQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }

                Picker("Default playback speed", selection: $settings.defaultPlaybackRate) {
                    ForEach(Self.speedPresets, id: \.self) { rate in
                        Text(MediaStatus.formatPlaybackRate(rate)).tag(rate)
                    }
                }

                Picker("Multiview quality ceiling", selection: $settings.multiviewQualityCeiling) {
                    ForEach(MultiviewQualityCeiling.allCases) { ceiling in
                        Text(ceiling.title).tag(ceiling)
                    }
                }
            }

            Section("Player & Audio") {
                Toggle("Default to Theater mode on watch pages", isOn: $settings.autoTheaterMode)
                Toggle("Disable Ambient Mode glow (lower GPU & battery use)", isOn: $settings.disableAmbientMode)
                Toggle("Auto-dismiss \"Video paused. Continue watching?\" prompt", isOn: $settings.autoDismissContinueWatching)
                Toggle("Prefer original audio track (avoid auto-dubbed audio)", isOn: $settings.preferOriginalAudio)
                Toggle("Auto-pause on screen lock, sleep, or audio disconnect", isOn: $settings.autoPauseOnSystemEvents)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("Duck background Multiview audio to 15% (instead of mute)", isOn: $settings.multiviewAudioDuckingEnabled)
                    Text("Opt-in: keeps non-focused Multiview streams softly audible at 15% volume and restores 100% on focus or exit.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }

            Section("Segments") {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Toggle("Auto-skip sponsored segments (SponsorBlock)", isOn: $settings.sponsorBlockEnabled)
                    Text("Opt-in: queries sponsor.ajay.app using a privacy-preserving 4-character SHA-256 video ID prefix and fails silently offline.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var distractionFreeTab: some View {
        @Bindable var settings = coordinator.settings

        Form {
            Section("Shorts & Feed") {
                Toggle("Hide YouTube Shorts across feeds & sidebar", isOn: $settings.hideShorts)
                Toggle("Open Shorts links in standard video player", isOn: $settings.redirectShortsToWatch)
                Toggle("Hide Home feed (search & subscriptions only)", isOn: $settings.hideHomeFeed)
            }

            Section("Web Chrome & End-Screens") {
                Toggle("Clean web chrome (hide web sidebar, logo & promos)", isOn: $settings.cleanWebChrome)
                Toggle("Hide YouTube top web header", isOn: $settings.hideWebHeader)
                Toggle("Hide video end-screen cards & teasers", isOn: $settings.hideEndScreens)
            }

            Section("Watch Page Distractions") {
                Toggle("Clean-Box streaming service players (remove site chrome during playback)", isOn: $settings.cleanBoxStreamingPlayers)
                Toggle("Hide right-side recommendations", isOn: $settings.hideWatchRecommendations)
                Toggle("Hide video comments", isOn: $settings.hideComments)
                Text("Promotes the native video player edge-to-edge on streaming services once playback starts. Browse pages stay untouched; press ⌘⇧B anytime for Full Page.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var accountTab: some View {
        Form {
            Section("Google Account") {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("YouTube Sign-In")
                            .font(AppFont.body)
                        Text("Cookies are stored securely in WebKit's persistent data store.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Sign In…") {
                        coordinator.openSignIn()
                    }
                }

                HStack {
                    Text("Manage Google Account")
                    Spacer()
                    Button("Open Account") {
                        coordinator.openGoogleAccount()
                    }
                }
            }

            Section("Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Streaming Service Sign-In Hub")
                        Text("Sign in or reset cookies for an individual service without affecting others.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Sign-In Hub…") {
                        coordinator.commandTarget?.openStreamingServicesSetup(step: 2)
                    }
                    .disabled(coordinator.commandTarget == nil)

                    Menu("Reset Login…") {
                        ForEach(coordinator.settings.enabledStreamingServices) { service in
                            Button("Reset \(service.name)…") {
                                servicePendingReset = service
                            }
                        }
                    }
                    .fixedSize()
                }

                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Clear Local History & Presets")
                        Text("Clears Continue Watching, Most Watched Channels & saved Multiview presets without signing you out.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Clear History") {
                        coordinator.clearLocalHistory()
                        showTransientStatus("Cleared local history & Multiview presets.")
                    }
                    .disabled(
                        coordinator.settings.continueWatching.isEmpty
                            && coordinator.settings.watchedChannels.isEmpty
                            && coordinator.settings.savedMultiviewPresets.isEmpty
                    )
                }

                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Clear Web Cache")
                        Text("Frees cached assets while keeping your Google login intact.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Clear Cache") {
                        Task {
                            await coordinator.clearWebCache()
                            showTransientStatus("Web cache cleared.")
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Sign Out & Reset Data")
                        Text("Removes all cookies, local storage, and cached media.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Clear All Data…", role: .destructive) {
                        showClearDataConfirm = true
                    }
                    .disabled(coordinator.isSigningOutData)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }

            Section("Open Source") {
                HStack(alignment: .center, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("MIT Licensed — zero paywalls, telemetry, or nags.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                        Text("Typography: Inter v4.1 (SIL Open Font License 1.1) · Updates powered by Sparkle 2.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textMuted)
                    }
                    Spacer()
                    Button("Support on GitHub") {
                        coordinator.updater.openTrustedGitHubURL(UpdateChecker.sponsorsURL)
                    }
                    .buttonStyle(.link)
                    .font(AppFont.caption(weight: .medium))
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, AppSpacing.xs)
    }

    private var updateStatusCaption: String {
        let updater = coordinator.updater
        if updater.isSparkleConfigured {
            return "Signed Sparkle 2 updates enabled."
        }
        if updater.isCheckingForUpdates {
            return "Checking GitHub Releases…"
        }
        switch updater.lastUpdateCheckResult {
        case .none:
            return "Source build — checks GitHub Releases on demand."
        case .upToDate(let current):
            return "Up to date (v\(current))."
        case .updateAvailable(_, let latest):
            return "Update available: \(latest.tagName)."
        case .noReleasesPublished:
            return "No GitHub Releases published yet."
        case .failed(let reason):
            return reason
        }
    }

    private func showTransientStatus(_ message: String) {
        statusClearTask?.cancel()
        statusMessage = message
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }
}
