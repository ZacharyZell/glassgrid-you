import SwiftUI
import YouTubeMacCore

/// Display mode for `FreshnessLabelView` across the Live Companion Drawer and 30pt Ticker Bar.
enum FreshnessLabelStyle {
    case drawerInline
    case tickerProgressive
}

/// Shared freshness and provider-status helpers for Live Pulse chrome views.
enum LivePulseFreshnessHelpers {
    static func isOffline(providerStatus: [String: String]) -> Bool {
        if providerStatus["espnScoreboard"] == "Unavailable" {
            return true
        }
        return !providerStatus.isEmpty && providerStatus.values.allSatisfy { $0 == "Unavailable" }
    }

    static func hasLiveGames(in snapshot: LivePulseSnapshot) -> Bool {
        snapshot.games.contains { $0.status == .live || $0.status == .halftime }
    }

    static func providerStatusTooltip(lastUpdatedAt: Date?, providerStatus: [String: String]) -> String {
        let syncLine: String
        if let lastUpdatedAt {
            syncLine = "Last sync: \(lastUpdatedAt.formatted(date: .omitted, time: .standard))"
        } else {
            syncLine = "Last sync: Pending"
        }

        let orderedKeys: [(key: String, label: String)] = [
            ("espnScoreboard", "ESPN"),
            ("sleeper", "Sleeper"),
            ("espnFantasy", "ESPN Fantasy"),
            ("kalshi", "Kalshi"),
            ("polymarket", "Polymarket")
        ]
        let statusParts = orderedKeys.compactMap { item -> String? in
            guard let status = providerStatus[item.key], !status.isEmpty else { return nil }
            return "\(item.label): \(status)"
        }
        if statusParts.isEmpty {
            return "Refresh Live Pulse Now\n\(syncLine)"
        }
        return "Refresh Live Pulse Now\n\(syncLine)\n\(statusParts.joined(separator: " · "))"
    }
}

/// Low-power 15s-bucketed freshness indicator (zero animation timelines, static when `isFrozen` or Reduce Motion is active).
struct FreshnessLabelView: View {
    let lastUpdatedAt: Date?
    let hasLiveGames: Bool
    let isOffline: Bool
    let isFrozen: Bool
    let style: FreshnessLabelStyle

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        if isFrozen || accessibilityReduceMotion {
            content(at: Date())
        } else {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                content(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func content(at now: Date) -> some View {
        let state = LivePulseFreshnessFormatter.format(
            lastUpdatedAt: lastUpdatedAt,
            now: now,
            hasLiveGames: hasLiveGames,
            isOffline: isOffline
        )

        switch style {
        case .drawerInline:
            HStack(spacing: AppSpacing.xs) {
                if state.isLiveDot {
                    Circle()
                        .fill(AppleTheme.positive)
                        .frame(width: 5, height: 5)
                } else if state.isStale || state.isOffline {
                    Circle()
                        .fill(AppleTheme.warning)
                        .frame(width: 5, height: 5)
                }

                Text(state.label)
                    .font(AppFont.caption(
                        weight: (state.isStale || state.isOffline || state.isLiveDot) ? .semibold : .regular,
                        tabular: true
                    ))
                    .foregroundStyle(state.isStale || state.isOffline ? AppleTheme.warning : AppleTheme.textSecondary)
                    .lineLimit(1)
            }
            .fixedSize()

        case .tickerProgressive:
            let dotColor: Color = {
                if state.isOffline || state.isTickerStale {
                    return AppleTheme.warning
                }
                if state.isLiveDot || lastUpdatedAt != nil {
                    return AppleTheme.positive
                }
                return AppleTheme.textMuted.opacity(0.65)
            }()

            HStack(spacing: 3) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)

                if state.isTickerStale || state.isOffline {
                    Text(state.label)
                        .font(AppFont.caption(weight: .semibold, tabular: true))
                        .foregroundStyle(AppleTheme.warning)
                        .lineLimit(1)
                }
            }
            .fixedSize()
            .padding(.horizontal, AppSpacing.xxs)
            .help("Feed status: \(state.label)")
        }
    }
}

/// Fixed 24x24pt manual refresh button with macOS 14/15 symbol animations and 1.2s checkmark completion feedback.
struct LivePulseRefreshButton: View {
    let isRefreshing: Bool
    let lastUpdatedAt: Date?
    let lastManualRefreshCompletedAt: Date?
    let providerStatus: [String: String]
    let isEnabled: Bool
    let isFrozen: Bool
    var iconFont: Font = AppIconFont.xs(weight: .semibold)
    var checkmarkFont: Font = AppIconFont.xs(weight: .bold)
    let action: () -> Void

    @State private var showCompletedCheckmark = false
    @State private var checkmarkResetTask: Task<Void, Never>?
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showCompletedCheckmark && !isRefreshing {
                    Image(systemName: "checkmark")
                        .font(checkmarkFont)
                        .foregroundStyle(AppleTheme.positive)
                } else {
                    refreshBaseIcon
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(isHovered && !isDisabled ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(LivePulseFreshnessHelpers.providerStatusTooltip(
            lastUpdatedAt: lastUpdatedAt,
            providerStatus: providerStatus
        ))
        .onChange(of: lastManualRefreshCompletedAt) { _, completedAt in
            guard completedAt != nil else {
                checkmarkResetTask?.cancel()
                showCompletedCheckmark = false
                return
            }
            checkmarkResetTask?.cancel()
            withAnimation(.easeInOut(duration: 0.18)) {
                showCompletedCheckmark = true
            }
            checkmarkResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCompletedCheckmark = false
                }
            }
        }
        .onDisappear {
            checkmarkResetTask?.cancel()
        }
    }

    private var isDisabled: Bool {
        isFrozen || isRefreshing || !isEnabled
    }

    @ViewBuilder
    private var refreshBaseIcon: some View {
        let icon = Image(systemName: "arrow.clockwise")
            .font(iconFont)
            .foregroundStyle(
                isRefreshing
                    ? AppleTheme.accentText
                    : (isHovered && !isDisabled ? Color.primary : AppleTheme.textSecondary)
            )

        if #available(macOS 15.0, *) {
            icon.symbolEffect(.rotate, isActive: isRefreshing)
        } else {
            icon.symbolEffect(.pulse, isActive: isRefreshing)
        }
    }
}
