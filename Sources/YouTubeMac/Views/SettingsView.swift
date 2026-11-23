import SwiftUI
import YouTubeMacCore

/// Native macOS Preferences window organized per Apple HIG: General, Playback, Distraction-Free, and Account & Data.
struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var showClearDataConfirm = false
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
        }
        .frame(width: 540, height: 450)
        .alert("Sign Out & Clear All Site Data?", isPresented: $showClearDataConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All Data", role: .destructive) {
                Task {
                    await controller.clearAllWebsiteData()
                    showTransientStatus("Cleared cookies, cache, and signed-out all tabs.")
                }
            }
        } message: {
            Text("This removes YouTube and Google cookies and signs you out of your account in this app.")
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        @Bindable var settings = controller.settings

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
            }

            Section("Mini-Player & Window") {
                Toggle("Auto pop-out Mini-Player when leaving a video or covered by another app", isOn: $settings.autoMiniPlayerOnLeave)
                Toggle("Keep Mini-Player visible across all Spaces", isOn: $settings.miniPlayerAllSpaces)
            }

            Section("Home, Tabs & Menu Bar") {
                Toggle("Show Home Shelf (Continue Watching, Subscriptions & Suggested)", isOn: $settings.showHomeShelf)
                Toggle("Show live YouTube search suggestions in Command Palette (⌘K)", isOn: $settings.searchAutocompleteEnabled)
                Toggle("Open non-YouTube links in default browser", isOn: $settings.openExternalLinksInBrowser)
                Toggle("Always show tab bar", isOn: $settings.alwaysShowTabBar)
                Toggle("Show menu bar quick-controls", isOn: $settings.showMenuBarControls)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var playbackTab: some View {
        @Bindable var settings = controller.settings

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
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Duck background Multiview audio to 15% (instead of mute)", isOn: $settings.multiviewAudioDuckingEnabled)
                    Text("Opt-in: keeps non-focused Multiview streams softly audible at 15% volume and restores 100% on focus or exit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Segments") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Auto-skip sponsored segments (SponsorBlock)", isOn: $settings.sponsorBlockEnabled)
                    Text("Opt-in: queries sponsor.ajay.app using a privacy-preserving 4-character SHA-256 video ID prefix and fails silently offline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var distractionFreeTab: some View {
        @Bindable var settings = controller.settings

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
                Toggle("Hide right-side recommendations", isOn: $settings.hideWatchRecommendations)
                Toggle("Hide video comments", isOn: $settings.hideComments)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var accountTab: some View {
        Form {
            Section("Google Account") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("YouTube Sign-In")
                            .font(.body)
                        Text("Cookies are stored securely in WebKit's persistent data store.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign In…") {
                        controller.openSignIn()
                    }
                }

                HStack {
                    Text("Manage Google Account")
                    Spacer()
                    Button("Open Account") {
                        controller.openGoogleAccount()
                    }
                }
            }

            Section("Storage") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Local History & Presets")
                        Text("Clears Continue Watching, Most Watched Channels & saved Multiview presets without signing you out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History") {
                        controller.clearLocalHistory()
                        showTransientStatus("Cleared local history & Multiview presets.")
                    }
                    .disabled(
                        controller.settings.continueWatching.isEmpty
                            && controller.settings.watchedChannels.isEmpty
                            && controller.settings.savedMultiviewPresets.isEmpty
                    )
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Web Cache")
                        Text("Frees cached assets while keeping your Google login intact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear Cache") {
                        Task {
                            await controller.clearWebCache()
                            showTransientStatus("Web cache cleared.")
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign Out & Reset Data")
                        Text("Removes all cookies, local storage, and cached media.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear All Data…", role: .destructive) {
                        showClearDataConfirm = true
                    }
                    .disabled(controller.isSigningOutData)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
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
