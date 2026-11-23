import AppKit
import SwiftUI
import YouTubeMacCore

/// Attaches the backing `NSWindow` exactly once when the view moves into a window hierarchy.
final class WindowObserverNSView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?
    private weak var attachedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== attachedWindow else { return }
        attachedWindow = window
        onWindowAvailable?(window)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowObserverNSView {
        let view = WindowObserverNSView(frame: .zero)
        view.onWindowAvailable = onWindowAvailable
        return view
    }

    func updateNSView(_ nsView: WindowObserverNSView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
    }
}

/// Apple Liquid Glass single-root macOS YouTube window where `TabWebViewHost` stays permanently mounted and respects WebKit fullscreen.
struct MainWindowView: View {
    @Bindable var controller: AppController
    @FocusState private var isOmniboxFocused: Bool
    @State private var isPillHovered = false
    @State private var isFocusPillHovered = false
    @State private var isHeaderHovered = false
    @State private var isSidebarHovered = false

    private var shouldDimCinemaChrome: Bool {
        controller.focusModeActive
            && !controller.isMultiviewActive
            && !controller.anyTabInFullscreen
            && !isOmniboxFocused
            && !controller.isCommandPalettePresented
            && !controller.isFindBarPresented
            && (controller.selectedTab?.mediaStatus.hasVideo ?? false)
    }

    private var shouldShowTabStrip: Bool {
        controller.tabs.count > 1 || controller.settings.alwaysShowTabBar
    }

    private var isSelectedTabPoppedOut: Bool {
        controller.poppedOutTabID != nil && controller.selectedTabID == controller.poppedOutTabID
    }

    private var isSelectedTabOnHome: Bool {
        guard let tab = controller.selectedTab, !tab.isCompanionTab else { return false }
        return SidebarDestination.matching(url: tab.url) == .home
    }

    private var shouldShowCompactHomeShelf: Bool {
        isSelectedTabOnHome
            && !isSelectedTabPoppedOut
            && !controller.isMultiviewActive
            && !controller.focusModeActive
            && !controller.anyTabInFullscreen
            && !controller.settings.hideHomeFeed
            && controller.settings.showHomeShelf
            && !(controller.selectedTab?.mediaStatus.isHomeFeedEmpty ?? false)
    }

    private var shouldShowPopulatedHomeDashboard: Bool {
        isSelectedTabOnHome
            && !isSelectedTabPoppedOut
            && !controller.isMultiviewActive
            && !controller.anyTabInFullscreen
            && !controller.settings.hideHomeFeed
            && controller.settings.showHomeShelf
            && (controller.selectedTab?.mediaStatus.isHomeFeedEmpty ?? false)
    }

    private var shouldShowHiddenHomeRecovery: Bool {
        isSelectedTabOnHome
            && !isSelectedTabPoppedOut
            && !controller.isMultiviewActive
            && !controller.anyTabInFullscreen
            && controller.settings.hideHomeFeed
    }

    var body: some View {
        HStack(spacing: 0) {
            if controller.isSidebarVisible {
                SidebarView(controller: controller)
                    .frame(width: WindowChromeLayout.sidebarWidth)
                    .opacity(shouldDimCinemaChrome && !isSidebarHovered ? 0.42 : 1.0)
                    .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isSidebarHovered)
                    .onHover { isSidebarHovered = $0 }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topHeaderBar
                        .zIndex(1)

                    if shouldShowTabStrip {
                        TabStripView(controller: controller)
                    }
                }
                .zIndex(1)
                .opacity(shouldDimCinemaChrome && !isHeaderHovered ? 0.42 : 1.0)
                .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isHeaderHovered)
                .onHover { isHeaderHovered = $0 }

                if controller.isMultiviewActive && !controller.anyTabInFullscreen {
                    MultiviewControlBar(controller: controller)
                }

                if shouldShowCompactHomeShelf {
                    HomeShelfBarView(controller: controller)
                }

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)

                    if let tab = controller.selectedTab, tab.isLoading {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(AppleTheme.accent)
                                .frame(width: proxy.size.width * max(0.08, tab.estimatedProgress), height: 2)
                                .animation(.easeOut(duration: 0.18), value: tab.estimatedProgress)
                        }
                        .frame(height: 2)
                    }
                }
                .frame(height: 1)

                // Single permanent WebKit container: never swapped across if/else branches and never mutates during fullscreen.
                ZStack {
                    TabWebViewHost(
                        tabs: controller.tabs,
                        selectedTabID: controller.selectedTabID,
                        poppedOutTabID: controller.poppedOutTabID,
                        anyTabInFullscreen: controller.anyTabInFullscreen,
                        multiviewTabIDs: controller.multiviewTabIDs,
                        multiviewLayoutMode: controller.multiviewLayoutMode,
                        multiviewSplitRatios: controller.multiviewSplitRatios,
                        onHoveredTileChanged: { tileID in
                            controller.setHoveredMultiviewTile(tileID)
                        },
                        onSplitRatiosChanged: { ratios in
                            controller.updateMultiviewSplitRatios(ratios)
                        },
                        onDividerHoverChanged: { dividerID in
                            controller.hoveredMultiviewDividerID = dividerID
                        },
                        onDividerDragStateChanged: { dividerID in
                            controller.activeMultiviewDividerDragID = dividerID
                        },
                        onDividerDoubleClickReset: { dividerID in
                            controller.handleMultiviewDividerDoubleClickReset(dividerID)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if controller.isMultiviewActive && !controller.anyTabInFullscreen {
                        MultiviewOverlayView(controller: controller)
                    }

                    if shouldShowHiddenHomeRecovery {
                        HiddenHomeFeedRecoveryView(controller: controller)
                    } else if shouldShowPopulatedHomeDashboard {
                        PopulatedHomeDashboardView(controller: controller)
                    }

                    if !controller.isMultiviewActive,
                       !controller.anyTabInFullscreen,
                       !isSelectedTabPoppedOut,
                       let tab = controller.selectedTab,
                       let loadError = tab.loadError {
                        TabErrorOverlayView(
                            error: loadError,
                            isCompactTile: false,
                            onRetry: { tab.reloadOrStop() },
                            onGoHome: { controller.navigateSelectedTab(to: .home) }
                        )
                    }

                    if isSelectedTabPoppedOut, let poppedTab = controller.poppedOutTab {
                        poppedOutPlaceholder(for: poppedTab)
                    }

                    if let toast = controller.activeToast {
                        VStack {
                            AppleHUDToast(toast: toast)
                                .padding(.top, 14)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if controller.isFindBarPresented && !controller.anyTabInFullscreen && !isSelectedTabPoppedOut {
                        FindBarView(controller: controller)
                            .padding(.top, 10)
                            .padding(.trailing, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppleTheme.canvasColor)
        }
        .ignoresSafeArea(.all, edges: .top)
        .overlay {
            if controller.isCommandPalettePresented && !controller.anyTabInFullscreen {
                CommandPaletteView(controller: controller)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.14), value: controller.isCommandPalettePresented)
        .background(
            WindowAccessor { window in
                controller.attachMainWindow(window)
            }
        )
        .onChange(of: controller.omniboxFocusTrigger) { _, _ in
            activateOmniboxForSearch(clearInput: controller.omniboxClearOnFocus)
        }
        .onChange(of: controller.selectedTab?.url) { _, newURL in
            if !isOmniboxFocused, let newURL {
                controller.omniboxText = newURL.absoluteString
            }
        }
        .onChange(of: controller.selectedTabID) { _, _ in
            if !isOmniboxFocused {
                controller.syncOmniboxToSelectedTab()
            }
            controller.syncWindowTitle()
        }
        .onChange(of: controller.selectedTab?.title) { _, _ in
            controller.syncWindowTitle()
        }
        .onChange(of: controller.multiviewTabIDs.count) { _, _ in
            controller.syncWindowTitle()
        }
    }

    @ViewBuilder
    private var topHeaderBar: some View {
        ZStack {
            WindowDragArea()

            LiquidGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    // Leading Liquid Glass navigation capsule (clears traffic lights cleanly when sidebar is collapsed)
                    HStack(spacing: 2) {
                        if !controller.isSidebarVisible {
                            AppleIconButton(
                                systemImage: "sidebar.leading",
                                helpText: "Show Sidebar (⌘⌥S)"
                            ) {
                                controller.toggleSidebar()
                            }
                        }

                        AppleIconButton(
                            systemImage: "chevron.left",
                            isDisabled: isSelectedTabPoppedOut || !(controller.selectedTab?.canGoBack ?? false),
                            helpText: "Back (⌘[)"
                        ) {
                            controller.selectedTab?.goBack()
                        }

                        AppleIconButton(
                            systemImage: "chevron.right",
                            isDisabled: isSelectedTabPoppedOut || !(controller.selectedTab?.canGoForward ?? false),
                            helpText: "Forward (⌘])"
                        ) {
                            controller.selectedTab?.goForward()
                        }

                        AppleIconButton(
                            systemImage: (controller.selectedTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise",
                            isDisabled: isSelectedTabPoppedOut,
                            helpText: (controller.selectedTab?.isLoading ?? false) ? "Stop Loading" : "Reload (⌘R)"
                        ) {
                            controller.selectedTab?.reloadOrStop()
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 32)
                    .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    .padding(
                        .leading,
                        WindowChromeLayout.collapsedNavLeadingPadding(
                            isSidebarVisible: controller.isSidebarVisible,
                            isNativeFullScreen: controller.isWindowInNativeFullScreen
                        )
                    )

                    Spacer(minLength: 6)

                    smartOmniboxPill

                    Spacer(minLength: 6)

                    // Trailing Liquid Glass control capsules
                    HStack(spacing: 6) {
                        focusModePill

                        HStack(spacing: 2) {
                            if controller.alwaysOnTop {
                                AppleIconButton(
                                    systemImage: "pin.fill",
                                    isActive: true,
                                    helpText: "Always on Top Active — Click to Unpin (⌘⌥P)"
                                ) {
                                    controller.toggleAlwaysOnTop()
                                }
                            }

                            if !shouldShowTabStrip {
                                AppleIconButton(
                                    systemImage: "plus",
                                    helpText: "New Tab (⌘T)"
                                ) {
                                    controller.createTab()
                                }
                            }

                            AppleIconButton(
                                systemImage: controller.isMultiviewActive ? "square.grid.2x2.fill" : "square.grid.2x2",
                                isActive: controller.isMultiviewActive,
                                isDisabled: controller.anyTabInFullscreen,
                                helpText: controller.isMultiviewActive ? "Exit Multiview (⌘⇧G)" : "Multiview — Watch Up to 4 Streams (⌘⇧G)"
                            ) {
                                controller.toggleMultiview()
                            }

                            AppleIconButton(
                                systemImage: controller.nowPlayingStatus.isPiP ? "pip.exit" : "pip.enter",
                                isActive: controller.nowPlayingStatus.isPiP,
                                isDisabled: !controller.nowPlayingStatus.hasVideo,
                                helpText: "Picture in Picture (⌘⇧P)"
                            ) {
                                controller.togglePictureInPicture()
                            }

                            AppleIconButton(
                                systemImage: controller.isMiniPlayer ? "arrow.down.right.and.arrow.up.left" : "rectangle.inset.bottomright.filled",
                                isActive: controller.isMiniPlayer,
                                isDisabled: !controller.isMiniPlayer && !controller.canPopOutActiveTab,
                                helpText: controller.isMiniPlayer ? "Return Floating Mini-Player (⌘⇧M)" : "Pop Out Floating Mini-Player (⌘⇧M)"
                            ) {
                                controller.toggleMiniPlayer()
                            }

                            controlsMenu
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 32)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .frame(height: WindowChromeLayout.topHeaderBarHeight)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
        .youtubeURLDropTarget(controller: controller)
    }

    @ViewBuilder
    private var focusModePill: some View {
        Button {
            controller.toggleFocusMode()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Image(systemName: controller.focusModeActive ? "eye.slash.fill" : "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                    if controller.focusModeActive {
                        Text("Focus")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
                .padding(.horizontal, controller.focusModeActive ? 11 : 9)

                Image(systemName: controller.focusModeActive ? "eye.slash.fill" : "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 9)
            }
            .foregroundStyle(
                controller.focusModeActive
                    ? AppleTheme.accent
                    : (isFocusPillHovered ? Color.primary : Color.primary.opacity(0.78))
            )
            .frame(height: 32)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: controller.focusModeActive ? AppleTheme.accent.opacity(0.20) : nil,
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isFocusPillHovered = $0 }
        .help("Focus Mode — Hide Recommendations & Comments (⌘⇧F)")
    }

    @ViewBuilder
    private var smartOmniboxPill: some View {
        let selectedMedia = controller.selectedTab?.mediaStatus
        let displayLabel: String = {
            if isSelectedTabOnHome {
                return "Search YouTube"
            }
            return controller.selectedTab?.displayTitle ?? "Search YouTube"
        }()

        Group {
            if isOmniboxFocused {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppleTheme.accent)

                    TextField("Search YouTube or paste URL…", text: $controller.omniboxText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($isOmniboxFocused)
                        .onSubmit {
                            controller.submitOmnibox()
                            isOmniboxFocused = false
                        }
                        .onExitCommand {
                            isOmniboxFocused = false
                            controller.syncOmniboxToSelectedTab()
                            controller.focusActiveWebView()
                        }

                    if !controller.omniboxText.isEmpty {
                        Button {
                            controller.omniboxText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 13)
                .frame(height: 32)
                .frame(minWidth: 110, idealWidth: 380, maxWidth: 480)
                .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accent.opacity(0.08), interactive: true)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppleTheme.accent.opacity(0.65), lineWidth: 1.2)
                )
            } else {
                Button {
                    activateOmniboxForSearch(clearInput: isSelectedTabOnHome)
                } label: {
                    HStack(spacing: 7) {
                        if selectedMedia?.isPlaying == true {
                            Image(systemName: selectedMedia?.isMuted == true ? "speaker.slash.fill" : "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedMedia?.isMuted == true ? Color.secondary : AppleTheme.accent)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(displayLabel)
                            .font(.system(size: 12.5, weight: isSelectedTabOnHome ? .regular : .medium))
                            .foregroundStyle(isSelectedTabOnHome ? Color.secondary : Color.primary.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if selectedMedia?.isHDR == true {
                            AppleHDRBadge()
                        }

                        if let rateText = selectedMedia?.formattedPlaybackRate {
                            AppleSpeedBadge(rateText: rateText)
                        }

                        if isPillHovered {
                            Text("⌘K")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .frame(minWidth: 110, idealWidth: 360, maxWidth: 450)
                    .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isPillHovered = $0 }
                .help("Edit URL (⌘L) · Command Palette & Search (⌘K)")
            }
        }
    }

    @ViewBuilder
    private var controlsMenu: some View {
        let activeRate = controller.nowPlayingStatus.playbackRate
        let hasVideo = controller.nowPlayingStatus.hasVideo

        Menu {
            Button {
                controller.toggleMultiview()
            } label: {
                Label(
                    controller.isMultiviewActive ? "Exit Multiview" : "Enter Multiview (Up to 4 Streams)",
                    systemImage: controller.isMultiviewActive ? "rectangle" : "square.grid.2x2"
                )
            }

            Button {
                controller.openYouTubeTVInMultiview()
            } label: {
                Label("Open YouTube TV in Multiview", systemImage: "tv")
            }
            .disabled(controller.isMultiviewActive && !controller.canAddMultiviewTile)

            Divider()

            Button {
                controller.toggleAlwaysOnTop()
            } label: {
                Label(
                    controller.alwaysOnTop ? "Always on Top: On" : "Always on Top",
                    systemImage: controller.alwaysOnTop ? "pin.fill" : "pin"
                )
            }

            Button {
                controller.toggleTheaterMode()
            } label: {
                Label("Toggle Theater Mode", systemImage: "rectangle.expand.vertical")
            }

            Toggle(
                "Auto Pop-Up Mini-Player on Leave",
                isOn: Binding(
                    get: { controller.settings.autoMiniPlayerOnLeave },
                    set: { controller.settings.autoMiniPlayerOnLeave = $0 }
                )
            )

            Divider()

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
                "Hide Top Web Header",
                isOn: Binding(
                    get: { controller.settings.hideWebHeader },
                    set: { controller.settings.hideWebHeader = $0 }
                )
            )

            Menu("Playback Speed") {
                Button("Increase Speed (+0.1×)") {
                    controller.stepPlaybackRate(by: 0.1)
                }
                .disabled(!hasVideo)

                Button("Decrease Speed (−0.1×)") {
                    controller.stepPlaybackRate(by: -0.1)
                }
                .disabled(!hasVideo)

                Button("Reset Speed (1×)") {
                    controller.resetPlaybackRate()
                }
                .disabled(!hasVideo)

                Divider()

                ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                    let isCurrent = hasVideo && abs(activeRate - rate) < 0.02
                    Button {
                        controller.setPlaybackRate(rate)
                    } label: {
                        if isCurrent {
                            Label(MediaStatus.formatPlaybackRate(rate), systemImage: "checkmark")
                        } else {
                            Text(MediaStatus.formatPlaybackRate(rate))
                        }
                    }
                    .disabled(!hasVideo)
                }
            }

            Divider()

            Button(controller.isCurrentPagePinned ? "Unpin Page" : "Pin Page to Sidebar") {
                controller.togglePinCurrentPage()
            }
            Button("Copy Video / Page Link") {
                controller.copyCurrentURL()
            }
            Button("Copy Link at Current Time") {
                controller.copyCurrentURLAtTime()
            }
            .disabled(!hasVideo)

            Button {
                controller.copyVideoFrame()
            } label: {
                Label("Copy Video Frame", systemImage: "camera.viewfinder")
            }
            .disabled(!hasVideo)

            Button {
                controller.saveVideoFrame()
            } label: {
                Label("Save Video Frame…", systemImage: "square.and.arrow.down")
            }
            .disabled(!hasVideo)

            Button {
                controller.shareCurrentURL()
            } label: {
                Label("Share Link…", systemImage: "square.and.arrow.up")
            }
            .disabled(controller.currentShareURL == nil)

            Button {
                controller.shareCurrentURLAtTime()
            } label: {
                Label("Share Link at Current Time…", systemImage: "clock.arrow.2.circlepath")
            }
            .disabled(controller.currentTimestampedShareURL == nil)

            Divider()

            Button("Find on Page…") {
                controller.presentFindBar()
            }
            .disabled(isSelectedTabPoppedOut)

            Button("Open in Default Browser") {
                controller.openCurrentInDefaultBrowser()
            }
            Button("Open Copied YouTube URL") {
                controller.openURLFromClipboard()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.78))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.primary)
        .frame(width: 28, height: 28)
        .help("Controls, Share & Page Actions")
    }

    @ViewBuilder
    private func poppedOutPlaceholder(for tab: BrowserTab) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accent.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: tab.mediaStatus.isPlaying ? "pip.fill" : "pause.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
            }

            VStack(spacing: 4) {
                Text(tab.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                Text(tab.mediaStatus.isPlaying ? "Playing in Floating Mini-Player" : "Paused in Floating Mini-Player")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            LiquidGlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        controller.dockMiniPlayer(selectTab: true, focusMain: true)
                    } label: {
                        Text("Return Video Here")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(AppleTheme.accent, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Label(tab.mediaStatus.isPlaying ? "Pause" : "Play", systemImage: tab.mediaStatus.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        controller.createTab(url: controller.settings.startupDestination.url, select: true)
                    } label: {
                        Text("Browse Home")
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(28)
        .appleGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
    }

    private func activateOmniboxForSearch(clearInput: Bool) {
        if clearInput {
            controller.omniboxText = ""
        } else {
            controller.syncOmniboxToSelectedTab()
        }
        isOmniboxFocused = true
        if !clearInput {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                if isOmniboxFocused {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
    }
}
