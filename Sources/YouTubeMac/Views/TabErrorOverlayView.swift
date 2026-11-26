import SwiftUI
import YouTubeMacCore

/// Per-tab Liquid Glass recovery card for offline errors, navigation failures, or WebContent process termination.
/// Supports both full single-tab presentation and compact tile-scoped Multiview presentation.
struct TabErrorOverlayView: View {
    let error: TabLoadError
    var isCompactTile: Bool = false
    let onRetry: () -> Void
    var onGoHome: (() -> Void)? = nil

    var body: some View {
        GlassRecoveryCard(
            systemImage: iconName,
            title: titleText,
            message: error.message,
            isCompactTile: isCompactTile,
            messageLineLimit: isCompactTile ? 2 : 3,
            primaryAction: GlassRecoveryAction(
                isCompactTile ? "Try Again" : "Try Again (⌘R)",
                systemImage: "arrow.clockwise",
                action: onRetry
            ),
            secondaryActions: secondaryActions
        )
    }

    private var secondaryActions: [GlassRecoveryAction] {
        guard let onGoHome, !isCompactTile else { return [] }
        return [
            GlassRecoveryAction("YouTube Home", systemImage: "house", action: onGoHome)
        ]
    }

    private var iconName: String {
        if error.isOffline {
            return "wifi.slash"
        }
        if error.isProcessCrash {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        return "exclamationmark.triangle"
    }

    private var titleText: String {
        if error.isOffline {
            return "Unable to Connect"
        }
        if error.isProcessCrash {
            return "Page Stopped Responding"
        }
        return "Couldn't Load Page"
    }
}
