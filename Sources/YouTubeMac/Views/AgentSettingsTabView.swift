import AppKit
import SwiftUI
import YouTubeMacCore

/// Native macOS Settings tab configuring AI Agent control (Claude, Gemini, Grok, Antigravity, CLI, Siri/Shortcuts),
/// permission tiers, opt-in local Streamable HTTP MCP, one-click client setup, and live activity logs.
struct AgentSettingsTabView: View {
    @Bindable var coordinator: AppCoordinator

    @State private var clientStatuses: [MCPClientKind: MCPClientInstallStatus] = [:]
    @State private var selectedHTTPClient: MCPClientKind = .claudeCode
    @State private var httpPortText: String = ""
    @State private var revealToken: Bool = false
    @State private var showRotateConfirm: Bool = false
    @State private var feedbackMessage: String?
    @State private var feedbackIsError: Bool = false
    @State private var feedbackClearTask: Task<Void, Never>?

    private var bridge: AgentBridgeController {
        coordinator.agentBridge
    }

    var body: some View {
        @Bindable var settings = coordinator.settings

        Form {
            controlSection(settings: settings)
            mcpClientsSection
            httpServerSection(settings: settings)
            siriAndShortcutsSection
            activityLogSection
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
        .onAppear {
            httpPortText = String(coordinator.settings.agentHTTPPort)
            refreshAllClientStatuses()
        }
        .alert("Rotate Local HTTP Bearer Token?", isPresented: $showRotateConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Rotate Token", role: .destructive) {
                _ = bridge.rotateHTTPToken()
                showFeedback("Generated a new 256-bit Bearer token. Update any HTTP MCP configs.", isError: false)
            }
        } message: {
            Text("Existing HTTP MCP clients using the previous token will immediately receive 401 Unauthorized until updated.")
        }
    }

    // MARK: - Section 1: Master Control & Permissions

    @ViewBuilder
    private func controlSection(settings: AppSettings) -> some View {
        @Bindable var bindableSettings = settings
        Section("Control & Permissions") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Toggle("Enable AI Agent & Assistant Control", isOn: $bindableSettings.agentControlEnabled)
                    Spacer()
                    socketStatusBadge
                }
                Text("Allow Claude, Gemini, Grok, Antigravity, Siri, Shortcuts, and local CLI tools to inspect and control GlassGrid You.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Picker("Permission Level", selection: $bindableSettings.agentPermissionLevel) {
                    ForEach(AgentPermissionLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .disabled(!settings.agentControlEnabled)

                Text(settings.agentPermissionLevel.subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)

                Text("Always blocked: cookies, Google/SSO logins, arbitrary JavaScript, and site-data wipes.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textMuted)
            }

            Toggle("Show HUD toast on AI actions", isOn: $bindableSettings.agentShowHUDToasts)
                .disabled(!settings.agentControlEnabled)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Toggle("Allow glassgridyou://action/... URL triggers", isOn: $bindableSettings.allowURLSchemeActions)
                    .disabled(!settings.agentControlEnabled)
                Text("Opt-in for Raycast or launcher scripts. Strictly limited to safe playback & catalog actions (blocked inside WebKit pages).")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var socketStatusBadge: some View {
        let (text, color): (String, Color) = {
            if !coordinator.settings.agentControlEnabled {
                return ("Off", AppleTheme.textSecondary)
            }
            switch bridge.unixSocketStatus {
            case .listening:
                return ("Socket Ready", AppleTheme.positive)
            case .anotherInstanceActive:
                return ("Another Window Active", AppleTheme.warning)
            case .failed:
                return ("Socket Error", AppleTheme.accentText)
            case .stopped:
                return ("Starting…", AppleTheme.textSecondary)
            }
        }()
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(AppFont.caption)
                .foregroundStyle(AppleTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Automation socket status: \(text)")
    }

    // MARK: - Section 2: MCP Clients (stdio)

    @ViewBuilder
    private var mcpClientsSection: some View {
        let binaryPath = MCPClientInstaller.resolvedCLIBinaryPath()
        Section("MCP Clients (Recommended · Local stdio)") {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.md) {
                    Text("Bundled Server")
                        .font(AppFont.subhead(weight: .medium))
                    Spacer()
                    Text(binaryPath)
                        .font(AppFont.mono(11))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Copy Path") {
                        copyToPasteboard(binaryPath)
                        showFeedback("Copied glassgrid binary path.", isError: false)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                if !MCPClientInstaller.isRunningFromApplicationsBundle {
                    Text("Tip: Install GlassGrid You.app into /Applications so client configs point to a stable path.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.warning)
                } else {
                    Text("Uses owner-only Unix socket IPC with zero tokens stored in client config files.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
            }

            ForEach(MCPClientKind.allCases) { client in
                mcpClientRow(client: client, binaryPath: binaryPath)
            }

            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(feedbackIsError ? AppleTheme.accentText : AppleTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func mcpClientRow(client: MCPClientKind, binaryPath: String) -> some View {
        let status = clientStatuses[client] ?? .notConfigured
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(client.displayName)
                            .font(AppFont.body)
                        clientStatusPill(status)
                    }
                    Text("~/\(client.defaultRelativeConfigPath) (\(client.configFormatTitle))")
                        .font(AppFont.mono(10))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if let cliSnippet = MCPClientConfigMerger.generateCLISnippet(
                    for: client,
                    mode: .stdio,
                    binaryPath: binaryPath,
                    httpPort: coordinator.settings.agentHTTPPort,
                    bearerToken: bridge.currentHTTPToken
                ) {
                    Button("CLI") {
                        copyToPasteboard(cliSnippet)
                        showFeedback("Copied \(client.displayName) CLI install command.", isError: false)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }

                Button("Copy") {
                    let snippet = MCPClientConfigMerger.generateSnippet(
                        for: client,
                        mode: .stdio,
                        binaryPath: binaryPath,
                        httpPort: coordinator.settings.agentHTTPPort,
                        bearerToken: bridge.currentHTTPToken
                    )
                    copyToPasteboard(snippet)
                    showFeedback("Copied \(client.displayName) \(client.configFormatTitle) config.", isError: false)
                }
                .controlSize(.small)
                .fixedSize()

                switch status {
                case .installed:
                    Button("Remove") {
                        switch MCPClientInstaller.remove(client: client) {
                        case .success(let msg):
                            showFeedback(msg, isError: false)
                        case .failure(let err):
                            showFeedback(err.localizedDescription, isError: true)
                        }
                        refreshAllClientStatuses()
                    }
                    .controlSize(.small)
                    .fixedSize()
                case .needsUpdate, .notConfigured, .legacyDetected, .error:
                    Button(statusLabelForInstall(status)) {
                        switch MCPClientInstaller.install(client: client) {
                        case .success(let msg):
                            showFeedback(msg, isError: false)
                        case .failure(let err):
                            showFeedback(err.localizedDescription, isError: true)
                        }
                        refreshAllClientStatuses()
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            if case .legacyDetected(let legacyPath) = status {
                Text("Legacy Antigravity file detected at \(legacyPath); Install targets ~/.gemini/config/mcp_config.json.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            } else if case .error(let detail) = status {
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.accentText)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func statusLabelForInstall(_ status: MCPClientInstallStatus) -> String {
        switch status {
        case .needsUpdate: return "Update"
        default: return "Install"
        }
    }

    @ViewBuilder
    private func clientStatusPill(_ status: MCPClientInstallStatus) -> some View {
        let (title, color): (String, Color) = {
            switch status {
            case .installed: return ("Configured", AppleTheme.positive)
            case .needsUpdate: return ("Update Needed", AppleTheme.warning)
            case .legacyDetected: return ("Legacy Config", AppleTheme.warning)
            case .error: return ("Error", AppleTheme.accentText)
            case .notConfigured: return ("Not Configured", AppleTheme.textSecondary)
            }
        }()
        Text(title)
            .font(AppFont.micro(weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: - Section 3: Opt-In Local Streamable HTTP MCP

    @ViewBuilder
    private func httpServerSection(settings: AppSettings) -> some View {
        @Bindable var bindableSettings = settings
        Section("Local Streamable HTTP MCP (Opt-In · 127.0.0.1 Only)") {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.md) {
                    Toggle("Enable Local HTTP MCP Server", isOn: $bindableSettings.agentHTTPServerEnabled)
                        .disabled(!settings.agentControlEnabled)
                    Spacer()
                    httpStatusLabel
                }
                Text("Binds strictly to 127.0.0.1/mcp with Host, Origin, and Bearer token enforcement.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
            }

            HStack(spacing: AppSpacing.md) {
                Text("Port")
                TextField("", text: $httpPortText, prompt: Text("41773"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 84)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { applyPortInput() }
                Button("Apply") {
                    applyPortInput()
                }
                .controlSize(.small)
                .fixedSize()
                Spacer()
                Text(verbatim: "http://127.0.0.1:\(settings.agentHTTPPort)/mcp")
                    .font(AppFont.mono(11))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .disabled(!settings.agentControlEnabled)

            HStack(spacing: AppSpacing.md) {
                Text("Bearer Token")
                Spacer()
                Text(revealToken ? bridge.currentHTTPToken : "••••••••••••••••••••••••••••••••")
                    .font(AppFont.mono(11))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button(revealToken ? "Hide" : "Reveal") {
                    revealToken.toggle()
                }
                .controlSize(.small)
                .fixedSize()
                Button("Copy") {
                    copyToPasteboard(bridge.currentHTTPToken)
                    showFeedback("Copied HTTP Bearer token to clipboard.", isError: false)
                }
                .controlSize(.small)
                .fixedSize()
                Button("Rotate…") {
                    showRotateConfirm = true
                }
                .controlSize(.small)
                .fixedSize()
            }

            HStack(spacing: AppSpacing.md) {
                Text("HTTP Snippet")
                Spacer()
                Picker("HTTP Client Snippet", selection: $selectedHTTPClient) {
                    ForEach(MCPClientKind.allCases) { client in
                        Text(client.displayName).tag(client)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button("Copy HTTP Snippet") {
                    let snippet = MCPClientConfigMerger.generateSnippet(
                        for: selectedHTTPClient,
                        mode: .streamableHTTP,
                        binaryPath: MCPClientInstaller.resolvedCLIBinaryPath(),
                        httpPort: coordinator.settings.agentHTTPPort,
                        bearerToken: bridge.currentHTTPToken
                    )
                    copyToPasteboard(snippet)
                    showFeedback("Copied \(selectedHTTPClient.displayName) HTTP snippet (contains Bearer token).", isError: false)
                }
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var httpStatusLabel: some View {
        let (text, color): (String, Color) = {
            if !coordinator.settings.agentControlEnabled || !coordinator.settings.agentHTTPServerEnabled {
                return ("Disabled", AppleTheme.textSecondary)
            }
            switch bridge.httpServerStatus {
            case .listening(let port):
                return ("Listening :\(port)", AppleTheme.positive)
            case .starting(let port):
                return ("Starting :\(port)…", AppleTheme.textSecondary)
            case .failed(_, let reason):
                return ("Failed: \(reason)", AppleTheme.accentText)
            case .disabled:
                return ("Disabled", AppleTheme.textSecondary)
            }
        }()
        Text(text)
            .font(AppFont.caption(tabular: true))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Section 4: Siri, Apple Intelligence & Shortcuts

    @ViewBuilder
    private var siriAndShortcutsSection: some View {
        Section("Siri, Apple Intelligence & Shortcuts") {
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Native App Intents & App Shortcuts")
                        .font(AppFont.body)
                    Text("Say \"What's playing in GlassGrid You\", \"Open YouTube TV in GlassGrid You\", or \"Toggle Mini-Player in GlassGrid You\".")
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                }
                Spacer()
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .fixedSize()
            }
        }
    }

    // MARK: - Section 5: Recent Activity

    @ViewBuilder
    private var activityLogSection: some View {
        Section {
            if bridge.activityLog.isEmpty {
                Text("No AI agent or shortcut activity yet.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppleTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.sm)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(bridge.activityLog) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                                Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(AppIconFont.sm())
                                    .foregroundStyle(entry.succeeded ? AppleTheme.positive : AppleTheme.warning)
                                    .frame(width: 16, alignment: .center)

                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(AppFont.micro(tabular: true))
                                    .foregroundStyle(AppleTheme.textSecondary)

                                Text(entry.source.badgeTitle)
                                    .font(AppFont.micro(weight: .semibold))
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, AppSpacing.xxs)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.xs))

                                Text(entry.action)
                                    .font(AppFont.mono(11))
                                    .lineLimit(1)

                                Text(entry.summary)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppleTheme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(height: 132)
            }
        } header: {
            HStack {
                Text("Recent Activity")
                Spacer()
                if !bridge.activityLog.isEmpty {
                    Button {
                        bridge.clearActivityLog()
                    } label: {
                        Text("Clear")
                            .font(AppFont.caption(weight: .medium))
                            .padding(.horizontal, AppSpacing.sm)
                            .minHitTarget(24, shape: Capsule(style: .continuous))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    private func refreshAllClientStatuses() {
        var next: [MCPClientKind: MCPClientInstallStatus] = [:]
        for client in MCPClientKind.allCases {
            next[client] = MCPClientInstaller.status(for: client)
        }
        clientStatuses = next
    }

    private func applyPortInput() {
        let trimmed = httpPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), (1024...65535).contains(parsed) else {
            httpPortText = String(coordinator.settings.agentHTTPPort)
            showFeedback("Port must be between 1024 and 65535.", isError: true)
            return
        }
        coordinator.settings.agentHTTPPort = parsed
        httpPortText = String(parsed)
        showFeedback("Updated HTTP port to \(parsed).", isError: false)
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedbackClearTask?.cancel()
        feedbackMessage = message
        feedbackIsError = isError
        feedbackClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(4000))
            guard !Task.isCancelled else { return }
            feedbackMessage = nil
        }
    }
}
