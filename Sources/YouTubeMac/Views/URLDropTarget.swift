import SwiftUI
import UniformTypeIdentifiers
import YouTubeMacCore

/// Chrome-only drag-and-drop modifier accepting YouTube / YouTube TV URLs (and optionally Companion HTTPS URLs
/// when `allowCompanionURLs` is true, e.g. on `MultiviewControlBar`).
/// Attached strictly to native chrome bars (`topHeaderBar`, `TabStripView`, `SidebarView`, `MultiviewControlBar`),
/// NEVER over `TabWebViewHost` or video player scrubbers.
private struct YouTubeURLDropTargetModifier: ViewModifier {
    let controller: AppController
    let allowCompanionURLs: Bool
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
        let acceptCompanion = allowCompanionURLs
        var accepted = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.url.identifier) { data, _ in
                    guard let data,
                          let raw = String(data: data, encoding: .utf8) else {
                        return
                    }
                    if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(raw) {
                        Task { @MainActor in
                            controllerRef.handleDroppedURL(ytURL)
                        }
                    } else if acceptCompanion, let webURL = YouTubeURLRouter.resolveCompanionURL(raw) {
                        Task { @MainActor in
                            controllerRef.handleDroppedCompanionURL(webURL)
                        }
                    }
                }
                break
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    guard let data,
                          let raw = String(data: data, encoding: .utf8) else {
                        return
                    }
                    if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(raw) {
                        Task { @MainActor in
                            controllerRef.handleDroppedURL(ytURL)
                        }
                    } else if acceptCompanion, let webURL = YouTubeURLRouter.resolveCompanionURL(raw) {
                        Task { @MainActor in
                            controllerRef.handleDroppedCompanionURL(webURL)
                        }
                    }
                }
                break
            }
        }
        return accepted
    }
}

extension View {
    func youtubeURLDropTarget(controller: AppController, allowCompanionURLs: Bool = false) -> some View {
        modifier(YouTubeURLDropTargetModifier(controller: controller, allowCompanionURLs: allowCompanionURLs))
    }
}
