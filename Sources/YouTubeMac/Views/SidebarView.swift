import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

/// macOS 26/27 Liquid Glass floating inset sidebar with concentric corners and adaptive crimson SF Symbols.
struct SidebarView: View {
    @Bindable var controller: AppController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHolidayPopoverPresented = false
    @State private var hoveredDestination: SidebarDestination?
    @State private var hoveredPinID: UUID?
    @State private var hoveredFolderID: UUID?
    @State private var hoveredPresetID: UUID?
    @State private var hoveredServiceID: String?
    @State private var isServicesExpanded = true
    @State private var servicePendingReset: StreamingService?
    @State private var isPresetsExpanded = true
    @State private var renamingPresetID: UUID?
    @State private var renamePresetDraft = ""
    @State private var renamingPinID: UUID?
    @State private var renamePinDraft = ""
    @State private var isNewFolderPopoverPresented = false
    @State private var newFolderNameDraft = ""
    @State private var movePinAfterFolderCreateID: UUID?
    @State private var renamingFolderID: UUID?
    @State private var renameFolderDraft = ""
    @State private var isNewFolderButtonHovered = false
    @State private var isAccountHovered = false
    @State private var isPinActionHovered = false
    @State private var isThemeHovered = false
    @State private var isSettingsHovered = false

    private var isResolvedDark: Bool {
        switch controller.settings.appearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var themeToggleHelpText: String {
        switch controller.settings.appearance {
        case .dark:
            return "Night Mode — Click for Day Mode, ⌥-Click for Match System (⌘⇧L)"
        case .light:
            return "Day Mode — Click for Night Mode, ⌥-Click for Match System (⌘⇧L)"
        case .system:
            let resolved = isResolvedDark ? "Night" : "Day"
            return "Match System (\(resolved)) — Click to toggle Day/Night (⌘⇧L)"
        }
    }

    private var browseDestinations: [SidebarDestination] {
        var items: [SidebarDestination] = [.home, .subscriptions]
        if !controller.settings.hideShorts {
            items.append(.shorts)
        }
        return items
    }

    private let libraryDestinations: [SidebarDestination] = [
        .watchLater, .history, .likedVideos, .playlists
    ]

    private var activeDestination: SidebarDestination? {
        guard let url = controller.selectedTab?.url else { return nil }
        return SidebarDestination.matching(url: url)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Titlebar drag area clearing traffic lights + sidebar toggle on right
                ZStack {
                    WindowDragArea()

                    HStack {
                        Spacer()
                        AppleIconButton(
                            systemImage: "sidebar.leading",
                            helpText: "Hide Sidebar (⌘⌥S)"
                        ) {
                            controller.toggleSidebar()
                        }
                    }
                    .padding(.leading, WindowChromeLayout.sidebarHeaderLeadingPadding(isNativeFullScreen: controller.isWindowInNativeFullScreen))
                    .padding(.trailing, 8)
                }
                .frame(height: WindowChromeLayout.sidebarHeaderHeight)

                // Original Liquid Glass brand mark
                HStack(spacing: AppSpacing.md) {
                    BrandMarkBadge(size: 22, cornerRadius: AppRadius.sm, showRing: true)

                    Text("GlassGrid You")
                        .font(AppFont.subhead(weight: .semibold))
                        .tracking(AppFont.tracking(for: 15))

                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xxs)
                .padding(.bottom, AppSpacing.md)

                if controller.settings.resolvedHolidayThemeID != .classic {
                    let palette = controller.settings.activeHolidayPalette
                    Button {
                        isHolidayPopoverPresented.toggle()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: palette.symbolName)
                                .font(AppIconFont.sm(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)

                            Text(palette.shortName)
                                .font(AppFont.callout(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                                .lineLimit(1)

                            Spacer(minLength: AppSpacing.xs)

                            if controller.settings.holidayThemeSelection == .auto {
                                Text("Auto")
                                    .font(AppFont.micro(weight: .semibold))
                                    .foregroundStyle(AppleTheme.accentText)
                                    .padding(.horizontal, AppSpacing.xs)
                                    .padding(.vertical, AppSpacing.xxs)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(AppleTheme.accentText.opacity(0.14))
                                    )
                            }

                            Image(systemName: "chevron.down")
                                .font(AppIconFont.xs(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AppleTheme.accentText.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(AppleTheme.accentText.opacity(0.22), lineWidth: 0.75)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.md)
                    .help("Seasonal Theme: \(palette.displayName) — Click to Customize")
                    .popover(isPresented: $isHolidayPopoverPresented, arrowEdge: .trailing) {
                        HolidayThemePopoverView(
                            controller: controller,
                            onDismiss: { isHolidayPopoverPresented = false }
                        )
                        .environment(\.font, AppFont.body)
                    }
                }

                // Scrollable navigation sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        VStack(spacing: AppSpacing.xxs) {
                            ForEach(browseDestinations) { destination in
                                sidebarRow(for: destination)
                            }
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            sectionHeader("Library")
                            ForEach(libraryDestinations) { destination in
                                sidebarRow(for: destination)
                            }
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            HStack(spacing: AppSpacing.xs) {
                                Button {
                                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                                        isServicesExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: AppSpacing.xs) {
                                        sectionHeader("Services")
                                        Spacer()
                                        Image(systemName: isServicesExpanded ? "chevron.down" : "chevron.right")
                                            .font(AppIconFont.xs(weight: .semibold))
                                            .foregroundStyle(AppleTheme.textMuted)
                                    }
                                    .minHitTarget(24, shape: Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button("Manage") {
                                    controller.openStreamingServicesSetup(step: 1)
                                }
                                .buttonStyle(.plain)
                                .font(AppFont.caption(weight: .medium))
                                .foregroundStyle(AppleTheme.accentText)
                                .padding(.horizontal, AppSpacing.xs)
                                .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .padding(.trailing, AppSpacing.xs)
                                .help("Choose Streaming Services & Sign In")
                            }

                            if isServicesExpanded {
                                ForEach(controller.settings.enabledStreamingServices) { service in
                                    streamingServiceRow(for: service)
                                }
                            }
                        }

                        if !controller.settings.savedMultiviewPresets.isEmpty || controller.isMultiviewActive {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                HStack(spacing: AppSpacing.xs) {
                                    Button {
                                        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                                            isPresetsExpanded.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            sectionHeader("Multiview Presets")
                                            Spacer()
                                            Image(systemName: isPresetsExpanded ? "chevron.down" : "chevron.right")
                                                .font(AppIconFont.xs(weight: .semibold))
                                                .foregroundStyle(AppleTheme.textMuted)
                                        }
                                        .minHitTarget(24, shape: Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Menu {
                                        Button("Import Presets (.json)…") {
                                            importMultiviewPresetsFromPanel()
                                        }
                                        Button("Export All Presets (.json)…") {
                                            exportMultiviewPresets(nil, suggestedFilename: "GlassGrid-Multiview-Presets.json")
                                        }
                                        .disabled(controller.settings.savedMultiviewPresets.isEmpty)
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(AppIconFont.sm(weight: .medium))
                                            .foregroundStyle(AppleTheme.textSecondary)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Circle())
                                    }
                                    .menuStyle(.borderlessButton)
                                    .menuIndicator(.hidden)
                                    .fixedSize()
                                    .padding(.trailing, AppSpacing.xs)
                                    .help("Import or Export Multiview Presets (.json)")
                                }

                                if isPresetsExpanded {
                                    if controller.settings.savedMultiviewPresets.isEmpty {
                                        Text("Save a grid or import presets (.json)")
                                            .font(AppFont.caption)
                                            .foregroundStyle(AppleTheme.textSecondary)
                                            .padding(.horizontal, AppSpacing.lg)
                                            .padding(.vertical, AppSpacing.xs)
                                    } else {
                                        ForEach(controller.settings.savedMultiviewPresets) { preset in
                                            multiviewPresetRow(for: preset)
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            HStack(spacing: AppSpacing.xs) {
                                sectionHeader("Pinned")
                                Spacer()
                                Button {
                                    movePinAfterFolderCreateID = nil
                                    newFolderNameDraft = ""
                                    isNewFolderPopoverPresented = true
                                } label: {
                                    Image(systemName: "folder.badge.plus")
                                        .font(AppIconFont.sm(weight: .medium))
                                        .foregroundStyle(isNewFolderButtonHovered ? Color.primary : AppleTheme.textSecondary)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Circle()
                                                .fill(isNewFolderButtonHovered ? Color.primary.opacity(0.09) : .clear)
                                        )
                                        .minHitTarget(24, shape: Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, AppSpacing.xs)
                                .onHover { isNewFolderButtonHovered = $0 }
                                .help("New Folder")
                                .popover(isPresented: $isNewFolderPopoverPresented, arrowEdge: .trailing) {
                                    newFolderPopover
                                }
                            }

                            let ungroupedPins = controller.pins(inFolder: nil)
                            if controller.settings.pinnedFolders.isEmpty && controller.settings.pinnedItems.isEmpty {
                                Text("Press ⌘D to pin channels or playlists")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppleTheme.textSecondary)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.sm)
                            } else {
                                ForEach(controller.settings.pinnedFolders) { folder in
                                    pinnedFolderSection(for: folder)
                                }

                                ForEach(ungroupedPins) { item in
                                    pinnedRow(for: item)
                                }
                            }

                            // Only offer to pin custom channels/playlists/videos — never permanent sidebar destinations.
                            if activeDestination == nil, !controller.isCurrentPagePinned, controller.selectedTab != nil {
                                Button {
                                    controller.togglePinCurrentPage()
                                } label: {
                                    HStack(spacing: AppSpacing.md) {
                                        Image(systemName: "plus.circle")
                                            .font(AppIconFont.toolbar)
                                            .foregroundStyle(AppleTheme.textSecondary)
                                            .frame(width: 18, alignment: .center)
                                        Text("Pin Current Page")
                                            .font(AppFont.body)
                                            .foregroundStyle(AppleTheme.textSecondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                            .fill(isPinActionHovered ? Color.primary.opacity(0.07) : .clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .onHover { isPinActionHovered = $0 }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.lg)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, AppSpacing.lg)

                // Airy Apple-style bottom utility row
                HStack(spacing: AppSpacing.xs) {
                    Button {
                        controller.openSignIn()
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(AppIconFont.lg)
                                .foregroundStyle(AppleTheme.textSecondary)
                            Text("Account")
                                .font(AppFont.body(weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.88))
                            Spacer()
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(isAccountHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { isAccountHovered = $0 }
                    .help("Sign in or switch Google account")

                    Button {
                        if NSEvent.modifierFlags.contains(.option) {
                            controller.setAppearance(.system)
                        } else {
                            controller.toggleDayNightMode(currentColorScheme: colorScheme)
                        }
                    } label: {
                        Image(systemName: isResolvedDark ? "moon.fill" : "sun.max.fill")
                            .font(AppIconFont.toolbar)
                            .foregroundStyle(isThemeHovered ? Color.primary : AppleTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(isThemeHovered ? Color.primary.opacity(0.09) : .clear)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isThemeHovered = $0 }
                    .help(themeToggleHelpText)
                    .contextMenu {
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

                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(AppIconFont.toolbar)
                            .foregroundStyle(isSettingsHovered ? Color.primary : AppleTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(isSettingsHovered ? Color.primary.opacity(0.09) : .clear)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isSettingsHovered = $0 }
                    .help("Settings (⌘,)")
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .background {
                ZStack {
                    HolidayAmbientGlowView(
                        surface: .sidebar,
                        isPaused: controller.hasLiveFullscreenTab || controller.focusModeActive
                    )
                    HolidayParticlesView(
                        palette: controller.settings.activeHolidayPalette,
                        intensity: controller.settings.holidayEffectsIntensity,
                        surface: .sidebar,
                        isHardStopped: controller.hasLiveFullscreenTab || controller.focusModeActive || reduceMotion
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: WindowChromeLayout.sidebarCardCornerRadius, style: .continuous))
            }
            .appleGlass(in: RoundedRectangle(cornerRadius: WindowChromeLayout.sidebarCardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(isResolvedDark ? 0.28 : 0.08), radius: 10, y: 2)
            .youtubeURLDropTarget(controller: controller)
            .padding(.leading, WindowChromeLayout.sidebarCardLeadingInset)
            .padding(.vertical, WindowChromeLayout.sidebarCardVerticalInset)
            .padding(.trailing, WindowChromeLayout.sidebarCardTrailingInset)
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
                        controller.resetStreamingServiceData(service)
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
    }

    @ViewBuilder
    private func streamingServiceRow(for service: StreamingService) -> some View {
        let isHovered = hoveredServiceID == service.id
        let isActive = StreamingServiceCatalog.service(matchingURL: controller.selectedTab?.url)?.id == service.id
        let isSignedIn = controller.settings.isServiceSignedIn(service.id)

        Button {
            controller.openStreamingService(service, inNewTab: false)
        } label: {
            HStack(spacing: AppSpacing.md) {
                StreamingServiceBadge(service: service, size: 18)

                Text(service.name)
                    .font(AppFont.body(weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: AppSpacing.xs)

                if isSignedIn {
                    Circle()
                        .fill(AppleTheme.positive)
                        .frame(width: 6, height: 6)
                        .help("Signed In")
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(
                        isActive
                            ? Color.primary.opacity(isResolvedDark ? 0.14 : 0.09)
                            : (isHovered ? Color.primary.opacity(isResolvedDark ? 0.08 : 0.05) : .clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredServiceID = hovering ? service.id : (hoveredServiceID == service.id ? nil : hoveredServiceID)
        }
        .contextMenu {
            Button("Add to Multiview") {
                controller.addStreamingServiceToMultiview(service)
            }
            .disabled(controller.anyTabInFullscreen || (controller.isMultiviewActive && !controller.canAddMultiviewTile))

            Button("Open in New Tab") {
                controller.openStreamingService(service, inNewTab: true)
            }

            Button("Open in New Window") {
                controller.coordinator?.openURLInNewWindow(service.homeURL, routingMode: service.routingMode)
            }

            Button("Open in Safari") {
                controller.openURLInSafari(service.homeURL)
            }

            Divider()

            Button("Sign In…") {
                controller.openStreamingServicesSetup(step: 2, focusServiceID: service.id)
            }

            Button("Reset Login & Site Data…", role: .destructive) {
                servicePendingReset = service
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AppFont.caption(weight: .semibold))
            .tracking(AppFont.tracking(for: 11) + 0.35)
            .foregroundStyle(AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxs)
    }

    @ViewBuilder
    private func sidebarRow(for destination: SidebarDestination) -> some View {
        let isSelected = activeDestination == destination
        let isHovered = hoveredDestination == destination

        Button {
            controller.navigateSelectedTab(to: destination)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: iconName(for: destination, selected: isSelected))
                    .font(AppIconFont.nav)
                    .foregroundStyle(AppleTheme.accentText)
                    .frame(width: 18, alignment: .center)

                Text(destination.title)
                    .font(AppFont.body(weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(controlActiveState == .inactive ? 0.055 : 0.11)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDestination = hovering ? destination : (hoveredDestination == destination ? nil : hoveredDestination)
        }
        .contextMenu {
            Button("Open in New Tab") {
                controller.createTab(url: destination.url, select: true)
            }
            Button("Open in New Window") {
                controller.openURLInNewWindow(destination.url)
            }
        }
    }

    @ViewBuilder
    private var newFolderPopover: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(movePinAfterFolderCreateID == nil ? "New Channel Folder" : "Move Pin to New Folder")
                .font(AppFont.body(weight: .semibold))
            TextField("e.g. Sports, Tech, News", text: $newFolderNameDraft)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.body)
                .frame(width: 210)
                .onSubmit {
                    commitCreateFolder()
                }
            HStack {
                Spacer()
                Button("Cancel") {
                    movePinAfterFolderCreateID = nil
                    isNewFolderPopoverPresented = false
                }
                .font(AppFont.callout(weight: .medium))
                Button("Create") {
                    commitCreateFolder()
                }
                .font(AppFont.callout(weight: .semibold))
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppSpacing.lg)
        .environment(\.font, AppFont.body)
    }

    private func commitCreateFolder() {
        let pinToMove = movePinAfterFolderCreateID
        if let folder = controller.createPinnedFolder(name: newFolderNameDraft) {
            if let pinToMove {
                controller.movePinToFolder(pinID: pinToMove, folderID: folder.id)
            }
            movePinAfterFolderCreateID = nil
            newFolderNameDraft = ""
            isNewFolderPopoverPresented = false
        }
    }

    @ViewBuilder
    private func pinnedFolderSection(for folder: PinnedFolder) -> some View {
        let childPins = controller.pins(inFolder: folder.id)
        let isHovered = hoveredFolderID == folder.id
        let isRenaming = Binding<Bool>(
            get: { renamingFolderID == folder.id },
            set: { if !$0 && renamingFolderID == folder.id { renamingFolderID = nil } }
        )

        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Button {
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    controller.togglePinnedFolderExpanded(id: folder.id)
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                        .font(AppIconFont.md)
                        .foregroundStyle(AppleTheme.accentText.opacity(controlActiveState == .inactive ? 0.65 : 0.90))
                        .frame(width: 18, alignment: .center)

                    Text(folder.name)
                        .font(AppFont.body(weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if !folder.isExpanded && !childPins.isEmpty {
                        Text("\(childPins.count)")
                            .font(AppFont.micro(weight: .semibold, tabular: true))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
                    }

                    Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(AppleTheme.textMuted)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredFolderID = hovering ? folder.id : (hoveredFolderID == folder.id ? nil : hoveredFolderID)
            }
            .contextMenu {
                if (2...MultiviewGridLayout.maxTiles).contains(childPins.count) {
                    Button("Open in Multiview") {
                        controller.openFolderInMultiview(id: folder.id)
                    }
                    .disabled(controller.anyTabInFullscreen)
                }
                if !childPins.isEmpty {
                    Button("Open All in Tabs") {
                        controller.openFolderInTabs(id: folder.id)
                    }
                    .disabled(controller.anyTabInFullscreen)
                    Divider()
                }
                Button("Rename Folder…") {
                    renameFolderDraft = folder.name
                    renamingFolderID = folder.id
                }
                Divider()
                Button("Delete Folder", role: .destructive) {
                    controller.deletePinnedFolder(id: folder.id)
                }
            }
            .popover(isPresented: isRenaming, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Rename Folder")
                        .font(AppFont.body(weight: .semibold))
                    TextField("Folder Name", text: $renameFolderDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(AppFont.body)
                        .frame(width: 200)
                        .onSubmit {
                            controller.renamePinnedFolder(id: folder.id, newName: renameFolderDraft)
                            renamingFolderID = nil
                        }
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            renamingFolderID = nil
                        }
                        .font(AppFont.callout(weight: .medium))
                        Button("Save") {
                            controller.renamePinnedFolder(id: folder.id, newName: renameFolderDraft)
                            renamingFolderID = nil
                        }
                        .font(AppFont.callout(weight: .semibold))
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(AppSpacing.lg)
                .environment(\.font, AppFont.body)
            }

            if folder.isExpanded {
                if childPins.isEmpty {
                    Text("Right-click a pin to move here")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textMuted)
                        .padding(.leading, 38)
                        .padding(.vertical, AppSpacing.xs)
                } else {
                    ForEach(childPins) { pin in
                        pinnedRow(for: pin)
                            .padding(.leading, AppSpacing.lg)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pinnedRow(for item: PinnedItem) -> some View {
        let isHovered = hoveredPinID == item.id
        let isSelected = controller.selectedTab?.url.absoluteString == item.urlString
        let siblings = controller.pins(inFolder: item.folderID)
        let pinIndex = siblings.firstIndex(where: { $0.id == item.id })
        let pinCount = siblings.count
        let isRenaming = Binding<Bool>(
            get: { renamingPinID == item.id },
            set: { if !$0 && renamingPinID == item.id { renamingPinID = nil } }
        )

        Button {
            controller.openPinnedItem(item)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: YouTubeURLRouter.pinnedItemIcon(for: item.urlString))
                    .font(AppIconFont.md)
                    .foregroundStyle(AppleTheme.accentText.opacity(controlActiveState == .inactive ? 0.65 : 0.90))
                    .frame(width: 18, alignment: .center)

                Text(item.title)
                    .font(AppFont.body(weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(controlActiveState == .inactive ? 0.055 : 0.11)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPinID = hovering ? item.id : (hoveredPinID == item.id ? nil : hoveredPinID)
        }
        .contextMenu {
            if let url = item.url {
                Button("Open in New Tab") {
                    controller.createTab(
                        url: url,
                        select: true,
                        routingMode: YouTubeURLRouter.preferredRoutingMode(for: url)
                    )
                }
                Button("Open in New Window") {
                    controller.openURLInNewWindow(url)
                }
            }
            Button("Rename…") {
                renamePinDraft = item.title
                renamingPinID = item.id
            }

            Menu("Move to Folder") {
                Button {
                    controller.movePinToFolder(pinID: item.id, folderID: nil)
                } label: {
                    if item.folderID == nil {
                        Label("Ungrouped", systemImage: "checkmark")
                    } else {
                        Text("Ungrouped")
                    }
                }

                if !controller.settings.pinnedFolders.isEmpty {
                    Divider()
                    ForEach(controller.settings.pinnedFolders) { folder in
                        Button {
                            controller.movePinToFolder(pinID: item.id, folderID: folder.id)
                        } label: {
                            if item.folderID == folder.id {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                }

                Divider()
                Button("New Folder…") {
                    movePinAfterFolderCreateID = item.id
                    newFolderNameDraft = ""
                    isNewFolderPopoverPresented = true
                }
            }

            if let idx = pinIndex, pinCount > 1 {
                Divider()
                if idx > 0 {
                    Button("Move Up") {
                        controller.movePin(id: item.id, by: -1)
                    }
                }
                if idx < pinCount - 1 {
                    Button("Move Down") {
                        controller.movePin(id: item.id, by: 1)
                    }
                }
            }
            Divider()
            Button("Unpin", role: .destructive) {
                controller.removePin(id: item.id)
            }
        }
        .popover(isPresented: isRenaming, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Rename Pinned Item")
                    .font(AppFont.body(weight: .semibold))
                TextField("Title", text: $renamePinDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.body)
                    .frame(width: 200)
                    .onSubmit {
                        controller.renamePin(id: item.id, newTitle: renamePinDraft)
                        renamingPinID = nil
                    }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        renamingPinID = nil
                    }
                    .font(AppFont.callout(weight: .medium))
                    Button("Save") {
                        controller.renamePin(id: item.id, newTitle: renamePinDraft)
                        renamingPinID = nil
                    }
                    .font(AppFont.callout(weight: .semibold))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(AppSpacing.lg)
            .environment(\.font, AppFont.body)
        }
    }

    @ViewBuilder
    private func multiviewPresetRow(for preset: MultiviewPreset) -> some View {
        let isHovered = hoveredPresetID == preset.id
        let isRenaming = Binding<Bool>(
            get: { renamingPresetID == preset.id },
            set: { if !$0 && renamingPresetID == preset.id { renamingPresetID = nil } }
        )

        Button {
            controller.launchMultiviewPreset(preset)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(AppIconFont.md)
                    .foregroundStyle(AppleTheme.accentText)
                    .frame(width: 18, alignment: .center)

                Text(preset.name)
                    .font(AppFont.body)
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text("\(preset.urlStrings.count)×")
                    .font(AppFont.micro(weight: .semibold, tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPresetID = hovering ? preset.id : (hoveredPresetID == preset.id ? nil : hoveredPresetID)
        }
        .contextMenu {
            Button("Launch Preset") {
                controller.launchMultiviewPreset(preset)
            }
            Button("Launch Preset in New Window") {
                controller.launchPresetInNewWindow(preset)
            }
            Button("Rename…") {
                renamePresetDraft = preset.name
                renamingPresetID = preset.id
            }
            Button("Export Preset (.json)…") {
                let sanitizedFile = preset.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "/", with: "-")
                let baseName = sanitizedFile.isEmpty ? "Multiview-Preset" : sanitizedFile
                exportMultiviewPresets([preset], suggestedFilename: "\(baseName).json")
            }
            Divider()
            Button("Delete Preset", role: .destructive) {
                controller.deleteMultiviewPreset(id: preset.id)
            }
        }
        .popover(isPresented: isRenaming, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Rename Multiview Preset")
                    .font(AppFont.body(weight: .semibold))
                TextField("Preset Name", text: $renamePresetDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(AppFont.body)
                    .frame(width: 200)
                    .onSubmit {
                        controller.renameMultiviewPreset(id: preset.id, newName: renamePresetDraft)
                        renamingPresetID = nil
                    }
                HStack {
                    Spacer()
                    Button("Cancel") {
                        renamingPresetID = nil
                    }
                    .font(AppFont.callout(weight: .medium))
                    Button("Save") {
                        controller.renameMultiviewPreset(id: preset.id, newName: renamePresetDraft)
                        renamingPresetID = nil
                    }
                    .font(AppFont.callout(weight: .semibold))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(AppSpacing.lg)
            .environment(\.font, AppFont.body)
        }
    }

    private func exportMultiviewPresets(_ presets: [MultiviewPreset]?, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        panel.title = "Export Multiview Presets"
        panel.message = "Save a portable JSON backup of your Multiview presets."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try controller.exportMultiviewPresetsData(presets: presets)
            try data.write(to: url, options: .atomic)
            let count = presets?.count ?? controller.settings.savedMultiviewPresets.count
            controller.showHUD(
                icon: "square.and.arrow.up",
                message: "Exported \(count) Multiview \(count == 1 ? "Preset" : "Presets")"
            )
        } catch {
            controller.showHUD(icon: "exclamationmark.triangle", message: error.localizedDescription)
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
        do {
            let data = try Data(contentsOf: url)
            _ = try controller.importMultiviewPresets(from: data)
        } catch {
            controller.showHUD(icon: "exclamationmark.triangle", message: error.localizedDescription)
        }
    }

    private func iconName(for destination: SidebarDestination, selected: Bool) -> String {
        switch destination {
        case .home: return selected ? "house.fill" : "house"
        case .subscriptions: return selected ? "rectangle.stack.badge.play.fill" : "rectangle.stack.badge.play"
        case .history: return "clock.arrow.circlepath"
        case .watchLater: return selected ? "clock.fill" : "clock"
        case .likedVideos: return selected ? "hand.thumbsup.fill" : "hand.thumbsup"
        case .playlists: return selected ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
        case .shorts: return selected ? "bolt.fill" : "bolt"
        }
    }
}
