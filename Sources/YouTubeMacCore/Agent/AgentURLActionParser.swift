import Foundation

/// Parsed safe automation action derived from `glassgridyou://action/<verb>?...`.
public struct ParsedURLAction: Equatable, Sendable {
    public let toolName: String
    public let arguments: [String: JSONValue]

    public init(toolName: String, arguments: [String: JSONValue]) {
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct AgentURLActionError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Strictly parses `glassgridyou://action/<verb>?...` (and legacy `youtubemac://action/<verb>?...`)
/// into safe Tier 2 playback & YouTube/catalog navigation commands.
/// Never allows arbitrary third-party URLs or Tier 3 mutations.
public enum AgentURLActionParser {
    public static func isActionURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "glassgridyou" || scheme == "youtubemac" else {
            return false
        }
        return url.host?.lowercased() == "action"
    }

    public static func parse(_ url: URL) -> Result<ParsedURLAction, AgentURLActionError> {
        guard isActionURL(url) else {
            return .failure(AgentURLActionError("Not an action URL."))
        }

        let verb = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !verb.isEmpty else {
            return .failure(AgentURLActionError("Missing action verb in URL."))
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name.lowercased()] = value
            }
        }

        switch verb {
        case "play":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("play")]))
        case "pause":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("pause")]))
        case "toggle-play", "toggle_play", "toggle-play-pause":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("toggle_play_pause")]))
        case "mute":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("mute")]))
        case "unmute":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("unmute")]))
        case "toggle-mute", "toggle_mute":
            return .success(ParsedURLAction(toolName: "playback_control", arguments: ["action": .string("toggle_mute")]))

        case "seek":
            if let rawSec = params["seconds"], let sec = Double(rawSec), sec.isFinite, sec >= 0 {
                return .success(ParsedURLAction(toolName: "seek_playback", arguments: ["seconds": .double(sec)]))
            }
            if let rawDelta = params["delta"], let delta = Double(rawDelta), delta.isFinite {
                return .success(ParsedURLAction(toolName: "seek_playback", arguments: ["delta_seconds": .double(delta)]))
            }
            return .failure(AgentURLActionError("seek action requires numeric seconds or delta parameter."))

        case "speed":
            guard let rawRate = params["rate"], let rate = Double(rawRate), rate.isFinite, rate >= 0.25, rate <= 4.0 else {
                return .failure(AgentURLActionError("speed action requires rate between 0.25 and 4.0."))
            }
            return .success(ParsedURLAction(toolName: "set_playback_speed", arguments: ["rate": .double(rate)]))

        case "search":
            guard let query = params["q"]?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
                return .failure(AgentURLActionError("search action requires non-empty q parameter."))
            }
            var args: [String: JSONValue] = ["query": .string(query)]
            if let newTab = parseBool(params["new_tab"]) {
                args["new_tab"] = .bool(newTab)
            }
            return .success(ParsedURLAction(toolName: "search_youtube", arguments: args))

        case "service":
            guard let rawServiceID = params["id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let service = StreamingServiceCatalog.resolveService(identifierOrAlias: rawServiceID) else {
                return .failure(AgentURLActionError("service action requires a valid built-in service id."))
            }
            var args: [String: JSONValue] = ["service_id": .string(service.id)]
            if let inMV = parseBool(params["multiview"]) {
                args["in_multiview"] = .bool(inMV)
            }
            return .success(ParsedURLAction(toolName: "open_service", arguments: args))

        case "multiview":
            let action = (params["action"] ?? "toggle").lowercased()
            let allowed = Set(["enter", "exit", "toggle", "set_layout", "cycle_layout", "solo", "exit_solo", "focus_audio", "cycle_audio_next", "cycle_audio_prev", "mute_all"])
            guard allowed.contains(action) else {
                return .failure(AgentURLActionError("Unsupported multiview URL action."))
            }
            var args: [String: JSONValue] = ["action": .string(action)]
            if let layout = params["layout"]?.lowercased(), ["auto", "spotlight", "stacked"].contains(layout) {
                args["layout"] = .string(layout)
            }
            if let rawSlot = params["slot"], let slot = Int(rawSlot), (1...4).contains(slot) {
                args["slot"] = .int(slot)
            }
            return .success(ParsedURLAction(toolName: "multiview_control", arguments: args))

        case "preset":
            var args: [String: JSONValue] = [:]
            if let id = params["id"], !id.isEmpty { args["preset_id"] = .string(id) }
            if let name = params["name"], !name.isEmpty { args["name"] = .string(name) }
            guard !args.isEmpty else {
                return .failure(AgentURLActionError("preset action requires id or name."))
            }
            return .success(ParsedURLAction(toolName: "launch_multiview_preset", arguments: args))

        case "mini-player", "mini_player":
            let action = (params["action"] ?? "toggle").lowercased()
            guard ["enter", "exit", "toggle"].contains(action) else {
                return .failure(AgentURLActionError("Unsupported mini-player action."))
            }
            return .success(ParsedURLAction(toolName: "mini_player_control", arguments: ["action": .string(action)]))

        case "focus-mode", "focus_mode":
            var args: [String: JSONValue] = [:]
            if let enabled = parseBool(params["enabled"]) {
                args["enabled"] = .bool(enabled)
            }
            return .success(ParsedURLAction(toolName: "set_focus_mode", arguments: args))

        case "appearance":
            let mode = (params["mode"] ?? "toggle").lowercased()
            guard ["system", "light", "dark", "toggle"].contains(mode) else {
                return .failure(AgentURLActionError("Unsupported appearance mode."))
            }
            return .success(ParsedURLAction(toolName: "set_appearance", arguments: ["mode": .string(mode)]))

        case "sleep-timer", "sleep_timer":
            let option = (params["option"] ?? "30m").lowercased()
            guard ["15m", "30m", "45m", "60m", "end_of_video", "off"].contains(option) else {
                return .failure(AgentURLActionError("Unsupported sleep-timer option."))
            }
            return .success(ParsedURLAction(toolName: "set_sleep_timer", arguments: ["option": .string(option)]))

        default:
            return .failure(AgentURLActionError("Action '\(verb)' is not permitted via URL scheme."))
        }
    }

    private static func parseBool(_ raw: String?) -> Bool? {
        guard let raw = raw?.lowercased() else { return nil }
        if raw == "true" || raw == "1" || raw == "yes" { return true }
        if raw == "false" || raw == "0" || raw == "no" { return false }
        return nil
    }
}
