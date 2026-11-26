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
                    .font(monogram.count >= 3 ? AppFont.micro(weight: .bold) : AppFont.caption(weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(monogram.count >= 3 ? -0.2 : 0)
            } else {
                Image(systemName: service.symbolName)
                    .font(size >= 24 ? AppIconFont.md(weight: .semibold) : AppIconFont.xs(weight: .semibold))
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
        HStack(spacing: AppSpacing.lg) {
            BrandMarkBadge(size: 30, cornerRadius: AppRadius.md)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(step == 1 ? "Choose Your Streaming Services" : "Sign In to Your Services")
                    .font(AppFont.subhead(weight: .semibold))
                Text(
                    step == 1
                        ? "Select the services you watch—they'll appear in your Sidebar and \"Add Screen\" picker."
                        : "Sign in once and stay logged in across every tab, Multiview tile, and window."
                )
                .font(AppFont.caption)
                .foregroundStyle(AppleTheme.textSecondary)
            }

            Spacer()

            Text("Step \(step) of 2")
                .font(AppFont.caption(weight: .semibold, tabular: true))
                .foregroundStyle(AppleTheme.accentText)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppleTheme.accentText.opacity(0.14), in: Capsule(style: .continuous))
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.vertical, AppSpacing.lg)
    }

    private var serviceSelectionStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                ForEach(StreamingServiceCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: category.systemImage)
                                .font(AppIconFont.sm(weight: .semibold))
                                .foregroundStyle(AppleTheme.accentText)
                            Text(category.title)
                                .font(AppFont.callout(weight: .semibold))
                                .foregroundStyle(AppleTheme.textSecondary)
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: AppSpacing.md),
                                GridItem(.flexible(), spacing: AppSpacing.md),
                                GridItem(.flexible(), spacing: AppSpacing.md)
                            ],
                            spacing: AppSpacing.md
                        ) {
                            ForEach(StreamingServiceCatalog.services(in: category)) { service in
                                serviceCard(for: service)
                            }
                        }
                    }
                }
            }
            .padding(AppSpacing.xxl)
        }
    }

    @ViewBuilder
    private func serviceCard(for service: StreamingService) -> some View {
        let isSelected = controller.settings.isServiceEnabled(service.id)
        let isSignedIn = controller.settings.isServiceSignedIn(service.id)

        Button {
            controller.settings.toggleStreamingService(service.id)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    StreamingServiceBadge(service: service, size: 30)

                    Spacer(minLength: AppSpacing.xs)

                    if service.requiresStrictDRM {
                        Text("Safari DRM")
                            .font(AppFont.micro(weight: .semibold))
                            .foregroundStyle(AppleTheme.textSecondary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
                            .help("Some titles on \(service.name) enforce Safari-only FairPlay DRM; GlassGrid You includes a 1-click Open in Safari fallback.")
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(AppIconFont.nav(weight: .semibold))
                        .foregroundStyle(isSelected ? AppleTheme.accentText : AppleTheme.textMuted)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(service.name)
                            .font(AppFont.body(weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isSignedIn {
                            Circle()
                                .fill(AppleTheme.positive)
                                .frame(width: 6, height: 6)
                                .help("Signed In")
                        }
                    }

                    Text(service.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppleTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appleGlass(
                in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous),
                tint: isSelected ? AppleTheme.accentText.opacity(0.14) : nil,
                interactive: true
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? AppleTheme.accentText.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.4 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(service.name), \(isSelected ? "selected" : "not selected")\(isSignedIn ? ", signed in" : "")\(service.requiresStrictDRM ? ", Safari DRM supported" : "")")
    }

    private var signInHubStep: some View {
        HStack(spacing: 0) {
            // Left 220pt Service Checklist
            ScrollView {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(enabledServices) { service in
                        let isActive = activeSignInService.id == service.id
                        let isSignedIn = controller.settings.isServiceSignedIn(service.id)

                        Button {
                            selectedSignInServiceID = service.id
                            currentSignInURL = nil
                            signInErrorMessage = nil
                            signInCheckTask?.cancel()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                StreamingServiceBadge(service: service, size: 28)

                                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                    Text(service.name)
                                        .font(AppFont.callout(weight: isActive ? .semibold : .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(isSignedIn ? "Signed In" : "Tap to sign in")
                                        .font(AppFont.micro)
                                        .foregroundStyle(isSignedIn ? AppleTheme.positive : AppleTheme.textSecondary)
                                }

                                Spacer()

                                if isSignedIn {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(AppIconFont.toolbar())
                                        .foregroundStyle(AppleTheme.positive)
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                    .fill(isActive ? AppleTheme.accentText.opacity(0.14) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                    .strokeBorder(isActive ? AppleTheme.accentText.opacity(0.45) : .clear, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.md)
            }
            .frame(width: 220)
            .background(Color.primary.opacity(0.025))

            Divider().opacity(0.45)

            // Right Live Embedded Sign-In WebView
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.md) {
                    StreamingServiceBadge(service: activeSignInService, size: 22)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.sm) {
                            Text(activeSignInService.name)
                                .font(AppFont.body(weight: .semibold))
                            if isSignInWebLoading {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        Text(currentSignInURL?.host ?? activeSignInService.signInURL.host ?? "")
                            .font(AppFont.micro)
                            .foregroundStyle(AppleTheme.textSecondary)
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
                            .font(AppIconFont.md(weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Reload Sign-In Page")

                    Button {
                        servicePendingReset = activeSignInService
                    } label: {
                        Image(systemName: "trash")
                            .font(AppIconFont.md(weight: .medium))
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
                        .font(AppFont.caption(weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.settings.isServiceSignedIn(activeSignInService.id) ? AppleTheme.positive : AppleTheme.accentFill)
                    .controlSize(.small)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .background(Color.primary.opacity(0.03))

                Divider().opacity(0.35)

                if let signInErrorMessage {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(AppIconFont.md(weight: .semibold))
                            .foregroundStyle(AppleTheme.warning)
                        Text(signInErrorMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: AppSpacing.md)
                        Button("Retry Sign-In") {
                            self.signInErrorMessage = nil
                            freshSignInToken += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppleTheme.accentFill)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppleTheme.warning.opacity(0.12))

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
        HStack(spacing: AppSpacing.md) {
            if step == 1 {
                Button {
                    controller.skipStreamingOnboarding()
                } label: {
                    Text("Skip for Now")
                        .font(AppFont.callout(weight: .medium))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(enabledServices.count) \(enabledServices.count == 1 ? "service" : "services") selected")
                    .font(AppFont.caption(tabular: true))
                    .foregroundStyle(AppleTheme.textSecondary)

                Button {
                    selectedSignInServiceID = enabledServices.first?.id
                    withAnimation(.easeInOut(duration: 0.16)) {
                        step = 2
                    }
                } label: {
                    Text("Continue to Sign In →")
                        .font(AppFont.callout(weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppleTheme.accentFill)
                .controlSize(.large)
            } else {
                Button {
                    signInCheckTask?.cancel()
                    signInErrorMessage = nil
                    withAnimation(.easeInOut(duration: 0.16)) {
                        step = 1
                    }
                } label: {
                    Text("← Back to Services")
                        .font(AppFont.callout(weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    controller.completeStreamingOnboarding()
                } label: {
                    Text("Sign In Later")
                        .font(AppFont.callout(weight: .medium))
                        .foregroundStyle(AppleTheme.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    controller.completeStreamingOnboarding()
                } label: {
                    Text("Finish Setup")
                        .font(AppFont.callout(weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppleTheme.accentFill)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.vertical, AppSpacing.lg)
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

/// Crisp Liquid Glass unified `+` picker shared by the header `+`, TabStrip `+`, and Multiview `+ Add Screen`.
struct AddScreenServicePickerPopover: View {
    @Bindable var controller: AppController
    let onDismiss: () -> Void

    @State private var selectedMode: GridPickerTargetMode
    @State private var searchQuery: String = ""
    @State private var clipboardURL: URL? = nil
    @State private var showAllPinned: Bool = false
    @State private var customURLInput: String = ""
    @State private var showMoreServices: Bool = false

    init(
        controller: AppController,
        initialMode: GridPickerTargetMode = .addToGrid,
        onDismiss: @escaping () -> Void
    ) {
        self.controller = controller
        self.onDismiss = onDismiss
        _selectedMode = State(initialValue: initialMode)
    }

    init(
        controller: AppController,
        targetIsMultiview: Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.init(
            controller: controller,
            initialMode: targetIsMultiview ? .addToGrid : .newTab,
            onDismiss: onDismiss
        )
    }

    private var isGridFull: Bool {
        controller.isMultiviewActive && !controller.canAddMultiviewTile
    }

    private var isGridBlocked: Bool {
        controller.hasLiveFullscreenTab || isGridFull
    }

    private var effectiveAddToGrid: Bool {
        selectedMode == .addToGrid && !isGridBlocked
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        !trimmedSearchQuery.isEmpty
    }

    private var enabledServices: [StreamingService] {
        controller.settings.enabledStreamingServices
    }

    private var filteredEnabledServices: [StreamingService] {
        enabledServices.filter { serviceMatchesFilter($0) }
    }

    private var filteredOtherServices: [StreamingService] {
        let enabledSet = Set(enabledServices.map(\.id))
        return StreamingServiceCatalog.all.filter { service in
            !enabledSet.contains(service.id) && serviceMatchesFilter(service)
        }
    }

    private var filteredCompanionSites: [CompanionQuickSite] {
        CompanionQuickSite.pickerCompanionSites.filter { site in
            matchesFilter(site.name, site.subtitle, site.urlString)
        }
    }

    private var filteredPresets: [MultiviewPreset] {
        controller.settings.savedMultiviewPresets.filter { preset in
            matchesFilter(preset.name)
        }
    }

    private var filteredAvailableTabs: [BrowserTab] {
        guard selectedMode == .addToGrid && !isGridBlocked else { return [] }
        return controller.tabs.filter { tab in
            !controller.multiviewTabIDs.contains(tab.id)
                && matchesFilter(tab.displayTitle, tab.url.absoluteString)
        }
    }

    private var filteredPinnedItems: [PinnedItem] {
        controller.settings.pinnedItems.filter { item in
            matchesFilter(item.title, item.urlString)
        }
    }

    private var showYouTubeHomeQuickStart: Bool {
        matchesFilter("YouTube Home", "youtube", "home", "new tab")
    }

    private var filteredClipboardURL: URL? {
        guard let clipboardURL else { return nil }
        guard matchesFilter("Open Copied URL", "clipboard", clipboardURL.absoluteString, clipboardURL.host) else {
            return nil
        }
        return clipboardURL
    }

    private var hasAnyCatalogMatches: Bool {
        showYouTubeHomeQuickStart
            || filteredClipboardURL != nil
            || !filteredEnabledServices.isEmpty
            || !filteredOtherServices.isEmpty
            || !filteredCompanionSites.isEmpty
            || !filteredPresets.isEmpty
            || !filteredAvailableTabs.isEmpty
            || !filteredPinnedItems.isEmpty
    }

    private var twoColumnGrid: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppSpacing.sm),
            GridItem(.flexible(), spacing: AppSpacing.sm)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stickyHeader
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if showYouTubeHomeQuickStart || filteredClipboardURL != nil {
                        quickStartSection
                    }

                    if !filteredEnabledServices.isEmpty {
                        sectionBlock(title: "Streaming Services") {
                            LazyVGrid(columns: twoColumnGrid, spacing: AppSpacing.sm) {
                                ForEach(filteredEnabledServices) { service in
                                    serviceChip(for: service)
                                }
                            }
                        }
                    }

                    if !filteredOtherServices.isEmpty {
                        moreServicesSection
                    }

                    if !filteredCompanionSites.isEmpty {
                        sectionBlock(title: "Sports, Fantasy & Markets") {
                            LazyVGrid(columns: twoColumnGrid, spacing: AppSpacing.sm) {
                                ForEach(filteredCompanionSites) { site in
                                    companionSiteChip(for: site)
                                }
                            }
                        }
                    }

                    if !filteredPresets.isEmpty {
                        presetsSection
                    }

                    if !filteredAvailableTabs.isEmpty {
                        openTabsSection
                    }

                    if !filteredPinnedItems.isEmpty {
                        pinnedItemsSection
                    }

                    if isFiltering && !hasAnyCatalogMatches {
                        Text("No matching services, sites, presets, or pins.")
                            .font(AppFont.callout)
                            .foregroundStyle(AppleTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, AppSpacing.xl)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
            .frame(maxHeight: 440)

            Divider()

            stickyFooter
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
        }
        .frame(width: 340)
        .onAppear {
            loadClipboardURLOnce()
        }
    }

    // MARK: - Sticky Header & Footer

    @ViewBuilder
    private var stickyHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                modeSegmentedControl

                Spacer(minLength: AppSpacing.xs)

                Button {
                    onDismiss()
                    controller.openStreamingServicesSetup(step: 1)
                } label: {
                    Text("Manage…")
                        .font(AppFont.caption(weight: .medium))
                        .foregroundStyle(AppleTheme.accentText)
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if selectedMode == .addToGrid && isGridBlocked {
                statusBanner
            }

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(AppIconFont.sm())
                    .foregroundStyle(AppleTheme.textSecondary)

                TextField("Filter services, sites, presets…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppFont.callout)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppIconFont.sm())
                            .foregroundStyle(AppleTheme.textSecondary)
                            .minHitTarget(24, shape: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear Filter")
                }
            }
            .padding(.leading, AppSpacing.md)
            .padding(.trailing, searchQuery.isEmpty ? AppSpacing.md : AppSpacing.xs)
            .frame(height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    @ViewBuilder
    private var modeSegmentedControl: some View {
        let gridTitle = controller.isMultiviewActive
            ? "Add to Grid (\(controller.multiviewTabs.count)/4)"
            : "Add to Grid"

        HStack(spacing: AppSpacing.xxs) {
            modeSegmentButton(
                title: gridTitle,
                systemImage: "square.grid.2x2",
                mode: .addToGrid
            )
            modeSegmentButton(
                title: "New Tab",
                systemImage: "plus.square",
                mode: .newTab
            )
        }
        .padding(AppSpacing.xxs)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
    }

    @ViewBuilder
    private func modeSegmentButton(title: String, systemImage: String, mode: GridPickerTargetMode) -> some View {
        let isSelected = selectedMode == mode
        Button {
            selectedMode = mode
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: systemImage)
                    .font(AppIconFont.xs(weight: .semibold))
                Text(title)
                    .font(AppFont.caption(weight: isSelected ? .semibold : .medium, tabular: true))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppleTheme.accentText : AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? AppleTheme.accentText.opacity(0.14) : Color.clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusBanner: some View {
        let message = controller.hasLiveFullscreenTab
            ? "Exit Fullscreen to Edit Grid — Opening as New Tab"
            : "Grid Full (4/4) — Opening as New Tab"
        let icon = controller.hasLiveFullscreenTab
            ? "arrow.down.right.and.arrow.up.left"
            : "square.grid.2x2"

        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppIconFont.xs(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)
            Text(message)
                .font(AppFont.caption(weight: .medium, tabular: true))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(AppleTheme.accentText.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .strokeBorder(AppleTheme.accentText.opacity(0.24), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var stickyFooter: some View {
        let trimmedInput = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInputEmpty = trimmedInput.isEmpty

        HStack(spacing: AppSpacing.sm) {
            TextField("Custom HTTPS URL (e.g. espn.com)…", text: $customURLInput)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.body)
                .onSubmit {
                    submitCustomURL()
                }

            Button {
                submitCustomURL()
            } label: {
                Text(effectiveAddToGrid ? "Add to Grid" : "Open Tab")
                    .font(AppFont.callout(weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, AppSpacing.md)
                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(isInputEmpty ? AppleTheme.accentFill.opacity(0.45) : AppleTheme.accentFill)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isInputEmpty)
        }
    }

    // MARK: - Catalog Sections

    @ViewBuilder
    private var quickStartSection: some View {
        sectionBlock(title: "Quick Start") {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if showYouTubeHomeQuickStart {
                    HStack(spacing: AppSpacing.xxs) {
                        Button {
                            onDismiss()
                            controller.openNewYouTubeTabFromPicker(addToGrid: effectiveAddToGrid)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "play.rectangle.fill")
                                    .font(AppIconFont.sm(weight: .semibold))
                                    .foregroundStyle(AppleTheme.accentText)
                                    .frame(width: 18, alignment: .center)
                                Text("YouTube Home")
                                    .font(AppFont.callout(weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: AppSpacing.xs)
                                Text("⌘T")
                                    .font(AppFont.micro(weight: .semibold))
                                    .foregroundStyle(AppleTheme.textSecondary)
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .minHitTarget(28, shape: Rectangle())
                        }
                        .buttonStyle(.plain)

                        quickSwitchButton(
                            action: {
                                onDismiss()
                                controller.openNewYouTubeTabFromPicker(addToGrid: !effectiveAddToGrid)
                            }
                        )
                    }
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }

                if let clipURL = filteredClipboardURL {
                    HStack(spacing: AppSpacing.xxs) {
                        Button {
                            onDismiss()
                            controller.openURLFromPicker(clipURL, addToGrid: effectiveAddToGrid)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(AppIconFont.sm(weight: .semibold))
                                    .foregroundStyle(AppleTheme.accentText)
                                    .frame(width: 18, alignment: .center)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Open Copied URL")
                                        .font(AppFont.callout(weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(truncatedClipboardLabel(for: clipURL))
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppleTheme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .minHitTarget(28, shape: Rectangle())
                        }
                        .buttonStyle(.plain)

                        quickSwitchButton(
                            action: {
                                onDismiss()
                                controller.openURLFromPicker(clipURL, addToGrid: !effectiveAddToGrid)
                            }
                        )
                    }
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var moreServicesSection: some View {
        let expandedBinding = Binding<Bool>(
            get: { isFiltering || showMoreServices },
            set: { newValue in
                if !isFiltering {
                    showMoreServices = newValue
                }
            }
        )

        Divider()
        DisclosureGroup(isExpanded: expandedBinding) {
            LazyVGrid(columns: twoColumnGrid, spacing: AppSpacing.sm) {
                ForEach(filteredOtherServices) { service in
                    serviceChip(for: service)
                }
            }
            .padding(.top, AppSpacing.sm)
        } label: {
            Text("More Services (\(filteredOtherServices.count))")
                .font(AppFont.caption(weight: .semibold, tabular: true))
                .foregroundStyle(AppleTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        Divider()
        sectionBlock(title: "Saved Multiview Presets") {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(filteredPresets) { preset in
                    Button {
                        onDismiss()
                        controller.launchMultiviewPreset(preset)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(AppIconFont.sm())
                                .foregroundStyle(AppleTheme.accentText)
                                .frame(width: 18, alignment: .center)
                            Text(preset.name)
                                .font(AppFont.callout(weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: AppSpacing.xs)
                            Text("\(preset.urlStrings.count)×")
                                .font(AppFont.micro(weight: .semibold, tabular: true))
                                .foregroundStyle(AppleTheme.textSecondary)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.xxs)
                                .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var openTabsSection: some View {
        Divider()
        sectionBlock(title: "Open Tabs") {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(filteredAvailableTabs.prefix(5)) { tab in
                    Button {
                        onDismiss()
                        controller.addExistingTabToMultiview(id: tab.id)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: tab.isCompanionTab ? "globe" : "play.rectangle")
                                .font(AppIconFont.sm())
                                .foregroundStyle(AppleTheme.textSecondary)
                                .frame(width: 18, alignment: .center)
                            Text(tab.displayTitle)
                                .font(AppFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.sm)
                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var pinnedItemsSection: some View {
        let visiblePins = (isFiltering || showAllPinned)
            ? filteredPinnedItems
            : Array(filteredPinnedItems.prefix(5))

        Divider()
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text("Pinned Channels & Playlists")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(AppleTheme.textSecondary)
                Spacer()
                if !isFiltering && filteredPinnedItems.count > 5 {
                    Button {
                        showAllPinned.toggle()
                    } label: {
                        Text(showAllPinned ? "Show Fewer" : "Show All (\(filteredPinnedItems.count))")
                            .font(AppFont.caption(weight: .medium, tabular: true))
                            .foregroundStyle(AppleTheme.accentText)
                            .padding(.horizontal, AppSpacing.xs)
                            .minHitTarget(24, shape: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(visiblePins) { item in
                HStack(spacing: AppSpacing.xxs) {
                    Button {
                        onDismiss()
                        controller.openPinnedItemFromPicker(item, addToGrid: effectiveAddToGrid)
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: YouTubeURLRouter.pinnedItemIcon(for: item.urlString))
                                .font(AppIconFont.sm())
                                .foregroundStyle(AppleTheme.textSecondary)
                                .frame(width: 18, alignment: .center)
                            Text(item.title)
                                .font(AppFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, AppSpacing.sm)
                        .minHitTarget(24, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    quickSwitchButton(
                        action: {
                            onDismiss()
                            controller.openPinnedItemFromPicker(item, addToGrid: !effectiveAddToGrid)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Shared Reusable Chips & Helpers

    @ViewBuilder
    private func sectionBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)
            content()
        }
    }

    @ViewBuilder
    private func serviceChip(for service: StreamingService) -> some View {
        pickerTwoColumnChip(
            primaryAction: {
                onDismiss()
                controller.openServiceFromPicker(service, addToGrid: effectiveAddToGrid)
            },
            quickSwitchAction: {
                onDismiss()
                controller.openServiceFromPicker(service, addToGrid: !effectiveAddToGrid)
            }
        ) {
            StreamingServiceBadge(service: service, size: 22)
            Text(service.name)
                .font(AppFont.callout(weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func companionSiteChip(for site: CompanionQuickSite) -> some View {
        pickerTwoColumnChip(
            primaryAction: {
                onDismiss()
                controller.openURLFromPicker(site.url, routingMode: site.routingMode, addToGrid: effectiveAddToGrid)
            },
            quickSwitchAction: {
                onDismiss()
                controller.openURLFromPicker(site.url, routingMode: site.routingMode, addToGrid: !effectiveAddToGrid)
            }
        ) {
            Image(systemName: site.systemImage)
                .font(AppIconFont.sm(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)
                .frame(width: 22, height: 22)
            Text(site.name)
                .font(AppFont.callout(weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func pickerTwoColumnChip<Label: View>(
        primaryAction: @escaping () -> Void,
        quickSwitchAction: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Button(action: primaryAction) {
                HStack(spacing: AppSpacing.sm) {
                    label()
                    Spacer(minLength: 0)
                }
                .padding(.leading, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .minHitTarget(28, shape: Rectangle())
            }
            .buttonStyle(.plain)

            quickSwitchButton(action: quickSwitchAction)
        }
        .frame(minHeight: 32)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    @ViewBuilder
    private func quickSwitchButton(action: @escaping () -> Void) -> some View {
        if !isGridBlocked {
            Button(action: action) {
                Image(systemName: effectiveAddToGrid ? "plus.square" : "square.grid.2x2")
                    .font(AppIconFont.xs(weight: .medium))
                    .foregroundStyle(AppleTheme.textSecondary)
                    .minHitTarget(24, shape: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, AppSpacing.xs)
            .help(effectiveAddToGrid ? "Open in New Tab" : "Add to Grid")
        } else {
            Spacer()
                .frame(width: AppSpacing.sm)
        }
    }

    private func serviceMatchesFilter(_ service: StreamingService) -> Bool {
        matchesFilter(service.name, service.id, service.subtitle, service.category.title)
    }

    private func matchesFilter(_ candidates: String?...) -> Bool {
        guard isFiltering else { return true }
        let query = trimmedSearchQuery
        return candidates.compactMap { $0 }.contains { candidate in
            candidate.localizedCaseInsensitiveContains(query)
        }
    }

    private func loadClipboardURLOnce() {
        guard let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !clip.isEmpty else {
            clipboardURL = nil
            return
        }
        if let ytURL = YouTubeURLRouter.extractYouTubeURLFromString(clip) {
            clipboardURL = ytURL
        } else if clip.contains("://"), let webURL = YouTubeURLRouter.resolveCompanionURL(clip) {
            clipboardURL = webURL
        } else {
            clipboardURL = nil
        }
    }

    private func truncatedClipboardLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path
        if path.isEmpty || path == "/" {
            return host
        }
        let combined = host + path
        if combined.count <= 38 {
            return combined
        }
        return String(combined.prefix(35)) + "…"
    }

    private func submitCustomURL() {
        let trimmed = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if controller.openRawInputFromPicker(trimmed, addToGrid: effectiveAddToGrid) {
            customURLInput = ""
            onDismiss()
        }
    }
}
