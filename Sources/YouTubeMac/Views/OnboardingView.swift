import AppKit
import SwiftUI
import YouTubeMacCore

/// IP-safe Liquid Glass gradient icon badge for a streaming service (zero scraped trademark logos).
struct StreamingServiceBadge: View {
    let service: StreamingService
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: service.accentHexStart),
                            Color(hex: service.accentHexEnd)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .strokeBorder(.white.opacity(0.24), lineWidth: 0.75)
                )

            if let monogram = service.monogram, !monogram.isEmpty, size >= 24 {
                Text(monogram)
                    .font(.system(size: monogram.count >= 3 ? size * 0.30 : size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(-0.3)
            } else {
                Image(systemName: service.symbolName)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: service.accentHexEnd).opacity(0.28), radius: 3, y: 1)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 0.84; g = 0.10; b = 0.18
        }
        self.init(red: r, green: g, blue: b)
    }
}

/// 2-Step Liquid Glass Streaming Service Onboarding Intro & Sign-In Hub.
struct StreamingOnboardingView: View {
    @Bindable var controller: AppController

    @State private var step: Int
    @State private var selectedSignInServiceID: String?
    @State private var webReloadToken: Int = 0
    @State private var freshSignInToken: Int = 0
    @State private var isSignInWebLoading: Bool = false
    @State private var currentSignInURL: URL?
    @State private var signInErrorMessage: String?
    @State private var signInCheckTask: Task<Void, Never>?
    @State private var resetTask: Task<Void, Never>?
    @State private var servicePendingReset: StreamingService?

    init(controller: AppController) {
        self.controller = controller
        _step = State(initialValue: controller.onboardingInitialStep)
        _selectedSignInServiceID = State(initialValue: controller.onboardingFocusServiceID)
    }

    private var enabledServices: [StreamingService] {
        controller.settings.enabledStreamingServices
    }

    private var activeSignInService: StreamingService {
        if let id = selectedSignInServiceID,
           let match = enabledServices.first(where: { $0.id == id }) {
            return match
        }
        return enabledServices.first ?? StreamingServiceCatalog.all[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.45)

            if step == 1 {
                serviceSelectionStep
            } else {
                signInHubStep
            }

            Divider().opacity(0.45)
            footerBar
        }
        .frame(minWidth: 680, idealWidth: 740, maxWidth: 820, minHeight: 460, idealHeight: 540, maxHeight: 620)
        .background(AppleTheme.canvasColor)
        .onAppear {
            step = controller.onboardingInitialStep
            if let focus = controller.onboardingFocusServiceID {
                selectedSignInServiceID = focus
            } else if selectedSignInServiceID == nil {
                selectedSignInServiceID = enabledServices.first?.id
            }
        }
        .onDisappear {
            signInCheckTask?.cancel()
            signInCheckTask = nil
            resetTask?.cancel()
            resetTask = nil
        }
        .confirmationDialog(
            "Reset \(servicePendingReset?.name ?? "Service") Login & Site Data?",
            isPresented: Binding(
                get: { servicePendingReset != nil },
                set: { if !$0 { servicePendingReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let service = servicePendingReset {
                Button("Reset \(service.name) Login & Data", role: .destructive) {
                    servicePendingReset = nil
                    signInErrorMessage = nil
                    signInCheckTask?.cancel()
                    resetTask?.cancel()
                    resetTask = Task { @MainActor in
                        await controller.resetStreamingServiceDataAndWait(service)
                        guard !Task.isCancelled, activeSignInService.id == service.id else { return }
                        freshSignInToken += 1
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                servicePendingReset = nil
            }
        } message: {
            if let service = servicePendingReset {
                if let ssoNote = StreamingServiceCatalog.sharedSSOWarning(for: service) {
                    Text("Clears cookies and site storage for \(service.name) only. \(ssoNote)")
                } else {
                    Text("Clears cookies and site storage for \(service.name) only without signing out of your other streaming services.")
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.24, green: 0.08, blue: 0.13),
                                Color(red: 0.84, green: 0.10, blue: 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .offset(x: 0.5)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step == 1 ? "Choose Your Streaming Services" : "Sign In to Your Services")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(
                    step == 1
                        ? "Select the services you watch—they'll appear in your Sidebar and \"Add Screen\" picker."
                        : "Sign in once and stay logged in across every tab, Multiview tile, and window."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Step \(step) of 2")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppleTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppleTheme.accent.opacity(0.14), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var serviceSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(StreamingServiceCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppleTheme.accent)
                            Text(category.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(StreamingServiceCatalog.services(in: category)) { service in
                                serviceCard(for: service)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func serviceCard(for service: StreamingService) -> some View {
        let isSelected = controller.settings.isServiceEnabled(service.id)
        let isSignedIn = controller.settings.isServiceSignedIn(service.id)

        Button {
            controller.settings.toggleStreamingService(service.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    StreamingServiceBadge(service: service, size: 30)

                    Spacer(minLength: 4)

                    if service.requiresStrictDRM {
                        Text("Safari DRM")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
                            .help("Some titles on \(service.name) enforce Safari-only FairPlay DRM; GlassGrid You includes a 1-click Open in Safari fallback.")
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? AppleTheme.accent : Color.secondary.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(service.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isSignedIn {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .help("Signed In")
                        }
                    }

                    Text(service.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: isSelected ? AppleTheme.accent.opacity(0.14) : nil,
                interactive: true
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AppleTheme.accent.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.4 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.name), \(isSelected ? "selected" : "not selected")\(isSignedIn ? ", signed in" : "")\(service.requiresStrictDRM ? ", Safari DRM supported" : "")")
    }

    private var signInHubStep: some View {
        HStack(spacing: 0) {
            // Left 220pt Service Checklist
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(enabledServices) { service in
                        let isActive = activeSignInService.id == service.id
                        let isSignedIn = controller.settings.isServiceSignedIn(service.id)

                        Button {
                            selectedSignInServiceID = service.id
                            currentSignInURL = nil
                            signInErrorMessage = nil
                            signInCheckTask?.cancel()
                        } label: {
                            HStack(spacing: 9) {
                                StreamingServiceBadge(service: service, size: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(service.name)
                                        .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(isSignedIn ? "Signed In" : "Tap to sign in")
                                        .font(.system(size: 10))
                                        .foregroundStyle(isSignedIn ? Color.green : .secondary)
                                }

                                Spacer()

                                if isSignedIn {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isActive ? AppleTheme.accent.opacity(0.16) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isActive ? AppleTheme.accent.opacity(0.45) : .clear, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
            .frame(width: 220)
            .background(Color.primary.opacity(0.025))

            Divider().opacity(0.45)

            // Right Live Embedded Sign-In WebView
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    StreamingServiceBadge(service: activeSignInService, size: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(activeSignInService.name)
                                .font(.system(size: 12.5, weight: .semibold))
                            if isSignInWebLoading {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        Text(currentSignInURL?.host ?? activeSignInService.signInURL.host ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        if signInErrorMessage != nil || currentSignInURL == nil {
                            signInErrorMessage = nil
                            freshSignInToken += 1
                        } else {
                            webReloadToken += 1
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reload Sign-In Page")

                    Button {
                        servicePendingReset = activeSignInService
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reset \(activeSignInService.name) Login & Site Data…")

                    if activeSignInService.requiresStrictDRM {
                        Button("Safari") {
                            controller.openURLInSafari(activeSignInService.homeURL)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open \(activeSignInService.name) in Safari for strict FairPlay DRM titles")
                    }

                    Button {
                        markActiveServiceSignedInAndAdvance()
                    } label: {
                        Label(
                            controller.settings.isServiceSignedIn(activeSignInService.id) ? "Signed In" : "Mark Done",
                            systemImage: "checkmark"
                        )
                        .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.settings.isServiceSignedIn(activeSignInService.id) ? .green : AppleTheme.accent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))

                Divider().opacity(0.35)

                if let signInErrorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(signInErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Retry Sign-In") {
                            self.signInErrorMessage = nil
                            freshSignInToken += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppleTheme.accent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.12))

                    Divider().opacity(0.35)
                }

                OnboardingSignInWebView(
                    service: activeSignInService,
                    reloadToken: webReloadToken,
                    freshSignInToken: freshSignInToken,
                    onURLChanged: { serviceID, newURL, didObserveAuthStep in
                        guard serviceID == activeSignInService.id else { return }
                        currentSignInURL = newURL
                        signInCheckTask?.cancel()
                        let targetService = activeSignInService
                        signInCheckTask = Task { @MainActor in
                            _ = await controller.evaluateSignInCompletion(
                                for: targetService,
                                url: newURL,
                                fromAuthFlow: didObserveAuthStep,
                                refreshIdleTabsOnNewSignIn: true
                            )
                        }
                    },
                    onLoadingChanged: { serviceID, loading in
                        guard serviceID == activeSignInService.id else { return }
                        isSignInWebLoading = loading
                    },
                    onError: { serviceID, errorMessage in
                        guard serviceID == activeSignInService.id else { return }
                        signInErrorMessage = errorMessage
                    }
                )
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            if step == 1 {
                Button("Skip for Now") {
                    controller.skipStreamingOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

                Spacer()

                Text("\(enabledServices.count) \(enabledServices.count == 1 ? "service" : "services") selected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                Button {
                    selectedSignInServiceID = enabledServices.first?.id
                    withAnimation(.easeInOut(duration: 0.16)) {
                        step = 2
                    }
                } label: {
                    Text("Continue to Sign In →")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppleTheme.accent)
                .controlSize(.large)
            } else {
                Button("← Back to Services") {
                    signInCheckTask?.cancel()
                    signInErrorMessage = nil
                    withAnimation(.easeInOut(duration: 0.16)) {
                        step = 1
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()

                Button("Sign In Later") {
                    controller.completeStreamingOnboarding()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

                Button("Finish Setup") {
                    controller.completeStreamingOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppleTheme.accent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func markActiveServiceSignedInAndAdvance() {
        let currentID = activeSignInService.id
        controller.settings.setServiceSignedIn(currentID, signedIn: true)
        if let nextUnsigned = enabledServices.first(where: { $0.id != currentID && !controller.settings.isServiceSignedIn($0.id) }) {
            signInCheckTask?.cancel()
            signInErrorMessage = nil
            selectedSignInServiceID = nextUnsigned.id
            currentSignInURL = nil
        }
    }
}

/// Crisp Liquid Glass "Add Screen" Service Picker Popover shared by MultiviewControlBar (`+ Add Screen`)
/// and quick service launch menus.
struct AddScreenServicePickerPopover: View {
    @Bindable var controller: AppController
    let targetIsMultiview: Bool
    let onDismiss: () -> Void

    @State private var customURLInput: String = ""
    @State private var showMoreServices: Bool = false

    private var enabledServices: [StreamingService] {
        controller.settings.enabledStreamingServices
    }

    private var otherServices: [StreamingService] {
        let enabledSet = Set(enabledServices.map(\.id))
        return StreamingServiceCatalog.all.filter { !enabledSet.contains($0.id) }
    }

    private var availableExistingTabs: [BrowserTab] {
        guard targetIsMultiview else { return [] }
        return controller.tabs.filter { !controller.multiviewTabIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(targetIsMultiview ? "Add Screen to Multiview" : "Open Streaming Service")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button {
                    onDismiss()
                    controller.openStreamingServicesSetup(step: 1)
                } label: {
                    Text("Manage…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppleTheme.accent)
                }
                .buttonStyle(.plain)
            }

            // User's Selected Services (1-click add/open)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 7),
                    GridItem(.flexible(), spacing: 7)
                ],
                spacing: 7
            ) {
                ForEach(enabledServices) { service in
                    Button {
                        onDismiss()
                        if targetIsMultiview {
                            controller.addStreamingServiceToMultiview(service)
                        } else {
                            controller.openStreamingService(service, inNewTab: true)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            StreamingServiceBadge(service: service, size: 22)
                            Text(service.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Open Existing Tabs (Multiview only)
            if !availableExistingTabs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Tabs")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(availableExistingTabs.prefix(4)) { tab in
                        Button {
                            onDismiss()
                            controller.addExistingTabToMultiview(id: tab.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.isCompanionTab ? "globe" : "play.rectangle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(tab.displayTitle)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Expandable More Services
            if !otherServices.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $showMoreServices) {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 6),
                                GridItem(.flexible(), spacing: 6)
                            ],
                            spacing: 6
                        ) {
                            ForEach(otherServices) { service in
                                Button {
                                    onDismiss()
                                    if targetIsMultiview {
                                        controller.addStreamingServiceToMultiview(service)
                                    } else {
                                        controller.openStreamingService(service, inNewTab: true)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        StreamingServiceBadge(service: service, size: 18)
                                        Text(service.name)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxHeight: 150)
                } label: {
                    Text("More Services (\(otherServices.count))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Inline Custom URL Input
            HStack(spacing: 6) {
                TextField("Custom HTTPS URL (e.g. espn.com)…", text: $customURLInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit {
                        submitCustomURL()
                    }
                Button("Add") {
                    submitCustomURL()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppleTheme.accent)
                .controlSize(.small)
                .disabled(customURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 316)
    }

    private func submitCustomURL() {
        let trimmed = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if controller.openCompanionTile(rawInput: trimmed) {
            customURLInput = ""
            onDismiss()
        }
    }
}
