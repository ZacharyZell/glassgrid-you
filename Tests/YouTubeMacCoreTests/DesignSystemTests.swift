import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import YouTubeMacCore

@Suite("Design System & Accessibility Tests")
struct DesignSystemTests {
    private static func repoRootURL() -> URL {
        // Tests/YouTubeMacCoreTests/DesignSystemTests.swift -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Bundled Inter v4.1 variable font and SIL OFL 1.1 license exist")
    func bundledInterFontAndLicenseExist() throws {
        let fontsDir = Self.repoRootURL()
            .appendingPathComponent("Sources/YouTubeMac/Resources/Fonts", isDirectory: true)
        let fontURL = fontsDir.appendingPathComponent("InterVariable.ttf")
        let licenseURL = fontsDir.appendingPathComponent("OFL.txt")

        #expect(FileManager.default.fileExists(atPath: fontURL.path))
        #expect(FileManager.default.fileExists(atPath: licenseURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: fontURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        #expect(fileSize > 500_000)

        let licenseText = try String(contentsOf: licenseURL, encoding: .utf8)
        #expect(licenseText.contains("SIL OPEN FONT LICENSE"))
    }

    @Test("CoreText registers InterVariable.ttf and instantiates wght/opsz/OpenType variants without fallback")
    func coreTextInterRegistrationAndVariations() throws {
        let fontURL = Self.repoRootURL()
            .appendingPathComponent("Sources/YouTubeMac/Resources/Fonts/InterVariable.ttf")

        var cfError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &cfError)
        if !registered {
            let error = cfError?.takeRetainedValue()
            let code = error.map { CFErrorGetCode($0) }
            #expect(code == CTFontManagerError.alreadyRegistered.rawValue)
        }

        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor]
        let baseDescriptor = try #require(descriptors?.first)

        let weightAxisTag = NSNumber(value: UInt32(0x77676874)) // 'wght'
        let opticalSizeAxisTag = NSNumber(value: UInt32(0x6F70737A)) // 'opsz'

        let weights = [400, 500, 600, 700]
        let opticalSizes: [Double] = [14, 17, 26]

        for weight in weights {
            for opsz in opticalSizes {
                let variations: [NSNumber: NSNumber] = [
                    weightAxisTag: NSNumber(value: weight),
                    opticalSizeAxisTag: NSNumber(value: opsz)
                ]
                let features: [[CFString: Any]] = [
                    [kCTFontOpenTypeFeatureTag: "cv05", kCTFontOpenTypeFeatureValue: 1],
                    [kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1],
                    [kCTFontOpenTypeFeatureTag: "ss01", kCTFontOpenTypeFeatureValue: 1]
                ]
                let attributes: [CFString: Any] = [
                    kCTFontVariationAttribute: variations,
                    kCTFontFeatureSettingsAttribute: features
                ]
                let configured = CTFontDescriptorCreateCopyWithAttributes(baseDescriptor, attributes as CFDictionary)
                let font = CTFontCreateWithFontDescriptor(configured, CGFloat(opsz), nil)
                let familyName = CTFontCopyFamilyName(font) as String

                #expect(familyName.contains("Inter"))
                #expect(!familyName.contains(".SFNS"))
                #expect(!familyName.contains("Helvetica"))
                #expect(CTFontGetSize(font) == CGFloat(opsz))
            }
        }
    }

    @Test("Solid crimson accent fills pass WCAG 2.1 AA >= 4.5:1 contrast with white text")
    func solidAccentFillWCAGContrast() {
        let fillContrast = DesignSystemMetrics.contrastRatio(
            foregroundHex: "#FFFFFF",
            backgroundHex: DesignSystemMetrics.accentFill
        )
        let hoverContrast = DesignSystemMetrics.contrastRatio(
            foregroundHex: "#FFFFFF",
            backgroundHex: DesignSystemMetrics.accentFillHover
        )

        #expect(fillContrast >= DesignSystemMetrics.wcagAANormalTextMinimum)
        #expect(hoverContrast >= DesignSystemMetrics.wcagAANormalTextMinimum)
    }

    @Test("Light-mode semantic and neutral foreground tokens pass WCAG 2.1 AA >= 4.5:1 across all light surfaces")
    func lightModeTokensWCAGContrast() {
        #expect(DesignSystemMetrics.lightSurfaces == ["#FFFFFF", "#F5F5F7", "#EBEBF0"])

        let tokens: [(name: String, hex: String)] = [
            ("accentTextLight", DesignSystemMetrics.accentTextLight),
            ("textSecondaryLight", DesignSystemMetrics.textSecondaryLight),
            ("textMutedLight", DesignSystemMetrics.textMutedLight),
            ("positiveLight", DesignSystemMetrics.positiveLight),
            ("warningLight", DesignSystemMetrics.warningLight),
            ("infoLight", DesignSystemMetrics.infoLight)
        ]

        for token in tokens {
            for surface in DesignSystemMetrics.lightSurfaces {
                let ratio = DesignSystemMetrics.contrastRatio(foregroundHex: token.hex, backgroundHex: surface)
                #expect(
                    ratio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                    "\(token.name) (\(token.hex)) on \(surface) has contrast \(ratio)"
                )
            }
        }
    }

    @Test("Dark-mode semantic and neutral foreground tokens pass WCAG 2.1 AA >= 4.5:1 across all dark surfaces")
    func darkModeTokensWCAGContrast() {
        #expect(DesignSystemMetrics.darkSurfaces == ["#161619", "#1C1C20", "#242429"])

        let tokens: [(name: String, hex: String)] = [
            ("accentTextDark", DesignSystemMetrics.accentTextDark),
            ("textSecondaryDark", DesignSystemMetrics.textSecondaryDark),
            ("textMutedDark", DesignSystemMetrics.textMutedDark),
            ("positiveDark", DesignSystemMetrics.positiveDark),
            ("warningDark", DesignSystemMetrics.warningDark),
            ("infoDark", DesignSystemMetrics.infoDark)
        ]

        for token in tokens {
            for surface in DesignSystemMetrics.darkSurfaces {
                let ratio = DesignSystemMetrics.contrastRatio(foregroundHex: token.hex, backgroundHex: surface)
                #expect(
                    ratio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                    "\(token.name) (\(token.hex)) on \(surface) has contrast \(ratio)"
                )
            }
        }
    }

    @Test("Tinted accent pills (12% Light, 14% Dark) pass WCAG 2.1 AA >= 4.5:1 across all representative surfaces")
    func tintedAccentPillsWCAGContrast() {
        for surface in DesignSystemMetrics.lightSurfaces {
            let composited = DesignSystemMetrics.compositedHex(
                foregroundHex: DesignSystemMetrics.accentTextLight,
                alpha: 0.12,
                over: surface
            )
            let ratio = DesignSystemMetrics.contrastRatio(
                foregroundHex: DesignSystemMetrics.accentTextLight,
                backgroundHex: composited
            )
            #expect(
                ratio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "Light tinted pill on \(surface) -> \(composited) has contrast \(ratio)"
            )
        }

        for surface in DesignSystemMetrics.darkSurfaces {
            let composited = DesignSystemMetrics.compositedHex(
                foregroundHex: DesignSystemMetrics.accentTextDark,
                alpha: 0.14,
                over: surface
            )
            let ratio = DesignSystemMetrics.contrastRatio(
                foregroundHex: DesignSystemMetrics.accentTextDark,
                backgroundHex: composited
            )
            #expect(
                ratio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "Dark tinted pill on \(surface) -> \(composited) has contrast \(ratio)"
            )
        }
    }

    @Test("All 18 streaming services achieve WCAG 2.1 AA >= 4.5:1 white-text contrast on both gradient stops")
    func streamingServiceBadgesWCAGContrast() {
        #expect(StreamingServiceCatalog.all.count == 18)

        for service in StreamingServiceCatalog.all {
            let startRatio = DesignSystemMetrics.contrastRatio(
                foregroundHex: "#FFFFFF",
                backgroundHex: service.accentHexStart
            )
            let endRatio = DesignSystemMetrics.contrastRatio(
                foregroundHex: "#FFFFFF",
                backgroundHex: service.accentHexEnd
            )
            #expect(
                startRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "\(service.id) accentHexStart (\(service.accentHexStart)) contrast \(startRatio)"
            )
            #expect(
                endRatio >= DesignSystemMetrics.wcagAANormalTextMinimum,
                "\(service.id) accentHexEnd (\(service.accentHexEnd)) contrast \(endRatio)"
            )
        }
    }

    @Test("Typography ramp, spacing grid, hit-target floor, and concentric radius invariants hold")
    func layoutSpacingRampAndConcentricInvariants() {
        let ramp = DesignSystemMetrics.typographyRamp
        #expect(!ramp.isEmpty)
        for size in ramp {
            #expect(size == size.rounded())
            #expect(size >= DesignSystemMetrics.minimumTextSize)
            #expect(size >= 10)
        }
        let isStrictlySorted = zip(ramp, ramp.dropFirst()).allSatisfy { $0 < $1 }
        #expect(isStrictlySorted)

        #expect(DesignSystemMetrics.spacingGrid == [2, 4, 6, 8, 12, 16, 20, 24])
        #expect(DesignSystemMetrics.minimumHitTarget >= 24)
        #expect(DesignSystemMetrics.concentricInnerRadius(outer: 16, padding: 8) == 8)
        #expect(DesignSystemMetrics.concentricInnerRadius(outer: 6, padding: 8) == 4)
    }
}
