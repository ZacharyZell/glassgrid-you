import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

/// Chrome-only drag-and-drop modifier accepting YouTube / YouTube TV URLs and plain-text links.
/// Attached strictly to native chrome bars (`topHeaderBar`, `TabStripView`, `SidebarView`, `MultiviewControlBar`),
/// NEVER over `TabWebViewHost` or video player scrubbers.
private struct YouTubeURLDropTargetModifier: ViewModifier {
    let controller: AppController
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppleTheme.accent.opacity(isTargeted ? 0.75 : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .onDrop(of: [UTType.url, UTType.plainText], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let controllerRef = controller
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                    guard let data,
                          let raw = String(data: data, encoding: .utf8),
                          let url = YouTubeURLRouter.extractYouTubeURLFromString(raw) else {
                        return
                    }
                    Task { @MainActor in
                        controllerRef.handleDroppedURL(url)
                    }
                }
                break
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data,
                          let raw = String(data: data, encoding: .utf8),
                          let url = YouTubeURLRouter.extractYouTubeURLFromString(raw) else {
                        return
                    }
                    Task { @MainActor in
                        controllerRef.handleDroppedURL(url)
                    }
                }
                break
            }
        }
        return accepted
    }
}

extension View {
    func youtubeURLDropTarget(controller: AppController) -> some View {
        modifier(YouTubeURLDropTargetModifier(controller: controller))
    }
}
