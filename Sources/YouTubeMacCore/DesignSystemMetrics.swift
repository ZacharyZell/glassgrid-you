import CoreGraphics
import Foundation

/// Pure Foundation + CoreGraphics design-system constants and WCAG 2.1 contrast math.
/// Kept completely free of AppKit, SwiftUI, CoreText, WebKit, and Sparkle so `glassgrid` CLI linkage stays clean
/// and `YouTubeMacCoreTests` can verify all contrast, ramp, spacing, and concentric-radius invariants offline.
public enum DesignSystemMetrics {
    // MARK: - Canonical Hex Palette

    public static let accentFill = "#D71920"
    public static let accentFillHover = "#C0141B"
    public static let accentTextLight = "#B81219"
    public static let accentTextDark = "#FF7076"

    public static let textSecondaryLight = "#4A4A52"
    public static let textSecondaryDark = "#A1A1AA"
    public static let textMutedLight = "#595962"
    public static let textMutedDark = "#A1A1AA"

    public static let positiveLight = "#147B3B"
    public static let positiveDark = "#34D958"
    public static let warningLight = "#9E5400"
    public static let warningDark = "#FFB340"
    public static let infoLight = "#005FCC"
    public static let infoDark = "#4DA3FF"

    public static let surfaceSolidLight = "#F5F5F7"
    public static let surfaceSolidDark = "#161619"

    public static let brandGradientStart = "#3D1421"
    public static let brandGradientEnd = "#D71920"

    /// Representative Day (Light) glass / elevated background samples for WCAG 2.1 testing.
    public static let lightSurfaces: [String] = ["#FFFFFF", "#F5F5F7", "#EBEBF0"]
    /// Representative Night (Dark) glass / elevated background samples for WCAG 2.1 testing.
    public static let darkSurfaces: [String] = ["#161619", "#1C1C20", "#242429"]

    // MARK: - Typography, Spacing, Radii & Hit-Target Invariants

    public static let typographyRamp: [CGFloat] = [10, 11, 12, 13, 15, 17, 22, 26]
    public static let minimumTextSize: CGFloat = 10

    public static let spacingGrid: [CGFloat] = [2, 4, 6, 8, 12, 16, 20, 24]
    public static let minimumHitTarget: CGFloat = 24

    public static let wcagAANormalTextMinimum: Double = 4.5
    public static let wcagAANonTextMinimum: Double = 3.0

    public static func concentricInnerRadius(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(4, outer - padding)
    }

    // MARK: - WCAG 2.1 Luminance & Contrast Math

    public static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    public static func relativeLuminance(hex: String) -> Double {
        guard let (r, g, b) = rgbComponents(fromHex: hex) else {
            return 0
        }
        func linearize(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    public static func contrastRatio(foregroundHex: String, backgroundHex: String) -> Double {
        let l1 = relativeLuminance(hex: foregroundHex)
        let l2 = relativeLuminance(hex: backgroundHex)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func compositedHex(foregroundHex: String, alpha: Double, over backgroundHex: String) -> String {
        guard let fg = rgbComponents(fromHex: foregroundHex),
              let bg = rgbComponents(fromHex: backgroundHex) else {
            return backgroundHex
        }
        let clampedAlpha = min(1.0, max(0.0, alpha))
        let r = fg.r * clampedAlpha + bg.r * (1.0 - clampedAlpha)
        let g = fg.g * clampedAlpha + bg.g * (1.0 - clampedAlpha)
        let b = fg.b * clampedAlpha + bg.b * (1.0 - clampedAlpha)
        let ri = min(255, max(0, Int((r * 255.0).rounded())))
        let gi = min(255, max(0, Int((g * 255.0).rounded())))
        let bi = min(255, max(0, Int((b * 255.0).rounded())))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}
