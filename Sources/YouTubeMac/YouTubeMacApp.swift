import AppIntents
import AppKit
import SwiftUI
import YouTubeMacCore

/// AppKit lifecycle bridge handling Dock reopen events, macOS Services, and incoming `glassgridyou://` URLs
/// across all open GlassGrid You windows via `AppCoordinator`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: AppCoordinator?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        if coordinator == nil, let active = AppCoordinator.sharedActive {
            attachCoordinator(active)
        } else {
            coordinator?.settings.applyAppearance()
            flushPendingURLs()
        }
        coordinator?.agentBridge.startServersIfEnabled()
        GlassGridShortcutsProvider.updateAppShortcutParameters()
    }

    @objc func openYouTubeURLService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let candidate = pboard.string(forType: .URL) ?? pboard.string(forType: .string)
        guard let candidate,
              let url = YouTubeURLRouter.extractYouTubeURLFromString(candidate) else {
            return
        }
        if let coordinator {
            coordinator.handleDroppedURL(url)
        } else {
            pendingURLs.append(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.handleDockReopen(hasVisibleWindows: flag)
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        coordinator?.handleAppDidResignActive()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        coordinator?.handleAppDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.handleAppWillTerminate()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let coordinator else { return nil }
        let menu = NSMenu(title: "GlassGrid You")

        let controller = coordinator.nowPlayingController
        if let controller {
            let status = controller.nowPlayingStatus
            if status.hasVideo {
                let titleText = status.title.isEmpty ? "Now Playing" : status.title
                let truncated = titleText.count > 44 ? String(titleText.prefix(43)) + "…" : titleText
                let header = NSMenuItem(title: truncated, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)

                let playItem = NSMenuItem(
                    title: status.isPlaying ? "Pause" : "Play",
                    action: #selector(dockTogglePlayPause),
                    keyEquivalent: ""
                )
                playItem.target = self
                menu.addItem(playItem)

                let muteItem = NSMenuItem(
                    title: status.isMuted ? "Unmute" : "Mute",
                    action: #selector(dockToggleMute),
                    keyEquivalent: ""
                )
                muteItem.target = self
                menu.addItem(muteItem)

                menu.addItem(.separator())
            }

            let multiviewItem = NSMenuItem(
                title: controller.isMultiviewActive ? "Exit Multiview" : "Enter Multiview",
                action: #selector(dockToggleMultiview),
                keyEquivalent: ""
            )
            multiviewItem.target = self
            multiviewItem.isEnabled = !controller.anyTabInFullscreen
            menu.addItem(multiviewItem)
        }

        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(dockNewWindow), keyEquivalent: "")
        newWindowItem.target = self
        menu.addItem(newWindowItem)

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(dockNewTab), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)

        let clipItem = NSMenuItem(title: "Open Copied YouTube URL", action: #selector(dockOpenClipboardURL), keyEquivalent: "")
        clipItem.target = self
        menu.addItem(clipItem)

        if let controller {
            menu.addItem(.separator())

            let sleepRootTitle = controller.sleepTimerOption.map { "Sleep Timer (\($0.shortTitle))" } ?? "Sleep Timer"
            let sleepRoot = NSMenuItem(title: sleepRootTitle, action: nil, keyEquivalent: "")
            let sleepSubmenu = NSMenu(title: "Sleep Timer")
            for option in SleepTimerOption.allCases {
                let item = NSMenuItem(title: option.title, action: #selector(dockSelectSleepTimer(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = option.rawValue
                item.state = (controller.sleepTimerOption == option) ? .on : .off
                sleepSubmenu.addItem(item)
            }
            if controller.isSleepTimerActive {
                sleepSubmenu.addItem(.separator())
                let offItem = NSMenuItem(title: "Turn Off Sleep Timer", action: #selector(dockClearSleepTimer), keyEquivalent: "")
                offItem.target = self
                sleepSubmenu.addItem(offItem)
            }
            sleepRoot.submenu = sleepSubmenu
            menu.addItem(sleepRoot)
        }

        return menu
    }

    @objc private func dockTogglePlayPause() {
        coordinator?.nowPlayingController?.togglePlayPause()
    }

    @objc private func dockToggleMute() {
        coordinator?.nowPlayingController?.toggleMute()
    }

    @objc private func dockToggleMultiview() {
        guard let target = coordinator?.commandTarget else {
            coordinator?.openNewWindow()
            return
        }
        target.focusMainWindow()
        target.toggleMultiview()
    }

    @objc private func dockNewWindow() {
        coordinator?.openNewWindow()
    }

    @objc private func dockNewTab() {
        guard let target = coordinator?.commandTarget else {
            coordinator?.openNewWindow()
            return
        }
        target.focusMainWindow()
        target.createTab()
    }

    @objc private func dockOpenClipboardURL() {
        coordinator?.openURLFromClipboard()
    }

    @objc private func dockSelectSleepTimer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = SleepTimerOption(rawValue: raw) else {
            return
        }
        coordinator?.nowPlayingController?.setSleepTimer(option)
    }

    @objc private func dockClearSleepTimer() {
        coordinator?.nowPlayingController?.setSleepTimer(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            coordinator.handleIncomingURL(url)
        }
    }

    func attachCoordinator(_ coordinator: AppCoordinator) {
        guard self.coordinator !== coordinator else { return }
        self.coordinator = coordinator
        coordinator.settings.applyAppearance()
        flushPendingURLs()
    }

    private func flushPendingURLs() {
        guard let coordinator, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls {
            coordinator.handleIncomingURL(url)
        }
    }
}

/// Hosts a single macOS window scene backed idempotently by `AppCoordinator.controller(for:)`
/// and registers SwiftUI's `openWindow` action so `⌘N`, Dock reopen, and deep links always work.
private struct WindowSceneRootView: View {
    let coordinator: AppCoordinator
    let appDelegate: AppDelegate
    let windowID: UUID
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let controller = coordinator.controller(for: windowID)
        MainWindowView(controller: controller)
            .task {
                appDelegate.attachCoordinator(coordinator)
                coordinator.openWindowHandler = { id in
                    openWindow(id: "main", value: id)
                }
            }
            .preferredColorScheme(coordinator.settings.preferredColorScheme)
            .tint(AppleTheme.accent)
    }
}

@main
struct YouTubeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator: AppCoordinator

    init() {
        let coord = AppCoordinator()
        AppCoordinator.sharedActive = coord
        _coordinator = State(initialValue: coord)
        let bridge = coord.agentBridge
        AppDependencyManager.shared.add(key: "GlassGridAgentBridge", dependency: bridge)
    }

    var body: some Scene {
        WindowGroup("GlassGrid You", id: "main", for: UUID.self) { $windowID in
            WindowSceneRootView(
                coordinator: coordinator,
                appDelegate: appDelegate,
                windowID: windowID
            )
        } defaultValue: {
            UUID()
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            appCommands
        }

        MenuBarExtra(
            "GlassGrid You",
            systemImage: (coordinator.nowPlayingController?.nowPlayingStatus.isPlaying ?? false) ? "play.circle.fill" : "play.rectangle.fill",
            isInserted: Binding(
                get: { coordinator.settings.showMenuBarControls },
                set: { coordinator.settings.showMenuBarControls = $0 }
            )
        ) {
            MenuBarView(coordinator: coordinator)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
                .tint(AppleTheme.accent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(coordinator: coordinator)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
                .tint(AppleTheme.accent)
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        // Snapshot strictly for menu labels & disabled states; every action closure resolves
        // `coordinator.commandTarget` dynamically at execution time to eliminate stale-window races.
        let targetSnapshot = coordinator.commandTarget
        let activeMediaStatus = targetSnapshot?.nowPlayingStatus ?? .empty
        let anyFullscreen = targetSnapshot?.anyTabInFullscreen ?? false
        let isPoppedOut = targetSnapshot?.isSelectedTabPoppedOut ?? false

        CommandGroup(after: .appInfo) {
            Button(coordinator.updater.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                coordinator.updater.checkForUpdates(presentAlert: true)
            }
            .disabled(!coordinator.updater.canCheckForUpdates)
        }

        // Suppress AppKit's auto-inserted "Hide Toolbar (⌥⌘T)" item so the unified titlebar
        // toolbar stays locked and never conflicts with Toggle Theater Mode (⌘⌥T).
        CommandGroup(replacing: .toolbar) {}

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                coordinator.openNewWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                if let active = coordinator.commandTarget {
                    active.createTab()
                } else {
                    coordinator.openNewWindow()
                }
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                guard let active = coordinator.commandTarget else { return }
                active.closeTab(id: active.selectedTabID)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(targetSnapshot == nil || anyFullscreen)

            Button("Close Window") {
                coordinator.commandTarget?.closeWindow()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil || anyFullscreen)

            Divider()

            Button("Manage Streaming Services…") {
                coordinator.commandTarget?.openStreamingServicesSetup(step: 1)
            }
            .disabled(targetSnapshot == nil || anyFullscreen)

            Button("Reopen Closed Tab") {
                coordinator.commandTarget?.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(targetSnapshot?.closedTabURLs.isEmpty ?? true)

            Divider()

            Button("Open YouTube URL from Clipboard") {
                coordinator.openURLFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Copy Current Link") {
                coordinator.commandTarget?.copyCurrentURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil)

            Button("Copy Link at Current Time") {
                coordinator.commandTarget?.copyCurrentURLAtTime()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!activeMediaStatus.hasVideo)

            Button("Share Link…") {
                coordinator.commandTarget?.shareCurrentURL()
            }
            .disabled(targetSnapshot?.currentShareURL == nil)

            Button("Share Link at Current Time…") {
                coordinator.commandTarget?.shareCurrentURLAtTime()
            }
            .disabled(targetSnapshot?.currentTimestampedShareURL == nil)

            Button("Open Current Page in Default Browser") {
                coordinator.commandTarget?.openCurrentInDefaultBrowser()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Find on Page…") {
                coordinator.commandTarget?.presentFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(targetSnapshot == nil || anyFullscreen || isPoppedOut)

            Button("Find Next") {
                coordinator.commandTarget?.findNextOnPage()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(targetSnapshot == nil || anyFullscreen || isPoppedOut)
        }

        CommandMenu("Navigate") {
            Button("Focus URL Bar") {
                coordinator.commandTarget?.focusOmnibox(clearForSearch: false)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Button("Command Palette & Search…") {
                coordinator.commandTarget?.toggleCommandPalette()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(targetSnapshot == nil || anyFullscreen)

            Divider()

            Button("Back") {
                coordinator.commandTarget?.selectedTab?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(targetSnapshot == nil || isPoppedOut || !(targetSnapshot?.selectedTab?.canGoBack ?? false))

            Button("Forward") {
                coordinator.commandTarget?.selectedTab?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(targetSnapshot == nil || isPoppedOut || !(targetSnapshot?.selectedTab?.canGoForward ?? false))

            Button("Reload Page") {
                coordinator.commandTarget?.selectedTab?.reloadOrStop()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(targetSnapshot == nil || isPoppedOut)

            Divider()

            Button("Home") {
                coordinator.commandTarget?.navigateSelectedTab(to: .home)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil)

            Button("Subscriptions") {
                coordinator.commandTarget?.navigateSelectedTab(to: .subscriptions)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil)

            Button("Watch Later") {
                coordinator.commandTarget?.navigateSelectedTab(to: .watchLater)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(targetSnapshot == nil)

            Button("History") {
                coordinator.commandTarget?.navigateSelectedTab(to: .history)
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Button((targetSnapshot?.isCurrentPagePinned ?? false) ? "Unpin Current Page" : "Pin Current Page") {
                coordinator.commandTarget?.togglePinCurrentPage()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Divider()

            Button("Select Next Tab") {
                coordinator.commandTarget?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((targetSnapshot?.tabs.count ?? 0) < 2 || anyFullscreen)

            Button("Select Previous Tab") {
                coordinator.commandTarget?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((targetSnapshot?.tabs.count ?? 0) < 2 || anyFullscreen)

            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") {
                    coordinator.commandTarget?.selectTab(atIndex: number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(!(targetSnapshot?.tabs.indices.contains(number - 1) ?? false) || anyFullscreen)
            }
        }

        CommandMenu("Playback") {
            Button(activeMediaStatus.isPlaying ? "Pause" : "Play") {
                coordinator.commandTarget?.togglePlayPause()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(!activeMediaStatus.hasVideo)

            Button(activeMediaStatus.isMuted ? "Unmute" : "Mute") {
                coordinator.commandTarget?.toggleMute()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!activeMediaStatus.hasVideo)

            Button("Picture in Picture") {
                coordinator.commandTarget?.togglePictureInPicture()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!activeMediaStatus.hasVideo)

            Button(
                (targetSnapshot?.isMiniPlayer ?? false)
                    ? ((targetSnapshot?.isFloatingMultiviewGrid ?? false) ? "Return Floating Grid" : "Exit Mini-Player")
                    : ((targetSnapshot?.isMultiviewActive ?? false) ? "Float Multiview Grid" : "Mini-Player")
            ) {
                coordinator.commandTarget?.toggleMiniPlayer()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil || (!(targetSnapshot?.isMiniPlayer ?? false) && !(targetSnapshot?.canPopOutActiveContent ?? false)))

            Button((targetSnapshot?.alwaysOnTop ?? false) ? "Disable Always on Top" : "Always on Top") {
                coordinator.commandTarget?.toggleAlwaysOnTop()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(targetSnapshot == nil)

            Button((targetSnapshot?.focusModeActive ?? false) ? "Exit Focus Mode" : "Focus Mode") {
                coordinator.commandTarget?.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil)

            Button("Toggle Theater Mode") {
                coordinator.commandTarget?.toggleTheaterMode()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(targetSnapshot == nil)

            let cleanBypassed = targetSnapshot?.selectedTab?.isCleanBoxBypassed ?? false
            let cleanControlAvailable = (targetSnapshot?.settings.cleanBoxStreamingPlayers ?? false)
                && (targetSnapshot?.selectedTab?.routingMode == .companion)
                && ((targetSnapshot?.selectedTab?.mediaStatus.isCleanBoxActive ?? false) || cleanBypassed)
                && !(targetSnapshot?.isMultiviewActive ?? false)
            Button(cleanBypassed ? "Restore Clean-Box Video" : "Show Full Page") {
                coordinator.commandTarget?.toggleCleanBoxForActiveTab()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil || !cleanControlAvailable)

            Divider()

            Button((targetSnapshot?.isMultiviewActive ?? false) ? "Exit Multiview" : "Multiview (Up to 4 Streams)") {
                coordinator.commandTarget?.toggleMultiview()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(targetSnapshot == nil || anyFullscreen)

            Button("Cycle Multiview Layout") {
                coordinator.commandTarget?.cycleMultiviewLayoutMode()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(!(targetSnapshot?.isMultiviewActive ?? false) || anyFullscreen)

            Button((targetSnapshot?.isMultiviewSoloActive ?? false) ? "Back to Multiview Grid" : "Solo / Expand Multiview Tile") {
                coordinator.commandTarget?.toggleMultiviewSolo()
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(!(targetSnapshot?.isMultiviewActive ?? false) || anyFullscreen)

            Button("Add Stream to Multiview") {
                coordinator.commandTarget?.addTileToMultiview()
            }
            .disabled(targetSnapshot == nil || ((targetSnapshot?.isMultiviewActive ?? false) && !(targetSnapshot?.canAddMultiviewTile ?? false)) || anyFullscreen)

            Button("Open YouTube TV in Multiview") {
                coordinator.commandTarget?.openYouTubeTVInMultiview()
            }
            .disabled(targetSnapshot == nil || ((targetSnapshot?.isMultiviewActive ?? false) && !(targetSnapshot?.canAddMultiviewTile ?? false)) || anyFullscreen)

            Menu("Multiview Audio Focus") {
                ForEach(1...MultiviewGridLayout.maxTiles, id: \.self) { slot in
                    Button("Stream \(slot) Audio") {
                        coordinator.commandTarget?.focusMultiviewAudio(slot: slot)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: [.command, .option])
                    .disabled(!(targetSnapshot?.isMultiviewActive ?? false) || !(targetSnapshot?.multiviewTabIDs.indices.contains(slot - 1) ?? false))
                }

                Divider()

                Button("Next Stream Audio") {
                    coordinator.commandTarget?.cycleMultiviewAudioFocus(by: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!(targetSnapshot?.isMultiviewActive ?? false))

                Button("Previous Stream Audio") {
                    coordinator.commandTarget?.cycleMultiviewAudioFocus(by: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!(targetSnapshot?.isMultiviewActive ?? false))

                Divider()

                Button("Mute All Streams") {
                    coordinator.commandTarget?.muteAllMultiviewTiles()
                }
                .disabled(!(targetSnapshot?.isMultiviewActive ?? false))
            }

            Button("Stream to AirPlay & TV Displays…") {
                coordinator.commandTarget?.openAirPlayPopover()
            }
            .disabled(targetSnapshot == nil || anyFullscreen)

            Divider()

            Menu("Playback Speed") {
                Button("Increase Speed (+0.1×)") {
                    coordinator.commandTarget?.stepPlaybackRate(by: 0.1)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!activeMediaStatus.hasVideo)

                Button("Decrease Speed (−0.1×)") {
                    coordinator.commandTarget?.stepPlaybackRate(by: -0.1)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!activeMediaStatus.hasVideo)

                Button("Reset Speed (1×)") {
                    coordinator.commandTarget?.resetPlaybackRate()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!activeMediaStatus.hasVideo)

                Divider()

                ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    let isCurrent = activeMediaStatus.hasVideo && abs(activeMediaStatus.playbackRate - rate) < 0.02
                    Button {
                        coordinator.commandTarget?.setPlaybackRate(rate)
                    } label: {
                        if isCurrent {
                            Label(MediaStatus.formatPlaybackRate(rate), systemImage: "checkmark")
                        } else {
                            Text(MediaStatus.formatPlaybackRate(rate))
                        }
                    }
                    .disabled(!activeMediaStatus.hasVideo)
                }
            }

            Menu("Sleep Timer") {
                ForEach(SleepTimerOption.allCases) { option in
                    Button {
                        coordinator.commandTarget?.setSleepTimer(option)
                    } label: {
                        if targetSnapshot?.sleepTimerOption == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                    .disabled(targetSnapshot == nil)
                }

                if targetSnapshot?.isSleepTimerActive == true {
                    Divider()
                    Button("Turn Off Sleep Timer") {
                        coordinator.commandTarget?.setSleepTimer(nil)
                    }
                }
            }

            if let targetSnapshot, targetSnapshot.activeChapters.count >= 2 {
                Menu("Chapters") {
                    let chapters = targetSnapshot.activeChapters
                    let current = targetSnapshot.activeTimeline.flatMap {
                        VideoChapterParser.activeChapter(at: $0.currentTime, in: chapters)
                    }
                    ForEach(chapters) { chapter in
                        Button {
                            coordinator.commandTarget?.seek(to: chapter.startSeconds)
                        } label: {
                            let label = "\(chapter.formattedStartTime)  \(chapter.title)"
                            if current?.id == chapter.id {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Copy Video Frame") {
                coordinator.commandTarget?.copyVideoFrame()
            }
            .disabled(!activeMediaStatus.hasVideo)

            Button("Save Video Frame…") {
                coordinator.commandTarget?.saveVideoFrame()
            }
            .disabled(!activeMediaStatus.hasVideo)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                coordinator.commandTarget?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(targetSnapshot == nil)

            Button(coordinator.settings.isEffectivelyDark ? "Switch to Day Mode" : "Switch to Night Mode") {
                if let active = coordinator.commandTarget {
                    active.toggleDayNightMode()
                } else {
                    coordinator.settings.appearance = coordinator.settings.isEffectivelyDark ? .light : .dark
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Menu("Appearance") {
                ForEach(AppAppearance.allCases) { mode in
                    Button {
                        if let active = coordinator.commandTarget {
                            active.setAppearance(mode)
                        } else {
                            coordinator.settings.appearance = mode
                        }
                    } label: {
                        if coordinator.settings.appearance == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            Divider()

            Button("Zoom In") {
                coordinator.commandTarget?.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Button("Zoom Out") {
                coordinator.commandTarget?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Button("Actual Size") {
                coordinator.commandTarget?.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(targetSnapshot == nil)

            Divider()

            Toggle(
                "Hide YouTube Shorts",
                isOn: Binding(
                    get: { coordinator.settings.hideShorts },
                    set: { coordinator.settings.hideShorts = $0 }
                )
            )
            Toggle(
                "Clean Web Chrome",
                isOn: Binding(
                    get: { coordinator.settings.cleanWebChrome },
                    set: { coordinator.settings.cleanWebChrome = $0 }
                )
            )
            Toggle(
                "Default to Theater Mode",
                isOn: Binding(
                    get: { coordinator.settings.autoTheaterMode },
                    set: { coordinator.settings.autoTheaterMode = $0 }
                )
            )
        }
    }
}
