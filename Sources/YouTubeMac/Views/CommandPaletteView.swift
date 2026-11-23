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
            .appleGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.26), radius: 28, y: 12)
            .padding(.top, 54)
            .padding(.horizontal, 20)
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
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppleTheme.accent)

            TextField("Search YouTube, open tabs, presets, or actions…", text: $controller.commandPaletteQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
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
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }

            Text("ESC")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    @ViewBuilder
    private var resultsList: some View {
        let currentItems = items
        if currentItems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("Type to search YouTube, jump to a tab, or run an action")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                            if index == 0 || currentItems[index - 1].section != item.section {
                                Text(item.section.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, index == 0 ? 6 : 10)
                                    .padding(.bottom, 3)
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
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
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
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    item.isActiveAudio || isSelected
                        ? AppleTheme.accent
                        : Color.secondary
                )
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if let badge = item.badgeText {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(item.isActiveAudio ? .white : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(item.isActiveAudio ? AppleTheme.accent : Color.primary.opacity(0.09))
                    )
            }

            if let shortcut = item.shortcutHint {
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(isSelected ? 0.12 : 0.07))
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? AppleTheme.accent.opacity(0.14)
                        : (isHovered ? Color.primary.opacity(0.06) : .clear)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var footerHints: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Text("↑↓")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text("Navigate")
                    .font(.system(size: 10.5))
            }
            HStack(spacing: 4) {
                Text("↩")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text("Open / Run")
                    .font(.system(size: 10.5))
            }
            Spacer()
            Text("⌘L to edit URL directly")
                .font(.system(size: 10.5))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
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
