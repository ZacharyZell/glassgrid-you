import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

@MainActor
private final class LocalHotKeyMonitor {
    nonisolated(unsafe) private var monitor: Any?

    deinit {
        removeMonitor()
    }

    func start(handler: @escaping @MainActor (UInt16, NSEvent.ModifierFlags) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let consumed = MainActor.assumeIsolated {
                handler(keyCode, flags)
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        removeMonitor()
    }

    nonisolated private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct GlobalHotKeyRecorderRow: View {
    let action: GlobalHotKeyAction
    let binding: GlobalHotKeyBinding
    let isCustom: Bool
    let isRecording: Bool
    let isGlobalEnabled: Bool
    let errorMessage: String?
    let onToggleRecording: () -> Void
    let onResetSingle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(AppFont.body)
                    if isCustom {
                        Text("Default: \(action.shortcutDisplay)")
                            .font(AppFont.micro(tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                }

                Spacer()

                if isCustom && !isRecording {
                    Button {
                        onResetSingle()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(AppIconFont.xs(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset \(action.title) to \(action.shortcutDisplay)")
                    .accessibilityLabel("Reset \(action.title) Shortcut")
                }

                Button(action: onToggleRecording) {
                    Text(isRecording ? "Press Shortcut…" : binding.displayString)
                        .font(AppFont.caption(weight: .semibold, tabular: true))
                        .foregroundStyle(
                            isRecording
                                ? Color.white
                                : (isGlobalEnabled ? AppleTheme.accentText : AppleTheme.textSecondary)
                        )
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xxs)
                        .frame(minWidth: 88)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isRecording ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isRecording ? AppleTheme.accentFill : Color.primary.opacity(isCustom ? 0.18 : 0.08),
                                    lineWidth: 0.75
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Press new modifier + key (Esc to cancel, Delete to reset)" : "Click to record a new global shortcut")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.warning)
            }
        }
    }
}

/// Native macOS Preferences window organized per Apple HIG: General, Playback, Distraction-Free, and Account & Data.
struct SettingsView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var showClearDataConfirm = false
    @State private var servicePendingReset: StreamingService?
    @State private var statusMessage: String?
    @State private var statusClearTask: Task<Void, Never>?
    @State private var newBlockedChannel = ""
    @State private var newBlockedKeyword = ""
    @State private var recordingHotKeyAction: GlobalHotKeyAction?
    @State private var hotKeyErrorByAction: [GlobalHotKeyAction: String] = [:]
    @State private var hotKeyMonitor = LocalHotKeyMonitor()

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

            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
        }
        .frame(width: 660, height: 580)
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
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("Peek-Away Auto-Fade on Mini-Player hover", isOn: $settings.miniPlayerPeekAwayEnabled)
                    Text("Fades the Mini-Player body to click-through on hover; move onto the top drag bar or hold ⌥ to keep it opaque.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("Show Notch Media HUD pill around MacBook notch", isOn: $settings.notchMediaHUDEnabled)
                    Text("Opt-in: displays compact playback controls near the notch (or top edge on external displays), automatically hidden in fullscreen.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
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
                    Toggle("Auto-pause other single-view tabs when playback starts", isOn: $settings.singleViewAutoPauseEnabled)
                    Text("Opt-in: pauses other single-view tabs when starting playback (Multiview grids are never interrupted).")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("Duck background Multiview audio to 15% (instead of mute)", isOn: $settings.multiviewAudioDuckingEnabled)
                    Text("Opt-in: keeps non-focused Multiview streams softly audible at 15% volume and restores 100% on focus or exit.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }

            Section("Segments") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Toggle("Auto-skip sponsored segments (SponsorBlock)", isOn: $settings.sponsorBlockEnabled)
                    Text("Opt-in: queries sponsor.ajay.app using a privacy-preserving 4-character SHA-256 video ID prefix and fails silently offline.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Categories to skip")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                            alignment: .leading,
                            spacing: AppSpacing.xs
                        ) {
                            ForEach(SponsorSegmentCategory.allCases) { category in
                                Toggle(
                                    category.shortLabel,
                                    isOn: Binding(
                                        get: { settings.sponsorBlockCategories.contains(category.rawValue) },
                                        set: { enabled in
                                            var updated = settings.sponsorBlockCategories
                                            if enabled {
                                                updated.insert(category.rawValue)
                                            } else {
                                                updated.remove(category.rawValue)
                                            }
                                            settings.sponsorBlockCategories = updated
                                        }
                                    )
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .disabled(!settings.sponsorBlockEnabled)
                    .opacity(settings.sponsorBlockEnabled ? 1.0 : 0.55)
                    .padding(.top, AppSpacing.xs)
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

            Section("Title & Content Filter") {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("DeArrow clickbait title removal", isOn: $settings.deArrowEnabled)
                    Text("Opt-in: replaces sensational video titles via sponsor.ajay.app/api/branding using a 4-character SHA-256 video ID prefix.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Toggle("Replace clickbait thumbnails with video frames (DeArrow)", isOn: $settings.deArrowThumbnailsEnabled)
                        .disabled(!settings.deArrowEnabled)
                        .opacity(settings.deArrowEnabled ? 1.0 : 0.55)
                    Text("Opt-in: fetches community-submitted video frames from dearrow-thumb.ajay.app (zero cookies) and falls back automatically when unavailable.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .opacity(settings.deArrowEnabled ? 1.0 : 0.55)
                }
                .padding(.leading, AppSpacing.lg)

                Toggle("Enable Content Filter (hide matching channels & keywords)", isOn: $settings.contentFilterConfig.isEnabled)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Blocked Channels")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)

                    HStack(spacing: AppSpacing.sm) {
                        TextField("Channel name…", text: $newBlockedChannel)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addBlockedChannel() }
                        Button("Add") { addBlockedChannel() }
                            .disabled(newBlockedChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !settings.contentFilterConfig.blockedChannels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(settings.contentFilterConfig.blockedChannels, id: \.self) { channel in
                                    Button {
                                        settings.contentFilterConfig.blockedChannels.removeAll { $0 == channel }
                                    } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            Text(channel)
                                                .font(AppFont.caption(weight: .medium))
                                            Image(systemName: "xmark")
                                                .font(AppIconFont.xs(weight: .bold))
                                        }
                                        .padding(.horizontal, AppSpacing.md)
                                        .minHitTarget(24, shape: Capsule(style: .continuous))
                                        .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove \(channel)")
                                }
                            }
                        }
                    }

                    Text("Blocked Keywords")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.top, AppSpacing.xs)

                    HStack(spacing: AppSpacing.sm) {
                        TextField("Keyword or spoiler phrase…", text: $newBlockedKeyword)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addBlockedKeyword() }
                        Button("Add") { addBlockedKeyword() }
                            .disabled(newBlockedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !settings.contentFilterConfig.blockedKeywords.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.xs) {
                                ForEach(settings.contentFilterConfig.blockedKeywords, id: \.self) { keyword in
                                    Button {
                                        settings.contentFilterConfig.blockedKeywords.removeAll { $0 == keyword }
                                    } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            Text(keyword)
                                                .font(AppFont.caption(weight: .medium))
                                            Image(systemName: "xmark")
                                                .font(AppIconFont.xs(weight: .bold))
                                        }
                                        .padding(.horizontal, AppSpacing.md)
                                        .minHitTarget(24, shape: Capsule(style: .continuous))
                                        .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove \(keyword)")
                                }
                            }
                        }
                    }
                }
                .disabled(!settings.contentFilterConfig.isEnabled)
                .opacity(settings.contentFilterConfig.isEnabled ? 1.0 : 0.55)
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
                        Text("Multiview Presets Backup")
                        Text("Export or import saved Multiview layouts as portable .json files.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    Spacer()
                    Button("Export Presets (.json)…") {
                        exportMultiviewPresetsFromPanel()
                    }
                    .disabled(coordinator.settings.savedMultiviewPresets.isEmpty)
                    Button("Import Presets (.json)…") {
                        importMultiviewPresetsFromPanel()
                    }
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

    @ViewBuilder
    private var shortcutsTab: some View {
        @Bindable var settings = coordinator.settings
        let hasCustomHotKeys = GlobalHotKeyAction.allCases.contains { settings.isCustomGlobalHotKeyBinding($0) }

        Form {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Toggle("Enable Global Shortcuts across all macOS apps", isOn: $settings.globalHotkeysEnabled)
                    Text("Opt-in: registers Carbon global hotkeys cleanly without Accessibility permissions. Click any shortcut to record (Esc cancels, Delete resets to default).")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }

                ForEach(GlobalHotKeyAction.allCases) { action in
                    let binding = settings.effectiveGlobalHotKeyBinding(for: action)
                    GlobalHotKeyRecorderRow(
                        action: action,
                        binding: binding,
                        isCustom: settings.isCustomGlobalHotKeyBinding(action),
                        isRecording: recordingHotKeyAction == action,
                        isGlobalEnabled: settings.globalHotkeysEnabled,
                        errorMessage: hotKeyErrorByAction[action],
                        onToggleRecording: {
                            toggleHotKeyRecording(for: action)
                        },
                        onResetSingle: {
                            hotKeyErrorByAction.removeValue(forKey: action)
                            settings.setGlobalHotKeyBinding(nil, for: action)
                        }
                    )
                }
            } header: {
                HStack {
                    Text("System-Wide Global Shortcuts")
                    Spacer()
                    Button("Reset Defaults") {
                        stopHotKeyRecording()
                        hotKeyErrorByAction.removeAll()
                        settings.resetAllGlobalHotKeyBindings()
                    }
                    .buttonStyle(.link)
                    .font(AppFont.caption(weight: .medium))
                    .disabled(!hasCustomHotKeys)
                }
            }

            Section("In-App Shortcuts") {
                shortcutRow("Command Palette & Search", "⌘K")
                shortcutRow("Always on Top", "⌘⌥P")
                shortcutRow("Mini-Player / Float Grid", "⌘⇧M")
                shortcutRow("Mini-Player Ghost Mode", "⌘⌥O")
                shortcutRow("Bookmark Current Timestamp", "⌘⇧K")
                shortcutRow("Multiview Grid", "⌘⇧G")
                shortcutRow("Cycle Multiview Layout", "⌘⌥G")
                shortcutRow("Solo / Expand Tile", "⌘⌥Z")
                shortcutRow("Compact Single-Row Header", "⌘⌥\\")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, AppSpacing.xs)
        .onDisappear {
            stopHotKeyRecording()
        }
    }

    @ViewBuilder
    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body)
            Spacer()
            Text(keys)
                .font(AppFont.caption(weight: .semibold, tabular: true))
                .foregroundStyle(AppleTheme.textSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xxs)
                .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
        }
    }

    private func addBlockedChannel() {
        let trimmed = newBlockedChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !coordinator.settings.contentFilterConfig.blockedChannels.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            coordinator.settings.contentFilterConfig.blockedChannels.append(trimmed)
        }
        newBlockedChannel = ""
    }

    private func addBlockedKeyword() {
        let trimmed = newBlockedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !coordinator.settings.contentFilterConfig.blockedKeywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            coordinator.settings.contentFilterConfig.blockedKeywords.append(trimmed)
        }
        newBlockedKeyword = ""
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

    private func toggleHotKeyRecording(for action: GlobalHotKeyAction) {
        if recordingHotKeyAction == action {
            stopHotKeyRecording()
            return
        }
        hotKeyErrorByAction.removeValue(forKey: action)
        recordingHotKeyAction = action
        hotKeyMonitor.start { keyCode, modifierFlags in
            handleHotKeyMonitorEvent(keyCode: keyCode, modifierFlags: modifierFlags, for: action)
        }
    }

    private func stopHotKeyRecording() {
        hotKeyMonitor.stop()
        recordingHotKeyAction = nil
    }

    private func handleHotKeyMonitorEvent(
        keyCode rawKeyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        for action: GlobalHotKeyAction
    ) -> Bool {
        let keyCode = UInt32(rawKeyCode)
        // Escape (0x35) cancels recording cleanly without dismissing Preferences.
        if keyCode == 0x35 {
            hotKeyErrorByAction.removeValue(forKey: action)
            stopHotKeyRecording()
            return true
        }
        // Delete (0x33) or ForwardDelete (0x75) resets the action back to its default shortcut.
        if keyCode == 0x33 || keyCode == 0x75 {
            coordinator.settings.setGlobalHotKeyBinding(nil, for: action)
            hotKeyErrorByAction.removeValue(forKey: action)
            stopHotKeyRecording()
            return true
        }

        let carbonModifiers = GlobalHotKeyBinding.carbonModifiers(fromAppKitFlags: modifierFlags.rawValue)
        let binding = GlobalHotKeyBinding(keyCode: keyCode, carbonModifiers: carbonModifiers)
        guard binding.isValid else {
            hotKeyErrorByAction[action] = "Include ⌃, ⌥, or ⌘ with a supported key (Esc to cancel)."
            return true
        }

        if let conflictingAction = coordinator.settings.globalHotKeyConflict(for: binding, excluding: action) {
            hotKeyErrorByAction[action] = "Conflicts with \"\(conflictingAction.title)\" (\(binding.displayString))."
            return true
        }

        coordinator.settings.setGlobalHotKeyBinding(binding, for: action)
        hotKeyErrorByAction.removeValue(forKey: action)
        stopHotKeyRecording()
        return true
    }

    private func exportMultiviewPresetsFromPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "GlassGrid-Multiview-Presets.json"
        panel.title = "Export Multiview Presets"
        panel.message = "Save a portable JSON backup of your Multiview presets."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let controller = coordinator.commandTarget ?? coordinator.openWindows.first
        do {
            let data: Data
            if let controller {
                data = try controller.exportMultiviewPresetsData()
            } else {
                data = try MultiviewPresetTransferCodec.encode(coordinator.settings.savedMultiviewPresets)
            }
            try data.write(to: url, options: .atomic)
            let count = coordinator.settings.savedMultiviewPresets.count
            showTransientStatus("Exported \(count) Multiview \(count == 1 ? "preset" : "presets").")
            controller?.showHUD(icon: "square.and.arrow.up", message: "Exported \(count) Multiview \(count == 1 ? "Preset" : "Presets")")
        } catch {
            showTransientStatus(error.localizedDescription)
            controller?.showHUD(icon: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    private func importMultiviewPresetsFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Multiview Presets"
        panel.message = "Select a GlassGrid You Multiview preset JSON file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let controller = coordinator.commandTarget ?? coordinator.openWindows.first
        do {
            let data = try Data(contentsOf: url)
            if let controller {
                let importedCount = try controller.importMultiviewPresets(from: data)
                showTransientStatus("Imported \(importedCount) Multiview \(importedCount == 1 ? "preset" : "presets").")
            } else {
                let decoded = try MultiviewPresetTransferCodec.decode(from: data, tier: .fullControl)
                var existing = coordinator.settings.savedMultiviewPresets
                var usedIDs = Set(existing.map(\.id))
                var importedCount = 0
                for preset in decoded {
                    guard existing.count < MultiviewPresetTransferCodec.maxImportedPresets else { break }
                    let uniqueID = usedIDs.contains(preset.id) ? UUID() : preset.id
                    usedIDs.insert(uniqueID)
                    existing.append(
                        MultiviewPreset(
                            id: uniqueID,
                            name: preset.name,
                            urlStrings: preset.urlStrings,
                            layoutMode: preset.layoutMode,
                            splitRatios: preset.splitRatios
                        )
                    )
                    importedCount += 1
                }
                coordinator.settings.savedMultiviewPresets = existing
                showTransientStatus("Imported \(importedCount) Multiview \(importedCount == 1 ? "preset" : "presets").")
            }
        } catch {
            showTransientStatus(error.localizedDescription)
            controller?.showHUD(icon: "exclamationmark.triangle", message: error.localizedDescription)
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
