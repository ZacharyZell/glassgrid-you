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
        VStack(spacing: isCompactTile ? 10 : 14) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accent.opacity(0.14))
                    .frame(width: isCompactTile ? 40 : 54, height: isCompactTile ? 40 : 54)
                Image(systemName: iconName)
                    .font(.system(size: isCompactTile ? 16 : 21, weight: .semibold))
                    .foregroundStyle(AppleTheme.accent)
            }

            VStack(spacing: 4) {
                Text(titleText)
                    .font(.system(size: isCompactTile ? 13.5 : 16, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(error.message)
                    .font(.system(size: isCompactTile ? 11.5 : 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(isCompactTile ? 2 : 3)
                    .frame(maxWidth: isCompactTile ? 260 : 380)
            }

            LiquidGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onRetry) {
                        Label(isCompactTile ? "Try Again" : "Try Again (⌘R)", systemImage: "arrow.clockwise")
                            .font(.system(size: isCompactTile ? 11.5 : 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, isCompactTile ? 12 : 14)
                            .padding(.vertical, isCompactTile ? 6 : 7)
                            .background(AppleTheme.accent, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if let onGoHome, !isCompactTile {
                        Button(action: onGoHome) {
                            Label("YouTube Home", systemImage: "house")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .appleGlass(in: Capsule(style: .continuous), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(isCompactTile ? 18 : 28)
        .appleGlass(in: RoundedRectangle(cornerRadius: isCompactTile ? 14 : 20, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: isCompactTile ? 10 : 18, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTheme.canvasColor.opacity(isCompactTile ? 0.94 : 1.0), ignoresSafeAreaEdges: [])
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
