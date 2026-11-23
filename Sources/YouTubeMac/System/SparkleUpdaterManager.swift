import AppKit
import Foundation
import Observation
import Sparkle
import YouTubeMacCore

/// Coordinates Sparkle 2 silent auto-updates when signed/configured with `SUFeedURL` + `SUPublicEDKey`,
/// and silently falls back to the zero-dependency GitHub Releases `UpdateChecker` in open-source forks,
/// unsigned dev builds, and CI (zero startup dialogs or console noise).
@MainActor
@Observable
public final class SparkleUpdaterManager {
    public let isSparkleConfigured: Bool
    public var isCheckingForUpdates: Bool = false
    public var lastUpdateCheckResult: ReleaseCheckResult?

    @ObservationIgnored
    private let settings: AppSettings

    @ObservationIgnored
    private let sparkleController: SPUStandardUpdaterController?

    public init(settings: AppSettings) {
        self.settings = settings
        let configured = SparkleConfiguration.isConfigured(infoDictionary: Bundle.main.infoDictionary)
        self.isSparkleConfigured = configured

        if configured {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
            self.sparkleController = controller
        } else {
            self.sparkleController = nil
        }
    }

    public var currentAppVersion: String {
        if let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "1.0.0"
    }

    public var automaticallyChecksForUpdates: Bool {
        get {
            if let sparkleController {
                return sparkleController.updater.automaticallyChecksForUpdates
            }
            return settings.automaticallyChecksForUpdates
        }
        set {
            settings.automaticallyChecksForUpdates = newValue
            if let sparkleController {
                sparkleController.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    public var canCheckForUpdates: Bool {
        if let sparkleController {
            return sparkleController.updater.canCheckForUpdates
        }
        return !isCheckingForUpdates
    }

    /// Opens a validated `https://` GitHub URL in the user's default browser.
    public func openTrustedGitHubURL(_ url: URL) {
        guard UpdateChecker.isTrustedGitHubDownloadURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Triggers native Sparkle 2 update UI when configured, or falls back transparently to `UpdateChecker`.
    public func checkForUpdates(presentAlert: Bool) {
        if let sparkleController {
            sparkleController.checkForUpdates(nil)
            return
        }

        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        let versionString = currentAppVersion

        Task { @MainActor [weak self] in
            let result = await UpdateChecker.checkLatestRelease(currentVersionString: versionString)
            guard let self else { return }
            self.lastUpdateCheckResult = result
            self.isCheckingForUpdates = false
            if presentAlert {
                self.presentFallbackUpdateAlert(result)
            }
        }
    }

    private func presentFallbackUpdateAlert(_ result: ReleaseCheckResult) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch result {
        case .updateAvailable(let current, let latest):
            alert.messageText = "GlassGrid You \(latest.tagName) is Available"
            alert.informativeText = "You are currently running v\(current). Would you like to download the latest release from GitHub?"
            alert.addButton(withTitle: "Download Release")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                openTrustedGitHubURL(latest.preferredDownloadURL)
            }

        case .upToDate(let current):
            alert.messageText = "You’re Up to Date"
            alert.informativeText = "GlassGrid You v\(current) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .noReleasesPublished:
            alert.messageText = "No Releases Published Yet"
            alert.informativeText = "GlassGrid You v\(currentAppVersion) has no published GitHub Release builds yet."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "View Releases")
            if alert.runModal() == .alertSecondButtonReturn {
                openTrustedGitHubURL(UpdateChecker.releasesPageURL)
            }

        case .failed(let message):
            alert.messageText = "Unable to Check for Updates"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
