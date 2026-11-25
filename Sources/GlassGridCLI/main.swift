import Darwin
import Foundation
import YouTubeMacCore

@main
enum GlassGridCLIMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let rawArgs = Array(CommandLine.arguments.dropFirst())

        if rawArgs.isEmpty {
            if isatty(STDIN_FILENO) == 0 {
                runMCPLoop(noLaunch: false)
                return
            }
            printUsage()
            return
        }

        var noLaunch = false
        var jsonOutput = false
        var positional: [String] = []
        for arg in rawArgs {
            switch arg {
            case "--no-launch":
                noLaunch = true
            case "--json":
                jsonOutput = true
            case "-h", "--help", "help":
                printUsage()
                return
            default:
                positional.append(arg)
            }
        }

        guard let command = positional.first?.lowercased() else {
            if isatty(STDIN_FILENO) == 0 {
                runMCPLoop(noLaunch: noLaunch)
            } else {
                printUsage()
            }
            return
        }

        if command == "mcp" || command == "--mcp" {
            runMCPLoop(noLaunch: noLaunch)
            return
        }

        let client = AgentUnixSocketClient(noLaunch: noLaunch)
        let exitCode = runCLIAction(
            command: command,
            args: Array(positional.dropFirst()),
            jsonOutput: jsonOutput,
            client: client
        )
        exit(exitCode)
    }

    // MARK: - MCP Stdio Server Loop

    private static func runMCPLoop(noLaunch: Bool) {
        let handler = MCPProtocolHandler()
        let client = AgentUnixSocketClient(noLaunch: noLaunch)

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let data = Data(trimmed.utf8)

            // Serve initialize / notifications / ping / tools/list / resources/list locally
            // without auto-launching the GUI app.
            if let localResult = handler.handleDiscoveryOnly(data) {
                switch localResult {
                case .noResponse:
                    break
                case .reply(let replyData):
                    writeLine(replyData)
                case .batchRejected:
                    break
                }
                continue
            }

            let request = AgentIPCRequest(
                kind: .mcpJSONRPC(payloadUTF8: trimmed, clientName: "mcp-stdio")
            )
            switch client.send(request) {
            case .success(let response):
                switch response.kind {
                case .mcpNoResponse:
                    break
                case .mcpReply(let payloadUTF8):
                    writeLine(Data(payloadUTF8.utf8))
                case .error(let code, let message):
                    writeJSONRPCError(requestData: data, code: -32000, message: "\(code): \(message)")
                default:
                    writeJSONRPCError(requestData: data, code: -32000, message: "Unexpected IPC response.")
                }
            case .failure(let error):
                writeToolOrProtocolError(requestData: data, message: error.message)
            }
        }
    }

    private static func writeLine(_ data: Data) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
        fflush(stdout)
    }

    private static func writeToolOrProtocolError(requestData: Data, message: String) {
        if let parsed = try? JSONValue.decode(from: requestData),
           let obj = parsed.objectValue,
           let idVal = obj["id"],
           obj["method"]?.stringValue == "tools/call" {
            let structured = AgentCommandOutcome.failure(code: "app_unavailable", message: message).toJSONValue()
            let envelope: JSONValue = .object([
                "jsonrpc": .string("2.0"),
                "id": idVal,
                "result": .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(message)
                        ])
                    ]),
                    "structuredContent": structured,
                    "isError": .bool(true)
                ])
            ])
            if let encoded = try? envelope.encodedData(prettyPrinted: false) {
                writeLine(encoded)
                return
            }
        }
        writeJSONRPCError(requestData: requestData, code: -32000, message: message)
    }

    private static func writeJSONRPCError(requestData: Data, code: Int, message: String) {
        let parsedId: JSONValue
        if let parsed = try? JSONValue.decode(from: requestData),
           let obj = parsed.objectValue,
           let idVal = obj["id"] {
            parsedId = idVal
        } else {
            parsedId = .null
        }
        let envelope: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": parsedId,
            "error": .object([
                "code": .int(code),
                "message": .string(message)
            ])
        ])
        if let encoded = try? envelope.encodedData(prettyPrinted: false) {
            writeLine(encoded)
        }
    }

    // MARK: - Ergonomic Scriptable CLI Subcommands

    private struct CLIUsageError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func runCLIAction(
        command: String,
        args: [String],
        jsonOutput: Bool,
        client: AgentUnixSocketClient
    ) -> Int32 {
        let mapped: Result<(tool: String, arguments: [String: JSONValue]), CLIUsageError>

        switch command {
        case "status":
            mapped = .success(("get_app_state", [:]))
        case "now-playing", "nowplaying":
            mapped = .success(("get_now_playing", [:]))
        case "tabs":
            mapped = .success(("list_tabs", [:]))
        case "play":
            mapped = .success(("playback_control", ["action": .string("play")]))
        case "pause":
            mapped = .success(("playback_control", ["action": .string("pause")]))
        case "toggle":
            mapped = .success(("playback_control", ["action": .string("toggle_play_pause")]))
        case "mute":
            mapped = .success(("playback_control", ["action": .string("mute")]))
        case "unmute":
            mapped = .success(("playback_control", ["action": .string("unmute")]))
        case "seek":
            if let first = args.first {
                if (first.hasPrefix("+") || first.hasPrefix("-")), let delta = Double(first), delta.isFinite {
                    mapped = .success(("seek_playback", ["delta_seconds": .double(delta)]))
                } else if let sec = Double(first), sec.isFinite, sec >= 0 {
                    mapped = .success(("seek_playback", ["seconds": .double(sec)]))
                } else {
                    mapped = .failure(CLIUsageError("Usage: glassgrid seek <seconds|+delta|-delta>"))
                }
            } else {
                mapped = .failure(CLIUsageError("Usage: glassgrid seek <seconds|+delta|-delta>"))
            }
        case "speed":
            if let first = args.first, let rate = Double(first), rate.isFinite {
                mapped = .success(("set_playback_speed", ["rate": .double(rate)]))
            } else {
                mapped = .failure(CLIUsageError("Usage: glassgrid speed <0.25..4.0>"))
            }
        case "search":
            let query = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                mapped = .failure(CLIUsageError("Usage: glassgrid search <query>"))
            } else {
                mapped = .success(("search_youtube", ["query": .string(query), "new_tab": .bool(true)]))
            }
        case "open":
            if let url = args.first {
                mapped = .success(("open_url", ["url": .string(url), "new_tab": .bool(true)]))
            } else {
                mapped = .failure(CLIUsageError("Usage: glassgrid open <https-url>"))
            }
        case "service":
            if let id = args.first {
                mapped = .success(("open_service", ["service_id": .string(id.lowercased()), "new_tab": .bool(true)]))
            } else {
                mapped = .failure(CLIUsageError("Usage: glassgrid service <service-id>"))
            }
        case "multiview":
            let sub = (args.first ?? "toggle").lowercased()
            switch sub {
            case "enter", "exit", "toggle", "solo", "exit_solo", "cycle_layout", "mute_all":
                mapped = .success(("multiview_control", ["action": .string(sub)]))
            case "layout":
                let mode = args.dropFirst().first?.lowercased() ?? "auto"
                mapped = .success(("multiview_control", ["action": .string("set_layout"), "layout": .string(mode)]))
            case "audio":
                if let slotStr = args.dropFirst().first, let slot = Int(slotStr) {
                    mapped = .success(("multiview_control", ["action": .string("focus_audio"), "slot": .int(slot)]))
                } else {
                    mapped = .failure(CLIUsageError("Usage: glassgrid multiview audio <1..4>"))
                }
            case "add":
                if let target = args.dropFirst().first {
                    let lowerTarget = target.lowercased()
                    if lowerTarget.hasPrefix("http://") || lowerTarget.hasPrefix("https://") {
                        mapped = .success(("multiview_manage_tile", ["action": .string("add"), "url": .string(target)]))
                    } else {
                        mapped = .success(("multiview_manage_tile", ["action": .string("add"), "service_id": .string(lowerTarget)]))
                    }
                } else {
                    mapped = .failure(CLIUsageError("Usage: glassgrid multiview add <service-id|https-url>"))
                }
            case "remove":
                if let slotStr = args.dropFirst().first, let slot = Int(slotStr) {
                    mapped = .success(("multiview_manage_tile", ["action": .string("remove"), "slot": .int(slot)]))
                } else {
                    mapped = .failure(CLIUsageError("Usage: glassgrid multiview remove <1..4>"))
                }
            default:
                mapped = .failure(CLIUsageError("Unsupported multiview subcommand '\(sub)'."))
            }
        case "preset":
            let name = args.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                mapped = .failure(CLIUsageError("Usage: glassgrid preset <name>"))
            } else {
                mapped = .success(("launch_multiview_preset", ["name": .string(name)]))
            }
        case "mini-player":
            let sub = (args.first ?? "toggle").lowercased()
            if ["compact", "standard", "large"].contains(sub) {
                mapped = .success(("mini_player_control", ["size_preset": .string(sub)]))
            } else {
                mapped = .success(("mini_player_control", ["action": .string(sub)]))
            }
        case "focus-mode":
            let arg = args.first?.lowercased()
            var toolArgs: [String: JSONValue] = [:]
            if arg == "on" || arg == "true" {
                toolArgs["enabled"] = .bool(true)
            } else if arg == "off" || arg == "false" {
                toolArgs["enabled"] = .bool(false)
            }
            mapped = .success(("set_focus_mode", toolArgs))
        case "appearance":
            let mode = (args.first ?? "toggle").lowercased()
            mapped = .success(("set_appearance", ["mode": .string(mode)]))
        case "sleep-timer":
            let opt = (args.first ?? "30m").lowercased()
            mapped = .success(("set_sleep_timer", ["option": .string(opt)]))
        default:
            mapped = .failure(CLIUsageError("Unknown command '\(command)'. Run 'glassgrid --help' for usage."))
        }

        switch mapped {
        case .failure(let usageError):
            fputs("Error: \(usageError.message)\n", stderr)
            return 2
        case .success(let (tool, arguments)):
            let req = AgentIPCRequest(
                kind: .toolCall(toolName: tool, arguments: arguments, source: .cli, clientName: "glassgrid-cli")
            )
            switch client.send(req) {
            case .failure(let error):
                if jsonOutput {
                    print(AgentCommandOutcome.failure(code: "client_error", message: error.message).toJSONValue().encodedString(prettyPrinted: true))
                } else {
                    fputs("Error: \(error.message)\n", stderr)
                }
                return 1
            case .success(let response):
                switch response.kind {
                case .commandOutcome(let outcome):
                    if jsonOutput {
                        print(outcome.toJSONValue().encodedString(prettyPrinted: true))
                    } else if outcome.ok {
                        print(outcome.message)
                    } else {
                        fputs("Error (\(outcome.errorCode ?? "failed")): \(outcome.message)\n", stderr)
                    }
                    return outcome.ok ? 0 : 1
                case .error(let code, let message):
                    if jsonOutput {
                        print(AgentCommandOutcome.failure(code: code, message: message).toJSONValue().encodedString(prettyPrinted: true))
                    } else {
                        fputs("Error (\(code)): \(message)\n", stderr)
                    }
                    return 1
                default:
                    fputs("Error: Unexpected IPC response.\n", stderr)
                    return 1
                }
            }
        }
    }

    private static func printUsage() {
        print("""
        GlassGrid You CLI & MCP Server

        USAGE:
          glassgrid mcp [--no-launch]              Run Model Context Protocol server over stdio
          glassgrid <command> [args] [--json]      Execute an automation command

        COMMANDS:
          status                                   Show window, appearance, Multiview, and audio status
          now-playing                              Show current video, chapters, and description
          tabs                                     List open tabs across windows
          play | pause | toggle | mute | unmute    Control playback
          seek <seconds|+delta|-delta>             Seek active video
          speed <0.25..4.0>                        Set playback speed
          search <query>                           Search YouTube
          open <https-url>                         Open validated HTTPS URL
          service <id>                             Open streaming service (youtube, yttv, twitch, primevideo, crunchyroll, ...)
          multiview <enter|exit|toggle|layout|audio|solo|add|remove>
          preset <name>                            Launch saved Multiview preset
          mini-player <enter|exit|toggle|compact|standard|large>  Control floating Mini-Player or grid size
          focus-mode [on|off|toggle]               Control Focus Mode
          appearance <system|light|dark|toggle>    Set Day / Night appearance
          sleep-timer <15m|30m|45m|60m|end_of_video|off>

        OPTIONS:
          --json                                   Print structured JSON output
          --no-launch                              Do not auto-launch GlassGrid You if closed
          -h, --help                               Show this help
        """)
    }
}
