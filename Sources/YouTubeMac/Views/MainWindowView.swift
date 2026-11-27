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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isOmniboxFocused: Bool
    @State private var isPillHovered = false
    @State private var isFocusPillHovered = false
    @State private var isHeaderHovered = false
    @State private var isSidebarHovered = false
    @State private var isDrawerHovered = false
    @State private var isControlsMenuHovered = false
    @State private var isCompactTabsPopoverPresented = false
    @State private var isCompactMultiviewPopoverPresented = false
    @State private var isHeaderAddPickerPresented = false
    @State private var hoveredCompactTabID: UUID?
    @State private var hoveredCompactCloseTabID: UUID?
    @State private var headerWidth: CGFloat = 1100
    @State private var inactiveTabsContentWidth: CGFloat = 0

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
        controller.isSelectedTabPoppedOut
    }

    private var isMultiviewGridPoppedOut: Bool {
        controller.isFloatingMultiviewGrid
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
                topHeaderBar
                    .zIndex(1)
                    .opacity(shouldDimCinemaChrome && !isHeaderHovered ? 0.42 : 1.0)
                    .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isHeaderHovered)
                    .onHover { isHeaderHovered = $0 }

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if !controller.isCompactHeaderActive && shouldShowTabStrip {
                            TabStripView(controller: controller)
                                .zIndex(1)
                                .opacity(shouldDimCinemaChrome && !isHeaderHovered ? 0.42 : 1.0)
                                .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isHeaderHovered)
                                .onHover { isHeaderHovered = $0 }
                        }

                        if !controller.isCompactHeaderActive && controller.isMultiviewActive && !controller.anyTabInFullscreen {
                            MultiviewControlBar(controller: controller)
                        }

                        if !controller.isCompactHeaderActive && shouldShowCompactHomeShelf {
                            HomeShelfBarView(controller: controller)
                        }

                        if controller.isLivePulseTickerRendered, let livePulseStore = controller.livePulseStore {
                            LivePulseTickerBar(
                                controller: controller,
                                store: livePulseStore,
                                isFrozen: controller.hasLiveFullscreenTab
                            )
                            .opacity(shouldDimCinemaChrome && !isHeaderHovered ? 0.42 : 1.0)
                            .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isHeaderHovered)
                            .onHover { isHeaderHovered = $0 }
                        }

                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)

                            if let tab = controller.selectedTab, tab.isLoading {
                                GeometryReader { proxy in
                                    Rectangle()
                                        .fill(AppleTheme.accentText)
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
                                poppedOutTabIDs: controller.poppedOutTabIDs,
                                anyTabInFullscreen: controller.hasLiveFullscreenTab,
                                multiviewTabIDs: controller.multiviewTabIDs,
                                soloMultiviewTabID: controller.soloMultiviewTabID,
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

                            if controller.isMultiviewActive && !controller.hasLiveFullscreenTab && !isMultiviewGridPoppedOut {
                                MultiviewOverlayView(controller: controller)
                            }

                            if shouldShowHiddenHomeRecovery {
                                HiddenHomeFeedRecoveryView(controller: controller)
                            } else if shouldShowPopulatedHomeDashboard {
                                PopulatedHomeDashboardView(controller: controller)
                            }

                            if !controller.isMultiviewActive,
                               !controller.hasLiveFullscreenTab,
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

                            if isMultiviewGridPoppedOut {
                                poppedOutMultiviewPlaceholder
                            } else if isSelectedTabPoppedOut, let poppedTab = controller.poppedOutTab {
                                poppedOutPlaceholder(for: poppedTab)
                            }

                            if let toast = controller.activeToast {
                                VStack {
                                    AppleHUDToast(toast: toast)
                                        .padding(.top, AppSpacing.lg)
                                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                    Spacer()
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if controller.isFindBarPresented && !controller.anyTabInFullscreen && !isSelectedTabPoppedOut {
                                FindBarView(controller: controller)
                                    .padding(.top, AppSpacing.md)
                                    .padding(.trailing, AppSpacing.lg)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppleTheme.canvasColor)

                    let effectiveDrawerWidth = controller.effectiveLivePulseDrawerWidth()
                    if controller.isLivePulseDrawerVisible,
                       effectiveDrawerWidth >= LivePulseLayout.drawerMinWidth,
                       let livePulseStore = controller.livePulseStore {
                        CompanionDrawerDividerNSView(
                            currentWidth: effectiveDrawerWidth,
                            isFrozen: controller.hasLiveFullscreenTab,
                            onDragWidthChanged: { newWidth in
                                controller.updateLivePulseDrawerWidth(newWidth)
                            },
                            onDoubleClickReset: {
                                controller.resetLivePulseDrawerWidth()
                            }
                        )
                        .frame(width: LivePulseLayout.drawerDividerWidth)

                        LiveCompanionDrawerView(
                            controller: controller,
                            store: livePulseStore,
                            isFrozen: controller.hasLiveFullscreenTab
                        )
                        .frame(width: effectiveDrawerWidth)
                        .opacity(shouldDimCinemaChrome && !isDrawerHovered ? 0.42 : 1.0)
                        .animation(.easeInOut(duration: 0.22), value: shouldDimCinemaChrome && !isDrawerHovered)
                        .onHover { isDrawerHovered = $0 }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppleTheme.canvasColor)
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
        .sheet(isPresented: $controller.isOnboardingPresented) {
            StreamingOnboardingView(controller: controller)
                .environment(\.font, AppFont.body)
                .preferredColorScheme(controller.settings.preferredColorScheme)
                .tint(AppleTheme.accentText)
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                controller.presentStreamingOnboardingIfNeeded()
            }
        }
        .onExitCommand {
            guard controller.isMultiviewSoloActive,
                  !isOmniboxFocused,
                  !controller.isFindBarPresented,
                  !controller.isCommandPalettePresented,
                  !controller.isOnboardingPresented,
                  !controller.anyTabInFullscreen else {
                return
            }
            if let responder = controller.mainWindow?.firstResponder, responder is NSTextView {
                return
            }
            controller.exitMultiviewSolo()
        }
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
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.selectedTabID) { _, _ in
            if !isOmniboxFocused {
                controller.syncOmniboxToSelectedTab()
            }
            controller.syncWindowTitle()
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.selectedTab?.title) { _, _ in
            controller.syncWindowTitle()
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.multiviewTabIDs.count) { _, _ in
            controller.syncWindowTitle()
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.selectedTab?.mediaStatus.isPlaying) { _, _ in
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.selectedTab?.mediaStatus.title) { _, _ in
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.selectedTab?.mediaStatus.streamContext) { _, _ in
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.multiviewAudioTabID) { _, _ in
            controller.syncLivePulseStreamSignals()
        }
        .onChange(of: controller.isCompactHeaderActive) { _, isCompact in
            if !isCompact {
                isCompactTabsPopoverPresented = false
                isCompactMultiviewPopoverPresented = false
            }
        }
        .onChange(of: controller.isMultiviewActive) { _, isMultiview in
            if !isMultiview {
                isCompactMultiviewPopoverPresented = false
            }
        }
        .onChange(of: controller.hasLiveFullscreenTab) { _, isFullscreen in
            if isFullscreen {
                isCompactTabsPopoverPresented = false
                isCompactMultiviewPopoverPresented = false
            }
        }
    }

    @ViewBuilder
    private var topHeaderBar: some View {
        let isCompact = controller.isCompactHeaderActive
        let foldSecondaryControls = isCompact && CompactHeaderLayout.shouldFoldSecondaryControls(headerWidth: headerWidth)
        let horizontalGutterWidth = isCompact ? CompactHeaderLayout.minDragGutterWidth : AppSpacing.sm

        ZStack {
            WindowDragArea()

            LiquidGlassGroup(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    // Leading Liquid Glass navigation capsule (clears traffic lights cleanly when sidebar is collapsed)
                    HStack(spacing: AppSpacing.xxs) {
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
                    .padding(.horizontal, AppSpacing.xs)
                    .frame(height: 32)
                    .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    .padding(
                        .leading,
                        WindowChromeLayout.collapsedNavLeadingPadding(
                            isSidebarVisible: controller.isSidebarVisible,
                            isNativeFullScreen: controller.isWindowInNativeFullScreen
                        )
                    )

                    Spacer(minLength: horizontalGutterWidth)

                    if isCompact {
                        compactCenterRail
                    } else {
                        smartOmniboxPill()
                    }

                    Spacer(minLength: horizontalGutterWidth)

                    // Trailing Liquid Glass control capsules
                    HStack(spacing: AppSpacing.sm) {
                        cleanBoxTogglePill

                        focusModePill

                        if isCompact && controller.isMultiviewActive && !controller.anyTabInFullscreen {
                            compactMultiviewPill
                        }

                        HStack(spacing: AppSpacing.xxs) {
                            if controller.alwaysOnTop {
                                AppleIconButton(
                                    systemImage: "pin.fill",
                                    isActive: true,
                                    helpText: "Always on Top Active — Click to Unpin (⌘⌥P)"
                                ) {
                                    controller.toggleAlwaysOnTop()
                                }
                            }

                            if !isCompact && !shouldShowTabStrip {
                                headerAddButton(standaloneGlass: false)
                            }

                            AppleIconButton(
                                systemImage: controller.isMultiviewActive ? "square.grid.2x2.fill" : "square.grid.2x2",
                                isActive: controller.isMultiviewActive,
                                isDisabled: controller.hasLiveFullscreenTab,
                                helpText: controller.isMultiviewActive ? "Exit Multiview (⌘⇧G)" : "Multiview — Watch Up to 4 Streams (⌘⇧G)"
                            ) {
                                controller.toggleMultiview()
                            }

                            if !foldSecondaryControls {
                                AppleIconButton(
                                    systemImage: controller.nowPlayingStatus.isPiP ? "pip.exit" : "pip.enter",
                                    isActive: controller.nowPlayingStatus.isPiP,
                                    isDisabled: !controller.nowPlayingStatus.hasVideo,
                                    helpText: "Picture in Picture (⌘⇧P)"
                                ) {
                                    controller.togglePictureInPicture()
                                }
                            }

                            AppleIconButton(
                                systemImage: controller.isMiniPlayer ? "arrow.down.right.and.arrow.up.left" : "rectangle.inset.bottomright.filled",
                                isActive: controller.isMiniPlayer,
                                isDisabled: !controller.isMiniPlayer && !controller.canPopOutActiveContent,
                                helpText: controller.isMiniPlayer
                                    ? (controller.isFloatingMultiviewGrid ? "Return Floating Grid (⌘⇧M)" : "Return Floating Mini-Player (⌘⇧M)")
                                    : (controller.isMultiviewActive ? "Float Multiview Grid (⌘⇧M)" : "Pop Out Floating Mini-Player (⌘⇧M)")
                            ) {
                                controller.toggleMiniPlayer()
                            }

                            if !foldSecondaryControls {
                                AppleIconButton(
                                    systemImage: "airplayvideo",
                                    isActive: controller.isAirPlayActive || controller.isAirPlayPopoverPresented,
                                    isDisabled: controller.hasLiveFullscreenTab,
                                    helpText: "AirPlay & TV Displays"
                                ) {
                                    controller.openAirPlayPopover()
                                }
                                .popover(isPresented: $controller.isAirPlayPopoverPresented, arrowEdge: .bottom) {
                                    AirPlayPopoverView(
                                        controller: controller,
                                        onDismiss: { controller.isAirPlayPopoverPresented = false }
                                    )
                                    .environment(\.font, AppFont.body)
                                }
                            }

                            if controller.settings.livePulseEnabled {
                                AppleIconButton(
                                    systemImage: controller.isLivePulseDrawerVisible ? "sportscourt.fill" : "sportscourt",
                                    isActive: controller.isLivePulseDrawerVisible || controller.isLivePulseTickerRendered,
                                    isDisabled: controller.hasLiveFullscreenTab,
                                    helpText: "Live Pulse Drawer (⌘⌥I) · Right-Click for Ticker"
                                ) {
                                    controller.toggleLivePulseDrawer()
                                }
                                .contextMenu {
                                    Button(controller.isLivePulseTickerRendered ? "Hide Live Pulse Ticker" : "Show Live Pulse Ticker") {
                                        controller.toggleLivePulseTicker()
                                    }
                                    Button(controller.isLivePulseDrawerVisible ? "Hide Live Companion Drawer" : "Show Live Companion Drawer") {
                                        controller.toggleLivePulseDrawer()
                                    }
                                }
                            }

                            AppleIconButton(
                                systemImage: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                                isActive: isCompact,
                                isDisabled: controller.hasLiveFullscreenTab,
                                helpText: isCompact ? "Expand Header Bars (⌘⌥\\)" : "Minimize Header to 1 Row (⌘⌥\\)"
                            ) {
                                controller.toggleCompactHeaderMode()
                            }

                            if foldSecondaryControls {
                                controlsMenu
                                    .popover(isPresented: $controller.isAirPlayPopoverPresented, arrowEdge: .bottom) {
                                        AirPlayPopoverView(
                                            controller: controller,
                                            onDismiss: { controller.isAirPlayPopoverPresented = false }
                                        )
                                        .environment(\.font, AppFont.body)
                                    }
                            } else {
                                controlsMenu
                            }
                        }
                        .padding(.horizontal, AppSpacing.xs)
                        .frame(height: 32)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                    }
                    .padding(.trailing, AppSpacing.lg)
                }
            }
        }
        .frame(height: WindowChromeLayout.topHeaderBarHeight)
        .background {
            ZStack {
                AppleTheme.canvasColor
                HolidayAmbientGlowView(
                    surface: .headerBar,
                    isPaused: controller.hasLiveFullscreenTab || controller.focusModeActive
                )
                HolidayParticlesView(
                    palette: controller.settings.activeHolidayPalette,
                    intensity: controller.settings.holidayEffectsIntensity,
                    surface: .headerBar,
                    isHardStopped: controller.hasLiveFullscreenTab || controller.focusModeActive || reduceMotion
                )
            }
            .clipped()
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { headerWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in
                        headerWidth = w
                    }
            }
        )
        .youtubeURLDropTarget(controller: controller)
    }

    @ViewBuilder
    private var compactCenterRail: some View {
        let inactiveTabs = controller.tabs.filter { $0.id != controller.selectedTabID }
        if controller.tabs.count <= 1 {
            HStack(spacing: AppSpacing.sm) {
                smartOmniboxPill(
                    minWidth: CompactHeaderLayout.minActiveOmniboxWidth,
                    idealWidth: 360,
                    maxWidth: 460
                )
                headerAddButton(standaloneGlass: true)
            }
        } else if CompactHeaderLayout.shouldCollapseInactiveTabs(headerWidth: headerWidth, tabCount: controller.tabs.count) {
            HStack(spacing: AppSpacing.sm) {
                compactTabsCollapseButton
                smartOmniboxPill(
                    minWidth: CompactHeaderLayout.minActiveOmniboxWidth,
                    idealWidth: 240,
                    maxWidth: 340
                )
                headerAddButton(standaloneGlass: true)
            }
        } else {
            HStack(spacing: AppSpacing.sm) {
                smartOmniboxPill(
                    minWidth: CompactHeaderLayout.minActiveOmniboxWidth,
                    idealWidth: 260,
                    maxWidth: 340
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(inactiveTabs) { tab in
                            compactInactiveTabPill(for: tab)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { inactiveTabsContentWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, w in
                                    inactiveTabsContentWidth = w
                                }
                        }
                    )
                }
                .frame(height: CompactHeaderLayout.compactTabHeight)
                .frame(
                    minWidth: inactiveTabsContentWidth > 0 ? min(inactiveTabsContentWidth, 76) : 0,
                    maxWidth: inactiveTabsContentWidth > 0 ? inactiveTabsContentWidth : nil
                )

                headerAddButton(standaloneGlass: true)
            }
        }
    }

    @ViewBuilder
    private func headerAddButton(standaloneGlass: Bool) -> some View {
        let button = AppleIconButton(
            systemImage: "plus",
            isActive: isHeaderAddPickerPresented,
            helpText: "Add to Grid, Open Service, or New Tab (⌘T)"
        ) {
            isHeaderAddPickerPresented.toggle()
        }

        Group {
            if standaloneGlass {
                button
                    .frame(width: CompactHeaderLayout.compactTabHeight, height: CompactHeaderLayout.compactTabHeight)
                    .appleGlass(in: Circle(), interactive: true)
            } else {
                button
            }
        }
        .popover(isPresented: $isHeaderAddPickerPresented, arrowEdge: .bottom) {
            AddScreenServicePickerPopover(
                controller: controller,
                initialMode: .addToGrid,
                onDismiss: { isHeaderAddPickerPresented = false }
            )
            .environment(\.font, AppFont.body)
        }
    }

    @ViewBuilder
    private var compactTabsCollapseButton: some View {
        Button {
            isCompactTabsPopoverPresented.toggle()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "square.on.square")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                Text("\(controller.tabs.count) Tabs")
                    .font(AppFont.callout(weight: .semibold, tabular: true))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, AppSpacing.md)
            .frame(height: CompactHeaderLayout.compactTabHeight)
            .appleGlass(in: Capsule(style: .continuous), interactive: true)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show All Open Tabs")
        .popover(isPresented: $isCompactTabsPopoverPresented, arrowEdge: .bottom) {
            CompactTabsPopoverView(
                controller: controller,
                onDismiss: { isCompactTabsPopoverPresented = false }
            )
            .environment(\.font, AppFont.body)
        }
    }

    @ViewBuilder
    private var compactMultiviewPill: some View {
        if controller.isMultiviewSoloActive {
            Button {
                controller.exitMultiviewSolo()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(AppIconFont.sm(weight: .semibold))
                    Text("Back")
                        .font(AppFont.callout(weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.md)
                .frame(height: CompactHeaderLayout.compactTabHeight)
                .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Return to Multiview Grid (Esc / ⌘⌥Z)")
        } else {
            let count = controller.multiviewTabs.count
            Button {
                isCompactMultiviewPopoverPresented.toggle()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                    Text(count == 4 ? "Quad" : "\(count)")
                        .font(AppFont.callout(weight: .semibold, tabular: true))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, AppSpacing.md)
                .frame(height: CompactHeaderLayout.compactTabHeight)
                .appleGlass(
                    in: Capsule(style: .continuous),
                    tint: AppleTheme.accentText.opacity(0.14),
                    interactive: true
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Multiview Layout & Controls")
            .popover(isPresented: $isCompactMultiviewPopoverPresented, arrowEdge: .bottom) {
                MultiviewCompactControlsPopover(
                    controller: controller,
                    onDismiss: { isCompactMultiviewPopoverPresented = false }
                )
                .environment(\.font, AppFont.body)
            }
        }
    }

    @ViewBuilder
    private func compactInactiveTabPill(for tab: BrowserTab) -> some View {
        let isHovered = hoveredCompactTabID == tab.id
        let multiviewSlot = controller.multiviewSlotNumber(for: tab.id)
        let isMultiviewAudio = controller.isMultiviewActive && controller.multiviewAudioTab?.id == tab.id
        let isInteractiveMuteLeading = !controller.isTabPoppedOut(tab.id)
            && tab.mediaStatus.hasVideo
            && (tab.mediaStatus.isPlaying || tab.mediaStatus.isMuted)

        HStack(spacing: AppSpacing.xs) {
            if let multiviewSlot {
                Text("\(multiviewSlot)")
                    .font(AppFont.micro(weight: .bold, tabular: true))
                    .foregroundStyle(isMultiviewAudio ? .white : .primary)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(isMultiviewAudio ? AppleTheme.accentFill : Color.primary.opacity(0.12))
                    )
            }

            compactTabLeadingIcon(for: tab)

            Text(tab.displayTitle)
                .font(AppFont.callout(weight: .regular))
                .foregroundStyle(tab.isSleeping ? AppleTheme.textMuted : Color.primary.opacity(0.84))
                .lineLimit(1)
                .truncationMode(.tail)

            if isHovered && controller.tabs.count > 1 {
                let isCloseHovered = hoveredCompactCloseTabID == tab.id
                Button {
                    controller.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(AppIconFont.xs(weight: .bold))
                        .foregroundStyle(isCloseHovered ? Color.primary : AppleTheme.textSecondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(isCloseHovered ? 0.18 : 0.09)))
                        .minHitTarget(24, shape: Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredCompactCloseTabID = hovering ? tab.id : (hoveredCompactCloseTabID == tab.id ? nil : hoveredCompactCloseTabID)
                }
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.leading, isInteractiveMuteLeading ? AppSpacing.xs : AppSpacing.md)
        .padding(.trailing, isHovered ? AppSpacing.xs : AppSpacing.md)
        .frame(height: CompactHeaderLayout.compactTabHeight)
        .frame(maxWidth: CompactHeaderLayout.maxInactiveTabWidth)
        .appleGlass(
            in: Capsule(style: .continuous),
            tint: multiviewSlot != nil
                ? AppleTheme.accentText.opacity(isHovered ? 0.14 : 0.08)
                : (isHovered ? Color.primary.opacity(0.06) : nil),
            interactive: true
        )
        .contentShape(Capsule(style: .continuous))
        .overlay(
            CompactTabMiddleClickDetector {
                if controller.tabs.count > 1 && !controller.anyTabInFullscreen {
                    controller.closeTab(id: tab.id)
                }
            }
        )
        .onTapGesture {
            controller.selectTab(id: tab.id)
        }
        .onHover { hovering in
            hoveredCompactTabID = hovering ? tab.id : (hoveredCompactTabID == tab.id ? nil : hoveredCompactTabID)
        }
        .contextMenu {
            Button("Switch to Tab") {
                controller.selectTab(id: tab.id)
            }
            if tab.mediaStatus.hasVideo {
                Button(tab.mediaStatus.isMuted ? "Unmute Tab" : "Mute Tab") {
                    controller.toggleMute(tabID: tab.id)
                }
            }
            if controller.isTabInMultiview(tab.id) {
                Button("Remove from Multiview") {
                    controller.removeTileFromMultiview(id: tab.id)
                }
            } else if !controller.isMultiviewActive || controller.canAddMultiviewTile {
                Button(controller.isMultiviewActive ? "Add to Multiview" : "Open in Multiview") {
                    controller.addExistingTabToMultiview(id: tab.id)
                }
            }
            Button("Open in New Window") {
                controller.openTabInNewWindow(id: tab.id)
            }
            if controller.isTabPoppedOut(tab.id) {
                Button(controller.isFloatingMultiviewGrid ? "Return Floating Grid to Window" : "Return Mini-Player to Tab") {
                    controller.dockMiniPlayer(selectTab: true, focusMain: false)
                }
            } else if controller.canPopOut(tab: tab) {
                Button("Pop Out to Mini-Player") {
                    controller.popOutToMiniPlayer(tab: tab, reason: .manual)
                }
            }
            let showCleanBoxAction = controller.settings.cleanBoxStreamingPlayers
                && (tab.mediaStatus.isCleanBoxActive || tab.isCleanBoxBypassed)
            if showCleanBoxAction {
                Button(tab.isCleanBoxBypassed ? "Clean-Box Video" : "Show Full Page") {
                    controller.toggleCleanBox(forTabID: tab.id)
                }
            }
            if controller.canPutTabToSleep(id: tab.id) {
                Button("Put Tab to Sleep") {
                    controller.putTabToSleep(id: tab.id)
                }
            }
            Divider()
            Button("Duplicate Tab") {
                controller.duplicateTab(id: tab.id)
            }
            if controller.tabs.count > 1 {
                Divider()
                Button("Close Tab") {
                    controller.closeTab(id: tab.id)
                }
                Button("Close Other Tabs") {
                    controller.closeOtherTabs(keepingID: tab.id)
                }
            }
        }
    }

    @ViewBuilder
    private func compactTabLeadingIcon(for tab: BrowserTab) -> some View {
        if controller.isTabPoppedOut(tab.id) {
            Image(systemName: "pip.fill")
                .font(AppIconFont.xs(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)
        } else if tab.mediaStatus.hasVideo && (tab.mediaStatus.isPlaying || tab.mediaStatus.isMuted) {
            Button {
                controller.toggleMute(tabID: tab.id)
            } label: {
                Image(systemName: tab.mediaStatus.isMuted ? "speaker.slash.fill" : "waveform")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(tab.mediaStatus.isMuted ? AppleTheme.textSecondary : AppleTheme.accentText)
                    .minHitTarget(24, shape: Circle())
            }
            .buttonStyle(.plain)
            .help(tab.mediaStatus.isMuted ? "Unmute Tab" : "Mute Tab")
        } else if tab.isSleeping {
            Image(systemName: "moon.zzz")
                .font(AppIconFont.xs(weight: .medium))
                .foregroundStyle(AppleTheme.textMuted)
        } else if tab.isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
        } else {
            Image(systemName: tab.isCompanionTab ? "globe" : "play.rectangle")
                .font(AppIconFont.xs(weight: .medium))
                .foregroundStyle(AppleTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var cleanBoxTogglePill: some View {
        if controller.settings.cleanBoxStreamingPlayers,
           let tab = controller.selectedTab,
           !controller.isMultiviewActive,
           tab.routingMode == .companion,
           tab.mediaStatus.isCleanBoxActive || tab.isCleanBoxBypassed {
            let isCleanActive = !tab.isCleanBoxBypassed
            Button {
                controller.toggleCleanBoxForActiveTab()
            } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: isCleanActive ? "rectangle.expand.diagonal" : "rectangle.inset.filled")
                            .font(AppIconFont.sm(weight: .semibold))
                        Text(isCleanActive ? "Full Page" : "Clean-Box")
                            .font(AppFont.callout(weight: .semibold))
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    Image(systemName: isCleanActive ? "rectangle.expand.diagonal" : "rectangle.inset.filled")
                        .font(AppIconFont.sm(weight: .semibold))
                        .padding(.horizontal, AppSpacing.md)
                }
                .foregroundStyle(isCleanActive ? Color.primary.opacity(0.86) : AppleTheme.accentText)
                .frame(height: 32)
                .appleGlass(
                    in: Capsule(style: .continuous),
                    tint: isCleanActive ? nil : AppleTheme.accentText.opacity(0.18),
                    interactive: true
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isCleanActive ? "Show Full Service Page (⌘⇧B)" : "Restore Clean-Box Video Player (⌘⇧B)")
        }
    }

    @ViewBuilder
    private var focusModePill: some View {
        Button {
            controller.toggleFocusMode()
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: controller.focusModeActive ? "eye.slash.fill" : "sparkles")
                        .font(AppIconFont.sm(weight: .semibold))
                    if controller.focusModeActive {
                        Text("Focus")
                            .font(AppFont.callout(weight: .semibold))
                    }
                }
                .padding(.horizontal, controller.focusModeActive ? AppSpacing.lg : AppSpacing.md)

                Image(systemName: controller.focusModeActive ? "eye.slash.fill" : "sparkles")
                    .font(AppIconFont.sm(weight: .semibold))
                    .padding(.horizontal, AppSpacing.md)
            }
            .foregroundStyle(
                controller.focusModeActive
                    ? AppleTheme.accentText
                    : (isFocusPillHovered ? Color.primary : Color.primary.opacity(0.80))
            )
            .frame(height: 32)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: controller.focusModeActive ? AppleTheme.accentText.opacity(0.20) : nil,
                interactive: true
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isFocusPillHovered = $0 }
        .help("Focus Mode — Hide Recommendations & Comments (⌘⇧F)")
    }

    @ViewBuilder
    private func smartOmniboxPill(
        minWidth: CGFloat = 136,
        idealWidth: CGFloat = 360,
        maxWidth: CGFloat = 460
    ) -> some View {
        let selectedMedia = controller.selectedTab?.mediaStatus
        let selectedSlot: Int? = {
            guard controller.isCompactHeaderActive || controller.tabs.count > 1 else {
                return nil
            }
            return controller.multiviewSlotNumber(for: controller.selectedTabID)
        }()
        let isSelectedMultiviewAudio = controller.isMultiviewActive
            && controller.multiviewAudioTab?.id == controller.selectedTabID
        let displayLabel: String = {
            if isSelectedTabOnHome {
                return "Search YouTube"
            }
            return controller.selectedTab?.displayTitle ?? "Search YouTube"
        }()

        Group {
            if isOmniboxFocused {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(AppIconFont.md(weight: .medium))
                        .foregroundStyle(AppleTheme.accentText)

                    TextField("Search YouTube or paste URL…", text: $controller.omniboxText)
                        .textFieldStyle(.plain)
                        .font(AppFont.body)
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
                                .font(AppIconFont.md)
                                .foregroundStyle(AppleTheme.textMuted)
                                .minHitTarget(24, shape: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .frame(height: 32)
                .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth)
                .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accentText.opacity(0.08), interactive: true)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppleTheme.accentText.opacity(0.65), lineWidth: 1.2)
                )
            } else {
                Button {
                    activateOmniboxForSearch(clearInput: isSelectedTabOnHome)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if let selectedSlot {
                            Text("\(selectedSlot)")
                                .font(AppFont.micro(weight: .bold, tabular: true))
                                .foregroundStyle(isSelectedMultiviewAudio ? .white : .primary)
                                .frame(width: 16, height: 16)
                                .background(
                                    Circle()
                                        .fill(isSelectedMultiviewAudio ? AppleTheme.accentFill : Color.primary.opacity(0.12))
                                )
                        }

                        if selectedMedia?.isPlaying == true {
                            Image(systemName: selectedMedia?.isMuted == true ? "speaker.slash.fill" : "waveform")
                                .font(AppIconFont.md(weight: .semibold))
                                .foregroundStyle(selectedMedia?.isMuted == true ? AppleTheme.textSecondary : AppleTheme.accentText)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(AppIconFont.md(weight: .medium))
                                .foregroundStyle(AppleTheme.textSecondary)
                        }

                        Text(displayLabel)
                            .font(AppFont.body(weight: isSelectedTabOnHome ? .regular : .medium))
                            .foregroundStyle(isSelectedTabOnHome ? AppleTheme.textSecondary : Color.primary.opacity(0.9))
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
                                .font(AppFont.micro(weight: .medium, tabular: true))
                                .foregroundStyle(AppleTheme.textSecondary)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, AppSpacing.xxs)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                    }
                    .padding(.leading, selectedSlot != nil ? AppSpacing.sm : AppSpacing.lg)
                    .padding(.trailing, AppSpacing.lg)
                    .frame(height: 32)
                    .frame(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth)
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

            Button {
                controller.toggleCompactHeaderMode()
            } label: {
                Label(
                    controller.isCompactHeaderActive ? "Expand Header Bars" : "Minimize Header to 1 Row",
                    systemImage: controller.isCompactHeaderActive ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
            }
            .disabled(controller.hasLiveFullscreenTab)

            Button {
                controller.togglePictureInPicture()
            } label: {
                Label(
                    controller.nowPlayingStatus.isPiP ? "Exit Picture in Picture" : "Picture in Picture",
                    systemImage: controller.nowPlayingStatus.isPiP ? "pip.exit" : "pip.enter"
                )
            }
            .disabled(!hasVideo)

            Button {
                controller.openAirPlayPopover()
            } label: {
                Label("AirPlay & TV Displays…", systemImage: "airplayvideo")
            }
            .disabled(controller.hasLiveFullscreenTab)

            Divider()

            Button {
                controller.toggleLivePulseTicker()
            } label: {
                Label(
                    controller.isLivePulseTickerRendered ? "Hide Live Pulse Ticker" : "Show Live Pulse Ticker",
                    systemImage: controller.isLivePulseTickerRendered ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg.rectangle"
                )
            }
            .disabled(controller.hasLiveFullscreenTab)

            Button {
                controller.toggleLivePulseDrawer()
            } label: {
                Label(
                    controller.isLivePulseDrawerVisible ? "Hide Live Pulse Drawer" : "Show Live Pulse Drawer",
                    systemImage: controller.isLivePulseDrawerVisible ? "sportscourt.fill" : "sportscourt"
                )
            }
            .disabled(controller.hasLiveFullscreenTab)

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

            let calendarHolidayPalette = HolidayThemeCatalog.palette(for: controller.settings.calendarHolidayThemeID)
            Menu("Holiday Theme") {
                Button {
                    controller.setHolidayThemeSelection(.auto)
                } label: {
                    let autoTitle = "Auto (\(calendarHolidayPalette.shortName))"
                    if controller.settings.holidayThemeSelection == .auto {
                        Label(autoTitle, systemImage: "checkmark")
                    } else {
                        Text(autoTitle)
                    }
                }

                Divider()

                ForEach(HolidayThemeSelection.allCases.filter { $0 != .auto }) { selection in
                    Button {
                        controller.setHolidayThemeSelection(selection)
                    } label: {
                        if controller.settings.holidayThemeSelection == selection {
                            Label(selection.title, systemImage: "checkmark")
                        } else {
                            Text(selection.title)
                        }
                    }
                }

                Divider()

                Menu("Ambient Effects") {
                    ForEach(HolidayEffectsIntensity.allCases) { intensity in
                        Button {
                            controller.setHolidayEffectsIntensity(intensity)
                        } label: {
                            if controller.settings.holidayEffectsIntensity == intensity {
                                Label(intensity.title, systemImage: "checkmark")
                            } else {
                                Text(intensity.title)
                            }
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
                "Clean-Box Service Players",
                isOn: Binding(
                    get: { controller.settings.cleanBoxStreamingPlayers },
                    set: { controller.settings.cleanBoxStreamingPlayers = $0 }
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
                .font(AppIconFont.toolbar)
                .foregroundStyle(isControlsMenuHovered ? Color.primary : Color.primary.opacity(0.80))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isControlsMenuHovered ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.primary)
        .frame(width: 28, height: 28)
        .onHover { isControlsMenuHovered = $0 }
        .help("Controls, Share & Page Actions")
    }

    @ViewBuilder
    private func poppedOutPlaceholder(for tab: BrowserTab) -> some View {
        GlassRecoveryCard(
            systemImage: tab.mediaStatus.isPlaying ? "pip.fill" : "pause.circle.fill",
            title: tab.displayTitle,
            message: tab.mediaStatus.isPlaying ? "Playing in Floating Mini-Player" : "Paused in Floating Mini-Player",
            messageLineLimit: 2,
            primaryAction: GlassRecoveryAction(
                "Return Video Here",
                systemImage: "arrow.down.right.and.arrow.up.left"
            ) {
                controller.dockMiniPlayer(selectTab: true, focusMain: true)
            },
            secondaryActions: [
                GlassRecoveryAction(
                    tab.mediaStatus.isPlaying ? "Pause" : "Play",
                    systemImage: tab.mediaStatus.isPlaying ? "pause.fill" : "play.fill"
                ) {
                    controller.togglePlayPause()
                },
                GlassRecoveryAction("Browse Home") {
                    controller.createTab(url: controller.settings.startupDestination.url, select: true)
                }
            ]
        )
    }

    @ViewBuilder
    private var poppedOutMultiviewPlaceholder: some View {
        let tabs = controller.multiviewTabs
        GlassRecoveryCard(
            systemImage: "pip.fill",
            title: "Multiview Grid in Floating Mini-Player",
            message: "\(tabs.count) streams active (\(controller.multiviewLayoutMode.title)) · Click a stream to switch audio",
            primaryAction: GlassRecoveryAction(
                "Return Grid Here",
                systemImage: "arrow.down.right.and.arrow.up.left"
            ) {
                controller.dockMiniPlayer(selectTab: true, focusMain: true)
            },
            secondaryActions: [
                GlassRecoveryAction("Mute All", systemImage: "speaker.slash.fill") {
                    controller.muteAllMultiviewTiles()
                },
                GlassRecoveryAction("Exit Multiview") {
                    controller.dockMiniPlayer(selectTab: true, focusMain: true)
                    controller.exitMultiview()
                }
            ]
        ) {
            if !tabs.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let isAudio = controller.multiviewAudioTabID == tab.id && !tab.mediaStatus.isMuted
                        Button {
                            controller.focusMultiviewAudio(tabID: tab.id, showFeedback: false)
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                Text("\(index + 1)")
                                    .font(AppFont.micro(weight: .bold, tabular: true))
                                Image(systemName: isAudio ? "waveform" : "speaker.slash.fill")
                                    .font(AppIconFont.xs(weight: .semibold))
                                Text(tab.displayTitle)
                                    .font(AppFont.caption(weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isAudio ? .white : Color.primary.opacity(0.86))
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .minHitTarget(24, shape: Capsule(style: .continuous))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isAudio ? AppleTheme.accentFill : Color.primary.opacity(0.08))
                            )
                            .frame(maxWidth: 160)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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

/// Strictly middle-click-only detector for compact inline header tab pills.
private final class CompactTabMiddleClickNSView: NSView {
    var onMiddleClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let eventType = NSApp.currentEvent?.type,
              eventType == .otherMouseDown || eventType == .otherMouseUp else {
            return nil
        }
        return super.hitTest(point)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            return
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onMiddleClick?()
            return
        }
        super.otherMouseUp(with: event)
    }
}

private struct CompactTabMiddleClickDetector: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> CompactTabMiddleClickNSView {
        let view = CompactTabMiddleClickNSView(frame: .zero)
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: CompactTabMiddleClickNSView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }
}

/// Popover listing all open tabs when narrow Split Screen collapses inline tabs in Compact Single-Row Header mode.
private struct CompactTabsPopoverView: View {
    @Bindable var controller: AppController
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Text("Open Tabs")
                    .font(AppFont.body(weight: .semibold))
                Spacer()
                Text("\(controller.tabs.count)")
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(controller.tabs) { tab in
                        let isSelected = tab.id == controller.selectedTabID
                        let multiviewSlot = controller.multiviewSlotNumber(for: tab.id)
                        let isMultiviewAudio = controller.isMultiviewActive && controller.multiviewAudioTab?.id == tab.id
                        let hasMediaControls = !controller.isTabPoppedOut(tab.id)
                            && tab.mediaStatus.hasVideo
                            && (tab.mediaStatus.isPlaying || tab.mediaStatus.isMuted)

                        HStack(spacing: AppSpacing.sm) {
                            Button {
                                controller.selectTab(id: tab.id)
                                onDismiss()
                            } label: {
                                HStack(spacing: AppSpacing.sm) {
                                    if let multiviewSlot {
                                        Text("\(multiviewSlot)")
                                            .font(AppFont.micro(weight: .bold, tabular: true))
                                            .foregroundStyle(isMultiviewAudio ? .white : .primary)
                                            .frame(width: 16, height: 16)
                                            .background(
                                                Circle()
                                                    .fill(isMultiviewAudio ? AppleTheme.accentFill : Color.primary.opacity(0.12))
                                            )
                                    } else {
                                        Image(systemName: tabIconName(for: tab))
                                            .font(AppIconFont.sm(weight: .medium))
                                            .foregroundStyle(tabIconColor(for: tab))
                                            .frame(width: 16, alignment: .center)
                                    }

                                    Text(tab.displayTitle)
                                        .font(AppFont.callout(weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(tab.isSleeping ? AppleTheme.textMuted : .primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer(minLength: AppSpacing.xs)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(AppIconFont.xs(weight: .semibold))
                                            .foregroundStyle(AppleTheme.accentText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if hasMediaControls {
                                Button {
                                    controller.toggleMute(tabID: tab.id)
                                } label: {
                                    Image(systemName: tab.mediaStatus.isMuted ? "speaker.slash.fill" : "waveform")
                                        .font(AppIconFont.xs(weight: .semibold))
                                        .foregroundStyle(tab.mediaStatus.isMuted ? AppleTheme.textSecondary : AppleTheme.accentText)
                                        .minHitTarget(24, shape: Circle())
                                }
                                .buttonStyle(.plain)
                                .help(tab.mediaStatus.isMuted ? "Unmute Tab" : "Mute Tab")
                            }

                            if controller.tabs.count > 1 {
                                Button {
                                    controller.closeTab(id: tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(AppIconFont.xs(weight: .bold))
                                        .foregroundStyle(AppleTheme.textSecondary)
                                        .minHitTarget(24, shape: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Close Tab (⌘W)")
                            }
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(isSelected ? AppleTheme.accentText.opacity(0.12) : Color.clear)
                        )
                    }
                }
            }
            .frame(maxHeight: 340)
        }
        .padding(AppSpacing.lg)
        .frame(width: 300)
    }

    private func tabIconName(for tab: BrowserTab) -> String {
        if controller.isTabPoppedOut(tab.id) {
            return "pip.fill"
        }
        if tab.mediaStatus.hasVideo && (tab.mediaStatus.isPlaying || tab.mediaStatus.isMuted) {
            return tab.mediaStatus.isMuted ? "speaker.slash.fill" : "waveform"
        }
        if tab.isSleeping {
            return "moon.zzz"
        }
        return tab.isCompanionTab ? "globe" : "play.rectangle"
    }

    private func tabIconColor(for tab: BrowserTab) -> Color {
        if controller.isTabPoppedOut(tab.id) {
            return AppleTheme.accentText
        }
        if tab.mediaStatus.hasVideo && tab.mediaStatus.isPlaying && !tab.mediaStatus.isMuted {
            return AppleTheme.accentText
        }
        if tab.isSleeping {
            return AppleTheme.textMuted
        }
        return AppleTheme.textSecondary
    }
}

/// Compact Liquid Glass Multiview controls popover used when Compact Single-Row Header hides `MultiviewControlBar`.
private struct MultiviewCompactControlsPopover: View {
    @Bindable var controller: AppController
    let onDismiss: () -> Void

    @State private var presetName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(AppIconFont.sm(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
                Text("Multiview Controls")
                    .font(AppFont.body(weight: .semibold))
                Spacer()
                Text("\(controller.multiviewTabs.count) / 4")
                    .font(AppFont.caption(weight: .semibold, tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
            }

            // Grid / Spotlight / Stacked mode selector (⌘⌥G)
            HStack(spacing: AppSpacing.xxs) {
                ForEach(MultiviewLayoutMode.allCases) { mode in
                    let isSelected = controller.multiviewLayoutMode == mode
                    Button {
                        controller.setMultiviewLayoutMode(mode)
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: mode.systemImage)
                                .font(AppIconFont.sm(weight: .semibold))
                            Text(mode.title)
                                .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? AppleTheme.accentText : Color.primary.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .minHitTarget(28, shape: Capsule(style: .continuous))
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? AppleTheme.accentText.opacity(0.16) : .clear)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Multiview \(mode.title) Layout (⌘⌥G)")
                }
            }
            .padding(AppSpacing.xxs)
            .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))

            // Solo / Back to Grid toggle (⌘⌥Z)
            Button {
                if controller.isMultiviewSoloActive {
                    controller.exitMultiviewSolo()
                } else {
                    controller.toggleMultiviewSolo()
                }
                onDismiss()
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: controller.isMultiviewSoloActive ? "square.grid.2x2" : "arrow.up.left.and.arrow.down.right")
                        .font(AppIconFont.sm(weight: .semibold))
                        .foregroundStyle(AppleTheme.accentText)
                        .frame(width: 18, alignment: .center)
                    Text(controller.isMultiviewSoloActive ? "Back to Multiview Grid" : "Solo Focused Tile")
                        .font(AppFont.callout(weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("⌘⌥Z")
                        .font(AppFont.micro(weight: .medium, tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                .padding(.horizontal, AppSpacing.sm)
                .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Divider()

            // Save Layout Preset inline quick field & button
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Save Layout Preset")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)

                HStack(spacing: AppSpacing.sm) {
                    TextField("e.g. Sunday Quad", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .font(AppFont.body)
                        .onSubmit {
                            savePreset()
                        }

                    Button {
                        savePreset()
                    } label: {
                        Text("Save")
                            .font(AppFont.callout(weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.md)
                            .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            .background(AppleTheme.accentFill, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Mute All, Reset Mixer & Exit to Single View
            VStack(spacing: AppSpacing.xs) {
                if controller.hasCustomMultiviewMix {
                    Button {
                        controller.resetMultiviewMixer()
                        onDismiss()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(AppIconFont.sm(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                                .frame(width: 18, alignment: .center)
                            Text("Reset Audio Mixer")
                                .font(AppFont.callout(weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    controller.muteAllMultiviewTiles()
                    onDismiss()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "speaker.slash.fill")
                            .font(AppIconFont.sm(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .frame(width: 18, alignment: .center)
                        Text("Mute All Streams")
                            .font(AppFont.callout(weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                    controller.exitMultiview()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "rectangle")
                            .font(AppIconFont.sm(weight: .semibold))
                            .foregroundStyle(AppleTheme.accentText)
                            .frame(width: 18, alignment: .center)
                        Text("Exit to Single View")
                            .font(AppFont.callout(weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("⌘⇧G")
                            .font(AppFont.micro(weight: .medium, tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 300)
        .onAppear {
            if presetName.isEmpty {
                let count = controller.multiviewTabs.count
                presetName = count == 4 ? "Quad-Box Preset" : "\(count)-Stream Multiview"
            }
        }
    }

    private func savePreset() {
        controller.saveCurrentMultiviewAsPreset(name: presetName)
        onDismiss()
    }
}
