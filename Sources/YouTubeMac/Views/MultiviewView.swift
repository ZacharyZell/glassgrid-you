import SwiftUI
import YouTubeMacCore

/// Compact macOS 26/27 Liquid Glass control bar for Native Multiview (2-Up / 3-Up / 2×2 Quad-Box).
struct MultiviewControlBar: View {
    @Bindable var controller: AppController
    @State private var isSavePresetPopoverPresented = false
    @State private var newPresetName = ""
    @State private var isAddScreenPopoverPresented = false

    private var availableTabsToAdd: [BrowserTab] {
        controller.tabs.filter { !controller.multiviewTabIDs.contains($0.id) }
    }

    private var streamCountLabel: String {
        let count = controller.multiviewTabs.count
        return count == 4 ? "Quad-Box" : "\(count) Streams"
    }

    var body: some View {
        LiquidGlassGroup(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                // Active Multiview indicator + count (or Back to Grid pill when Soloed)
                if controller.isMultiviewSoloActive {
                    Button {
                        controller.exitMultiviewSolo()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(AppIconFont.sm(weight: .semibold))
                            Text("Back to Grid")
                                .font(AppFont.callout(weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .frame(height: 28)
                        .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Return to Multiview Grid (Esc / ⌘⌥Z)")
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(AppIconFont.sm(weight: .semibold))
                            .foregroundStyle(AppleTheme.accentText)
                        Text(streamCountLabel)
                            .font(AppFont.callout(weight: .semibold, tabular: true))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .frame(height: 28)
                    .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accentText.opacity(0.14))
                }

                // Layout mode segmented capsule (Grid / Spotlight / Stacked)
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
                            .foregroundStyle(isSelected ? AppleTheme.accentText : Color.primary.opacity(0.80))
                            .padding(.horizontal, AppSpacing.md)
                            .frame(height: 24)
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
                .padding(.horizontal, AppSpacing.xxs)
                .frame(height: 28)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)

                Spacer(minLength: AppSpacing.md)

                // Responsive audio hint (degrades gracefully at narrow Split Screen widths with zero mid-word truncation)
                ViewThatFits(in: .horizontal) {
                    Text("Click any stream or press ⌘⌥1–\(controller.multiviewTabs.count) for audio")
                        .font(AppFont.caption(weight: .medium, tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .fixedSize()

                    Text("⌘⌥1–\(controller.multiviewTabs.count) audio")
                        .font(AppFont.caption(weight: .medium, tabular: true))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .fixedSize()

                    EmptyView()
                }
                .layoutPriority(-1)

                // Trailing action capsule: Save Layout, Add Stream, Mute All, Exit Single View
                HStack(spacing: AppSpacing.sm) {
                    savePresetButton

                    addStreamMenu

                    Button {
                        controller.muteAllMultiviewTiles()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "speaker.slash.fill")
                                    .font(AppIconFont.sm(weight: .semibold))
                                Text("Mute All")
                                    .font(AppFont.caption(weight: .medium))
                            }
                            .fixedSize()
                            .padding(.horizontal, AppSpacing.md)

                            Image(systemName: "speaker.slash.fill")
                                .font(AppIconFont.sm(weight: .semibold))
                                .fixedSize()
                                .padding(.horizontal, AppSpacing.md)
                        }
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .frame(height: 28)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Mute All Multiview Streams")

                    Button {
                        controller.exitMultiview()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "rectangle.fill")
                                    .font(AppIconFont.sm(weight: .semibold))
                                Text("Single View")
                                    .font(AppFont.caption(weight: .semibold))
                            }
                            .fixedSize()
                            .padding(.horizontal, AppSpacing.lg)

                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "rectangle.fill")
                                    .font(AppIconFont.sm(weight: .semibold))
                                Text("Exit")
                                    .font(AppFont.caption(weight: .semibold))
                            }
                            .fixedSize()
                            .padding(.horizontal, AppSpacing.md)
                        }
                        .foregroundStyle(.primary)
                        .frame(height: 28)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Exit Multiview (⌘⇧G)")
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .frame(height: 36)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
        .youtubeURLDropTarget(controller: controller, allowCompanionURLs: true)
    }

    @ViewBuilder
    private var savePresetButton: some View {
        Button {
            newPresetName = defaultPresetName()
            isSavePresetPopoverPresented = true
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "bookmark.badge.plus")
                        .font(AppIconFont.sm(weight: .semibold))
                    Text("Save")
                        .font(AppFont.caption(weight: .medium))
                }
                .fixedSize()
                .padding(.horizontal, AppSpacing.md)

                Image(systemName: "bookmark.badge.plus")
                    .font(AppIconFont.sm(weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, AppSpacing.md)
            }
            .foregroundStyle(Color.primary.opacity(0.86))
            .frame(height: 28)
            .appleGlass(in: Capsule(style: .continuous), interactive: true)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Save Current Multiview Grid as Preset")
        .popover(isPresented: $isSavePresetPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("Save Multiview Preset")
                    .font(AppFont.body(weight: .semibold))

                TextField("e.g. NFL Sunday Quad", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.body)
                    .frame(width: 220)
                    .onSubmit {
                        commitSavePreset()
                    }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isSavePresetPopoverPresented = false
                    }
                    .font(AppFont.callout(weight: .medium))
                    Button("Save Preset") {
                        commitSavePreset()
                    }
                    .font(AppFont.callout(weight: .semibold))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(AppSpacing.lg)
            .environment(\.font, AppFont.body)
        }
    }

    private func defaultPresetName() -> String {
        let count = controller.multiviewTabs.count
        return count == 4 ? "Quad-Box Preset" : "\(count)-Stream Multiview"
    }

    private func commitSavePreset() {
        controller.saveCurrentMultiviewAsPreset(name: newPresetName)
        isSavePresetPopoverPresented = false
    }

    @ViewBuilder
    private var addStreamMenu: some View {
        let canAdd = controller.canAddMultiviewTile
        let isDisabled = controller.hasLiveFullscreenTab
        Button {
            isAddScreenPopoverPresented.toggle()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "plus")
                    .font(AppIconFont.sm(weight: .bold))
                Text(canAdd ? "Add Screen" : "4 / 4")
                    .font(AppFont.caption(weight: .semibold, tabular: true))
            }
            .foregroundStyle(isDisabled ? AppleTheme.textMuted : (canAdd ? Color.primary : AppleTheme.textSecondary))
            .padding(.horizontal, AppSpacing.lg)
            .frame(height: 28)
            .appleGlass(in: Capsule(style: .continuous), interactive: !isDisabled)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(
            isDisabled
                ? "Exit Fullscreen to Edit Grid"
                : (canAdd
                    ? "Add a Streaming Service, Open Tab, or Custom URL (up to 4)"
                    : "Grid Full (4/4) — Open Services or New Tab")
        )
        .popover(isPresented: $isAddScreenPopoverPresented, arrowEdge: .bottom) {
            AddScreenServicePickerPopover(
                controller: controller,
                initialMode: .addToGrid,
                onDismiss: { isAddScreenPopoverPresented = false }
            )
            .environment(\.font, AppFont.body)
        }
    }
}

/// Non-blocking Liquid Glass tile border and top-36pt-only pill overlay aligned pixel-for-pixel
/// with `FlippedTabHostContainerView` via `MultiviewGridLayout`.
/// Zero hit-testable views are placed over video bodies or bottom player scrubbers.
struct MultiviewOverlayView: View {
    @Bindable var controller: AppController
    @State private var hoveredActionPillTileID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let tiles = controller.multiviewTabs
            let frames = MultiviewGridLayout.frames(
                forCount: tiles.count,
                in: proxy.size,
                mode: controller.multiviewLayoutMode,
                ratios: controller.multiviewSplitRatios
            )
            let dividers = MultiviewGridLayout.dividers(
                forCount: tiles.count,
                in: proxy.size,
                mode: controller.multiviewLayoutMode,
                ratios: controller.multiviewSplitRatios
            )

            ZStack(alignment: .topLeading) {
                if let soloTab = controller.soloMultiviewTab,
                   let soloIdx = tiles.firstIndex(where: { $0.id == soloTab.id }) {
                    let isHovered = (controller.hoveredMultiviewTileID == soloTab.id) || (hoveredActionPillTileID == soloTab.id)
                    tileTopCornerControls(
                        tab: soloTab,
                        index: soloIdx,
                        totalCount: tiles.count,
                        isAudio: true,
                        showActions: isHovered,
                        tileWidth: proxy.size.width
                    )
                    .frame(width: proxy.size.width, height: 36, alignment: .top)
                } else {
                    ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tab in
                        if index < frames.count {
                            let rect = frames[index]
                            let isAudio = (controller.multiviewAudioTab?.id == tab.id)
                            let isFocused = (controller.selectedTabID == tab.id)
                            let isHovered = controller.activeMultiviewDividerDragID == nil
                                && ((controller.hoveredMultiviewTileID == tab.id) || (hoveredActionPillTileID == tab.id))

                            // 0. Per-tile load failure / WebContent crash recovery card (strictly scoped to this tile's rect)
                            if let tileError = tab.loadError {
                                TabErrorOverlayView(
                                    error: tileError,
                                    isCompactTile: true,
                                    onRetry: { tab.reloadOrStop() }
                                )
                                .frame(width: rect.width, height: rect.height)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                                .position(x: rect.midX, y: rect.midY)
                            }

                            // 1. Non-interactive rounded border (100% pass-through to WKWebView)
                            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                                .strokeBorder(
                                    borderColor(isAudio: isAudio, isFocused: isFocused),
                                    lineWidth: isAudio ? 2.0 : 1.0
                                )
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .allowsHitTesting(false)

                            // 2. Compact top-36pt corner controls (only the two corner pills accept hits;
                            // empty space between them and everything below y+36 passes straight to WKWebView).
                            tileTopCornerControls(
                                tab: tab,
                                index: index,
                                totalCount: tiles.count,
                                isAudio: isAudio,
                                showActions: isHovered,
                                tileWidth: rect.width
                            )
                            .frame(width: rect.width, height: 36, alignment: .top)
                            .offset(x: rect.minX, y: rect.minY)
                        }
                    }

                    // 3. Purely visual Liquid Glass divider pills & live drag ratio capsules (100% non-hit-tested;
                    // AppKit MultiviewDividerNSView handles 120Hz cursor & drag hit-testing underneath).
                    ForEach(dividers) { divider in
                        let isDragging = controller.activeMultiviewDividerDragID == divider.id
                        let isHovering = controller.hoveredMultiviewDividerID == divider.id
                        if isDragging || isHovering {
                            dividerVisual(for: divider, isDragging: isDragging)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dividerVisual(for divider: MultiviewDividerDescriptor, isDragging: Bool) -> some View {
        let isVertical = divider.axis == .vertical
        let pillWidth: CGFloat = isVertical ? 4 : 44
        let pillHeight: CGFloat = isVertical ? 44 : 4

        ZStack {
            Capsule(style: .continuous)
                .fill(isDragging ? AppleTheme.accentText : Color.primary.opacity(0.36))
                .frame(width: pillWidth, height: pillHeight)
                .shadow(color: Color.black.opacity(isDragging ? 0.38 : 0.18), radius: 3, y: 1)

            if isDragging {
                Text("\(divider.leadingPercent)% / \(divider.trailingPercent)%")
                    .font(AppFont.micro(weight: .semibold, tabular: true))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .appleGlass(
                        in: Capsule(style: .continuous),
                        tint: Color.black.opacity(0.68)
                    )
                    .environment(\.colorScheme, .dark)
                    .fixedSize()
                    .offset(x: isVertical ? 36 : 0, y: isVertical ? 0 : -22)
            }
        }
        .position(x: divider.frame.midX, y: divider.frame.midY)
        .allowsHitTesting(false)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    private func borderColor(isAudio: Bool, isFocused: Bool) -> Color {
        if isAudio {
            return AppleTheme.accentText.opacity(0.92)
        }
        if isFocused {
            return Color.white.opacity(0.32)
        }
        return Color.primary.opacity(0.16)
    }

    @ViewBuilder
    private func tileTopCornerControls(
        tab: BrowserTab,
        index: Int,
        totalCount: Int,
        isAudio: Bool,
        showActions: Bool,
        tileWidth: CGFloat
    ) -> some View {
        // Only the two compact pills inside this top 36pt bar accept pointer hits;
        // the empty space between them passes clicks straight through to the WKWebView.
        LiquidGlassGroup(spacing: AppSpacing.sm) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                tileAudioBadge(
                    tab: tab,
                    slotNumber: index + 1,
                    isAudio: isAudio,
                    maxWidth: max(90, tileWidth - 200)
                )

                Spacer(minLength: AppSpacing.sm)

                if showActions {
                    tileActionPill(tab: tab, index: index, totalCount: totalCount)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
        .animation(.easeOut(duration: 0.14), value: showActions)
    }

    @ViewBuilder
    private func tileAudioBadge(
        tab: BrowserTab,
        slotNumber: Int,
        isAudio: Bool,
        maxWidth: CGFloat
    ) -> some View {
        let isSilentCompanionWeb = tab.isCompanionTab && !tab.mediaStatus.hasVideo
        let isMuted = tab.mediaStatus.isMuted || !isAudio
        Button {
            if isSilentCompanionWeb {
                controller.selectTab(id: tab.id)
            } else if isAudio {
                controller.toggleMute(tabID: tab.id)
            } else {
                controller.focusMultiviewAudio(tabID: tab.id, showFeedback: false)
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Text("\(slotNumber)")
                    .font(AppFont.micro(weight: .bold, tabular: true))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(isAudio ? AppleTheme.accentFill : Color.white.opacity(0.22))
                    )

                if isSilentCompanionWeb {
                    Image(systemName: "globe")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                } else {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "waveform")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(isMuted ? Color.white.opacity(0.82) : AppleTheme.accentText)
                }

                if tileTitleVisible(maxWidth: maxWidth) {
                    Text(tab.displayTitle)
                        .font(AppFont.caption(weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if tab.mediaStatus.isHDR {
                    AppleHDRBadge(onDarkMedia: true)
                }
            }
            .padding(.leading, AppSpacing.xs)
            .padding(.trailing, AppSpacing.md)
            .frame(height: 26)
            .appleGlass(
                in: Capsule(style: .continuous),
                tint: isAudio ? Color.black.opacity(0.58) : Color.black.opacity(0.46),
                interactive: true
            )
            .environment(\.colorScheme, .dark)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: min(240, maxWidth), alignment: .leading)
        .help(isAudio ? "Active Audio Stream — Click to Mute/Unmute (⌘⌥\(slotNumber))" : "Switch Audio to Stream \(slotNumber) (⌘⌥\(slotNumber))")
    }

    private func tileTitleVisible(maxWidth: CGFloat) -> Bool {
        maxWidth >= 110
    }

    @ViewBuilder
    private func tileActionPill(tab: BrowserTab, index: Int, totalCount: Int) -> some View {
        let isYTTV = YouTubeURLRouter.isYouTubeTVHost(tab.url.host)
        let isCompanion = tab.isCompanionTab
        let isSoloed = (controller.soloMultiviewTabID == tab.id)
        let companionServiceName = isCompanion ? StreamingServiceCatalog.service(matchingURL: tab.url)?.name : nil

        // Strictly <= 5 compact icons in top-36pt pill (never encroaches on bottom 64pt video scrubber).
        HStack(spacing: AppSpacing.xxs) {
            // 1. Zero-Latency Solo / Back to Grid
            tileIconButton(
                systemImage: isSoloed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                helpText: isSoloed ? "Back to Multiview Grid (Esc / ⌘⌥Z)" : "Solo / Expand Tile (⌘⌥Z)"
            ) {
                controller.toggleMultiviewSolo(tabID: tab.id)
            }

            // 2. Live Stream Sync Micro-Nudge (-5s, -1s, +1s, Jump to Live)
            if tab.mediaStatus.hasVideo {
                Menu {
                    Button("Nudge Back −5s") {
                        controller.nudgeMultiviewTile(id: tab.id, seconds: -5)
                    }
                    .font(AppFont.body(tabular: true))
                    Button("Nudge Back −1s") {
                        controller.nudgeMultiviewTile(id: tab.id, seconds: -1)
                    }
                    .font(AppFont.body(tabular: true))
                    Button("Nudge Forward +1s") {
                        controller.nudgeMultiviewTile(id: tab.id, seconds: 1)
                    }
                    .font(AppFont.body(tabular: true))
                    Divider()
                    Button("Jump to Live Edge") {
                        controller.jumpMultiviewTileToLive(id: tab.id)
                    }
                    .font(AppFont.body)
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .minHitTarget(24, shape: Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Live Stream Sync Micro-Nudge")
            }

            // 3. Reload / Browse
            if isCompanion {
                tileIconButton(
                    systemImage: "arrow.clockwise",
                    helpText: "Reload Stream"
                ) {
                    tab.reloadOrStop()
                }
            } else {
                tileIconButton(
                    systemImage: isYTTV ? "tv" : "house",
                    helpText: isYTTV ? "Open YouTube TV Live Guide" : "Browse YouTube in This Tile"
                ) {
                    controller.navigateMultiviewTileToBrowse(id: tab.id)
                }
            }

            // 4. Overflow Tile Actions (Reorder, Promote, Open in Safari, Exit to Single View)
            Menu {
                if !isSoloed {
                    if index > 0 {
                        Button("Promote to Main Tile") {
                            controller.promoteMultiviewTileToPrimary(id: tab.id)
                        }
                        Button("Move Tile Left") {
                            controller.moveMultiviewTile(id: tab.id, by: -1)
                        }
                    }
                    if index < totalCount - 1 {
                        Button("Move Tile Right") {
                            controller.moveMultiviewTile(id: tab.id, by: 1)
                        }
                    }
                    Divider()
                }
                let showCleanBoxAction = controller.settings.cleanBoxStreamingPlayers
                    && (tab.mediaStatus.isCleanBoxActive || tab.isCleanBoxBypassed)
                if showCleanBoxAction {
                    Button(tab.isCleanBoxBypassed ? "Clean-Box Video" : "Show Full Page") {
                        controller.toggleCleanBox(forTabID: tab.id)
                    }
                }
                if isCompanion {
                    Button(companionServiceName.map { "Browse \($0)" } ?? "Browse Service Home") {
                        controller.navigateMultiviewTileToBrowse(id: tab.id)
                    }
                }
                if showCleanBoxAction || isCompanion {
                    Divider()
                }
                Button("Expand to Single View") {
                    controller.exitMultiview(focusTabID: tab.id)
                }
                Button("Open in Safari") {
                    controller.openURLInSafari(tab.url)
                }
                Divider()
                Button("Remove from Multiview", role: .destructive) {
                    controller.removeTileFromMultiview(id: tab.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppIconFont.xs(weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .minHitTarget(24, shape: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tile Options")

            // 5. Remove Tile
            tileIconButton(
                systemImage: "xmark",
                helpText: "Remove from Multiview"
            ) {
                controller.removeTileFromMultiview(id: tab.id)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .frame(height: 26)
        .appleGlass(
            in: Capsule(style: .continuous),
            tint: Color.black.opacity(0.54),
            interactive: true
        )
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            hoveredActionPillTileID = hovering ? tab.id : (hoveredActionPillTileID == tab.id ? nil : hoveredActionPillTileID)
        }
    }

    @ViewBuilder
    private func tileIconButton(
        systemImage: String,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppIconFont.xs(weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .minHitTarget(24, shape: Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
