import Foundation
import YouTubeMacCore

public enum MCPClientInstallStatus: Equatable, Sendable {
    case notConfigured
    case installed(path: String)
    case needsUpdate(path: String, detail: String)
    case legacyDetected(legacyPath: String)
    case error(String)
}

/// Safely detects, installs, updates, and removes `glassgrid` MCP entries across
/// Claude Desktop, Claude Code, Gemini CLI, Antigravity, and Grok CLI using `O_NOFOLLOW` + atomic `0600` writes.
public enum MCPClientInstaller {
    public static func resolvedCLIBinaryPath() -> String {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/glassgrid")
            .path
        if FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        if FileManager.default.isExecutableFile(atPath: MCPClientConfigMerger.defaultBinaryPath) {
            return MCPClientConfigMerger.defaultBinaryPath
        }
        return bundled
    }

    public static var isRunningFromApplicationsBundle: Bool {
        Bundle.main.bundleURL.path == "/Applications/GlassGrid You.app"
            || FileManager.default.isExecutableFile(atPath: MCPClientConfigMerger.defaultBinaryPath)
    }

    public static func status(for client: MCPClientKind, homeDirectory: String = NSHomeDirectory()) -> MCPClientInstallStatus {
        let binaryPath = resolvedCLIBinaryPath()
        let targetPath = client.resolvedConfigPath(homeDirectory: homeDirectory)
        let targetURL = URL(fileURLWithPath: targetPath)

        do {
            if let (data, _) = try AgentSecureFileIO.readFileNoFollow(at: targetURL) {
                if client == .grokCLI {
                    guard let text = String(data: data, encoding: .utf8) else {
                        return .error("Config is not valid UTF-8.")
                    }
                    let check = MCPClientConfigMerger.inspectTOMLServerConfigured(existing: text, expectedBinaryPath: binaryPath)
                    if !check.present {
                        return .notConfigured
                    }
                    return check.matchesBinary
                        ? .installed(path: targetPath)
                        : .needsUpdate(path: targetPath, detail: "Points to an older binary path.")
                } else {
                    if let entry = MCPClientConfigMerger.inspectJSONServer(existing: data) {
                        let cmd = entry["command"] as? String
                        let args = entry["args"] as? [String]
                        if cmd == binaryPath && args == ["mcp"] {
                            return .installed(path: targetPath)
                        }
                        return .needsUpdate(path: targetPath, detail: "Points to another binary or HTTP endpoint.")
                    }
                    return .notConfigured
                }
            }
        } catch {
            return .error(error.localizedDescription)
        }

        if let legacyPath = client.resolvedLegacyConfigPath(homeDirectory: homeDirectory),
           FileManager.default.fileExists(atPath: legacyPath) {
            return .legacyDetected(legacyPath: legacyPath)
        }

        return .notConfigured
    }

    public static func install(
        client: MCPClientKind,
        homeDirectory: String = NSHomeDirectory()
    ) -> Result<String, Error> {
        let binaryPath = resolvedCLIBinaryPath()
        let targetURL = URL(fileURLWithPath: client.resolvedConfigPath(homeDirectory: homeDirectory))
        let backupURL = URL(fileURLWithPath: targetURL.path + ".glassgrid-backup")

        do {
            let existing = try AgentSecureFileIO.readFileNoFollow(at: targetURL)
            let targetMode: mode_t = existing.map { min($0.mode, 0o600) } ?? 0o600

            let nextData: Data
            if client == .grokCLI {
                let existingString: String?
                if let data = existing?.data {
                    guard let s = String(data: data, encoding: .utf8) else {
                        throw MCPConfigMergeError.invalidTOML("non-UTF-8 file")
                    }
                    existingString = s
                } else {
                    existingString = nil
                }
                let merged = try MCPClientConfigMerger.mergeTOMLConfig(
                    existing: existingString,
                    mode: .stdio,
                    binaryPath: binaryPath
                )
                nextData = Data(merged.utf8)
            } else {
                let serverObj = MCPClientConfigMerger.stdioServerObject(binaryPath: binaryPath)
                nextData = try MCPClientConfigMerger.mergeJSONConfig(
                    existing: existing?.data,
                    serverObject: serverObj
                )
            }

            try AgentSecureFileIO.writeAtomicSecureFile(
                data: nextData,
                to: targetURL,
                mode: targetMode,
                backupURL: existing != nil ? backupURL : nil,
                existingDataForBackup: existing?.data
            )
            return .success("Configured \(client.displayName) at \(targetURL.path)")
        } catch let mergeErr as MCPConfigMergeError {
            return .failure(NSError(domain: "MCPClientInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: mergeErr.message]))
        } catch {
            return .failure(error)
        }
    }

    public static func remove(
        client: MCPClientKind,
        homeDirectory: String = NSHomeDirectory()
    ) -> Result<String, Error> {
        let targetURL = URL(fileURLWithPath: client.resolvedConfigPath(homeDirectory: homeDirectory))
        let backupURL = URL(fileURLWithPath: targetURL.path + ".glassgrid-backup")

        do {
            guard let existing = try AgentSecureFileIO.readFileNoFollow(at: targetURL) else {
                return .success("No config file found for \(client.displayName).")
            }
            let targetMode = min(existing.mode, 0o600)
            let nextData: Data
            if client == .grokCLI {
                guard let s = String(data: existing.data, encoding: .utf8) else {
                    throw MCPConfigMergeError.invalidTOML("non-UTF-8 file")
                }
                let updated = try MCPClientConfigMerger.removeTOMLConfig(existing: s)
                nextData = Data(updated.utf8)
            } else {
                nextData = try MCPClientConfigMerger.removeJSONConfig(existing: existing.data)
            }

            try AgentSecureFileIO.writeAtomicSecureFile(
                data: nextData,
                to: targetURL,
                mode: targetMode,
                backupURL: backupURL,
                existingDataForBackup: existing.data
            )
            return .success("Removed GlassGrid You from \(client.displayName).")
        } catch let mergeErr as MCPConfigMergeError {
            return .failure(NSError(domain: "MCPClientInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: mergeErr.message]))
        } catch {
            return .failure(error)
        }
    }
}
