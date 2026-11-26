import AppKit
import SwiftUI
import YouTubeMacCore

/// Spotlight-style macOS 26/27 Liquid Glass Command Palette (`⌘K`) searching Open Tabs, Saved Multiview Presets,
/// Continue Watching, Pinned & Watched Channels, App Actions (with shortcut hints), and live YouTube autocomplete.
struct CommandPaletteView: View {
    @Bindable var controller: AppController
    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex: Int = 0
    @State private var hoveredItemID: String?

    private var items: [CommandPaletteItem] {
        controller.commandPaletteItems
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Subtle click-to-dismiss scrim (mounted only while palette is open)
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    controller.dismissCommandPalette(refocusWebView: true)
                }

            VStack(spacing: 0) {
                searchHeader

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                resultsList

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                footerHints
            }
            .frame(maxWidth: 580)
            .appleGlass(in: RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .shadow(color: .black.opacity(0.26), radius: 28, y: 12)
            .padding(.top, 54)
            .padding(.horizontal, AppSpacing.xxl)
        }
        .onAppear {
            selectedIndex = 0
            focusSearchField()
        }
        .onChange(of: controller.commandPaletteFocusTrigger) { _, _ in
            selectedIndex = 0
            focusSearchField()
        }
        .onChange(of: controller.commandPaletteQuery) { _, _ in
            selectedIndex = 0
            controller.scheduleCommandPaletteSuggestions()
        }
        .onChange(of: items.count) { _, newCount in
            if newCount == 0 {
                selectedIndex = 0
            } else if selectedIndex >= newCount {
                selectedIndex = newCount - 1
            }
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(AppIconFont.nav(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)

            TextField("Search YouTube, open tabs, presets, or actions…", text: $controller.commandPaletteQuery)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .focused($isSearchFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onSubmit {
                    executeSelectedItem()
                }
                .onExitCommand {
                    controller.dismissCommandPalette(refocusWebView: true)
                }

            if !controller.commandPaletteQuery.isEmpty {
                Button {
                    controller.commandPaletteQuery = ""
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppIconFont.nav())
                        .foregroundStyle(AppleTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }

            Text("ESC")
                .font(AppFont.micro(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(height: 48)
    }

    @ViewBuilder
    private var resultsList: some View {
        let currentItems = items
        if currentItems.isEmpty {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppIconFont.xl)
                    .foregroundStyle(AppleTheme.textMuted)
                Text("Type to search YouTube, jump to a tab, or run an action")
                    .font(AppFont.callout)
                    .foregroundStyle(AppleTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || currentItems[index - 1].section != item.section {
                                Text(item.section.title)
                                    .font(AppFont.caption(weight: .semibold))
                                    .foregroundStyle(AppleTheme.textSecondary)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.top, index == 0 ? AppSpacing.sm : AppSpacing.md)
                                    .padding(.bottom, AppSpacing.xxs)
                            }

                            paletteRow(item: item, isSelected: index == selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    controller.executeCommandPaletteItem(item)
                                }
                                .onHover { hovering in
                                    hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                                    if hovering {
                                        selectedIndex = index
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.md)
                }
                .frame(maxHeight: 360)
                .onChange(of: selectedIndex) { _, newIdx in
                    if currentItems.indices.contains(newIdx) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            scrollProxy.scrollTo(currentItems[newIdx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func paletteRow(item: CommandPaletteItem, isSelected: Bool) -> some View {
        let isHovered = hoveredItemID == item.id
        HStack(spacing: AppSpacing.md) {
            Image(systemName: item.systemImage)
                .font(AppIconFont.toolbar(weight: .semibold))
                .foregroundStyle(
                    item.isActiveAudio || isSelected
                        ? AppleTheme.accentText
                        : AppleTheme.textSecondary
                )
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.title)
                    .font(AppFont.body(weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: AppSpacing.md)

            if let badge = item.badgeText {
                Text(badge)
                    .font(AppFont.micro(weight: .semibold, tabular: true))
                    .foregroundStyle(item.isActiveAudio ? .white : AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(item.isActiveAudio ? AppleTheme.accentFill : Color.primary.opacity(0.09))
                    )
            }

            if let shortcut = item.shortcutHint {
                Text(shortcut)
                    .font(AppFont.micro(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                            .fill(Color.primary.opacity(isSelected ? 0.12 : 0.07))
                    )
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(
                    isSelected
                        ? AppleTheme.accentText.opacity(0.14)
                        : (isHovered ? Color.primary.opacity(0.06) : .clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
    }

    @ViewBuilder
    private var footerHints: some View {
        HStack(spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.xs) {
                Text("↑↓")
                    .font(AppFont.micro(weight: .semibold))
                Text("Navigate")
                    .font(AppFont.caption)
            }
            HStack(spacing: AppSpacing.xs) {
                Text("↩")
                    .font(AppFont.micro(weight: .semibold))
                Text("Open / Run")
                    .font(AppFont.caption)
            }
            Spacer()
            Text("⌘L to edit URL directly")
                .font(AppFont.caption)
        }
        .foregroundStyle(AppleTheme.textSecondary)
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: 30)
    }

    private func focusSearchField() {
        isSearchFocused = true
    }

    private func moveSelection(by delta: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    private func executeSelectedItem() {
        let currentItems = items
        guard currentItems.indices.contains(selectedIndex) else {
            let trimmed = controller.commandPaletteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               let resolved = YouTubeURLRouter.resolveOmniboxInput(
                   trimmed,
                   redirectShortsToWatch: controller.settings.redirectShortsToWatch
               ) {
                controller.dismissCommandPalette(refocusWebView: false)
                controller.navigateSelectedTab(to: resolved)
                controller.focusActiveWebView()
            }
            return
        }
        controller.executeCommandPaletteItem(currentItems[selectedIndex])
    }
}
