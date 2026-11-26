import AppKit
import CoreText
import Foundation
import os
import SwiftUI
import YouTubeMacCore

// MARK: - CoreText Inter Font Registration & Caching

private struct SendableCTFont: @unchecked Sendable {
    let font: CTFont
}

private struct SendableCTFontDescriptor: @unchecked Sendable {
    let descriptor: CTFontDescriptor
}

private struct FontCacheKey: Hashable, Sendable {
    let sizeTenths: Int
    let weightValue: Int
    let tabular: Bool
}

private struct InterLoaderState: Sendable {
    var didAttemptRegistration = false
    var baseDescriptor: SendableCTFontDescriptor?
    var fontCache: [FontCacheKey: SendableCTFont] = [:]
}

/// Thread-safe CoreText loader and variation-axis bridge for bundled Inter v4.1 (`InterVariable.ttf`).
/// Resolves `Bundle.main` first (`.app` bundle) and only falls back to `Bundle.module` when running
/// unbundled via SwiftPM (`swift run` / `swift test`) so distributed `.app` builds never trip SPM's
/// synthesized `Bundle.module` fatal lookup.
enum InterFontLoader {
    private static let stateLock = OSAllocatedUnfairLock(initialState: InterLoaderState())

    /// FourCC variation axis tags (`'wght'` = 0x77676874, `'opsz'` = 0x6F70737A).
    private static let weightAxisTag = NSNumber(value: UInt32(0x77676874))
    private static let opticalSizeAxisTag = NSNumber(value: UInt32(0x6F70737A))

    static var isInterLoaded: Bool {
        registerIfNeeded()
        return stateLock.withLock { $0.baseDescriptor != nil }
    }

    static func registerIfNeeded() {
        let alreadyAttempted = stateLock.withLock { $0.didAttemptRegistration }
        if alreadyAttempted { return }

        guard let url = resolveFontURL() else {
            stateLock.withLock { $0.didAttemptRegistration = true }
            return
        }

        var cfError: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)

        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        let first = descriptors?.first.map { SendableCTFontDescriptor(descriptor: $0) }

        stateLock.withLock { state in
            state.didAttemptRegistration = true
            if state.baseDescriptor == nil {
                state.baseDescriptor = first
            }
        }
    }

    static func resolvedFamilyName(for size: CGFloat = 13) -> String {
        CTFontCopyFamilyName(ctFont(size: size, weight: .regular, tabular: false)) as String
    }

    static func ctFont(size: CGFloat, weight: Font.Weight = .regular, tabular: Bool = false) -> CTFont {
        registerIfNeeded()

        let clampedSize = max(DesignSystemMetrics.minimumTextSize, size)
        let weightValue = numericWeight(for: weight)
        let key = FontCacheKey(
            sizeTenths: Int((clampedSize * 10.0).rounded()),
            weightValue: weightValue,
            tabular: tabular
        )

        if let cached = stateLock.withLock({ $0.fontCache[key] }) {
            return cached.font
        }

        let wrappedDescriptor = stateLock.withLock { $0.baseDescriptor }
        let created: CTFont
        if let descriptor = wrappedDescriptor?.descriptor {
            let opticalSize = min(32.0, max(14.0, Double(clampedSize)))
            let variations: [NSNumber: NSNumber] = [
                weightAxisTag: NSNumber(value: weightValue),
                opticalSizeAxisTag: NSNumber(value: opticalSize)
            ]

            var features: [[CFString: Any]] = [
                [kCTFontOpenTypeFeatureTag: "cv05", kCTFontOpenTypeFeatureValue: 1]
            ]
            if tabular {
                features.append([kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1])
                features.append([kCTFontOpenTypeFeatureTag: "ss01", kCTFontOpenTypeFeatureValue: 1])
            }

            let attributes: [CFString: Any] = [
                kCTFontVariationAttribute: variations,
                kCTFontFeatureSettingsAttribute: features
            ]
            let configured = CTFontDescriptorCreateCopyWithAttributes(descriptor, attributes as CFDictionary)
            created = CTFontCreateWithFontDescriptor(configured, clampedSize, nil)
        } else {
            created = NSFont.systemFont(ofSize: clampedSize, weight: appKitWeight(for: weightValue)) as CTFont
        }

        let wrapped = SendableCTFont(font: created)
        stateLock.withLock { state in
            state.fontCache[key] = wrapped
        }
        return created
    }

    private static func resolveFontURL() -> URL? {
        if let mainURL = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf", subdirectory: "Fonts") {
            return mainURL
        }
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            return Bundle.module.url(forResource: "InterVariable", withExtension: "ttf", subdirectory: "Fonts")
        }
        return nil
    }

    private static func numericWeight(for weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 100
        case .thin: return 200
        case .light: return 300
        case .regular: return 400
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 800
        default: return 400
        }
    }

    private static func appKitWeight(for value: Int) -> NSFont.Weight {
        switch value {
        case ...150: return .ultraLight
        case ...250: return .thin
        case ...350: return .light
        case ...450: return .regular
        case ...550: return .medium
        case ...650: return .semibold
        case ...750: return .bold
        default: return .heavy
        }
    }
}

// MARK: - Typography Tokens (100% Text — NEVER apply to Image(systemName:))

/// Inter v4.1 typography tokens backed by CoreText variable axes (`wght`, `opsz`) and OpenType features (`cv05`, `tnum`, `ss01`).
/// Uses strictly integer sizes `>= 10pt`: `[10, 11, 12, 13, 15, 17, 22, 26]`.
enum AppFont {
    static let micro: Font = micro()
    static let caption: Font = caption()
    static let callout: Font = callout()
    static let body: Font = body()
    static let subhead: Font = subhead()
    static let title: Font = title()
    static let largeTitle: Font = largeTitle()
    static let hero: Font = hero()

    static func micro(weight: Font.Weight = .semibold, tabular: Bool = false) -> Font {
        font(size: 10, weight: weight, tabular: tabular)
    }

    static func caption(weight: Font.Weight = .regular, tabular: Bool = false) -> Font {
        font(size: 11, weight: weight, tabular: tabular)
    }

    static func callout(weight: Font.Weight = .regular, tabular: Bool = false) -> Font {
        font(size: 12, weight: weight, tabular: tabular)
    }

    static func body(weight: Font.Weight = .regular, tabular: Bool = false) -> Font {
        font(size: 13, weight: weight, tabular: tabular)
    }

    static func subhead(weight: Font.Weight = .semibold, tabular: Bool = false) -> Font {
        font(size: 15, weight: weight, tabular: tabular)
    }

    static func title(weight: Font.Weight = .semibold, tabular: Bool = false) -> Font {
        font(size: 17, weight: weight, tabular: tabular)
    }

    static func largeTitle(weight: Font.Weight = .bold, tabular: Bool = false) -> Font {
        font(size: 22, weight: weight, tabular: tabular)
    }

    static func hero(weight: Font.Weight = .bold, tabular: Bool = false) -> Font {
        font(size: 26, weight: weight, tabular: tabular)
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular, tabular: Bool = false) -> Font {
        Font(InterFontLoader.ctFont(size: size, weight: weight, tabular: tabular))
    }

    static func nsFont(size: CGFloat, weight: Font.Weight = .regular, tabular: Bool = false) -> NSFont {
        InterFontLoader.ctFont(size: size, weight: weight, tabular: tabular) as NSFont
    }

    /// Strictly for technical code snippets, CLI commands, socket paths, and URLs.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: max(DesignSystemMetrics.minimumTextSize, size), weight: weight, design: .monospaced)
    }

    /// Dynamic Inter optical tracking (`rsms.me/inter/dynmetrics`) in points for a given font size.
    static func tracking(for size: CGFloat) -> CGFloat {
        let clamped = max(Double(DesignSystemMetrics.minimumTextSize), Double(size))
        let emTracking = -0.0223 + 0.185 * exp(-0.1745 * clamped)
        let points = emTracking * clamped
        return CGFloat((points * 100.0).rounded() / 100.0)
    }
}

// MARK: - SF Symbol Icon Tokens (Never use Inter on Image(systemName:))

/// Dedicated SF Symbol font scale. Keeps `.system(size:weight:)` isolated from `AppFont`
/// so SF Symbols preserve exact optical weights and alignment.
enum AppIconFont {
    static let xs: Font = xs()
    static let sm: Font = sm()
    static let md: Font = md()
    static let toolbar: Font = toolbar()
    static let nav: Font = nav()
    static let lg: Font = lg()
    static let xl: Font = xl()
    static let hero: Font = hero()

    static func xs(weight: Font.Weight = .semibold) -> Font { .system(size: 10, weight: weight) }
    static func sm(weight: Font.Weight = .medium) -> Font { .system(size: 11, weight: weight) }
    static func md(weight: Font.Weight = .medium) -> Font { .system(size: 12, weight: weight) }
    static func toolbar(weight: Font.Weight = .medium) -> Font { .system(size: 13, weight: weight) }
    static func nav(weight: Font.Weight = .medium) -> Font { .system(size: 14, weight: weight) }
    static func lg(weight: Font.Weight = .medium) -> Font { .system(size: 16, weight: weight) }
    static func xl(weight: Font.Weight = .semibold) -> Font { .system(size: 20, weight: weight) }
    static func hero(weight: Font.Weight = .semibold) -> Font { .system(size: 22, weight: weight) }
}

// MARK: - Spacing & Concentric Radii Tokens

enum AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
}

enum AppRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 20

    static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
        DesignSystemMetrics.concentricInnerRadius(outer: outer, padding: padding)
    }
}

// MARK: - Minimum Interactive Hit-Target Helper

extension View {
    /// Guarantees a minimum clickable hit target (`>= 24×24pt` by default) even around compact visual badges or glyphs.
    func minHitTarget<S: Shape>(
        _ size: CGFloat = DesignSystemMetrics.minimumHitTarget,
        shape: S = Rectangle()
    ) -> some View {
        self
            .frame(minWidth: size, minHeight: size)
            .contentShape(shape)
    }
}
