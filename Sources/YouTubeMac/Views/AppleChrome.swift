import AppKit
import SwiftUI

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
enum AppleTheme {
    /// Adaptive crimson accent: deeper high-contrast crimson in Light Mode, luminous crimson in Dark Mode.
    static let accentNSColor = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
            ? NSColor(calibratedRed: 1.0, green: 0.212, blue: 0.239, alpha: 1.0)    // #FF363D
            : NSColor(calibratedRed: 0.843, green: 0.098, blue: 0.125, alpha: 1.0) // #D71920
    }

    static var accent: Color {
        Color(nsColor: accentNSColor)
    }

    static let canvasNSColor = NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
            ? NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
            : .white
    }

    static var canvasColor: Color {
        Color(nsColor: canvasNSColor)
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

extension View {
    /// Applies authentic macOS 26+ Liquid Glass (`.glassEffect`) with a crisp `.regularMaterial` fallback on macOS 14–15.
    @ViewBuilder
    func appleGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(makeAppleGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            fallbackMaterialGlass(in: shape, tint: tint)
        }
        #else
        fallbackMaterialGlass(in: shape, tint: tint)
        #endif
    }

    private func fallbackMaterialGlass<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        self
            .background {
                shape.fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            shape.fill(tint)
                        }
                    }
            }
            .overlay(
                shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            )
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

    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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
    var onDoubleClick: (() -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView(frame: .zero)
        view.onDoubleClick = onDoubleClick
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {
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
                .font(.system(size: 13, weight: .medium))
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
            return Color.primary.opacity(0.24)
        }
        if isActive {
            return AppleTheme.accent
        }
        return isHovered ? Color.primary : Color.primary.opacity(0.78)
    }

    private var backgroundColor: Color {
        if isDisabled {
            return .clear
        }
        if isActive {
            return AppleTheme.accent.opacity(isHovered ? 0.22 : 0.14)
        }
        return isHovered ? Color.primary.opacity(0.09) : .clear
    }
}

/// Compact Apple TV–style outlined HDR badge shown when a high dynamic range stream is active.
struct AppleHDRBadge: View {
    var body: some View {
        Text("HDR")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .tracking(0.45)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.28), lineWidth: 0.85)
            )
            .help("High Dynamic Range (HDR10) Active")
    }
}

/// Compact Apple-style playback speed pill badge shown only when playback speed differs from 1×.
struct AppleSpeedBadge: View {
    let rateText: String

    var body: some View {
        Text(rateText)
            .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(AppleTheme.accent)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(AppleTheme.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(AppleTheme.accent.opacity(0.32), lineWidth: 0.75)
            )
            .help("Playback Speed: \(rateText)")
    }
}

/// Subtle non-blocking macOS Liquid Glass HUD toast overlay.
struct AppleHUDToast: View {
    let toast: HUDToast

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppleTheme.accent)
            Text(toast.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8.5)
        .appleGlass(in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}
