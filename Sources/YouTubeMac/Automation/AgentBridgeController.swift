import AppKit
import Foundation
import Observation
import WebKit
import YouTubeMacCore

/// Centralized `@MainActor` automation gateway enforcing the Master Kill Switch, 3-tier Permission Model,
/// live WebKit fullscreen immutability, strict precondition checks, web-content sanitization, and activity auditing
/// uniformly across MCP (stdio & HTTP), CLI, AppIntents, and `glassgridyou://action/...`.
@MainActor
@Observable
public final class AgentBridgeController: AgentCommandExecutor {
    public private(set) var unixSocketStatus: AgentUnixSocketStatus = .stopped
    public private(set) var httpServerStatus: AgentHTTPServerStatus = .disabled
    public private(set) var activityLog: [AgentActivityEntry] = []
    public private(set) var currentHTTPToken: String = ""

    @ObservationIgnored
    private weak var coordinator: AppCoordinator?

    @ObservationIgnored
    private let tokenStore = AgentTokenStore()

    @ObservationIgnored
    private var unixSocketServer: AgentUnixSocketServer?

    @ObservationIgnored
    private var httpServer: AgentHTTPServer?

    @ObservationIgnored
    private var windowReadyContinuations: [CheckedContinuation<Void, Never>] = []

    @ObservationIgnored
    private var isShutDown = false

    private static let maxActivityEntries = 100

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.currentHTTPToken = tokenStore.loadOrCreateToken()

        self.unixSocketServer = AgentUnixSocketServer(executor: self) { [weak self] status in
            self?.unixSocketStatus = status
        }
        self.httpServer = AgentHTTPServer(executor: self) { [weak self] status in
            self?.httpServerStatus = status
        }
    }

    public var isAutomationEnabled: Bool {
        coordinator?.settings.agentControlEnabled ?? false
    }

    public var currentPermissionTier: AgentPermissionLevel {
        coordinator?.settings.agentPermissionLevel ?? .playbackAndNavigation
    }

    public var resolvedSocketPath: String {
        AgentSocketPath.resolve(overridePath: ProcessInfo.processInfo.environment["GLASSGRID_SOCKET_PATH"]).socketPath
    }

    // MARK: - Server Lifecycle & Readiness

    public func startServersIfEnabled() {
        guard !isShutDown else { return }
        reconcileServerState()
    }

    public func reconcileServerState() {
        guard !isShutDown, let settings = coordinator?.settings else { return }

        if settings.agentControlEnabled {
            unixSocketServer?.start()
            if settings.agentHTTPServerEnabled {
                if currentHTTPToken.isEmpty {
                    currentHTTPToken = tokenStore.loadOrCreateToken()
                }
                httpServer?.start(port: settings.agentHTTPPort, bearerToken: currentHTTPToken)
            } else {
                httpServer?.stop()
            }
        } else {
            unixSocketServer?.stop()
            httpServer?.stop()
        }
    }

    @discardableResult
    public func rotateHTTPToken() -> String {
        let next = tokenStore.rotateToken()
        currentHTTPToken = next
        httpServer?.updateBearerToken(next)
        return next
    }

    public func clearActivityLog() {
        activityLog.removeAll()
    }

    public func notifyWindowReady() {
        guard !windowReadyContinuations.isEmpty else { return }
        let continuations = windowReadyContinuations
        windowReadyContinuations.removeAll()
        for cont in continuations {
            cont.resume()
        }
    }

    public func waitForWindowReadiness(timeoutSeconds: TimeInterval = 3.0) async {
        guard let coordinator else { return }
        if coordinator.openWindowHandler != nil || !coordinator.openWindows.isEmpty {
            return
        }
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            self?.notifyWindowReady()
        }
        await withCheckedContinuation { continuation in
            guard let coord = self.coordinator,
                  coord.openWindowHandler == nil && coord.openWindows.isEmpty else {
                continuation.resume()
                return
            }
            windowReadyContinuations.append(continuation)
        }
        timeoutTask.cancel()
    }

    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        notifyWindowReady()
        unixSocketServer?.stopSynchronously()
        httpServer?.stopSynchronously()
    }

    // MARK: - URL Scheme Action Handler (`glassgridyou://action/...`)

    public func handleActionURL(_ url: URL) {
        guard let coordinator else { return }
        let context = AgentRequestContext(source: .urlAction, clientName: "url-scheme")

        guard coordinator.settings.agentControlEnabled,
              coordinator.settings.allowURLSchemeActions else {
            recordActivity(
                source: .urlAction,
                action: "url_action",
                summary: url.path,
                succeeded: false,
                errorCode: "url_actions_disabled"
            )
            coordinator.commandTarget?.showHUD(
                icon: "hand.raised.fill",
                message: "URL Actions Disabled in Settings"
            )
            return
        }

        switch AgentURLActionParser.parse(url) {
        case .failure(let error):
            recordActivity(
                source: .urlAction,
                action: "url_action",
                summary: error.message,
                succeeded: false,
                errorCode: "invalid_url_action"
            )
            coordinator.commandTarget?.showHUD(icon: "exclamationmark.triangle", message: "Blocked Invalid Action URL")

        case .success(let parsed):
            Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = await self.execute(
                    toolName: parsed.toolName,
                    arguments: parsed.arguments,
                    context: context
                )
                if !outcome.ok {
                    coordinator.commandTarget?.showHUD(icon: "exclamationmark.triangle", message: outcome.message)
                }
            }
        }
    }

    // MARK: - AgentCommandExecutor

    public func isAutomationEnabled() async -> Bool {
        isAutomationEnabled
    }

    public func currentPermissionLevel() async -> AgentPermissionLevel {
        currentPermissionTier
    }

    public func readResource(uri: String, context: AgentRequestContext) async -> AgentResourceOutcome {
        guard isAutomationEnabled else {
            return .failure(
                uri: uri,
                code: "automation_disabled",
                message: "AI & Automation is disabled in GlassGrid You. Enable it in Settings → AI & Automation."
            )
        }

        let outcome: AgentResourceOutcome
        switch uri {
        case "glassgrid://state":
            outcome = .success(uri: uri, text: buildAppStateJSON(windowIDString: nil).encodedString(prettyPrinted: true))
        case "glassgrid://now-playing":
            outcome = .success(uri: uri, text: buildNowPlayingJSON(windowIDString: nil, includeDescription: true, includeChapters: true).encodedString(prettyPrinted: true))
        case "glassgrid://tabs":
            outcome = .success(uri: uri, text: buildTabsJSON(windowIDString: nil).encodedString(prettyPrinted: true))
        case "glassgrid://multiview":
            outcome = .success(uri: uri, text: buildMultiviewJSON(windowIDString: nil).encodedString(prettyPrinted: true))
        case "glassgrid://services":
            outcome = .success(uri: uri, text: buildServicesJSON().encodedString(prettyPrinted: true))
        default:
            outcome = .failure(uri: uri, code: "resource_not_found", message: "Unknown resource URI: \(uri)")
        }

        recordActivity(
            source: context.source,
            action: "read:\(uri)",
            summary: outcome.errorCode == nil ? "Read resource" : (outcome.errorMessage ?? "Error"),
            succeeded: outcome.errorCode == nil,
            errorCode: outcome.errorCode
        )
        return outcome
    }

    public func execute(
        toolName: String,
        arguments: [String: JSONValue],
        context: AgentRequestContext
    ) async -> AgentCommandOutcome {
        guard isAutomationEnabled else {
            let outcome = AgentCommandOutcome.failure(
                code: "automation_disabled",
                message: "AI & Automation is disabled in GlassGrid You. Enable it in Settings → AI & Automation."
            )
            recordActivity(source: context.source, action: toolName, summary: outcome.message, succeeded: false, errorCode: outcome.errorCode)
            return outcome
        }

        guard let tool = AgentToolCatalog.tool(named: toolName) else {
            let outcome = AgentCommandOutcome.failure(code: "unknown_tool", message: "Unknown tool '\(toolName)'.")
            recordActivity(source: context.source, action: toolName, summary: outcome.message, succeeded: false, errorCode: outcome.errorCode)
            return outcome
        }

        let currentTier = currentPermissionTier
        guard currentTier >= tool.requiredTier else {
            let outcome = AgentCommandOutcome.failure(
                code: "permission_denied",
                message: "Tool '\(toolName)' requires '\(tool.requiredTier.title)' permission (current: '\(currentTier.title)')."
            )
            recordActivity(source: context.source, action: toolName, summary: outcome.message, succeeded: false, errorCode: outcome.errorCode)
            return outcome
        }

        // For cold background launches, allow the SwiftUI window scene up to 3s to register `openWindowHandler`.
        if tool.requiredTier > .readOnly {
            await waitForWindowReadiness(timeoutSeconds: 3.0)
        }

        let outcome = dispatchTool(name: toolName, args: arguments, currentTier: currentTier)
        recordActivity(
            source: context.source,
            action: toolName,
            summary: outcome.message,
            succeeded: outcome.ok,
            errorCode: outcome.errorCode
        )
        if outcome.ok, tool.requiredTier > .readOnly, coordinator?.settings.agentShowHUDToasts == true {
            coordinator?.commandTarget?.showHUD(icon: "sparkles", message: outcome.message)
        }
        return outcome
    }

    // MARK: - Tool Dispatcher

    private func dispatchTool(
        name: String,
        args: [String: JSONValue],
        currentTier: AgentPermissionLevel
    ) -> AgentCommandOutcome {
        guard let coordinator else {
            return .failure(code: "app_unavailable", message: "AppCoordinator is unavailable.")
        }

        switch name {
        case "get_app_state":
            let winID = args["window_id"]?.stringValue
            if let winID, resolveWindow(idString: winID, fallback: nil) == nil {
                return .failure(code: "not_found", message: "Window '\(winID)' not found.")
            }
            return .success("Fetched app state.", data: buildAppStateJSON(windowIDString: winID))

        case "get_now_playing":
            let winID = args["window_id"]?.stringValue
            if let winID, resolveWindow(idString: winID, fallback: nil) == nil {
                return .failure(code: "not_found", message: "Window '\(winID)' not found.")
            }
            let includeDesc = args["include_description"]?.boolValue ?? true
            let includeChapters = args["include_chapters"]?.boolValue ?? true
            return .success(
                "Fetched now-playing status.",
                data: buildNowPlayingJSON(windowIDString: winID, includeDescription: includeDesc, includeChapters: includeChapters)
            )

        case "list_tabs":
            let winID = args["window_id"]?.stringValue
            if let winID, resolveWindow(idString: winID, fallback: nil) == nil {
                return .failure(code: "not_found", message: "Window '\(winID)' not found.")
            }
            return .success("Listed open tabs.", data: buildTabsJSON(windowIDString: winID))

        case "get_multiview_state":
            let winID = args["window_id"]?.stringValue
            if let winID, resolveWindow(idString: winID, fallback: nil) == nil {
                return .failure(code: "not_found", message: "Window '\(winID)' not found.")
            }
            return .success("Fetched Multiview state.", data: buildMultiviewJSON(windowIDString: winID))

        case "list_library":
            let includeSet: Set<String>? = args["include"]?.arrayValue.map { Set($0.compactMap(\.stringValue)) }
            return .success("Fetched library.", data: buildLibraryJSON(include: includeSet))

        case "playback_control":
            return executePlaybackControl(args: args, coordinator: coordinator)

        case "seek_playback":
            return executeSeekPlayback(args: args, coordinator: coordinator)

        case "set_playback_speed":
            return executeSetSpeed(args: args, coordinator: coordinator)

        case "set_volume":
            return executeSetVolume(args: args, coordinator: coordinator)

        case "search_youtube":
            return executeSearchYouTube(args: args, coordinator: coordinator)

        case "open_url":
            return executeOpenURL(args: args, currentTier: currentTier, coordinator: coordinator)

        case "navigate_destination":
            return executeNavigateDestination(args: args, coordinator: coordinator)

        case "select_tab":
            return executeSelectTab(args: args, coordinator: coordinator)

        case "open_service":
            return executeOpenService(args: args, coordinator: coordinator)

        case "multiview_control":
            return executeMultiviewControl(args: args, coordinator: coordinator)

        case "multiview_manage_tile":
            return executeMultiviewManageTile(args: args, currentTier: currentTier, coordinator: coordinator)

        case "launch_multiview_preset":
            return executeLaunchPreset(args: args, coordinator: coordinator)

        case "mini_player_control":
            return executeMiniPlayerControl(args: args, coordinator: coordinator)

        case "set_appearance":
            guard let modeRaw = args["mode"]?.stringValue else {
                return .failure(code: "invalid_arguments", message: "Missing mode.")
            }
            let targetMode: AppAppearance
            switch modeRaw {
            case "system": targetMode = .system
            case "light": targetMode = .light
            case "dark": targetMode = .dark
            case "toggle": targetMode = coordinator.settings.isEffectivelyDark ? .light : .dark
            default:
                return .failure(code: "invalid_arguments", message: "Invalid appearance mode '\(modeRaw)'.")
            }
            if let active = coordinator.commandTarget {
                active.setAppearance(targetMode, showFeedback: false)
            } else {
                coordinator.settings.appearance = targetMode
            }
            return .success("Appearance: \(targetMode.title)", data: .object(["appearance": .string(targetMode.rawValue)]))

        case "set_focus_mode":
            guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
                return .failure(code: "no_window", message: "No open GlassGrid You window.")
            }
            let target = args["enabled"]?.boolValue ?? !controller.focusModeActive
            if controller.focusModeActive != target {
                controller.toggleFocusMode()
            }
            return .success(
                target ? "Focus Mode On" : "Focus Mode Off",
                data: .object(["focusModeActive": .bool(controller.focusModeActive)])
            )

        case "set_sleep_timer":
            guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
                return .failure(code: "no_window", message: "No open GlassGrid You window.")
            }
            guard let optionRaw = args["option"]?.stringValue else {
                return .failure(code: "invalid_arguments", message: "Missing option.")
            }
            let parsed: SleepTimerOption?
            switch optionRaw {
            case "15m": parsed = .minutes15
            case "30m": parsed = .minutes30
            case "45m": parsed = .minutes45
            case "60m": parsed = .minutes60
            case "end_of_video": parsed = .endOfVideo
            case "off": parsed = nil
            default:
                return .failure(code: "invalid_arguments", message: "Invalid sleep timer option '\(optionRaw)'.")
            }
            controller.setSleepTimer(parsed)
            return .success(
                parsed.map { "Sleep Timer: \($0.title)" } ?? "Sleep Timer Off",
                data: .object(["sleepTimer": parsed.map { .string($0.rawValue) } ?? .null])
            )

        case "set_ui_chrome":
            return executeSetUIChrome(args: args, coordinator: coordinator)

        case "manage_tabs":
            return executeManageTabs(args: args, coordinator: coordinator)

        case "manage_multiview_preset":
            return executeManagePreset(args: args, coordinator: coordinator)

        case "manage_pins":
            return executeManagePins(args: args, currentTier: currentTier, coordinator: coordinator)

        case "manage_window":
            return executeManageWindow(args: args, coordinator: coordinator)

        case "set_distraction_free_preferences":
            return executeSetPreferences(args: args, coordinator: coordinator)

        case "find_on_page":
            return executeFindOnPage(args: args, coordinator: coordinator)

        default:
            return .failure(code: "unknown_tool", message: "Unknown tool '\(name)'.")
        }
    }

    // MARK: - Individual Tool Executors

    private func executePlaybackControl(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        let targetTab = resolveTab(args: args, in: controller, defaultTab: controller.activeMediaTab)
        guard let tab = targetTab else {
            return .failure(code: "not_found", message: "Target tab not found.")
        }

        if action == "toggle_theater" {
            tab.evaluate(EnhancementScript.toggleTheaterModeScript)
            return .success("Toggled Theater Mode")
        }

        guard tab.mediaStatus.hasVideo else {
            return .failure(code: "no_active_video", message: "No active video in the target tab.")
        }

        switch action {
        case "play":
            tab.playMedia()
            return .success("Playing", data: .object(["tabID": .string(tab.id.uuidString)]))
        case "pause":
            tab.pauseMedia()
            return .success("Paused", data: .object(["tabID": .string(tab.id.uuidString)]))
        case "toggle_play_pause":
            tab.togglePlayPause()
            return .success(tab.mediaStatus.isPlaying ? "Paused" : "Playing")
        case "mute":
            tab.setMuted(true)
            return .success("Muted")
        case "unmute":
            if controller.isMultiviewActive && controller.multiviewTabIDs.contains(tab.id) && tab.id != controller.multiviewAudioTabID {
                controller.focusMultiviewAudio(tabID: tab.id, showFeedback: false)
            } else {
                tab.setMuted(false)
            }
            return .success("Unmuted")
        case "toggle_mute":
            controller.toggleMute(tabID: tab.id)
            return .success("Toggled Mute")
        case "toggle_pip":
            Task { @MainActor in
                _ = await tab.togglePictureInPicture()
            }
            return .success("Toggled Picture in Picture")
        case "jump_to_live":
            tab.seekToLiveEdge()
            return .success("Jumped to Live Edge")
        default:
            return .failure(code: "invalid_arguments", message: "Unsupported playback action '\(action)'.")
        }
    }

    private func executeSeekPlayback(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard let tab = resolveTab(args: args, in: controller, defaultTab: controller.activeMediaTab) else {
            return .failure(code: "not_found", message: "Target tab not found.")
        }
        guard tab.mediaStatus.hasVideo else {
            return .failure(code: "no_active_video", message: "No active video in the target tab.")
        }

        if let delta = args["delta_seconds"]?.doubleValue {
            guard delta.isFinite else {
                return .failure(code: "invalid_arguments", message: "Invalid delta_seconds.")
            }
            tab.seekBy(seconds: delta)
            return .success("Seeked \(delta >= 0 ? "+" : "")\(Int(delta.rounded()))s")
        }

        if let chapterIdx = args["chapter_index"]?.intValue {
            guard !tab.chapters.isEmpty else {
                return .failure(code: "no_chapters", message: "Current video has no parsed chapters.")
            }
            let zeroIdx = chapterIdx - 1
            guard tab.chapters.indices.contains(zeroIdx) else {
                return .failure(code: "invalid_arguments", message: "Chapter index \(chapterIdx) out of range (1..\(tab.chapters.count)).")
            }
            let chapter = tab.chapters[zeroIdx]
            return seekTabAbsolute(tab, to: chapter.startSeconds, label: "Chapter \(chapterIdx): \(chapter.title)")
        }

        if let query = args["chapter_query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            guard !tab.chapters.isEmpty else {
                return .failure(code: "no_chapters", message: "Current video has no parsed chapters.")
            }
            guard let chapter = tab.chapters.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) else {
                return .failure(code: "not_found", message: "No chapter matching '\(query)'.")
            }
            return seekTabAbsolute(tab, to: chapter.startSeconds, label: "Chapter: \(chapter.title)")
        }

        if let sec = args["seconds"]?.doubleValue {
            guard sec.isFinite, sec >= 0 else {
                return .failure(code: "invalid_arguments", message: "seconds must be >= 0.")
            }
            return seekTabAbsolute(tab, to: sec, label: "Seeked to \(MediaState.formatTime(sec))")
        }

        return .failure(code: "invalid_arguments", message: "Provide seconds, delta_seconds, chapter_index, or chapter_query.")
    }

    private func seekTabAbsolute(_ tab: BrowserTab, to seconds: Double, label: String) -> AgentCommandOutcome {
        let duration = tab.timeline.duration
        guard duration.isFinite, duration > 0, duration < 86400 else {
            return .failure(code: "livestream_seek_unsupported", message: "Absolute seek is unavailable on livestreams or unknown-duration streams.")
        }
        let clamped = min(max(seconds, 0), duration)
        tab.timeline.update(currentTime: clamped, duration: duration)
        tab.seekTo(seconds: clamped)
        return .success(label, data: .object(["currentTime": .double(clamped)]))
    }

    private func executeSetSpeed(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let rate = args["rate"]?.doubleValue, rate.isFinite, rate >= 0.25, rate <= 4.0 else {
            return .failure(code: "invalid_arguments", message: "rate must be between 0.25 and 4.0.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard let tab = controller.activeMediaTab, tab.mediaStatus.hasVideo else {
            return .failure(code: "no_active_video", message: "No active video to adjust speed.")
        }
        controller.setPlaybackRate(rate, showFeedback: false)
        return .success("Speed \(MediaStatus.formatPlaybackRate(rate))", data: .object(["playbackRate": .double(rate)]))
    }

    private func executeSetVolume(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let percent = args["volume_percent"]?.intValue, (0...100).contains(percent) else {
            return .failure(code: "invalid_arguments", message: "volume_percent must be 0..100.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard let tab = resolveTab(args: args, in: controller, defaultTab: controller.activeMediaTab) else {
            return .failure(code: "not_found", message: "Target tab not found.")
        }
        let muted = args["muted"]?.boolValue ?? (percent == 0)
        if controller.isMultiviewActive && controller.multiviewTabIDs.contains(tab.id) {
            let targetPercent = muted ? 0 : percent
            if controller.hasLiveFullscreenTab {
                tab.setAudioLevel(muted: muted, volumePercent: percent)
            } else {
                controller.setMultiviewTileVolume(tabID: tab.id, volumePercent: targetPercent)
            }
            return .success(muted || targetPercent == 0 ? "Muted" : "Volume \(targetPercent)%")
        }
        tab.setAudioLevel(muted: muted, volumePercent: percent)
        return .success(muted ? "Muted" : "Volume \(percent)%")
    }

    private func executeSearchYouTube(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let rawQuery = args["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawQuery.isEmpty else {
            return .failure(code: "invalid_arguments", message: "query must be non-empty.")
        }
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: rawQuery)]
        guard let searchURL = components.url else {
            return .failure(code: "invalid_arguments", message: "Unable to encode search query.")
        }

        let inMultiview = args["in_multiview"]?.boolValue ?? false
        let newTab = args["new_tab"]?.boolValue ?? true
        let controller: AppController
        switch resolveOrCreateWindow(idString: args["window_id"]?.stringValue, urlForNewWindow: searchURL, coordinator: coordinator) {
        case .existing(let resolved):
            controller = resolved
        case .openedNewWindow:
            return .success("Opened YouTube search in new window.")
        case .notFound(let msg):
            return .failure(code: "not_found", message: msg)
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot navigate, create tabs, or mutate Multiview while a video is in WebKit fullscreen.")
        }

        if inMultiview {
            controller.addTileToMultiview(url: searchURL, routingMode: .youtube)
            return .success("Opened YouTube search in Multiview")
        } else if newTab {
            let created = controller.createTab(url: searchURL, select: true, routingMode: .youtube)
            return .success("Searched YouTube", data: .object(["tabID": .string(created.id.uuidString)]))
        } else {
            controller.navigateSelectedTab(to: searchURL)
            return .success("Searched YouTube")
        }
    }

    private func executeOpenURL(
        args: [String: JSONValue],
        currentTier: AgentPermissionLevel,
        coordinator: AppCoordinator
    ) -> AgentCommandOutcome {
        guard let rawURL = args["url"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing url.")
        }
        let url: URL
        switch AgentSecurity.validateURL(rawURL, tier: currentTier) {
        case .success(let validated):
            url = validated
        case .failure(let error):
            let code = (error == .tierRestrictedCompanionDomain) ? "permission_denied" : "invalid_url"
            return .failure(code: code, message: error.message)
        }

        let routingMode = YouTubeURLRouter.preferredRoutingMode(for: url)
        let inNewWindow = args["in_new_window"]?.boolValue ?? false
        if inNewWindow {
            coordinator.openURLInNewWindow(url, routingMode: routingMode)
            return .success("Opened URL in new window", data: .object(["url": .string(url.absoluteString)]))
        }

        let controller: AppController
        switch resolveOrCreateWindow(idString: args["window_id"]?.stringValue, urlForNewWindow: url, coordinator: coordinator) {
        case .existing(let resolved):
            controller = resolved
        case .openedNewWindow:
            return .success("Opened URL in new window", data: .object(["url": .string(url.absoluteString)]))
        case .notFound(let msg):
            return .failure(code: "not_found", message: msg)
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot change tabs or layout while a video is in WebKit fullscreen.")
        }

        let inMultiview = args["in_multiview"]?.boolValue ?? false
        let newTab = args["new_tab"]?.boolValue ?? true
        if inMultiview {
            if controller.isMultiviewActive && !controller.canAddMultiviewTile {
                return .failure(code: "multiview_full", message: "Multiview already has the maximum of 4 streams.")
            }
            controller.addTileToMultiview(url: url, routingMode: routingMode)
            return .success("Added URL to Multiview", data: .object(["url": .string(url.absoluteString)]))
        } else if newTab {
            let tab = controller.createTab(url: url, select: true, routingMode: routingMode)
            return .success("Opened URL in new tab", data: .object(["tabID": .string(tab.id.uuidString)]))
        } else {
            controller.navigateSelectedTab(to: url)
            return .success("Navigated to URL", data: .object(["url": .string(url.absoluteString)]))
        }
    }

    private func executeNavigateDestination(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let dest = args["destination"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing destination.")
        }
        let windowID = args["window_id"]?.stringValue
        guard let controller = resolveWindow(idString: windowID, fallback: coordinator.commandTarget) else {
            if let windowID {
                return .failure(code: "not_found", message: "Window '\(windowID)' not found.")
            }
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot navigate while a video is in WebKit fullscreen.")
        }

        switch dest {
        case "back":
            guard controller.selectedTab?.canGoBack == true else {
                return .failure(code: "cannot_go_back", message: "Active tab cannot go back.")
            }
            controller.selectedTab?.goBack()
            return .success("Navigated Back")
        case "forward":
            guard controller.selectedTab?.canGoForward == true else {
                return .failure(code: "cannot_go_forward", message: "Active tab cannot go forward.")
            }
            controller.selectedTab?.goForward()
            return .success("Navigated Forward")
        case "reload":
            controller.selectedTab?.reloadOrStop()
            return .success("Reloaded Tab")
        default:
            let sidebarDest: SidebarDestination?
            switch dest {
            case "home": sidebarDest = .home
            case "subscriptions": sidebarDest = .subscriptions
            case "history": sidebarDest = .history
            case "watch_later": sidebarDest = .watchLater
            case "liked_videos": sidebarDest = .likedVideos
            case "playlists": sidebarDest = .playlists
            default: sidebarDest = nil
            }
            guard let sidebarDest else {
                return .failure(code: "invalid_arguments", message: "Unknown destination '\(dest)'.")
            }
            controller.navigateSelectedTab(to: sidebarDest)
            return .success("Opened \(sidebarDest.title)")
        }
    }

    private func executeSelectTab(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot switch tabs while a video is in WebKit fullscreen.")
        }
        if let tabIDStr = args["tab_id"]?.stringValue {
            guard let uuid = UUID(uuidString: tabIDStr), controller.tabs.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Tab '\(tabIDStr)' not found.")
            }
            controller.selectTab(id: uuid)
            return .success("Selected Tab")
        }
        if let index = args["index"]?.intValue {
            guard controller.tabs.indices.contains(index - 1) else {
                return .failure(code: "invalid_arguments", message: "Tab index \(index) out of range (1..\(controller.tabs.count)).")
            }
            controller.selectTab(atIndex: index)
            return .success("Selected Tab \(index)")
        }
        if let direction = args["direction"]?.stringValue {
            guard controller.tabs.count > 1 else {
                return .failure(code: "single_tab", message: "Only 1 tab is open.")
            }
            if direction == "next" {
                controller.selectNextTab()
                return .success("Selected Next Tab")
            } else if direction == "previous" {
                controller.selectPreviousTab()
                return .success("Selected Previous Tab")
            }
        }
        return .failure(code: "invalid_arguments", message: "Provide tab_id, index, or direction.")
    }

    private func executeOpenService(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let rawServiceID = args["service_id"]?.stringValue,
              let service = StreamingServiceCatalog.resolveService(identifierOrAlias: rawServiceID) else {
            return .failure(code: "not_found", message: "Unknown streaming service ID.")
        }

        let inMultiview = args["in_multiview"]?.boolValue ?? false
        let newTab = args["new_tab"]?.boolValue ?? true

        let controller: AppController
        switch resolveOrCreateWindow(idString: args["window_id"]?.stringValue, urlForNewWindow: service.homeURL, coordinator: coordinator) {
        case .existing(let resolved):
            controller = resolved
        case .openedNewWindow:
            return .success("Opened \(service.name) in new window")
        case .notFound(let msg):
            return .failure(code: "not_found", message: msg)
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot open streaming services while a video is in WebKit fullscreen.")
        }

        if inMultiview {
            if controller.isMultiviewActive && !controller.canAddMultiviewTile {
                return .failure(code: "multiview_full", message: "Multiview already has 4 streams.")
            }
            controller.addStreamingServiceToMultiview(service)
            return .success("Added \(service.name) to Multiview")
        } else {
            controller.openStreamingService(service, inNewTab: newTab)
            return .success("Opened \(service.name)")
        }
    }

    private func executeMultiviewControl(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        // Audio focus operations remain safe even during fullscreen.
        switch action {
        case "focus_audio":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            if let slot = args["slot"]?.intValue {
                guard controller.multiviewTabIDs.indices.contains(slot - 1) else {
                    return .failure(code: "invalid_arguments", message: "Multiview slot \(slot) is out of range.")
                }
                controller.focusMultiviewAudio(slot: slot)
                return .success("Audio Focus: Stream \(slot)")
            }
            if let tabIDStr = args["tab_id"]?.stringValue,
               let uuid = UUID(uuidString: tabIDStr),
               controller.multiviewTabIDs.contains(uuid) {
                controller.focusMultiviewAudio(tabID: uuid, showFeedback: true)
                return .success("Updated Multiview Audio Focus")
            }
            return .failure(code: "invalid_arguments", message: "Provide slot (1..4) or tab_id in Multiview.")

        case "cycle_audio_next":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.cycleMultiviewAudioFocus(by: 1)
            return .success("Next Stream Audio")

        case "cycle_audio_prev":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.cycleMultiviewAudioFocus(by: -1)
            return .success("Previous Stream Audio")

        case "mute_all":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.muteAllMultiviewTiles()
            return .success("Muted All Multiview Streams")

        case "reset_mixer":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.resetMultiviewMixer(showFeedback: true)
            return .success("Multiview Mixer Reset")

        default:
            break
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot mutate Multiview layout while a video is in WebKit fullscreen.")
        }

        switch action {
        case "enter":
            if let rawIDs = args["tab_ids"]?.arrayValue {
                let uuids = rawIDs.compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
                guard uuids.count >= 2 else {
                    return .failure(code: "invalid_arguments", message: "tab_ids requires at least 2 valid tab UUIDs.")
                }
                controller.enterMultiview(with: uuids)
            } else {
                controller.enterMultiview()
            }
            return .success("Entered Multiview (\(controller.multiviewTabIDs.count) Streams)")

        case "exit":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.exitMultiview(focusTabID: controller.multiviewAudioTabID ?? controller.selectedTabID, showFeedback: true)
            return .success("Exited Multiview")

        case "toggle":
            controller.toggleMultiview()
            return .success(controller.isMultiviewActive ? "Entered Multiview" : "Exited Multiview")

        case "set_layout":
            guard let layoutRaw = args["layout"]?.stringValue,
                  let mode = MultiviewLayoutMode(rawValue: layoutRaw) else {
                return .failure(code: "invalid_arguments", message: "layout must be auto, spotlight, or stacked.")
            }
            controller.setMultiviewLayoutMode(mode, showFeedback: true)
            return .success("Multiview Layout: \(mode.title)")

        case "cycle_layout":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            controller.cycleMultiviewLayoutMode()
            return .success("Multiview Layout: \(controller.multiviewLayoutMode.title)")

        case "solo":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            let targetID = resolveTab(args: args, in: controller, defaultTab: controller.multiviewAudioTab)?.id
            controller.toggleMultiviewSolo(tabID: targetID)
            return .success(controller.isMultiviewSoloActive ? "Expanded Multiview Solo" : "Back to Multiview Grid")

        case "exit_solo":
            guard controller.isMultiviewSoloActive else {
                return .failure(code: "not_in_solo", message: "Multiview Solo is not active.")
            }
            controller.exitMultiviewSolo(showFeedback: true)
            return .success("Back to Multiview Grid")

        case "promote_primary":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            guard let target = resolveTab(args: args, in: controller, defaultTab: controller.selectedTab),
                  controller.multiviewTabIDs.contains(target.id) else {
                return .failure(code: "not_found", message: "Target tile not found in Multiview.")
            }
            controller.promoteMultiviewTileToPrimary(id: target.id)
            return .success("Promoted Tile to Primary")

        default:
            return .failure(code: "invalid_arguments", message: "Unsupported Multiview action '\(action)'.")
        }
    }

    private func executeMultiviewManageTile(
        args: [String: JSONValue],
        currentTier: AgentPermissionLevel,
        coordinator: AppCoordinator
    ) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot add or remove Multiview tiles while a video is in WebKit fullscreen.")
        }

        switch action {
        case "add":
            if controller.isMultiviewActive && !controller.canAddMultiviewTile {
                return .failure(code: "multiview_full", message: "Multiview already has 4 streams.")
            }
            if let rawServiceID = args["service_id"]?.stringValue {
                guard let svc = StreamingServiceCatalog.resolveService(identifierOrAlias: rawServiceID) else {
                    return .failure(code: "not_found", message: "Unknown streaming service '\(rawServiceID)'.")
                }
                controller.addStreamingServiceToMultiview(svc)
                return .success("Added \(svc.name) to Multiview")
            }
            if let rawURL = args["url"]?.stringValue {
                switch AgentSecurity.validateURL(rawURL, tier: currentTier) {
                case .success(let validated):
                    let mode = YouTubeURLRouter.preferredRoutingMode(for: validated)
                    controller.addTileToMultiview(url: validated, routingMode: mode)
                    return .success("Added Stream to Multiview")
                case .failure(let err):
                    let code = (err == .tierRestrictedCompanionDomain) ? "permission_denied" : "invalid_url"
                    return .failure(code: code, message: err.message)
                }
            }
            if let tabIDStr = args["tab_id"]?.stringValue,
               let uuid = UUID(uuidString: tabIDStr),
               controller.tabs.contains(where: { $0.id == uuid }) {
                controller.addExistingTabToMultiview(id: uuid)
                return .success("Added Tab to Multiview")
            }
            return .failure(code: "invalid_arguments", message: "Provide url, service_id, or tab_id.")

        case "remove":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Multiview is not active.")
            }
            let closeTab = args["close_tab"]?.boolValue ?? false
            if closeTab && currentTier < .fullControl {
                return .failure(code: "permission_denied", message: "close_tab=true requires Full Control permission.")
            }
            guard let target = resolveTab(args: args, in: controller, defaultTab: nil),
                  controller.multiviewTabIDs.contains(target.id) else {
                return .failure(code: "not_found", message: "Specify a valid slot (1..4) or tab_id in Multiview.")
            }
            controller.removeTileFromMultiview(id: target.id, closeTabIfMultiple: closeTab)
            return .success("Removed Stream from Multiview")

        default:
            return .failure(code: "invalid_arguments", message: "Invalid action '\(action)'.")
        }
    }

    private func executeLaunchPreset(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        let presets = coordinator.settings.savedMultiviewPresets
        let preset: MultiviewPreset?
        if let idStr = args["preset_id"]?.stringValue, let uuid = UUID(uuidString: idStr) {
            preset = presets.first { $0.id == uuid }
        } else if let name = args["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            preset = presets.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                ?? presets.first { $0.name.localizedCaseInsensitiveContains(name) }
        } else {
            return .failure(code: "invalid_arguments", message: "Provide preset_id or name.")
        }

        guard let preset else {
            return .failure(code: "not_found", message: "Multiview preset not found.")
        }

        if args["in_new_window"]?.boolValue == true {
            coordinator.launchPresetInNewWindow(preset)
            return .success("Launched Preset \"\(preset.name)\" in New Window")
        }

        let windowID = args["window_id"]?.stringValue
        let controller: AppController
        if let windowID {
            guard let resolved = resolveWindow(idString: windowID, fallback: nil) else {
                return .failure(code: "not_found", message: "Window '\(windowID)' not found.")
            }
            controller = resolved
        } else if let target = coordinator.commandTarget {
            controller = target
        } else {
            coordinator.launchPresetInNewWindow(preset)
            return .success("Launched Preset \"\(preset.name)\" in New Window")
        }

        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot launch Multiview preset while a video is in WebKit fullscreen.")
        }

        controller.launchMultiviewPreset(preset)
        return .success("Launched Preset \"\(preset.name)\"")
    }

    private func executeMiniPlayerControl(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard !coordinator.hasAnyWindowInLiveFullscreen else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot enter or exit Mini-Player while any window has a video in WebKit fullscreen.")
        }

        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        let validatedOpacity: Double?
        if let opacity = args["opacity"]?.doubleValue {
            guard opacity.isFinite, opacity >= 0.4, opacity <= 1.0 else {
                return .failure(code: "invalid_arguments", message: "opacity must be between 0.40 and 1.0.")
            }
            validatedOpacity = opacity
        } else {
            validatedOpacity = nil
        }

        let validatedPreset: String?
        if let rawPreset = args["size_preset"]?.stringValue {
            guard MiniPlayerGridSizePreset(rawValue: rawPreset) != nil || MiniPlayerSizePreset(rawValue: rawPreset) != nil else {
                return .failure(code: "invalid_arguments", message: "size_preset must be compact, standard, large, or extraLarge.")
            }
            validatedPreset = rawPreset
        } else {
            validatedPreset = nil
        }

        if let validatedOpacity {
            coordinator.settings.miniPlayerOpacity = validatedOpacity
        }

        let outcome: AgentCommandOutcome
        if let action = args["action"]?.stringValue {
            outcome = executeMiniPlayerAction(action, controller: controller)
        } else if validatedOpacity != nil || validatedPreset != nil {
            outcome = .success("Updated Mini-Player Settings")
        } else {
            outcome = executeMiniPlayerAction("toggle", controller: controller)
        }

        if outcome.ok, let validatedPreset {
            controller.applyFloatingMiniPlayerSizePreset(validatedPreset)
        }
        return outcome
    }

    private func executeMiniPlayerAction(_ action: String, controller: AppController) -> AgentCommandOutcome {
        switch action {
        case "enter":
            if controller.isMiniPlayer {
                return .success(controller.isFloatingMultiviewGrid ? "Floating Multiview Grid Already Active" : "Mini-Player Already Active")
            }
            guard controller.canPopOutActiveContent else {
                return .failure(code: "cannot_pop_out_mini_player", message: "No eligible video or active Multiview stream available for Mini-Player.")
            }
            controller.toggleMiniPlayer()
            return .success(controller.isFloatingMultiviewGrid ? "Entered Floating Multiview Grid" : "Entered Mini-Player")
        case "exit":
            guard controller.isMiniPlayer else {
                return .failure(code: "mini_player_inactive", message: "Mini-Player is not active.")
            }
            let wasGrid = controller.isFloatingMultiviewGrid
            controller.dockMiniPlayer(selectTab: true, focusMain: true)
            return .success(wasGrid ? "Docked Floating Multiview Grid" : "Docked Mini-Player")
        case "toggle":
            if controller.isMiniPlayer {
                let wasGrid = controller.isFloatingMultiviewGrid
                controller.dockMiniPlayer(selectTab: true, focusMain: true)
                return .success(wasGrid ? "Docked Floating Multiview Grid" : "Docked Mini-Player")
            } else {
                guard controller.canPopOutActiveContent else {
                    return .failure(code: "cannot_pop_out_mini_player", message: "No eligible watch-page video or active Multiview stream available for Mini-Player.")
                }
                controller.toggleMiniPlayer()
                return .success(controller.isFloatingMultiviewGrid ? "Entered Floating Multiview Grid" : "Entered Mini-Player")
            }
        default:
            return .failure(code: "invalid_arguments", message: "Invalid Mini-Player action '\(action)'.")
        }
    }

    private func executeSetUIChrome(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        if let sidebarVisible = args["sidebar_visible"]?.boolValue {
            guard !controller.hasLiveFullscreenTab else {
                return .failure(code: "blocked_by_fullscreen", message: "Cannot toggle sidebar during WebKit fullscreen.")
            }
            if controller.isSidebarVisible != sidebarVisible {
                controller.toggleSidebar()
            }
        }
        if let alwaysOnTop = args["always_on_top"]?.boolValue {
            if controller.alwaysOnTop != alwaysOnTop {
                controller.toggleAlwaysOnTop()
            }
        }
        if let zoom = args["zoom_action"]?.stringValue {
            switch zoom {
            case "in": controller.zoomIn()
            case "out": controller.zoomOut()
            case "reset": controller.resetZoom()
            default:
                return .failure(code: "invalid_arguments", message: "zoom_action must be in, out, or reset.")
            }
        }
        return .success("Updated UI Chrome")
    }

    private func executeManageTabs(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard !controller.hasLiveFullscreenTab else {
            return .failure(code: "blocked_by_fullscreen", message: "Cannot close, duplicate, or sleep tabs while a video is in WebKit fullscreen.")
        }

        if action == "reopen_closed" {
            guard !controller.closedTabURLs.isEmpty else {
                return .failure(code: "no_closed_tabs", message: "No recently closed tabs to reopen.")
            }
            controller.reopenClosedTab()
            return .success("Reopened Closed Tab")
        }

        guard let tab = resolveTab(args: args, in: controller, defaultTab: controller.selectedTab) else {
            return .failure(code: "not_found", message: "Target tab not found.")
        }

        switch action {
        case "close":
            let wasSoleSingleWindowTab = (controller.tabs.count <= 1 && !coordinator.hasMultipleWindows)
            controller.closeTab(id: tab.id)
            if wasSoleSingleWindowTab {
                return .success(
                    "Paused playback and hid the last window.",
                    data: .object(["closed": .bool(false), "windowHidden": .bool(true)])
                )
            }
            return .success("Closed Tab", data: .object(["closed": .bool(true), "windowHidden": .bool(false)]))

        case "close_others":
            guard controller.tabs.count > 1 else {
                return .failure(code: "single_tab", message: "Only 1 tab is open.")
            }
            controller.closeOtherTabs(keepingID: tab.id)
            return .success("Closed Other Tabs")

        case "duplicate":
            controller.duplicateTab(id: tab.id)
            return .success("Duplicated Tab")

        case "sleep":
            guard controller.canPutTabToSleep(id: tab.id) else {
                return .failure(code: "cannot_sleep_tab", message: "Cannot sleep the selected, popped-out, or Multiview tab.")
            }
            controller.putTabToSleep(id: tab.id)
            return .success("Put Tab to Sleep")

        default:
            return .failure(code: "invalid_arguments", message: "Invalid manage_tabs action '\(action)'.")
        }
    }

    private func executeManagePreset(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        switch action {
        case "save_current":
            guard controller.isMultiviewActive else {
                return .failure(code: "multiview_inactive", message: "Enter Multiview before saving a preset.")
            }
            let name = args["name"]?.stringValue ?? ""
            let beforeCount = coordinator.settings.savedMultiviewPresets.count
            controller.saveCurrentMultiviewAsPreset(name: name)
            guard coordinator.settings.savedMultiviewPresets.count > beforeCount,
                  let saved = coordinator.settings.savedMultiviewPresets.last else {
                return .failure(code: "save_failed", message: "Unable to save Multiview preset.")
            }
            return .success("Saved Preset \"\(saved.name)\"", data: .object(["presetID": .string(saved.id.uuidString)]))

        case "rename":
            guard let idStr = args["preset_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.savedMultiviewPresets.contains(where: { $0.id == uuid }),
                  let newName = args["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !newName.isEmpty else {
                return .failure(code: "invalid_arguments", message: "Valid preset_id and non-empty name are required.")
            }
            controller.renameMultiviewPreset(id: uuid, newName: newName)
            return .success("Renamed Preset to \"\(newName)\"")

        case "delete":
            guard let idStr = args["preset_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.savedMultiviewPresets.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Preset not found.")
            }
            controller.deleteMultiviewPreset(id: uuid)
            return .success("Deleted Preset")

        default:
            return .failure(code: "invalid_arguments", message: "Invalid manage_multiview_preset action '\(action)'.")
        }
    }

    private func executeManagePins(
        args: [String: JSONValue],
        currentTier: AgentPermissionLevel,
        coordinator: AppCoordinator
    ) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }

        switch action {
        case "pin_current":
            if !controller.isCurrentPagePinned {
                controller.togglePinCurrentPage()
            }
            return .success("Pinned Current Page")

        case "unpin_current":
            if controller.isCurrentPagePinned {
                controller.togglePinCurrentPage()
            }
            return .success("Unpinned Current Page")

        case "add_pin":
            guard let rawURL = args["url"]?.stringValue else {
                return .failure(code: "invalid_arguments", message: "url is required.")
            }
            switch AgentSecurity.validateURL(rawURL, tier: currentTier) {
            case .failure(let err):
                return .failure(code: "invalid_url", message: err.message)
            case .success(let validated):
                let title = AgentSecurity.sanitizeWebText(
                    args["title"]?.stringValue ?? (validated.host ?? "Link"),
                    maxLength: 120
                ).text
                let folderID = args["folder_id"]?.stringValue.flatMap(UUID.init(uuidString:))
                if let folderID, !coordinator.settings.pinnedFolders.contains(where: { $0.id == folderID }) {
                    return .failure(code: "not_found", message: "Folder not found.")
                }
                let pin = PinnedItem(title: title.isEmpty ? "Pin" : title, urlString: validated.absoluteString, folderID: folderID)
                coordinator.settings.pinnedItems.append(pin)
                return .success("Added Pin \"\(pin.title)\"", data: .object(["pinID": .string(pin.id.uuidString)]))
            }

        case "remove_pin":
            guard let idStr = args["pin_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.pinnedItems.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Pin not found.")
            }
            controller.removePin(id: uuid)
            return .success("Removed Pin")

        case "create_folder":
            guard let name = args["name"]?.stringValue,
                  let folder = controller.createPinnedFolder(name: name) else {
                return .failure(code: "invalid_arguments", message: "Non-empty folder name required.")
            }
            return .success("Created Folder \"\(folder.name)\"", data: .object(["folderID": .string(folder.id.uuidString)]))

        case "delete_folder":
            guard let idStr = args["folder_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.pinnedFolders.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Folder not found.")
            }
            controller.deletePinnedFolder(id: uuid)
            return .success("Deleted Folder")

        case "move_pin_to_folder":
            guard let pinStr = args["pin_id"]?.stringValue,
                  let pinUUID = UUID(uuidString: pinStr),
                  coordinator.settings.pinnedItems.contains(where: { $0.id == pinUUID }) else {
                return .failure(code: "not_found", message: "Pin not found.")
            }
            let folderUUID: UUID?
            if let folderStr = args["folder_id"]?.stringValue, !folderStr.isEmpty {
                guard let parsed = UUID(uuidString: folderStr),
                      coordinator.settings.pinnedFolders.contains(where: { $0.id == parsed }) else {
                    return .failure(code: "not_found", message: "Folder not found.")
                }
                folderUUID = parsed
            } else {
                folderUUID = nil
            }
            controller.movePinToFolder(pinID: pinUUID, folderID: folderUUID)
            return .success("Moved Pin")

        case "open_folder_multiview":
            guard !controller.hasLiveFullscreenTab else {
                return .failure(code: "blocked_by_fullscreen", message: "Cannot open folder in Multiview while a video is in WebKit fullscreen.")
            }
            guard let idStr = args["folder_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.pinnedFolders.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Folder not found.")
            }
            controller.openFolderInMultiview(id: uuid)
            return .success("Opened Folder in Multiview")

        case "open_folder_tabs":
            guard !controller.hasLiveFullscreenTab else {
                return .failure(code: "blocked_by_fullscreen", message: "Cannot open folder tabs while a video is in WebKit fullscreen.")
            }
            guard let idStr = args["folder_id"]?.stringValue,
                  let uuid = UUID(uuidString: idStr),
                  coordinator.settings.pinnedFolders.contains(where: { $0.id == uuid }) else {
                return .failure(code: "not_found", message: "Folder not found.")
            }
            controller.openFolderInTabs(id: uuid)
            return .success("Opened Folder in Tabs")

        default:
            return .failure(code: "invalid_arguments", message: "Invalid manage_pins action '\(action)'.")
        }
    }

    private func executeManageWindow(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        switch action {
        case "new_window":
            coordinator.openNewWindow()
            return .success("Opened New Window")

        case "focus":
            guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
                return .failure(code: "no_window", message: "Target window not found.")
            }
            controller.focusMainWindow()
            return .success("Focused Window")

        case "move_to_display":
            guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
                return .failure(code: "no_window", message: "Target window not found.")
            }
            guard !controller.hasLiveFullscreenTab else {
                return .failure(code: "blocked_by_fullscreen", message: "Cannot move window between displays while a video is in WebKit fullscreen.")
            }
            coordinator.refreshConnectedDisplays()
            let targetDisplay: ConnectedDisplayDescriptor?
            if let displayID = args["display_id"]?.intValue {
                targetDisplay = coordinator.connectedDisplays.first { Int($0.id) == displayID }
            } else if let name = args["display_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                targetDisplay = coordinator.connectedDisplays.first { $0.name.localizedCaseInsensitiveContains(name) }
            } else {
                return .failure(code: "invalid_arguments", message: "Provide display_id or display_name.")
            }
            guard let targetDisplay else {
                return .failure(code: "not_found", message: "Target display not found.")
            }
            controller.moveWindowToDisplay(id: targetDisplay.id)
            return .success("Moved Window to \(targetDisplay.name)")

        default:
            return .failure(code: "invalid_arguments", message: "Invalid manage_window action '\(action)'.")
        }
    }

    private func executeSetPreferences(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        let s = coordinator.settings
        if let v = args["hide_shorts"]?.boolValue { s.hideShorts = v }
        if let v = args["redirect_shorts_to_watch"]?.boolValue { s.redirectShortsToWatch = v }
        if let v = args["clean_web_chrome"]?.boolValue { s.cleanWebChrome = v }
        if let v = args["clean_box_streaming_players"]?.boolValue { s.cleanBoxStreamingPlayers = v }
        if let v = args["hide_web_header"]?.boolValue { s.hideWebHeader = v }
        if let v = args["auto_theater_mode"]?.boolValue { s.autoTheaterMode = v }
        if let v = args["hide_end_screens"]?.boolValue { s.hideEndScreens = v }
        if let v = args["hide_watch_recommendations"]?.boolValue { s.hideWatchRecommendations = v }
        if let v = args["hide_comments"]?.boolValue { s.hideComments = v }
        if let v = args["hide_home_feed"]?.boolValue { s.hideHomeFeed = v }
        if let v = args["multiview_audio_ducking"]?.boolValue { s.multiviewAudioDuckingEnabled = v }
        if let rawQ = args["preferred_quality"]?.stringValue {
            switch rawQ {
            case "auto": s.preferredQuality = .auto
            case "2160p": s.preferredQuality = .uhd2160
            case "1440p": s.preferredQuality = .qhd1440
            case "1080p": s.preferredQuality = .fhd1080
            case "720p": s.preferredQuality = .hd720
            default:
                return .failure(code: "invalid_arguments", message: "Invalid preferred_quality '\(rawQ)'.")
            }
        }
        return .success("Updated Distraction-Free Preferences")
    }

    private func executeFindOnPage(args: [String: JSONValue], coordinator: AppCoordinator) -> AgentCommandOutcome {
        guard let action = args["action"]?.stringValue else {
            return .failure(code: "invalid_arguments", message: "Missing action.")
        }
        guard let controller = resolveWindow(idString: args["window_id"]?.stringValue, fallback: coordinator.commandTarget) else {
            return .failure(code: "no_window", message: "No open GlassGrid You window.")
        }
        guard !controller.hasLiveFullscreenTab && !controller.isSelectedTabPoppedOut else {
            return .failure(code: "blocked_by_fullscreen", message: "Find on Page is unavailable during fullscreen or when the selected tab is popped out.")
        }

        switch action {
        case "find":
            guard let query = args["query"]?.stringValue, !query.isEmpty else {
                return .failure(code: "invalid_arguments", message: "query is required for action=find.")
            }
            controller.presentFindBar()
            controller.findQuery = query
            controller.scheduleDebouncedFindOnPage()
            return .success("Finding \"\(query)\"")
        case "next":
            controller.findNextOnPage()
            return .success("Find Next")
        case "previous":
            controller.findPreviousOnPage()
            return .success("Find Previous")
        case "clear":
            controller.dismissFindBar()
            return .success("Cleared Find Highlights")
        default:
            return .failure(code: "invalid_arguments", message: "Invalid find_on_page action '\(action)'.")
        }
    }

    // MARK: - Snapshot Builders (All Web Fields Sanitized + Tagged)

    private func buildAppStateJSON(windowIDString: String?) -> JSONValue {
        guard let coordinator else { return .object([:]) }
        let target = resolveWindow(idString: windowIDString, fallback: coordinator.commandTarget)
        return .object([
            "contentTrust": .string(AgentSecurity.untrustedWebContentTag),
            "appVersion": .string(coordinator.updater.currentAppVersion),
            "windowCount": .int(coordinator.openWindows.count),
            "activeWindowID": target.map { .string($0.windowID.uuidString) } ?? .null,
            "appearance": .string(coordinator.settings.appearance.rawValue),
            "isEffectivelyDark": .bool(coordinator.settings.isEffectivelyDark),
            "permissionLevel": .string(coordinator.settings.agentPermissionLevel.rawValue),
            "focusModeActive": .bool(target?.focusModeActive ?? false),
            "alwaysOnTop": .bool(target?.alwaysOnTop ?? false),
            "isSidebarVisible": .bool(target?.isSidebarVisible ?? coordinator.settings.isSidebarVisible),
            "isMiniPlayer": .bool(target?.isMiniPlayer ?? false),
            "isFloatingMultiviewGrid": .bool(target?.isFloatingMultiviewGrid ?? false),
            "miniPlayerOpacity": .double(coordinator.settings.miniPlayerOpacity),
            "cleanBoxStreamingPlayers": .bool(coordinator.settings.cleanBoxStreamingPlayers),
            "isMultiviewActive": .bool(target?.isMultiviewActive ?? false),
            "multiviewLayoutMode": .string((target?.multiviewLayoutMode ?? .auto).rawValue),
            "multiviewCount": .int(target?.multiviewTabIDs.count ?? 0),
            "anyTabInFullscreen": .bool(target?.hasLiveFullscreenTab ?? false),
            "sleepTimer": target?.sleepTimerOption.map { .string($0.rawValue) } ?? .null,
            "audioOutputName": .string(coordinator.currentAudioOutputName),
            "isAirPlayAudioActive": .bool(coordinator.isAirPlayAudioActive)
        ])
    }

    private func buildNowPlayingJSON(
        windowIDString: String?,
        includeDescription: Bool,
        includeChapters: Bool
    ) -> JSONValue {
        guard let coordinator else { return .object(["hasVideo": .bool(false)]) }
        let controller = resolveWindow(idString: windowIDString, fallback: coordinator.nowPlayingController ?? coordinator.commandTarget)
        guard let controller, let tab = controller.activeMediaTab else {
            return .object([
                "contentTrust": .string(AgentSecurity.untrustedWebContentTag),
                "hasVideo": .bool(false)
            ])
        }

        let status = tab.mediaStatus
        let cleanTitle = AgentSecurity.sanitizeWebText(
            status.title.isEmpty ? tab.displayTitle : status.title,
            maxLength: AgentSecurity.maxWebTitleLength
        ).text
        let cleanChannel = AgentSecurity.sanitizeWebText(status.channel, maxLength: AgentSecurity.maxChannelNameLength).text
        let rawURL = (tab.pendingLazyURL ?? tab.url)
        let videoID = YouTubeURLRouter.extractVideoID(from: rawURL) ?? ""
        let cur = tab.timeline.currentTime
        let dur = tab.timeline.duration

        var obj: [String: JSONValue] = [
            "contentTrust": .string(AgentSecurity.untrustedWebContentTag),
            "windowID": .string(controller.windowID.uuidString),
            "tabID": .string(tab.id.uuidString),
            "hasVideo": .bool(status.hasVideo),
            "isPlaying": .bool(status.isPlaying),
            "title": .string(cleanTitle),
            "channel": .string(cleanChannel),
            "channelURL": .string(status.channelURLString),
            "url": .string(status.urlString.isEmpty ? rawURL.absoluteString : status.urlString),
            "videoID": .string(videoID),
            "currentTime": .double(cur),
            "duration": .double(dur),
            "formattedTime": .string(MediaState.formatTime(cur)),
            "formattedDuration": .string(MediaState.formatTime(dur)),
            "isMuted": .bool(status.isMuted),
            "volumePercent": .int(status.volumePercent),
            "playbackRate": .double(status.playbackRate),
            "isHDR": .bool(status.isHDR),
            "isPiP": .bool(status.isPiP),
            "isTheater": .bool(status.isTheater),
            "isCleanBoxActive": .bool(status.isCleanBoxActive),
            "isCleanBoxEligible": .bool(status.isCleanBoxEligible),
            "isCleanBoxBypassed": .bool(tab.isCleanBoxBypassed),
            "isAirPlayActive": .bool(status.isAirPlayActive),
            "isInFullscreen": .bool(tab.isInFullscreen || tab.webView.fullscreenState != .notInFullscreen)
        ]

        if includeChapters {
            let cappedChapters = Array(tab.chapters.prefix(AgentSecurity.maxChaptersCount))
            let currentChapter = VideoChapterParser.activeChapter(at: cur, in: cappedChapters)
            obj["activeChapterTitle"] = currentChapter.map {
                .string(AgentSecurity.sanitizeWebText($0.title, maxLength: AgentSecurity.maxChapterTitleLength).text)
            } ?? .null
            obj["chapters"] = .array(cappedChapters.enumerated().map { idx, ch in
                .object([
                    "index": .int(idx + 1),
                    "title": .string(AgentSecurity.sanitizeWebText(ch.title, maxLength: AgentSecurity.maxChapterTitleLength).text),
                    "startSeconds": .double(ch.startSeconds),
                    "formattedStartTime": .string(ch.formattedStartTime)
                ])
            })
        }

        if includeDescription {
            let sanitized = AgentSecurity.sanitizeWebText(tab.videoDescription, maxLength: AgentSecurity.maxVideoDescriptionLength)
            obj["description"] = .string(sanitized.text)
            obj["descriptionTruncated"] = .bool(sanitized.truncated || tab.videoDescriptionWasTruncated)
        }

        return .object(obj)
    }

    private func buildTabsJSON(windowIDString: String?) -> JSONValue {
        guard let coordinator else { return .object(["windows": .array([])]) }
        let targetWindows: [AppController]
        if let windowIDString, let exact = resolveWindow(idString: windowIDString, fallback: nil) {
            targetWindows = [exact]
        } else {
            targetWindows = coordinator.openWindows
        }

        let windowsJSON: [JSONValue] = targetWindows.map { ctrl in
            let tabsJSON: [JSONValue] = ctrl.tabs.enumerated().map { idx, tab in
                let effectiveURL = tab.pendingLazyURL ?? tab.url
                let cleanTitle = AgentSecurity.sanitizeWebText(tab.displayTitle, maxLength: AgentSecurity.maxWebTitleLength).text
                return .object([
                    "id": .string(tab.id.uuidString),
                    "index": .int(idx + 1),
                    "title": .string(cleanTitle),
                    "url": .string(effectiveURL.absoluteString),
                    "routingMode": .string(tab.routingMode.rawValue),
                    "isSelected": .bool(tab.id == ctrl.selectedTabID),
                    "isPlaying": .bool(tab.mediaStatus.isPlaying),
                    "hasVideo": .bool(tab.mediaStatus.hasVideo),
                    "isSleeping": .bool(tab.isSleeping || tab.pendingLazyURL != nil),
                    "isPoppedOut": .bool(ctrl.isTabPoppedOut(tab.id)),
                    "isCleanBoxActive": .bool(tab.mediaStatus.isCleanBoxActive),
                    "multiviewSlot": ctrl.multiviewSlotNumber(for: tab.id).map(JSONValue.int) ?? .null,
                    "isActiveAudio": .bool(ctrl.isMultiviewActive && ctrl.multiviewAudioTabID == tab.id),
                    "isInFullscreen": .bool(tab.isInFullscreen || tab.webView.fullscreenState != .notInFullscreen)
                ])
            }
            return .object([
                "windowID": .string(ctrl.windowID.uuidString),
                "isPrimary": .bool(ctrl.isPrimaryWindow),
                "selectedTabID": .string(ctrl.selectedTabID.uuidString),
                "tabs": .array(tabsJSON)
            ])
        }

        return .object([
            "contentTrust": .string(AgentSecurity.untrustedWebContentTag),
            "windows": .array(windowsJSON)
        ])
    }

    private func buildMultiviewJSON(windowIDString: String?) -> JSONValue {
        guard let coordinator,
              let ctrl = resolveWindow(idString: windowIDString, fallback: coordinator.commandTarget) else {
            return .object(["isActive": .bool(false)])
        }

        let tilesJSON: [JSONValue] = ctrl.multiviewTabs.enumerated().map { idx, tab in
            let effectiveURL = tab.pendingLazyURL ?? tab.url
            let effectiveAudio = ctrl.effectiveMultiviewVolume(for: tab.id)
            return .object([
                "slot": .int(idx + 1),
                "tabID": .string(tab.id.uuidString),
                "title": .string(AgentSecurity.sanitizeWebText(tab.displayTitle, maxLength: AgentSecurity.maxWebTitleLength).text),
                "url": .string(effectiveURL.absoluteString),
                "isPlaying": .bool(tab.mediaStatus.isPlaying),
                "isActiveAudio": .bool(ctrl.multiviewAudioTabID == tab.id),
                "volumePercent": .int(effectiveAudio.volumePercent),
                "isMuted": .bool(effectiveAudio.muted)
            ])
        }

        let presetsJSON: [JSONValue] = coordinator.settings.savedMultiviewPresets.map { preset in
            .object([
                "id": .string(preset.id.uuidString),
                "name": .string(AgentSecurity.sanitizeWebText(preset.name, maxLength: 120).text),
                "layoutMode": .string(preset.layoutMode.rawValue),
                "streamCount": .int(preset.urlStrings.count)
            ])
        }

        return .object([
            "contentTrust": .string(AgentSecurity.untrustedWebContentTag),
            "windowID": .string(ctrl.windowID.uuidString),
            "isActive": .bool(ctrl.isMultiviewActive),
            "isFloatingMiniPlayer": .bool(ctrl.isFloatingMultiviewGrid),
            "layoutMode": .string(ctrl.multiviewLayoutMode.rawValue),
            "soloTabID": ctrl.soloMultiviewTabID.map { .string($0.uuidString) } ?? .null,
            "audioTabID": ctrl.multiviewAudioTabID.map { .string($0.uuidString) } ?? .null,
            "hasCustomMix": .bool(ctrl.hasCustomMultiviewMix),
            "canAddTile": .bool(ctrl.canAddMultiviewTile),
            "maxTiles": .int(MultiviewGridLayout.maxTiles),
            "tiles": .array(tilesJSON),
            "savedPresets": .array(presetsJSON)
        ])
    }

    private func buildServicesJSON() -> JSONValue {
        guard let coordinator else { return .object(["services": .array([])]) }
        let items: [JSONValue] = StreamingServiceCatalog.all.map { svc in
            .object([
                "id": .string(svc.id),
                "name": .string(svc.name),
                "category": .string(svc.category.title),
                "enabled": .bool(coordinator.settings.isServiceEnabled(svc.id)),
                "requiresStrictDRM": .bool(svc.requiresStrictDRM),
                "homeURL": .string(svc.homeURLString)
            ])
        }
        return .object(["services": .array(items)])
    }

    private func buildLibraryJSON(include: Set<String>?) -> JSONValue {
        guard let coordinator else { return .object([:]) }
        let wantAll = (include == nil || include?.isEmpty == true)
        var obj: [String: JSONValue] = [
            "contentTrust": .string(AgentSecurity.untrustedWebContentTag)
        ]

        if wantAll || include?.contains("services") == true {
            obj["services"] = buildServicesJSON().objectValue?["services"] ?? .array([])
        }
        if wantAll || include?.contains("presets") == true {
            obj["presets"] = .array(coordinator.settings.savedMultiviewPresets.map { p in
                .object([
                    "id": .string(p.id.uuidString),
                    "name": .string(AgentSecurity.sanitizeWebText(p.name, maxLength: 120).text),
                    "layoutMode": .string(p.layoutMode.rawValue),
                    "urls": .array(p.urlStrings.map(JSONValue.string))
                ])
            })
        }
        if wantAll || include?.contains("pins") == true {
            obj["pins"] = .array(coordinator.settings.pinnedItems.map { item in
                .object([
                    "id": .string(item.id.uuidString),
                    "title": .string(AgentSecurity.sanitizeWebText(item.title, maxLength: 160).text),
                    "url": .string(item.urlString),
                    "folderID": item.folderID.map { .string($0.uuidString) } ?? .null
                ])
            })
        }
        if wantAll || include?.contains("folders") == true {
            obj["folders"] = .array(coordinator.settings.pinnedFolders.map { folder in
                .object([
                    "id": .string(folder.id.uuidString),
                    "name": .string(AgentSecurity.sanitizeWebText(folder.name, maxLength: 120).text)
                ])
            })
        }
        if wantAll || include?.contains("continue_watching") == true {
            obj["continueWatching"] = .array(coordinator.settings.continueWatching.map { cw in
                .object([
                    "videoID": .string(cw.videoID),
                    "title": .string(AgentSecurity.sanitizeWebText(cw.title, maxLength: AgentSecurity.maxWebTitleLength).text),
                    "channel": .string(AgentSecurity.sanitizeWebText(cw.channel, maxLength: AgentSecurity.maxChannelNameLength).text),
                    "currentTime": .double(cw.currentTime),
                    "duration": .double(cw.duration)
                ])
            })
        }
        if wantAll || include?.contains("displays") == true {
            coordinator.refreshConnectedDisplays()
            obj["displays"] = .array(coordinator.connectedDisplays.map { disp in
                .object([
                    "id": .int(Int(disp.id)),
                    "name": .string(disp.name),
                    "isPrimary": .bool(disp.isPrimary),
                    "pixelWidth": .int(disp.pixelWidth),
                    "pixelHeight": .int(disp.pixelHeight)
                ])
            })
        }
        return .object(obj)
    }

    // MARK: - Resolution & Activity Helpers

    private func resolveWindow(idString: String?, fallback: AppController?) -> AppController? {
        guard let coordinator else { return nil }
        if let idString {
            guard let uuid = UUID(uuidString: idString) else { return nil }
            return coordinator.openWindows.first { $0.windowID == uuid }
        }
        return fallback
    }

    private enum WindowTargetResolution {
        case existing(AppController)
        case openedNewWindow
        case notFound(String)
    }

    private func resolveOrCreateWindow(
        idString: String?,
        urlForNewWindow: URL,
        coordinator: AppCoordinator
    ) -> WindowTargetResolution {
        if let idString {
            if let existing = resolveWindow(idString: idString, fallback: nil) {
                return .existing(existing)
            }
            return .notFound("Window '\(idString)' not found.")
        }
        if let existing = coordinator.commandTarget {
            return .existing(existing)
        }
        coordinator.openURLInNewWindow(urlForNewWindow)
        return .openedNewWindow
    }

    private func resolveTab(args: [String: JSONValue], in controller: AppController, defaultTab: BrowserTab?) -> BrowserTab? {
        if let tabIDStr = args["tab_id"]?.stringValue {
            guard let uuid = UUID(uuidString: tabIDStr) else { return nil }
            return controller.tabs.first { $0.id == uuid }
        }
        if let slot = args["slot"]?.intValue {
            let idx = slot - 1
            guard controller.isMultiviewActive, controller.multiviewTabIDs.indices.contains(idx) else { return nil }
            let id = controller.multiviewTabIDs[idx]
            return controller.tabs.first { $0.id == id }
        }
        if let index = args["index"]?.intValue {
            let idx = index - 1
            guard controller.tabs.indices.contains(idx) else { return nil }
            return controller.tabs[idx]
        }
        return defaultTab
    }

    private func recordActivity(
        source: AgentCommandSource,
        action: String,
        summary: String,
        succeeded: Bool,
        errorCode: String?
    ) {
        let entry = AgentActivityEntry(
            source: source,
            action: action,
            summary: AgentSecurity.sanitizeWebText(summary, maxLength: 180).text,
            succeeded: succeeded,
            errorCode: errorCode
        )
        activityLog.insert(entry, at: 0)
        if activityLog.count > Self.maxActivityEntries {
            activityLog.removeLast(activityLog.count - Self.maxActivityEntries)
        }
    }
}
