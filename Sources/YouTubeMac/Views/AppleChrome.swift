import AppKit
import Observation
import SwiftUI
import YouTubeMacCore

extension Notification.Name {
    static let glassGridThemeDidChange = Notification.Name("com.glassgrid.themeDidChange")
}

/// Reactive main-actor runtime holding the currently active holiday palette and freshly rebuilt immutable `NSColor`
/// tokens so SwiftUI `Color(nsColor:)` views repaint immediately without modifying individual view files.
@MainActor
@Observable
final class ThemeRuntime {
    static let shared = ThemeRuntime()

    private(set) var activePalette: HolidayThemePalette
    private(set) var accentFillNSColor: NSColor
    private(set) var accentFillHoverNSColor: NSColor
    private(set) var accentTextNSColor: NSColor
    private(set) var brandGradientStartNSColor: NSColor
    private(set) var brandGradientEndNSColor: NSColor
    private(set) var ambientGlowNSColor: NSColor

    private init(palette: HolidayThemePalette = HolidayThemeCatalog.classic) {
        self.activePalette = palette
        self.accentFillNSColor = Self.makeNSColor(hex: palette.accentFill)
        self.accentFillHoverNSColor = Self.makeNSColor(hex: palette.accentFillHover)
        self.accentTextNSColor = Self.makeAdaptiveNSColor(lightHex: palette.accentTextLight, darkHex: palette.accentTextDark)
        self.brandGradientStartNSColor = Self.makeNSColor(hex: palette.brandGradientStart)
        self.brandGradientEndNSColor = Self.makeNSColor(hex: palette.brandGradientEnd)
        self.ambientGlowNSColor = Self.makeAdaptiveNSColor(lightHex: palette.ambientGlowLight, darkHex: palette.ambientGlowDark)
    }

    func apply(palette: HolidayThemePalette) {
        guard palette != activePalette else { return }
        activePalette = palette
        accentFillNSColor = Self.makeNSColor(hex: palette.accentFill)
        accentFillHoverNSColor = Self.makeNSColor(hex: palette.accentFillHover)
        accentTextNSColor = Self.makeAdaptiveNSColor(lightHex: palette.accentTextLight, darkHex: palette.accentTextDark)
        brandGradientStartNSColor = Self.makeNSColor(hex: palette.brandGradientStart)
        brandGradientEndNSColor = Self.makeNSColor(hex: palette.brandGradientEnd)
        ambientGlowNSColor = Self.makeAdaptiveNSColor(lightHex: palette.ambientGlowLight, darkHex: palette.ambientGlowDark)
        NotificationCenter.default.post(name: .glassGridThemeDidChange, object: palette.id)
    }

    private static func makeNSColor(hex: String) -> NSColor {
        guard let (r, g, b) = DesignSystemMetrics.rgbComponents(fromHex: hex) else {
            return .systemRed
        }
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    private static func makeAdaptiveNSColor(lightHex: String, darkHex: String) -> NSColor {
        let light = makeNSColor(hex: lightHex)
        let dark = makeNSColor(hex: darkHex)
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

/// Lightweight non-blocking HUD toast payload for keyboard shortcuts and automated playback actions.
public struct HUDToast: Equatable, Sendable {
    public let id: UUID
    public let icon: String
    public let message: String

    public init(id: UUID = UUID(), icon: String, message: String) {
        self.id = id
        self.icon = icon
        self.message = message
    }
}

/// Shared Apple-inspired palette and native AppKit / Liquid Glass chrome primitives.
/// All Day/Night palette values derive from `DesignSystemMetrics` / `HolidayThemeCatalog` so WCAG 2.1 AA contrast (`>= 4.5:1`)
/// is enforced identically in runtime SwiftUI/AppKit and offline `DesignSystemTests`.
@MainActor
enum AppleTheme {
    private static func nsColor(hex: String) -> NSColor {
        guard let (r, g, b) = DesignSystemMetrics.rgbComponents(fromHex: hex) else {
            return .systemRed
        }
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
    }

    private static func adaptiveNSColor(lightHex: String, darkHex: String) -> NSColor {
        let light = nsColor(hex: lightHex)
        let dark = nsColor(hex: darkHex)
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }

    static func color(hex: String) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }

    // MARK: - Brand Accent Tokens (Split Fill vs Text for WCAG 2.1 AA)

    static var activeHolidayPalette: HolidayThemePalette {
        ThemeRuntime.shared.activePalette
    }

    /// Solid accent fill for CTA buttons and active filled badges paired with `#FFFFFF` foreground (`>= 5.19:1`).
    static var accentFillNSColor: NSColor { ThemeRuntime.shared.accentFillNSColor }
    static var accentFill: Color { Color(nsColor: accentFillNSColor) }

    /// Hover state for solid accent fills (`>= 6.26:1` with `#FFFFFF`).
    static var accentFillHover: Color { Color(nsColor: ThemeRuntime.shared.accentFillHoverNSColor) }

    /// Adaptive accent text/icon/tinted-pill accent (`>= 4.5:1` on both Day and Night glass).
    static var accentTextNSColor: NSColor { ThemeRuntime.shared.accentTextNSColor }
    static var accentText: Color { Color(nsColor: accentTextNSColor) }

    /// Compatibility aliases; prefer explicit `accentFill` (solid white-text fills) or `accentText` (foregrounds/pills).
    static var accentNSColor: NSColor { accentTextNSColor }
    static var accent: Color { accentText }

    /// Ambient radial wash color for chrome-only seasonal Liquid Glass tinting.
    static var ambientGlowNSColor: NSColor { ThemeRuntime.shared.ambientGlowNSColor }
    static var ambientGlow: Color { Color(nsColor: ambientGlowNSColor) }

    // MARK: - Accessible Semantic & Neutral Tokens

    static let textPrimaryNSColor = adaptiveNSColor(
        lightHex: "#161619",
        darkHex: "#F5F5F7"
    )
    static var textPrimary: Color { Color(nsColor: textPrimaryNSColor) }

    static let textSecondaryNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.textSecondaryLight,
        darkHex: DesignSystemMetrics.textSecondaryDark
    )
    static var textSecondary: Color { Color(nsColor: textSecondaryNSColor) }

    static let textMutedNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.textMutedLight,
        darkHex: DesignSystemMetrics.textMutedDark
    )
    static var textMuted: Color { Color(nsColor: textMutedNSColor) }

    static let positiveNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.positiveLight,
        darkHex: DesignSystemMetrics.positiveDark
    )
    static var positive: Color { Color(nsColor: positiveNSColor) }

    static let warningNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.warningLight,
        darkHex: DesignSystemMetrics.warningDark
    )
    static var warning: Color { Color(nsColor: warningNSColor) }

    static let infoNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.infoLight,
        darkHex: DesignSystemMetrics.infoDark
    )
    static var info: Color { Color(nsColor: infoNSColor) }

    static let surfaceSolidNSColor = adaptiveNSColor(
        lightHex: DesignSystemMetrics.surfaceSolidLight,
        darkHex: DesignSystemMetrics.surfaceSolidDark
    )
    static var surfaceSolid: Color { Color(nsColor: surfaceSolidNSColor) }

    static let canvasNSColor = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
            ? NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
            : .white
    }
    static var canvasColor: Color { Color(nsColor: canvasNSColor) }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: ThemeRuntime.shared.brandGradientStartNSColor),
                Color(nsColor: ThemeRuntime.shared.brandGradientEndNSColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Batches neighboring macOS 26+ Liquid Glass views into a single `GlassEffectContainer`, with clean macOS 14–15 fallback.
struct LiquidGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private func makeAppleGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint {
        glass = glass.tint(tint)
    }
    if interactive {
        glass = glass.interactive()
    }
    return glass
}
#endif

/// Accessible Liquid Glass modifier honoring `accessibilityReduceTransparency` and `colorSchemeContrast`.
private struct AppleGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(AppleTheme.surfaceSolid)
                        .overlay {
                            if let tint {
                                shape.fill(tint)
                            }
                        }
                }
                .overlay(
                    shape.strokeBorder(
                        Color.primary.opacity(colorSchemeContrast == .increased ? 0.50 : 0.20),
                        lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.85
                    )
                )
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(makeAppleGlass(tint: tint, interactive: interactive), in: shape)
                    .overlay {
                        if colorSchemeContrast == .increased {
                            shape.strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.0)
                        }
                    }
            } else {
                fallbackMaterialGlass(content: content)
            }
            #else
            fallbackMaterialGlass(content: content)
            #endif
        }
    }

    @ViewBuilder
    private func fallbackMaterialGlass(content: Content) -> some View {
        let strokeOpacity: Double = colorSchemeContrast == .increased
            ? 0.45
            : (colorScheme == .dark ? 0.16 : 0.12)
        content
            .background {
                shape.fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            shape.fill(tint)
                        }
                    }
            }
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(strokeOpacity),
                    lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.75
                )
            )
    }
}

extension View {
    /// Applies authentic macOS 26+ Liquid Glass (`.glassEffect`) with a crisp `.regularMaterial` fallback on macOS 14–15,
    /// and automatically adapts for macOS Reduce Transparency and Increase Contrast accessibility preferences.
    func appleGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AppleGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

/// Genuine AppKit `NSVisualEffectView` for authentic macOS translucent behind-window surfaces.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material {
            nsView.material = material
        }
        if nsView.blendingMode != blendingMode {
            nsView.blendingMode = blendingMode
        }
        if nsView.state != state {
            nsView.state = state
        }
    }
}

/// Dedicated macOS titlebar/panel drag surface that accepts first-click events and invokes `window?.performDrag(with:)`
/// so both the Main Window and inactive Floating Mini-Player move effortlessly even when `isMovableByWindowBackground == false`.
final class WindowDragNSView: NSView {
    var onDoubleClick: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var edgeResizeInset: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if edgeResizeInset > 0, let window {
            let winPoint = superview?.convert(point, to: nil) ?? convert(point, to: nil)
            let size = window.frame.size
            let nearHorizontalEdge = winPoint.x <= edgeResizeInset || winPoint.x >= (size.width - edgeResizeInset)
            let nearTopEdge = winPoint.y >= (size.height - edgeResizeInset)
            let nearBottomEdge = winPoint.y <= edgeResizeInset
            if nearHorizontalEdge || nearTopEdge || nearBottomEdge {
                return nil
            }
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if let onDoubleClick {
                onDoubleClick()
            } else {
                window?.performZoom(nil)
            }
            return
        }
        window?.performDrag(with: event)
        onDragEnded?()
    }
}

struct WindowDragArea: NSViewRepresentable {
    var edgeResizeInset: CGFloat = 0
    var onDoubleClick: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView(frame: .zero)
        view.edgeResizeInset = edgeResizeInset
        view.onDoubleClick = onDoubleClick
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
        nsView.edgeResizeInset = edgeResizeInset
        nsView.onDoubleClick = onDoubleClick
        nsView.onDragEnded = onDragEnded
    }
}

/// Refined Apple-style icon button designed to live cleanly inside Liquid Glass capsules and toolbars.
struct AppleIconButton: View {
    let systemImage: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    var helpText: String = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppIconFont.toolbar)
                .foregroundStyle(foregroundColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(backgroundColor)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color.primary.opacity(0.28)
        }
        if isActive {
            return AppleTheme.accentText
        }
        return isHovered ? Color.primary : Color.primary.opacity(0.80)
    }

    private var backgroundColor: Color {
        if isDisabled {
            return .clear
        }
        if isActive {
            return AppleTheme.accentText.opacity(isHovered ? 0.20 : 0.12)
        }
        return isHovered ? Color.primary.opacity(0.09) : .clear
    }
}

/// Compact Apple TV–style outlined HDR badge (`10pt` Inter) shown when a high dynamic range stream is active.
struct AppleHDRBadge: View {
    var onDarkMedia: Bool = false

    var body: some View {
        Text("HDR")
            .font(AppFont.micro(weight: .bold))
            .tracking(AppFont.tracking(for: 10))
            .foregroundStyle(onDarkMedia ? Color.white.opacity(0.92) : AppleTheme.textSecondary)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .strokeBorder(
                        onDarkMedia ? Color.white.opacity(0.42) : Color.primary.opacity(0.32),
                        lineWidth: 0.85
                    )
            )
            .help("High Dynamic Range (HDR10) Active")
    }
}

/// Compact Apple-style playback speed pill badge (`10pt` tabular Inter) shown only when playback speed differs from 1×.
struct AppleSpeedBadge: View {
    let rateText: String
    var onDarkMedia: Bool = false

    var body: some View {
        Text(rateText)
            .font(AppFont.micro(weight: .semibold, tabular: true))
            .foregroundStyle(onDarkMedia ? Color.white.opacity(0.94) : AppleTheme.accentText)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .fill(onDarkMedia ? Color.white.opacity(0.20) : AppleTheme.accentText.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous)
                    .strokeBorder(
                        onDarkMedia ? Color.white.opacity(0.36) : AppleTheme.accentText.opacity(0.35),
                        lineWidth: 0.75
                    )
            )
            .help("Playback Speed: \(rateText)")
    }
}

/// Subtle non-blocking macOS Liquid Glass HUD toast overlay.
struct AppleHUDToast: View {
    let toast: HUDToast

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: toast.icon)
                .font(AppIconFont.md(weight: .semibold))
                .foregroundStyle(AppleTheme.accentText)
            Text(toast.message)
                .font(AppFont.callout(weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.md)
        .appleGlass(in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}

/// Canonical GlassGrid You crimson Liquid Glass emblem used across Sidebar, Onboarding, and Menu Bar.
struct BrandMarkBadge: View {
    var size: CGFloat = 22
    var cornerRadius: CGFloat = AppRadius.sm
    var showRing: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppleTheme.brandGradient)
                .frame(width: size, height: size)
                .overlay {
                    if showRing {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.85)
                            .padding(max(3, size * 0.16))
                    }
                }

            Image(systemName: "play.fill")
                .font(.system(size: max(8, (size * 0.36).rounded()), weight: .black))
                .foregroundStyle(.white)
                .offset(x: 0.5)
        }
    }
}

/// Action descriptor for `GlassRecoveryCard` buttons.
struct GlassRecoveryAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

/// Shared Liquid Glass recovery & placeholder card unifying offline/error, hidden Home feed,
/// and floating mini-player placeholder surfaces with WCAG 2.1 AA contrast and consistent radii.
struct GlassRecoveryCard<ExtraContent: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var isCompactTile: Bool = false
    var messageLineLimit: Int? = nil
    let primaryAction: GlassRecoveryAction
    var secondaryActions: [GlassRecoveryAction] = []
    @ViewBuilder let extraContent: () -> ExtraContent

    var body: some View {
        VStack(spacing: isCompactTile ? AppSpacing.md : AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(AppleTheme.accentText.opacity(0.14))
                    .frame(width: isCompactTile ? 40 : 56, height: isCompactTile ? 40 : 56)
                Image(systemName: systemImage)
                    .font(isCompactTile ? AppIconFont.lg(weight: .semibold) : AppIconFont.hero(weight: .semibold))
                    .foregroundStyle(AppleTheme.accentText)
            }

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(isCompactTile ? AppFont.subhead(weight: .semibold) : AppFont.title(weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(isCompactTile ? AppFont.caption : AppFont.callout)
                    .foregroundStyle(AppleTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(messageLineLimit)
                    .frame(maxWidth: isCompactTile ? 260 : 380)
            }

            extraContent()

            LiquidGlassGroup(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    Button(action: primaryAction.action) {
                        actionLabel(primaryAction, weight: .semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, isCompactTile ? AppSpacing.lg : AppSpacing.xl)
                            .padding(.vertical, AppSpacing.sm)
                            .minHitTarget(isCompactTile ? 28 : 32, shape: Capsule(style: .continuous))
                            .background(AppleTheme.accentFill, in: Capsule(style: .continuous))
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if !isCompactTile {
                        ForEach(secondaryActions) { item in
                            Button(action: item.action) {
                                actionLabel(item, weight: .medium)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, AppSpacing.sm)
                                    .minHitTarget(32, shape: Capsule(style: .continuous))
                                    .appleGlass(in: Capsule(style: .continuous), interactive: true)
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, AppSpacing.xxs)
        }
        .padding(isCompactTile ? AppSpacing.xl : AppSpacing.xxxl)
        .appleGlass(in: RoundedRectangle(cornerRadius: isCompactTile ? AppRadius.xl : AppRadius.sheet, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: isCompactTile ? 10 : 18, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTheme.canvasColor.opacity(isCompactTile ? 0.94 : 1.0), ignoresSafeAreaEdges: [])
    }

    @ViewBuilder
    private func actionLabel(_ item: GlassRecoveryAction, weight: Font.Weight) -> some View {
        if let symbol = item.systemImage {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: symbol)
                    .font(isCompactTile ? AppIconFont.sm(weight: weight) : AppIconFont.md(weight: weight))
                Text(item.title)
                    .font(isCompactTile ? AppFont.caption(weight: weight) : AppFont.callout(weight: weight))
            }
        } else {
            Text(item.title)
                .font(isCompactTile ? AppFont.caption(weight: weight) : AppFont.callout(weight: weight))
        }
    }
}

extension GlassRecoveryCard where ExtraContent == EmptyView {
    init(
        systemImage: String,
        title: String,
        message: String,
        isCompactTile: Bool = false,
        messageLineLimit: Int? = nil,
        primaryAction: GlassRecoveryAction,
        secondaryActions: [GlassRecoveryAction] = []
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            isCompactTile: isCompactTile,
            messageLineLimit: messageLineLimit,
            primaryAction: primaryAction,
            secondaryActions: secondaryActions,
            extraContent: { EmptyView() }
        )
    }
}

/// Shared Spoiler Delay Buffer popover used by both `LivePulseTickerBar` and `LiveCompanionDrawerView`.
struct SpoilerDelayPopover: View {
    @Binding var selectedDelay: SpoilerDelayOption
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("Spoiler Delay Buffer")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(AppleTheme.textSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)

            ForEach(SpoilerDelayOption.allCases) { option in
                let isSelected = selectedDelay == option
                Button {
                    selectedDelay = option
                    isPresented = false
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: isSelected ? "checkmark" : "clock")
                            .font(AppIconFont.xs(weight: .semibold))
                            .foregroundStyle(isSelected ? AppleTheme.accentText : AppleTheme.textSecondary)
                            .frame(width: 14)
                        Text(option.displayName)
                            .font(AppFont.callout(weight: isSelected ? .semibold : .regular, tabular: true))
                            .foregroundStyle(.primary)
                        Spacer(minLength: AppSpacing.md)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .fill(isSelected ? AppleTheme.accentText.opacity(0.12) : .clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.sm)
        .frame(width: 180)
    }
}
