import AppIntents
import AppKit
import Foundation
import YouTubeMacCore

private enum GlassGridIntentError: Error, CustomLocalizedStringResourceConvertible {
    case automationDisabled
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .automationDisabled:
            return "AI & Automation is turned off in GlassGrid You. Open GlassGrid You → Settings → AI & Automation to enable Siri, Shortcuts, and AI agent control."
        case .failed(let message):
            return "\(message)"
        }
    }
}

@MainActor
private func executeBridgeCommand(
    _ bridge: AgentBridgeController,
    toolName: String,
    arguments: [String: JSONValue] = [:],
    activateApp: Bool = false
) async throws -> AgentCommandOutcome {
    guard bridge.isAutomationEnabled else {
        throw GlassGridIntentError.automationDisabled
    }
    if activateApp {
        NSApp.activate(ignoringOtherApps: true)
    }
    let outcome = await bridge.execute(
        toolName: toolName,
        arguments: arguments,
        context: AgentRequestContext(source: .appIntents, clientName: "Siri & Shortcuts")
    )
    if !outcome.ok {
        throw GlassGridIntentError.failed(outcome.message)
    }
    return outcome
}

// MARK: - AppEntities & Globally Unique Queries (Xcode 16+ safe)

public struct GlassGridStreamingServiceEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Streaming Service"
    public static let defaultQuery = GlassGridStreamingServiceEntityQuery()

    public let id: String
    public let name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct GlassGridStreamingServiceEntityQuery: EntityStringQuery, Sendable {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [GlassGridStreamingServiceEntity] {
        let idSet = Set(identifiers)
        return StreamingServiceCatalog.all
            .filter { idSet.contains($0.id) }
            .map { GlassGridStreamingServiceEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [GlassGridStreamingServiceEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return try await suggestedEntities()
        }
        let aliasMatchID = StreamingServiceCatalog.resolveService(identifierOrAlias: query)?.id
        return StreamingServiceCatalog.all
            .filter {
                $0.id == aliasMatchID
                    || $0.name.localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }
            .map { GlassGridStreamingServiceEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [GlassGridStreamingServiceEntity] {
        StreamingServiceCatalog.all.map { GlassGridStreamingServiceEntity(id: $0.id, name: $0.name) }
    }
}

public struct GlassGridMultiviewPresetEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Multiview Preset"
    public static let defaultQuery = GlassGridMultiviewPresetEntityQuery()

    public let id: String
    public let name: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct GlassGridMultiviewPresetEntityQuery: EntityStringQuery, Sendable {
    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [GlassGridMultiviewPresetEntity] {
        let outcome = await agentBridge.execute(
            toolName: "list_library",
            arguments: ["include": .array([.string("presets")])],
            context: AgentRequestContext(source: .appIntents, clientName: "Siri & Shortcuts")
        )
        let presets = outcome.data?.objectValue?["presets"]?.arrayValue ?? []
        let idSet = Set(identifiers)
        return presets.compactMap { item in
            guard let id = item.objectValue?["id"]?.stringValue,
                  let name = item.objectValue?["name"]?.stringValue,
                  idSet.contains(id) else { return nil }
            return GlassGridMultiviewPresetEntity(id: id, name: name)
        }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [GlassGridMultiviewPresetEntity] {
        let all = try await suggestedEntities()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [GlassGridMultiviewPresetEntity] {
        guard agentBridge.isAutomationEnabled else { return [] }
        let outcome = await agentBridge.execute(
            toolName: "list_library",
            arguments: ["include": .array([.string("presets")])],
            context: AgentRequestContext(source: .appIntents, clientName: "Siri & Shortcuts")
        )
        let presets = outcome.data?.objectValue?["presets"]?.arrayValue ?? []
        return presets.compactMap { item in
            guard let id = item.objectValue?["id"]?.stringValue,
                  let name = item.objectValue?["name"]?.stringValue else { return nil }
            return GlassGridMultiviewPresetEntity(id: id, name: name)
        }
    }
}

public struct GlassGridTabEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Browser Tab"
    public static let defaultQuery = GlassGridTabEntityQuery()

    public let id: String
    public let title: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct GlassGridTabEntityQuery: EntityQuery, Sendable {
    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [GlassGridTabEntity] {
        let all = try await suggestedEntities()
        let idSet = Set(identifiers)
        return all.filter { idSet.contains($0.id) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [GlassGridTabEntity] {
        guard agentBridge.isAutomationEnabled else { return [] }
        let outcome = await agentBridge.execute(
            toolName: "list_tabs",
            arguments: [:],
            context: AgentRequestContext(source: .appIntents, clientName: "Siri & Shortcuts")
        )
        let windows = outcome.data?.objectValue?["windows"]?.arrayValue ?? []
        var result: [GlassGridTabEntity] = []
        for win in windows {
            let tabs = win.objectValue?["tabs"]?.arrayValue ?? []
            for tab in tabs {
                if let id = tab.objectValue?["id"]?.stringValue,
                   let title = tab.objectValue?["title"]?.stringValue {
                    result.append(GlassGridTabEntity(id: id, title: title))
                }
            }
        }
        return result
    }
}

// MARK: - AppEnums (Static Let for Swift 6 Strict Concurrency)

public enum GlassGridPlaybackActionEnum: String, AppEnum, Sendable {
    case play
    case pause
    case togglePlayPause
    case mute
    case unmute
    case toggleMute
    case jumpToLive

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback Action"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .play: "Play",
        .pause: "Pause",
        .togglePlayPause: "Play or Pause",
        .mute: "Mute",
        .unmute: "Unmute",
        .toggleMute: "Toggle Mute",
        .jumpToLive: "Jump to Live"
    ]

    var toolAction: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .togglePlayPause: return "toggle_play_pause"
        case .mute: return "mute"
        case .unmute: return "unmute"
        case .toggleMute: return "toggle_mute"
        case .jumpToLive: return "jump_to_live"
        }
    }
}

public enum GlassGridMultiviewActionEnum: String, AppEnum, Sendable {
    case enter
    case exit
    case toggle
    case cycleLayout
    case solo
    case exitSolo
    case nextAudio
    case previousAudio
    case muteAll

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Multiview Action"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .enter: "Enter Multiview",
        .exit: "Exit Multiview",
        .toggle: "Toggle Multiview",
        .cycleLayout: "Cycle Multiview Layout",
        .solo: "Solo Active Tile",
        .exitSolo: "Exit Solo",
        .nextAudio: "Next Stream Audio",
        .previousAudio: "Previous Stream Audio",
        .muteAll: "Mute All Streams"
    ]

    var toolAction: String {
        switch self {
        case .enter: return "enter"
        case .exit: return "exit"
        case .toggle: return "toggle"
        case .cycleLayout: return "cycle_layout"
        case .solo: return "solo"
        case .exitSolo: return "exit_solo"
        case .nextAudio: return "cycle_audio_next"
        case .previousAudio: return "cycle_audio_prev"
        case .muteAll: return "mute_all"
        }
    }
}

public enum GlassGridAppearanceEnum: String, AppEnum, Sendable {
    case system
    case light
    case dark
    case toggle

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Appearance Mode"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .system: "Match System",
        .light: "Day (Light)",
        .dark: "Night (Dark)",
        .toggle: "Toggle Day / Night"
    ]
}

public enum GlassGridSleepTimerEnum: String, AppEnum, Sendable {
    case minutes15 = "15m"
    case minutes30 = "30m"
    case minutes45 = "45m"
    case minutes60 = "60m"
    case endOfVideo = "end_of_video"
    case off = "off"

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sleep Timer"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .minutes15: "15 Minutes",
        .minutes30: "30 Minutes",
        .minutes45: "45 Minutes",
        .minutes60: "60 Minutes",
        .endOfVideo: "End of Current Video",
        .off: "Turn Off"
    ]
}

// MARK: - 12 Focused Single-Purpose AppIntents

public struct GetNowPlayingIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Now Playing"
    public static let description = IntentDescription("Reads the active video title, channel, and timestamp in GlassGrid You.")

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let outcome = try await executeBridgeCommand(agentBridge, toolName: "get_now_playing", arguments: [:])
        let obj = outcome.data?.objectValue ?? [:]
        let hasVideo = obj["hasVideo"]?.boolValue ?? false
        guard hasVideo else {
            return .result(value: "Nothing is playing.", dialog: "Nothing is currently playing in GlassGrid You.")
        }
        let title = obj["title"]?.stringValue ?? "Video"
        let channel = obj["channel"]?.stringValue ?? ""
        let time = obj["formattedTime"]?.stringValue ?? "0:00"
        let summary = channel.isEmpty ? "\(title) (\(time))" : "\(title) by \(channel) (\(time))"
        return .result(value: summary, dialog: "\(summary)")
    }
}

public struct ControlPlaybackIntent: AppIntent {
    public static let title: LocalizedStringResource = "Control Playback"
    public static let description = IntentDescription("Play, pause, mute, unmute, or jump to live in GlassGrid You.")

    @Parameter(title: "Action", default: .togglePlayPause)
    public var action: GlassGridPlaybackActionEnum

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "playback_control",
            arguments: ["action": .string(action.toolAction)]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct SeekPlaybackIntent: AppIntent {
    public static let title: LocalizedStringResource = "Seek Video"
    public static let description = IntentDescription("Jump forward or backward by seconds in the active video.")

    @Parameter(title: "Seconds Offset", default: 15)
    public var deltaSeconds: Double

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "seek_playback",
            arguments: ["delta_seconds": .double(deltaSeconds)]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct SetPlaybackSpeedIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Playback Speed"
    public static let description = IntentDescription("Adjust playback speed between 0.25x and 4.0x.")

    @Parameter(title: "Speed", default: 1.5, inclusiveRange: (0.25, 4.0))
    public var rate: Double

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "set_playback_speed",
            arguments: ["rate": .double(rate)]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct SearchYouTubeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search YouTube"
    public static let description = IntentDescription("Search YouTube inside GlassGrid You.")

    @Parameter(title: "Search Query")
    public var query: String

    @Parameter(title: "Open in New Tab", default: true)
    public var openInNewTab: Bool

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "search_youtube",
            arguments: ["query": .string(query), "new_tab": .bool(openInNewTab)],
            activateApp: true
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct OpenStreamingServiceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Streaming Service"
    public static let description = IntentDescription("Open a built-in streaming service in GlassGrid You.")

    @Parameter(title: "Streaming Service")
    public var service: GlassGridStreamingServiceEntity

    @Parameter(title: "Add to Multiview", default: false)
    public var addToMultiview: Bool

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "open_service",
            arguments: ["service_id": .string(service.id), "in_multiview": .bool(addToMultiview), "new_tab": .bool(true)],
            activateApp: true
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct LaunchMultiviewPresetIntent: AppIntent {
    public static let title: LocalizedStringResource = "Launch Multiview Preset"
    public static let description = IntentDescription("Launch a saved Multiview grid preset in GlassGrid You.")

    @Parameter(title: "Preset")
    public var preset: GlassGridMultiviewPresetEntity

    @Parameter(title: "Open in New Window", default: false)
    public var inNewWindow: Bool

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "launch_multiview_preset",
            arguments: ["preset_id": .string(preset.id), "in_new_window": .bool(inNewWindow)],
            activateApp: true
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct ControlMultiviewIntent: AppIntent {
    public static let title: LocalizedStringResource = "Control Multiview"
    public static let description = IntentDescription("Enter, exit, toggle, cycle layout, solo, or switch audio in Multiview.")

    @Parameter(title: "Action", default: .toggle)
    public var action: GlassGridMultiviewActionEnum

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "multiview_control",
            arguments: ["action": .string(action.toolAction)],
            activateApp: action == .enter || action == .toggle
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct ToggleMiniPlayerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Mini-Player"
    public static let description = IntentDescription("Float or dock the always-on-top Mini-Player.")

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "mini_player_control",
            arguments: ["action": .string("toggle")]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct SetAppearanceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Appearance"
    public static let description = IntentDescription("Switch GlassGrid You between Day, Night, or Match System.")

    @Parameter(title: "Appearance", default: .toggle)
    public var mode: GlassGridAppearanceEnum

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "set_appearance",
            arguments: ["mode": .string(mode.rawValue)]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct ToggleFocusModeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Focus Mode"
    public static let description = IntentDescription("Toggle distraction-free Focus Mode in GlassGrid You.")

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "set_focus_mode",
            arguments: [:]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

public struct SetSleepTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Sleep Timer"
    public static let description = IntentDescription("Start or turn off the GlassGrid You sleep timer.")

    @Parameter(title: "Timer", default: .minutes30)
    public var option: GlassGridSleepTimerEnum

    @Dependency(key: "GlassGridAgentBridge")
    private var agentBridge: AgentBridgeController

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await executeBridgeCommand(
            agentBridge,
            toolName: "set_sleep_timer",
            arguments: ["option": .string(option.rawValue)]
        )
        return .result(dialog: "\(outcome.message)")
    }
}

// MARK: - AppShortcutsProvider (Max 10 entries; every phrase includes \(.applicationName))

public struct GlassGridShortcutsProvider: AppShortcutsProvider {
    public static let shortcutTileColor: ShortcutTileColor = .red

    @AppShortcutsBuilder
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNowPlayingIntent(),
            phrases: [
                "What's playing in \(.applicationName)",
                "Now playing in \(.applicationName)"
            ],
            shortTitle: "Now Playing",
            systemImageName: "play.rectangle.fill"
        )
        AppShortcut(
            intent: ControlPlaybackIntent(),
            phrases: [
                "Play or pause in \(.applicationName)",
                "Control playback in \(.applicationName)"
            ],
            shortTitle: "Play or Pause",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: SearchYouTubeIntent(),
            phrases: [
                "Search YouTube in \(.applicationName)"
            ],
            shortTitle: "Search YouTube",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenStreamingServiceIntent(),
            phrases: [
                "Open \(\.$service) in \(.applicationName)"
            ],
            shortTitle: "Open Streaming Service",
            systemImageName: "tv.fill"
        )
        AppShortcut(
            intent: LaunchMultiviewPresetIntent(),
            phrases: [
                "Launch \(\.$preset) in \(.applicationName)"
            ],
            shortTitle: "Launch Multiview Preset",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: ToggleMiniPlayerIntent(),
            phrases: [
                "Toggle Mini-Player in \(.applicationName)"
            ],
            shortTitle: "Toggle Mini-Player",
            systemImageName: "pip.enter"
        )
        AppShortcut(
            intent: ToggleFocusModeIntent(),
            phrases: [
                "Toggle Focus Mode in \(.applicationName)"
            ],
            shortTitle: "Toggle Focus Mode",
            systemImageName: "eye.slash.fill"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: [
                "Set sleep timer in \(.applicationName)"
            ],
            shortTitle: "Set Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )
    }
}
