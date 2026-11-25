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
        LiquidGlassGroup(spacing: 8) {
            HStack(spacing: 10) {
                // Active Multiview indicator + count (or Back to Grid pill when Soloed)
                if controller.isMultiviewSoloActive {
                    Button {
                        controller.exitMultiviewSolo()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back to Grid")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(AppleTheme.accent, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Return to Multiview Grid (Esc / ⌘⌥Z)")
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppleTheme.accent)
                        Text(streamCountLabel)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .appleGlass(in: Capsule(style: .continuous), tint: AppleTheme.accent.opacity(0.14))
                }

                // Layout mode segmented capsule (Grid / Spotlight / Stacked)
                HStack(spacing: 2) {
                    ForEach(MultiviewLayoutMode.allCases) { mode in
                        let isSelected = controller.multiviewLayoutMode == mode
                        Button {
                            controller.setMultiviewLayoutMode(mode)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(mode.title)
                                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            }
                            .foregroundStyle(isSelected ? AppleTheme.accent : Color.primary.opacity(0.76))
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? AppleTheme.accent.opacity(0.16) : .clear)
                            )
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Multiview \(mode.title) Layout (⌘⌥G)")
                    }
                }
                .padding(.horizontal, 3)
                .frame(height: 26)
                .appleGlass(in: Capsule(style: .continuous), interactive: true)

                Spacer(minLength: 8)

                // Responsive audio hint (degrades gracefully at narrow Split Screen widths with zero mid-word truncation)
                ViewThatFits(in: .horizontal) {
                    Text("Click any stream or press ⌘⌥1–\(controller.multiviewTabs.count) for audio")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    Text("⌘⌥1–\(controller.multiviewTabs.count) audio")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    EmptyView()
                }
                .layoutPriority(-1)

                // Trailing action capsule: Save Layout, Add Stream, Mute All, Exit Single View
                HStack(spacing: 6) {
                    savePresetButton

                    addStreamMenu

                    Button {
                        controller.muteAllMultiviewTiles()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Image(systemName: "speaker.slash.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("Mute All")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .fixedSize()
                            .padding(.horizontal, 9)

                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                                .fixedSize()
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(Color.primary.opacity(0.84))
                        .frame(height: 26)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Mute All Multiview Streams")

                    Button {
                        controller.exitMultiview()
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("Single View")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .fixedSize()
                            .padding(.horizontal, 10)

                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text("Exit")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .fixedSize()
                            .padding(.horizontal, 9)
                        }
                        .foregroundStyle(.primary)
                        .frame(height: 26)
                        .appleGlass(in: Capsule(style: .continuous), interactive: true)
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Exit Multiview (⌘⇧G)")
                }
            }
            .padding(.horizontal, 12)
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
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.badge.plus")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Save")
                        .font(.system(size: 11, weight: .medium))
                }
                .fixedSize()
                .padding(.horizontal, 9)

                Image(systemName: "bookmark.badge.plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(Color.primary.opacity(0.86))
            .frame(height: 26)
            .appleGlass(in: Capsule(style: .continuous), interactive: true)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Save Current Multiview Grid as Preset")
        .popover(isPresented: $isSavePresetPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save Multiview Preset")
                    .font(.system(size: 13, weight: .semibold))

                TextField("e.g. NFL Sunday Quad", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .onSubmit {
                        commitSavePreset()
                    }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        isSavePresetPopoverPresented = false
                    }
                    Button("Save Preset") {
                        commitSavePreset()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
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
        Button {
            isAddScreenPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                Text(canAdd ? "Add Screen" : "4 / 4")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(canAdd ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .appleGlass(in: Capsule(style: .continuous), interactive: canAdd)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .help(canAdd ? "Add a Streaming Service, Open Tab, or Custom URL (up to 4)" : "Maximum 4 streams active")
        .popover(isPresented: $isAddScreenPopoverPresented, arrowEdge: .bottom) {
            AddScreenServicePickerPopover(
                controller: controller,
                targetIsMultiview: true,
                onDismiss: { isAddScreenPopoverPresented = false }
            )
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
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .position(x: rect.midX, y: rect.midY)
                            }

                            // 1. Non-interactive rounded border (100% pass-through to WKWebView)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                .fill(isDragging ? AppleTheme.accent : Color.primary.opacity(0.36))
                .frame(width: pillWidth, height: pillHeight)
                .shadow(color: Color.black.opacity(isDragging ? 0.38 : 0.18), radius: 3, y: 1)

            if isDragging {
                Text("\(divider.leadingPercent)% / \(divider.trailingPercent)%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
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
            return AppleTheme.accent.opacity(0.92)
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
        LiquidGlassGroup(spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                tileAudioBadge(
                    tab: tab,
                    slotNumber: index + 1,
                    isAudio: isAudio,
                    maxWidth: max(90, tileWidth - 200)
                )

                Spacer(minLength: 6)

                if showActions {
                    tileActionPill(tab: tab, index: index, totalCount: totalCount)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
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
            HStack(spacing: 5) {
                Text("\(slotNumber)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(isAudio ? AppleTheme.accent : Color.white.opacity(0.22))
                    )

                if isSilentCompanionWeb {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                } else {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "waveform")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isMuted ? Color.white.opacity(0.78) : AppleTheme.accent)
                }

                if tileTitleVisible(maxWidth: maxWidth) {
                    Text(tab.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if tab.mediaStatus.isHDR {
                    Text("HDR")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.7)
                        )
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: 24)
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
        HStack(spacing: 2) {
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
                    Button("Nudge Back −1s") {
                        controller.nudgeMultiviewTile(id: tab.id, seconds: -1)
                    }
                    Button("Nudge Forward +1s") {
                        controller.nudgeMultiviewTile(id: tab.id, seconds: 1)
                    }
                    Divider()
                    Button("Jump to Live Edge") {
                        controller.jumpMultiviewTileToLive(id: tab.id)
                    }
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
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
        .padding(.horizontal, 4)
        .frame(height: 24)
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
