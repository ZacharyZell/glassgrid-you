import AppKit
import SwiftUI
import YouTubeMacCore

/// macOS 26/27 Liquid Glass floating inset sidebar with concentric corners and adaptive crimson SF Symbols.
struct SidebarView: View {
    @Bindable var controller: AppController
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var hoveredDestination: SidebarDestination?
    @State private var hoveredPinID: UUID?
    @State private var hoveredPresetID: UUID?
    @State private var isPresetsExpanded = true
    @State private var renamingPresetID: UUID?
    @State private var renamePresetDraft = ""
    @State private var renamingPinID: UUID?
    @State private var renamePinDraft = ""
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
                    .padding(.leading, 68)
                    .padding(.trailing, 8)
                }
                .frame(height: 36)

                // Original Liquid Glass brand mark
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.24, green: 0.08, blue: 0.13),
                                        Color(red: 0.84, green: 0.10, blue: 0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.85)
                                    .padding(3.5)
                            )

                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.white)
                            .offset(x: 0.5)
                    }

                    Text("GlassGrid You")
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .tracking(-0.2)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)

                // Scrollable navigation sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 2) {
                            ForEach(browseDestinations) { destination in
                                sidebarRow(for: destination)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader("Library")
                            ForEach(libraryDestinations) { destination in
                                sidebarRow(for: destination)
                            }
                        }

                        if !controller.settings.savedMultiviewPresets.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Button {
                                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                                        isPresetsExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        sectionHeader("Multiview Presets")
                                        Spacer()
                                        Image(systemName: isPresetsExpanded ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.secondary.opacity(0.75))
                                            .padding(.trailing, 8)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isPresetsExpanded {
                                    ForEach(controller.settings.savedMultiviewPresets) { preset in
                                        multiviewPresetRow(for: preset)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader("Pinned")

                            if controller.settings.pinnedItems.isEmpty {
                                Text("Press ⌘D to pin channels or playlists")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                            } else {
                                ForEach(controller.settings.pinnedItems) { item in
                                    pinnedRow(for: item)
                                }
                            }

                            // Only offer to pin custom channels/playlists/videos — never permanent sidebar destinations.
                            if activeDestination == nil, !controller.isCurrentPagePinned, controller.selectedTab != nil {
                                Button {
                                    controller.togglePinCurrentPage()
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 18)
                                        Text("Pin Current Page")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(isPinActionHovered ? Color.primary.opacity(0.07) : .clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .onHover { isPinActionHovered = $0 }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                // Airy Apple-style bottom utility row
                HStack(spacing: 4) {
                    Button {
                        controller.openSignIn()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            Text("Account")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.85))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isAccountHovered ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(Capsule(style: .continuous))
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isThemeHovered ? Color.primary : .secondary)
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
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(isSettingsHovered ? Color.primary : .secondary)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
            .appleGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(isResolvedDark ? 0.28 : 0.08), radius: 10, y: 2)
            .youtubeURLDropTarget(controller: controller)
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.bottom, 3)
    }

    @ViewBuilder
    private func sidebarRow(for destination: SidebarDestination) -> some View {
        let isSelected = activeDestination == destination
        let isHovered = hoveredDestination == destination

        Button {
            controller.navigateSelectedTab(to: destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: destination, selected: isSelected))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppleTheme.accent)
                    .frame(width: 18, alignment: .center)

                Text(destination.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(controlActiveState == .inactive ? 0.055 : 0.11)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDestination = hovering ? destination : (hoveredDestination == destination ? nil : hoveredDestination)
        }
        .contextMenu {
            Button("Open in New Tab") {
                controller.createTab(url: destination.url, select: true)
            }
        }
    }

    @ViewBuilder
    private func pinnedRow(for item: PinnedItem) -> some View {
        let isHovered = hoveredPinID == item.id
        let isSelected = controller.selectedTab?.url.absoluteString == item.urlString
        let pinIndex = controller.settings.pinnedItems.firstIndex(where: { $0.id == item.id })
        let pinCount = controller.settings.pinnedItems.count
        let isRenaming = Binding<Bool>(
            get: { renamingPinID == item.id },
            set: { if !$0 && renamingPinID == item.id { renamingPinID = nil } }
        )

        Button {
            if let url = item.url {
                controller.navigateSelectedTab(to: url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: YouTubeURLRouter.pinnedItemIcon(for: item.urlString))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppleTheme.accent.opacity(0.85))
                    .frame(width: 18, alignment: .center)

                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.primary.opacity(controlActiveState == .inactive ? 0.055 : 0.11)
                            : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPinID = hovering ? item.id : (hoveredPinID == item.id ? nil : hoveredPinID)
        }
        .contextMenu {
            if let url = item.url {
                Button("Open in New Tab") {
                    controller.createTab(url: url, select: true)
                }
            }
            Button("Rename…") {
                renamePinDraft = item.title
                renamingPinID = item.id
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename Pinned Item")
                    .font(.system(size: 12.5, weight: .semibold))
                TextField("Title", text: $renamePinDraft)
                    .textFieldStyle(.roundedBorder)
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
                    Button("Save") {
                        controller.renamePin(id: item.id, newTitle: renamePinDraft)
                        renamingPinID = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
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
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppleTheme.accent.opacity(0.88))
                    .frame(width: 18, alignment: .center)

                Text(preset.name)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text("\(preset.urlStrings.count)×")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredPresetID = hovering ? preset.id : (hoveredPresetID == preset.id ? nil : hoveredPresetID)
        }
        .contextMenu {
            Button("Launch Preset") {
                controller.launchMultiviewPreset(preset)
            }
            Button("Rename…") {
                renamePresetDraft = preset.name
                renamingPresetID = preset.id
            }
            Divider()
            Button("Delete Preset", role: .destructive) {
                controller.deleteMultiviewPreset(id: preset.id)
            }
        }
        .popover(isPresented: isRenaming, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rename Multiview Preset")
                    .font(.system(size: 12.5, weight: .semibold))
                TextField("Preset Name", text: $renamePresetDraft)
                    .textFieldStyle(.roundedBorder)
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
                    Button("Save") {
                        controller.renameMultiviewPreset(id: preset.id, newName: renamePresetDraft)
                        renamingPresetID = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(12)
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
        case .shorts: return "bolt.fill"
        }
    }
}
