import Foundation

/// Canonical metadata for a single MCP tool exposed by GlassGrid You.
public struct AgentToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let requiredTier: AgentPermissionLevel
    public let inputSchema: JSONValue
    public let readOnlyHint: Bool
    public let destructiveHint: Bool
    public let idempotentHint: Bool
    public let openWorldHint: Bool

    public init(
        name: String,
        description: String,
        requiredTier: AgentPermissionLevel,
        inputSchema: JSONValue,
        readOnlyHint: Bool = false,
        destructiveHint: Bool = false,
        idempotentHint: Bool = false,
        openWorldHint: Bool = false
    ) {
        self.name = name
        self.description = description
        self.requiredTier = requiredTier
        self.inputSchema = inputSchema
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }

    public func toMCPDictionary() -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string("\(description) [Permission: \(requiredTier.title)]"),
            "inputSchema": inputSchema,
            "annotations": .object([
                "title": .string(name),
                "readOnlyHint": .bool(readOnlyHint),
                "destructiveHint": .bool(destructiveHint),
                "idempotentHint": .bool(idempotentHint),
                "openWorldHint": .bool(openWorldHint)
            ])
        ])
    }
}

/// Canonical metadata for a read-only MCP resource exposed by GlassGrid You.
public struct AgentResourceDefinition: Sendable {
    public let uri: String
    public let name: String
    public let description: String
    public let mimeType: String

    public init(uri: String, name: String, description: String, mimeType: String = "application/json") {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }

    public func toMCPDictionary() -> JSONValue {
        .object([
            "uri": .string(uri),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType)
        ])
    }
}

/// Single source of truth for all 28 GlassGrid You MCP tools and 5 read-only resources.
public enum AgentToolCatalog {
    public static let resources: [AgentResourceDefinition] = [
        AgentResourceDefinition(
            uri: "glassgrid://state",
            name: "App State",
            description: "Active window summary, appearance, Focus Mode, Mini-Player, Multiview, sleep timer, audio output, and permission tier."
        ),
        AgentResourceDefinition(
            uri: "glassgrid://now-playing",
            name: "Now Playing",
            description: "Current playing or active video metadata, timeline position, chapters, and sanitized description (tagged untrusted_web_page)."
        ),
        AgentResourceDefinition(
            uri: "glassgrid://tabs",
            name: "Open Tabs",
            description: "All open tabs across GlassGrid You windows including sleeping, popped-out, and Multiview slot state."
        ),
        AgentResourceDefinition(
            uri: "glassgrid://multiview",
            name: "Multiview Grid",
            description: "Active Multiview tiles, layout mode, audio focus, solo state, and saved presets."
        ),
        AgentResourceDefinition(
            uri: "glassgrid://services",
            name: "Streaming Services",
            description: "All 18 built-in streaming services with category, enabled status, and DRM notes."
        )
    ]

    public static let tools: [AgentToolDefinition] = [
        // 1-5: Read-Only
        AgentToolDefinition(
            name: "get_app_state",
            description: "Read GlassGrid You window, appearance, Focus Mode, Mini-Player, Multiview summary, sleep timer, and audio output state.",
            requiredTier: .readOnly,
            inputSchema: schema(properties: [
                "window_id": strProp("Optional target window UUID string.")
            ]),
            readOnlyHint: true,
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "get_now_playing",
            description: "Read active video metadata, playback state, timeline, chapters, and capped video description (untrusted web context).",
            requiredTier: .readOnly,
            inputSchema: schema(properties: [
                "window_id": strProp("Optional target window UUID string."),
                "include_description": boolProp("Include sanitized video description up to 4,000 characters (default true)."),
                "include_chapters": boolProp("Include parsed video chapters (default true).")
            ]),
            readOnlyHint: true,
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "list_tabs",
            description: "List all open tabs across windows with titles, URLs, routing modes, sleeping status, and Multiview slots.",
            requiredTier: .readOnly,
            inputSchema: schema(properties: [
                "window_id": strProp("Optional window UUID to filter tabs.")
            ]),
            readOnlyHint: true,
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "get_multiview_state",
            description: "Inspect active Multiview tiles, layout mode, solo tile, exclusive audio focus, and saved presets.",
            requiredTier: .readOnly,
            inputSchema: schema(properties: [
                "window_id": strProp("Optional target window UUID string.")
            ]),
            readOnlyHint: true,
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "list_library",
            description: "List enabled streaming services, saved Multiview presets, pins, folders, Continue Watching items, and connected displays.",
            requiredTier: .readOnly,
            inputSchema: schema(properties: [
                "include": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("services"),
                            .string("presets"),
                            .string("pins"),
                            .string("folders"),
                            .string("continue_watching"),
                            .string("displays")
                        ])
                    ]),
                    "description": .string("Sections to include (omit to include all).")
                ])
            ]),
            readOnlyHint: true,
            idempotentHint: true
        ),

        // 6-22: Playback & Navigation
        AgentToolDefinition(
            name: "playback_control",
            description: "Control playback: play, pause, toggle_play_pause, mute, unmute, toggle_mute, toggle_pip, toggle_theater, or jump_to_live.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["play", "pause", "toggle_play_pause", "mute", "unmute", "toggle_mute", "toggle_pip", "toggle_theater", "jump_to_live"], "Playback action to perform."),
                    "tab_id": strProp("Optional target tab UUID string."),
                    "slot": intProp("Optional 1-based Multiview slot (1..4).", min: 1, max: 4),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            ),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "seek_playback",
            description: "Seek active video to absolute seconds, relative delta_seconds, 1-based chapter_index, or matching chapter_query.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "seconds": numProp("Absolute target timestamp in seconds (>= 0).", min: 0),
                "delta_seconds": numProp("Relative offset in seconds (e.g. -10 or 30)."),
                "chapter_index": intProp("1-based chapter index to jump to.", min: 1),
                "chapter_query": strProp("Case-insensitive substring matching a chapter title."),
                "tab_id": strProp("Optional target tab UUID string."),
                "slot": intProp("Optional 1-based Multiview slot (1..4).", min: 1, max: 4),
                "window_id": strProp("Optional target window UUID string.")
            ])
        ),
        AgentToolDefinition(
            name: "set_playback_speed",
            description: "Set active video playback speed between 0.25x and 4.0x.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "rate": numProp("Playback speed multiplier (0.25 to 4.0).", min: 0.25, max: 4.0),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["rate"]
            ),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "set_volume",
            description: "Set audio level (0..100%) and optional mute state on a tab or Multiview slot.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "volume_percent": intProp("Volume percentage (0..100).", min: 0, max: 100),
                    "muted": boolProp("Optional explicit mute override."),
                    "tab_id": strProp("Optional target tab UUID string."),
                    "slot": intProp("Optional 1-based Multiview slot (1..4).", min: 1, max: 4),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["volume_percent"]
            ),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "search_youtube",
            description: "Search YouTube in the active tab, a new tab, or as a Multiview stream.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "query": strProp("YouTube search query."),
                    "new_tab": boolProp("Open results in a new tab instead of navigating the current tab."),
                    "in_multiview": boolProp("Open search results as a tile in Multiview."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["query"]
            ),
            openWorldHint: true
        ),
        AgentToolDefinition(
            name: "open_url",
            description: "Open a validated HTTPS URL. YouTube and catalog streaming services are allowed in Playback & Navigation; arbitrary public HTTPS Companion sites require Full Control.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "url": strProp("HTTPS URL to open."),
                    "new_tab": boolProp("Open in a new tab (default true)."),
                    "in_multiview": boolProp("Add directly to Multiview."),
                    "in_new_window": boolProp("Open in a fresh GlassGrid You window."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["url"]
            ),
            openWorldHint: true
        ),
        AgentToolDefinition(
            name: "navigate_destination",
            description: "Navigate the selected tab to home, subscriptions, history, watch_later, liked_videos, playlists, back, forward, or reload.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "destination": enumProp(["home", "subscriptions", "history", "watch_later", "liked_videos", "playlists", "back", "forward", "reload"], "Built-in navigation destination."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["destination"]
            )
        ),
        AgentToolDefinition(
            name: "select_tab",
            description: "Switch focus to a tab by tab_id, 1-based index, or direction (next/previous).",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "tab_id": strProp("Target tab UUID string."),
                "index": intProp("1-based tab index.", min: 1),
                "direction": enumProp(["next", "previous"], "Relative tab direction."),
                "window_id": strProp("Optional target window UUID string.")
            ]),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "open_service",
            description: "Open any built-in streaming service by ID or alias (e.g. youtube, yttv, twitch, espn, peacock, paramount, primevideo, disneyplus, hulu, max/hbomax, appletv, netflix, crunchyroll).",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "service_id": strProp("Canonical service ID from list_library / glassgrid://services."),
                    "new_tab": boolProp("Open in a new tab (default true)."),
                    "in_multiview": boolProp("Add directly into Multiview."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["service_id"]
            )
        ),
        AgentToolDefinition(
            name: "multiview_control",
            description: "Control Multiview grid mode, layout (auto/spotlight/stacked), solo mode, primary slot promotion, and exclusive audio focus.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["enter", "exit", "toggle", "set_layout", "cycle_layout", "solo", "exit_solo", "focus_audio", "cycle_audio_next", "cycle_audio_prev", "mute_all", "reset_mixer", "promote_primary"], "Multiview action."),
                    "layout": enumProp(["auto", "spotlight", "stacked"], "Target layout when action is set_layout."),
                    "tab_id": strProp("Optional target tab UUID string."),
                    "slot": intProp("Optional 1-based Multiview slot (1..4).", min: 1, max: 4),
                    "tab_ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional explicit tab UUIDs when entering Multiview (2..4).")
                    ]),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            )
        ),
        AgentToolDefinition(
            name: "multiview_manage_tile",
            description: "Add or remove a stream tile in Multiview by URL, streaming service ID, tab ID, or slot.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["add", "remove"], "Whether to add or remove a Multiview tile."),
                    "url": strProp("HTTPS URL to add as a new tile."),
                    "service_id": strProp("Streaming service ID to add as a new tile."),
                    "tab_id": strProp("Existing tab UUID to add or remove."),
                    "slot": intProp("1-based Multiview slot to remove.", min: 1, max: 4),
                    "close_tab": boolProp("Also close the underlying tab when removing a tile (requires Full Control)."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            )
        ),
        AgentToolDefinition(
            name: "launch_multiview_preset",
            description: "Launch a saved Multiview preset by preset_id or name in the active window or a new window.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "preset_id": strProp("Saved Multiview preset UUID."),
                "name": strProp("Case-insensitive preset name."),
                "in_new_window": boolProp("Open the preset in a dedicated new window."),
                "window_id": strProp("Optional target window UUID string.")
            ])
        ),
        AgentToolDefinition(
            name: "mini_player_control",
            description: "Enter, exit, toggle, adjust opacity (0.4..1.0), or set grid/single size preset (compact, standard, large, extraLarge) for the Floating Mini-Player or Floating Multiview Grid.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "action": enumProp(["enter", "exit", "toggle"], "Mini-Player state action."),
                "opacity": numProp("Optional Mini-Player opacity (0.40 to 1.0).", min: 0.4, max: 1.0),
                "size_preset": enumProp(["compact", "standard", "large", "extraLarge"], "Optional floating Mini-Player or Multiview Grid size preset."),
                "window_id": strProp("Optional target window UUID string.")
            ])
        ),
        AgentToolDefinition(
            name: "set_appearance",
            description: "Set Day (light), Night (dark), Match System (system), or toggle appearance across GlassGrid You and YouTube.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "mode": enumProp(["system", "light", "dark", "toggle"], "Appearance mode.")
                ],
                required: ["mode"]
            ),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "set_focus_mode",
            description: "Enable, disable, or toggle distraction-free Focus Mode.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "enabled": boolProp("Target Focus Mode state (omit to toggle)."),
                "window_id": strProp("Optional target window UUID string.")
            ])
        ),
        AgentToolDefinition(
            name: "set_sleep_timer",
            description: "Set or turn off the playback sleep timer.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(
                properties: [
                    "option": enumProp(["15m", "30m", "45m", "60m", "end_of_video", "off"], "Sleep timer duration or off."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["option"]
            ),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "set_ui_chrome",
            description: "Show/hide sidebar, toggle always-on-top, or zoom web content in/out/reset.",
            requiredTier: .playbackAndNavigation,
            inputSchema: schema(properties: [
                "sidebar_visible": boolProp("Show or hide the Liquid Glass sidebar."),
                "always_on_top": boolProp("Keep the window floating above other windows."),
                "zoom_action": enumProp(["in", "out", "reset"], "Page zoom adjustment."),
                "window_id": strProp("Optional target window UUID string.")
            ])
        ),

        // 23-28: Full Control
        AgentToolDefinition(
            name: "manage_tabs",
            description: "Close, close_others, duplicate, reopen_closed, or sleep tabs.",
            requiredTier: .fullControl,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["close", "close_others", "duplicate", "reopen_closed", "sleep"], "Tab lifecycle action."),
                    "tab_id": strProp("Target tab UUID (defaults to selected tab)."),
                    "index": intProp("Optional 1-based tab index.", min: 1),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            ),
            destructiveHint: true
        ),
        AgentToolDefinition(
            name: "manage_multiview_preset",
            description: "Save the active Multiview grid as a preset, or rename/delete an existing preset.",
            requiredTier: .fullControl,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["save_current", "rename", "delete"], "Preset management action."),
                    "preset_id": strProp("Preset UUID (for rename or delete)."),
                    "name": strProp("Preset name."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            ),
            destructiveHint: true
        ),
        AgentToolDefinition(
            name: "manage_pins",
            description: "Pin/unpin pages, create/delete sidebar folders, organize pins, or open folders in tabs/Multiview.",
            requiredTier: .fullControl,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["pin_current", "unpin_current", "add_pin", "remove_pin", "create_folder", "delete_folder", "move_pin_to_folder", "open_folder_multiview", "open_folder_tabs"], "Pin or folder action."),
                    "pin_id": strProp("Pin UUID."),
                    "folder_id": strProp("Folder UUID."),
                    "title": strProp("Pin title."),
                    "url": strProp("HTTPS URL for add_pin."),
                    "name": strProp("Folder name."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            ),
            destructiveHint: true
        ),
        AgentToolDefinition(
            name: "manage_window",
            description: "Open a new GlassGrid You window, focus a specific window, or move a window to a connected display.",
            requiredTier: .fullControl,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["new_window", "focus", "move_to_display"], "Window management action."),
                    "window_id": strProp("Target window UUID."),
                    "display_id": intProp("Target display numeric ID from list_library."),
                    "display_name": strProp("Case-insensitive display name substring.")
                ],
                required: ["action"]
            )
        ),
        AgentToolDefinition(
            name: "set_distraction_free_preferences",
            description: "Update distraction-free YouTube preferences and quality/ducking settings.",
            requiredTier: .fullControl,
            inputSchema: schema(properties: [
                "hide_shorts": boolProp("Hide YouTube Shorts."),
                "redirect_shorts_to_watch": boolProp("Redirect Shorts links to standard watch player."),
                "clean_web_chrome": boolProp("Clean YouTube web chrome."),
                "hide_web_header": boolProp("Hide YouTube web top masthead."),
                "auto_theater_mode": boolProp("Default to Theater mode on watch pages."),
                "hide_end_screens": boolProp("Hide end-screen cards."),
                "hide_watch_recommendations": boolProp("Hide right-side recommendations."),
                "hide_comments": boolProp("Hide video comments."),
                "hide_home_feed": boolProp("Hide YouTube Home feed."),
                "clean_box_streaming_players": boolProp("Isolate active video players edge-to-edge across all 18 streaming services (Clean-Box)."),
                "multiview_audio_ducking": boolProp("Duck background Multiview audio to 15% instead of muting."),
                "preferred_quality": enumProp(["auto", "2160p", "1440p", "1080p", "720p"], "Preferred video quality.")
            ]),
            idempotentHint: true
        ),
        AgentToolDefinition(
            name: "find_on_page",
            description: "Find text on the current page, advance next/previous match, or clear highlights.",
            requiredTier: .fullControl,
            inputSchema: schema(
                properties: [
                    "action": enumProp(["find", "next", "previous", "clear"], "Find bar action."),
                    "query": strProp("Search query (required for action=find)."),
                    "window_id": strProp("Optional target window UUID string.")
                ],
                required: ["action"]
            )
        )
    ]

    public static func tool(named name: String) -> AgentToolDefinition? {
        tools.first { $0.name == name }
    }

    public static func resource(forURI uri: String) -> AgentResourceDefinition? {
        resources.first { $0.uri == uri }
    }

    // MARK: - JSON Schema Builders

    private static func schema(properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var obj: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false)
        ]
        if !required.isEmpty {
            obj["required"] = .array(required.map(JSONValue.string))
        }
        return .object(obj)
    }

    private static func strProp(_ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func boolProp(_ description: String) -> JSONValue {
        .object([
            "type": .string("boolean"),
            "description": .string(description)
        ])
    }

    private static func intProp(_ description: String, min: Int? = nil, max: Int? = nil) -> JSONValue {
        var obj: [String: JSONValue] = [
            "type": .string("integer"),
            "description": .string(description)
        ]
        if let min { obj["minimum"] = .int(min) }
        if let max { obj["maximum"] = .int(max) }
        return .object(obj)
    }

    private static func numProp(_ description: String, min: Double? = nil, max: Double? = nil) -> JSONValue {
        var obj: [String: JSONValue] = [
            "type": .string("number"),
            "description": .string(description)
        ]
        if let min { obj["minimum"] = .double(min) }
        if let max { obj["maximum"] = .double(max) }
        return .object(obj)
    }

    private static func enumProp(_ values: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"),
            "enum": .array(values.map(JSONValue.string)),
            "description": .string(description)
        ])
    }
}
