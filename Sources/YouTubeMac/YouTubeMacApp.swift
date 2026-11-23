import AppKit
import SwiftUI
import YouTubeMacCore

/// AppKit lifecycle bridge handling Dock reopen events, macOS Services, and incoming `glassgridyou://` URLs.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: AppController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = self
        controller?.settings.applyAppearance()
        flushPendingURLs()
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
        if let controller {
            controller.handleDroppedURL(url)
        } else {
            pendingURLs.append(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.focusMainWindow()
        return true
    }

    func applicationDidResignActive(_ notification: Notification) {
        controller?.handleAppDidResignActive()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.handleAppDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.handleAppWillTerminate()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let controller else { return nil }
        let menu = NSMenu(title: "GlassGrid You")

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

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(dockNewTab), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)

        let clipItem = NSMenuItem(title: "Open Copied YouTube URL", action: #selector(dockOpenClipboardURL), keyEquivalent: "")
        clipItem.target = self
        menu.addItem(clipItem)

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

        return menu
    }

    @objc private func dockTogglePlayPause() {
        controller?.togglePlayPause()
    }

    @objc private func dockToggleMute() {
        controller?.toggleMute()
    }

    @objc private func dockToggleMultiview() {
        controller?.focusMainWindow()
        controller?.toggleMultiview()
    }

    @objc private func dockNewTab() {
        controller?.focusMainWindow()
        controller?.createTab()
    }

    @objc private func dockOpenClipboardURL() {
        controller?.openURLFromClipboard()
    }

    @objc private func dockSelectSleepTimer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = SleepTimerOption(rawValue: raw) else {
            return
        }
        controller?.setSleepTimer(option)
    }

    @objc private func dockClearSleepTimer() {
        controller?.setSleepTimer(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            controller.handleIncomingURL(url)
        }
    }

    func attachController(_ controller: AppController) {
        guard self.controller !== controller else { return }
        self.controller = controller
        controller.settings.applyAppearance()
        flushPendingURLs()
    }

    private func flushPendingURLs() {
        guard let controller, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls {
            controller.handleIncomingURL(url)
        }
    }
}

@main
struct YouTubeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = AppController()

    var body: some Scene {
        Window("GlassGrid You", id: "main") {
            MainWindowView(controller: controller)
                .task {
                    appDelegate.attachController(controller)
                }
                .preferredColorScheme(controller.settings.preferredColorScheme)
                .tint(AppleTheme.accent)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            appCommands
        }

        MenuBarExtra(
            "GlassGrid You",
            systemImage: controller.nowPlayingStatus.isPlaying ? "play.circle.fill" : "play.rectangle.fill",
            isInserted: Binding(
                get: { controller.settings.showMenuBarControls },
                set: { controller.settings.showMenuBarControls = $0 }
            )
        ) {
            MenuBarView(controller: controller)
                .preferredColorScheme(controller.settings.preferredColorScheme)
                .tint(AppleTheme.accent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(controller: controller)
                .preferredColorScheme(controller.settings.preferredColorScheme)
                .tint(AppleTheme.accent)
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(after: .appInfo) {
            Button(controller.isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                controller.checkForUpdates(presentAlert: true)
            }
            .disabled(controller.isCheckingForUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                controller.createTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                controller.closeTab(id: controller.selectedTabID)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(controller.anyTabInFullscreen)

            Button("Reopen Closed Tab") {
                controller.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(controller.closedTabURLs.isEmpty)

            Divider()

            Button("Open YouTube URL from Clipboard") {
                controller.openURLFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Copy Current Link") {
                controller.copyCurrentURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Copy Link at Current Time") {
                controller.copyCurrentURLAtTime()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!controller.nowPlayingStatus.hasVideo)

            Button("Share Link…") {
                controller.shareCurrentURL()
            }
            .disabled(controller.currentShareURL == nil)

            Button("Share Link at Current Time…") {
                controller.shareCurrentURLAtTime()
            }
            .disabled(controller.currentTimestampedShareURL == nil)

            Button("Open Current Page in Default Browser") {
                controller.openCurrentInDefaultBrowser()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Find on Page…") {
                controller.presentFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(controller.anyTabInFullscreen || controller.isSelectedTabPoppedOut)

            Button("Find Next") {
                controller.findNextOnPage()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(controller.anyTabInFullscreen || controller.isSelectedTabPoppedOut)
        }

        CommandMenu("Navigate") {
            Button("Focus URL Bar") {
                controller.focusOmnibox(clearForSearch: false)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Command Palette & Search…") {
                controller.toggleCommandPalette()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(controller.anyTabInFullscreen)

            Divider()

            Button("Back") {
                controller.selectedTab?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(controller.isSelectedTabPoppedOut || !(controller.selectedTab?.canGoBack ?? false))

            Button("Forward") {
                controller.selectedTab?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(controller.isSelectedTabPoppedOut || !(controller.selectedTab?.canGoForward ?? false))

            Button("Reload Page") {
                controller.selectedTab?.reloadOrStop()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller.isSelectedTabPoppedOut)

            Divider()

            Button("Home") {
                controller.navigateSelectedTab(to: .home)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Subscriptions") {
                controller.navigateSelectedTab(to: .subscriptions)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Watch Later") {
                controller.navigateSelectedTab(to: .watchLater)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Button("History") {
                controller.navigateSelectedTab(to: .history)
            }
            .keyboardShortcut("y", modifiers: .command)

            Button(controller.isCurrentPagePinned ? "Unpin Current Page" : "Pin Current Page") {
                controller.togglePinCurrentPage()
            }
            .keyboardShortcut("d", modifiers: .command)

            Divider()

            Button("Select Next Tab") {
                controller.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(controller.tabs.count < 2 || controller.anyTabInFullscreen)

            Button("Select Previous Tab") {
                controller.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(controller.tabs.count < 2 || controller.anyTabInFullscreen)

            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") {
                    controller.selectTab(atIndex: number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled(!controller.tabs.indices.contains(number - 1) || controller.anyTabInFullscreen)
            }
        }

        CommandMenu("Playback") {
            Button(controller.nowPlayingStatus.isPlaying ? "Pause" : "Play") {
                controller.togglePlayPause()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(!controller.nowPlayingStatus.hasVideo)

            Button(controller.nowPlayingStatus.isMuted ? "Unmute" : "Mute") {
                controller.toggleMute()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!controller.nowPlayingStatus.hasVideo)

            Button("Picture in Picture") {
                controller.togglePictureInPicture()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!controller.nowPlayingStatus.hasVideo)

            Button(controller.isMiniPlayer ? "Exit Mini-Player" : "Mini-Player") {
                controller.toggleMiniPlayer()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!controller.isMiniPlayer && !controller.canPopOutActiveTab)

            Button(controller.alwaysOnTop ? "Disable Always on Top" : "Always on Top") {
                controller.toggleAlwaysOnTop()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])

            Button(controller.focusModeActive ? "Exit Focus Mode" : "Focus Mode") {
                controller.toggleFocusMode()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Toggle Theater Mode") {
                controller.toggleTheaterMode()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            Button(controller.isMultiviewActive ? "Exit Multiview" : "Multiview (Up to 4 Streams)") {
                controller.toggleMultiview()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(controller.anyTabInFullscreen)

            Button("Cycle Multiview Layout") {
                controller.cycleMultiviewLayoutMode()
            }
            .keyboardShortcut("g", modifiers: [.command, .option])
            .disabled(!controller.isMultiviewActive || controller.anyTabInFullscreen)

            Button("Add Stream to Multiview") {
                controller.addTileToMultiview()
            }
            .disabled((controller.isMultiviewActive && !controller.canAddMultiviewTile) || controller.anyTabInFullscreen)

            Button("Open YouTube TV in Multiview") {
                controller.openYouTubeTVInMultiview()
            }
            .disabled((controller.isMultiviewActive && !controller.canAddMultiviewTile) || controller.anyTabInFullscreen)

            Menu("Multiview Audio Focus") {
                ForEach(1...MultiviewGridLayout.maxTiles, id: \.self) { slot in
                    Button("Stream \(slot) Audio") {
                        controller.focusMultiviewAudio(slot: slot)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: [.command, .option])
                    .disabled(!controller.isMultiviewActive || !controller.multiviewTabIDs.indices.contains(slot - 1))
                }

                Divider()

                Button("Next Stream Audio") {
                    controller.cycleMultiviewAudioFocus(by: 1)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!controller.isMultiviewActive)

                Button("Previous Stream Audio") {
                    controller.cycleMultiviewAudioFocus(by: -1)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!controller.isMultiviewActive)

                Divider()

                Button("Mute All Streams") {
                    controller.muteAllMultiviewTiles()
                }
                .disabled(!controller.isMultiviewActive)
            }

            Divider()

            Menu("Playback Speed") {
                Button("Increase Speed (+0.1×)") {
                    controller.stepPlaybackRate(by: 0.1)
                }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!controller.nowPlayingStatus.hasVideo)

                Button("Decrease Speed (−0.1×)") {
                    controller.stepPlaybackRate(by: -0.1)
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!controller.nowPlayingStatus.hasVideo)

                Button("Reset Speed (1×)") {
                    controller.resetPlaybackRate()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!controller.nowPlayingStatus.hasVideo)

                Divider()

                ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    let isCurrent = controller.nowPlayingStatus.hasVideo && abs(controller.nowPlayingStatus.playbackRate - rate) < 0.02
                    Button {
                        controller.setPlaybackRate(rate)
                    } label: {
                        if isCurrent {
                            Label(MediaStatus.formatPlaybackRate(rate), systemImage: "checkmark")
                        } else {
                            Text(MediaStatus.formatPlaybackRate(rate))
                        }
                    }
                    .disabled(!controller.nowPlayingStatus.hasVideo)
                }
            }

            Menu("Sleep Timer") {
                ForEach(SleepTimerOption.allCases) { option in
                    Button {
                        controller.setSleepTimer(option)
                    } label: {
                        if controller.sleepTimerOption == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }

                if controller.isSleepTimerActive {
                    Divider()
                    Button("Turn Off Sleep Timer") {
                        controller.setSleepTimer(nil)
                    }
                }
            }

            if controller.activeChapters.count >= 2 {
                Menu("Chapters") {
                    let chapters = controller.activeChapters
                    let current = controller.activeTimeline.flatMap {
                        VideoChapterParser.activeChapter(at: $0.currentTime, in: chapters)
                    }
                    ForEach(chapters) { chapter in
                        Button {
                            controller.seek(to: chapter.startSeconds)
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
                controller.copyVideoFrame()
            }
            .disabled(!controller.nowPlayingStatus.hasVideo)

            Button("Save Video Frame…") {
                controller.saveVideoFrame()
            }
            .disabled(!controller.nowPlayingStatus.hasVideo)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                controller.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(controller.settings.isEffectivelyDark ? "Switch to Day Mode" : "Switch to Night Mode") {
                controller.toggleDayNightMode()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Menu("Appearance") {
                ForEach(AppAppearance.allCases) { mode in
                    Button {
                        controller.setAppearance(mode)
                    } label: {
                        if controller.settings.appearance == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }

            Divider()

            Button("Zoom In") {
                controller.zoomIn()
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Zoom Out") {
                controller.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                controller.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle(
                "Hide YouTube Shorts",
                isOn: Binding(
                    get: { controller.settings.hideShorts },
                    set: { controller.settings.hideShorts = $0 }
                )
            )
            Toggle(
                "Clean Web Chrome",
                isOn: Binding(
                    get: { controller.settings.cleanWebChrome },
                    set: { controller.settings.cleanWebChrome = $0 }
                )
            )
            Toggle(
                "Default to Theater Mode",
                isOn: Binding(
                    get: { controller.settings.autoTheaterMode },
                    set: { controller.settings.autoTheaterMode = $0 }
                )
            )
        }
    }
}
