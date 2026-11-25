import AppKit
import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

/// Strictly middle-click-only detector that returns `nil` from `hitTest(_:)` for all left/right/hover/drag events
/// so SwiftUI taps, context menus, hover highlights, close buttons, and drag-to-reorder stay 100% untouched.
private final class MiddleClickNSView: NSView {
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

private struct MiddleClickDetector: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> MiddleClickNSView {
        let view = MiddleClickNSView(frame: .zero)
        view.onMiddleClick = onMiddleClick
        return view
    }

    func updateNSView(_ nsView: MiddleClickNSView, context: Context) {
        nsView.onMiddleClick = onMiddleClick
    }
}

/// Safari-compact Liquid Glass multi-tab strip displayed when multiple tabs are open or when configured to always show.
struct TabStripView: View {
    private static let internalTabDragPrefix = "ytmac-tab:"

    @Bindable var controller: AppController
    @State private var hoveredTabID: UUID?
    @State private var hoveredCloseTabID: UUID?
    @State private var dropTargetedTabID: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LiquidGlassGroup(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(controller.tabs) { tab in
                                tabPill(for: tab)
                                    .id(tab.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }
                .onChange(of: controller.selectedTabID) { _, newID in
                    withAnimation(.easeOut(duration: 0.18)) {
                        scrollProxy.scrollTo(newID, anchor: .center)
                    }
                }
            }

            AppleIconButton(systemImage: "plus", helpText: "New Tab (⌘T) — Right-Click for Streaming Services") {
                controller.createTab()
            }
            .appleGlass(in: Circle(), interactive: true)
            .contextMenu {
                ForEach(controller.settings.enabledStreamingServices) { service in
                    Button {
                        controller.openStreamingService(service, inNewTab: true)
                    } label: {
                        Label("Open \(service.name)", systemImage: service.symbolName)
                    }
                }
                Divider()
                Button("Manage Streaming Services…") {
                    controller.openStreamingServicesSetup(step: 1)
                }
            }
            .padding(.trailing, 10)
        }
        .frame(height: 36)
        .background(AppleTheme.canvasColor, ignoresSafeAreaEdges: [])
        .youtubeURLDropTarget(controller: controller)
    }

    @ViewBuilder
    private func tabPill(for tab: BrowserTab) -> some View {
        let isSelected = tab.id == controller.selectedTabID
        let isHovered = hoveredTabID == tab.id
        let showClose = controller.tabs.count > 1 && (isSelected || isHovered)
        let multiviewSlot = controller.multiviewSlotNumber(for: tab.id)
        let isMultiviewAudio = controller.isMultiviewActive && controller.multiviewAudioTab?.id == tab.id

        let pillContent = HStack(spacing: 6) {
            if let multiviewSlot {
                Text("\(multiviewSlot)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(isMultiviewAudio ? .white : Color.primary.opacity(0.8))
                    .frame(width: 15, height: 15)
                    .background(
                        Circle()
                            .fill(isMultiviewAudio ? AppleTheme.accent : Color.primary.opacity(0.12))
                    )
            }

            tabLeadingIcon(for: tab)

            Text(tab.displayTitle)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(
                    isSelected
                        ? Color.primary
                        : Color.primary.opacity(tab.isSleeping ? 0.50 : 0.75)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            if showClose {
                let isCloseHovered = hoveredCloseTabID == tab.id
                Button {
                    controller.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isCloseHovered ? Color.primary : .secondary)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color.primary.opacity(isCloseHovered ? 0.18 : 0.09)))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredCloseTabID = hovering ? tab.id : (hoveredCloseTabID == tab.id ? nil : hoveredCloseTabID)
                }
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .contentShape(Capsule(style: .continuous))

        Group {
            if isSelected {
                pillContent
                    .appleGlass(in: Capsule(style: .continuous), interactive: true)
            } else if multiviewSlot != nil {
                pillContent
                    .background(
                        Capsule(style: .continuous)
                            .fill(isHovered ? AppleTheme.accent.opacity(0.12) : Color.primary.opacity(0.06))
                    )
            } else {
                pillContent
                    .background(
                        Capsule(style: .continuous)
                            .fill(isHovered ? Color.primary.opacity(0.07) : Color.primary.opacity(0.03))
                    )
            }
        }
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(AppleTheme.accent.opacity(dropTargetedTabID == tab.id ? 0.85 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .overlay(
            MiddleClickDetector {
                if controller.tabs.count > 1 && !controller.anyTabInFullscreen {
                    controller.closeTab(id: tab.id)
                }
            }
        )
        .onTapGesture {
            controller.selectTab(id: tab.id)
        }
        .onDrag {
            NSItemProvider(object: "\(Self.internalTabDragPrefix)\(tab.id.uuidString)" as NSString)
        }
        .onDrop(
            of: [UTType.plainText, UTType.url],
            isTargeted: Binding(
                get: { dropTargetedTabID == tab.id },
                set: { targeted in
                    if targeted {
                        dropTargetedTabID = tab.id
                    } else if dropTargetedTabID == tab.id {
                        dropTargetedTabID = nil
                    }
                }
            )
        ) { providers in
            handleTabPillDrop(providers: providers, targetTabID: tab.id)
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
        .contextMenu {
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
            if tab.mediaStatus.hasVideo || controller.isTabPoppedOut(tab.id) || controller.isMultiviewActive || controller.canPutTabToSleep(id: tab.id) || showCleanBoxAction {
                Divider()
            }
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
    private func tabLeadingIcon(for tab: BrowserTab) -> some View {
        if controller.isTabPoppedOut(tab.id) {
            Image(systemName: "pip.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppleTheme.accent)
        } else if tab.mediaStatus.hasVideo && (tab.mediaStatus.isPlaying || tab.mediaStatus.isMuted) {
            Button {
                controller.toggleMute(tabID: tab.id)
            } label: {
                Image(systemName: tab.mediaStatus.isMuted ? "speaker.slash.fill" : "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tab.mediaStatus.isMuted ? .secondary : AppleTheme.accent)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tab.mediaStatus.isMuted ? "Unmute Tab" : "Mute Tab")
        } else if tab.isSleeping {
            Image(systemName: "moon.zzz")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.75))
        } else if tab.isLoading {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.65)
        } else {
            Image(systemName: tab.isCompanionTab ? "globe" : "play.rectangle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func handleTabPillDrop(providers: [NSItemProvider], targetTabID: UUID) -> Bool {
        let controllerRef = controller
        let prefix = Self.internalTabDragPrefix

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data, let raw = String(data: data, encoding: .utf8) else { return }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix(prefix),
                       let draggedID = UUID(uuidString: String(trimmed.dropFirst(prefix.count))) {
                        Task { @MainActor in
                            controllerRef.moveTab(fromID: draggedID, toID: targetTabID)
                        }
                    } else if let externalURL = YouTubeURLRouter.extractYouTubeURLFromString(trimmed) {
                        Task { @MainActor in
                            controllerRef.handleDroppedURL(externalURL)
                        }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                    guard let data,
                          let raw = String(data: data, encoding: .utf8),
                          let externalURL = YouTubeURLRouter.extractYouTubeURLFromString(raw) else {
                        return
                    }
                    Task { @MainActor in
                        controllerRef.handleDroppedURL(externalURL)
                    }
                }
                return true
            }
        }
        return false
    }
}
