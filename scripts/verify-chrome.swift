#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Window Chrome Constants (Mirrors Sources/YouTubeMacCore/WindowChromeLayout.swift)

enum ChromeMetrics {
    static let sidebarWidth: CGFloat = 234
    static let sidebarCardLeadingInset: CGFloat = 8
    static let sidebarCardTrailingInset: CGFloat = 4
    static let sidebarCardVerticalInset: CGFloat = 8
    static let sidebarCardCornerRadius: CGFloat = 16
    static let sidebarHeaderHeight: CGFloat = 36
    static let topHeaderBarHeight: CGFloat = 52
    static let expandedSidebarHeaderLeadingPadding: CGFloat = 78
    static let collapsedNavLeadingPadding: CGFloat = 90
    static let nativeFullScreenCollapsedPadding: CGFloat = 12

    static let minimumTrafficLightClearance: CGFloat = 6.0
    static let maximumCenterlineDelta: CGFloat = 1.5
    static let minimumExpandedSidebarLeadingClearance: CGFloat = 4.0
    static let minimumCollapsedNavLeadingClearance: CGFloat = 8.0

    static var sidebarHeaderCenterY: CGFloat {
        sidebarCardVerticalInset + sidebarHeaderHeight / 2.0
    }

    static var topHeaderBarCenterY: CGFloat {
        topHeaderBarHeight / 2.0
    }

    static func sidebarCardRect(windowSize: CGSize) -> CGRect {
        CGRect(
            x: sidebarCardLeadingInset,
            y: sidebarCardVerticalInset,
            width: max(0, sidebarWidth - sidebarCardLeadingInset - sidebarCardTrailingInset),
            height: max(0, windowSize.height - (sidebarCardVerticalInset * 2.0))
        )
    }

    static func inwardClearance(
        ofCircleIn buttonFrame: CGRect,
        insideRoundedRect rect: CGRect,
        cornerRadius: CGFloat
    ) -> CGFloat {
        let hx = max(0, rect.width / 2.0)
        let hy = max(0, rect.height / 2.0)
        let rc = max(0, min(cornerRadius, min(hx, hy)))
        let radius = max(0, min(buttonFrame.width, buttonFrame.height) / 2.0)

        let qx = abs(buttonFrame.midX - rect.midX) - (hx - rc)
        let qy = abs(buttonFrame.midY - rect.midY) - (hy - rc)
        let outsideDistance = hypot(max(qx, 0), max(qy, 0))
        let insideDistance = min(max(qx, qy), 0)
        let signedDistance = outsideDistance + insideDistance - rc
        return -signedDistance - radius
    }
}

// MARK: - CLI Argument Parsing

struct CLIOptions {
    var screenshotPath: String?
    var outDirPath: String = "build/chrome-audit"
    var explicitScale: CGFloat?
    var skipLive: Bool = false

    static func parse(_ args: [String]) -> CLIOptions {
        var opts = CLIOptions()
        var index = 1
        while index < args.count {
            switch args[index] {
            case "--screenshot":
                index += 1
                if index < args.count { opts.screenshotPath = args[index] }
            case "--out-dir":
                index += 1
                if index < args.count { opts.outDirPath = args[index] }
            case "--scale":
                index += 1
                if index < args.count, let value = Double(args[index]), value > 0 {
                    opts.explicitScale = CGFloat(value)
                }
            case "--skip-live":
                opts.skipLive = true
            case "-h", "--help":
                print("""
                Usage: verify-chrome.swift [--screenshot <path.png>] [--out-dir <dir>] [--scale <1|2>] [--skip-live]
                  Runs a live AppKit unified-toolbar traffic-light geometry audit on the host macOS version
                  and optionally slices a full-window screenshot into 1:1 lossless chrome close-up PNGs.
                """)
                exit(0)
            default:
                fputs("warning: ignoring unrecognized argument '\(args[index])'\n", stderr)
            }
            index += 1
        }
        return opts
    }
}

// MARK: - Live AppKit Unified-Toolbar Geometry Audit

@MainActor
func runLiveAppKitAudit() -> Bool {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    let windowSize = CGSize(width: 1280, height: 800)
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: windowSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden

    let toolbar = NSToolbar(identifier: "GlassGridYouUnifiedTitlebar")
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    toolbar.autosavesConfiguration = false
    toolbar.isVisible = true
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.titlebarSeparatorStyle = .none
    window.isReleasedWhenClosed = false
    window.layoutIfNeeded()

    func topLeftFrame(for buttonType: NSWindow.ButtonType) -> CGRect? {
        guard let button = window.standardWindowButton(buttonType) else { return nil }
        let frameInWindow = button.convert(button.bounds, to: nil)
        let topLeftY = window.frame.height - frameInWindow.maxY
        return CGRect(
            x: frameInWindow.minX,
            y: topLeftY,
            width: frameInWindow.width,
            height: frameInWindow.height
        )
    }

    guard let closeFrame = topLeftFrame(for: .closeButton),
          let minFrame = topLeftFrame(for: .miniaturizeButton),
          let zoomFrame = topLeftFrame(for: .zoomButton)
    else {
        fputs("FAIL: Could not locate standard macOS traffic-light buttons on NSWindow.\n", stderr)
        return false
    }

    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let buttons: [(String, CGRect)] = [
        ("close", closeFrame),
        ("miniaturize", minFrame),
        ("zoom", zoomFrame)
    ]

    let cardRect = ChromeMetrics.sidebarCardRect(windowSize: window.frame.size)
    var clearances: [CGFloat] = []
    print("=== Live AppKit Chrome Audit (\(osVersion)) ===")
    print(String(format: "Window: %.0fx%.0fpt | Sidebar Card: (%.1f, %.1f, %.1fx%.1f, R=%.0f)",
                 window.frame.width, window.frame.height,
                 cardRect.minX, cardRect.minY, cardRect.width, cardRect.height,
                 ChromeMetrics.sidebarCardCornerRadius))

    for (name, frame) in buttons {
        let clearance = ChromeMetrics.inwardClearance(
            ofCircleIn: frame,
            insideRoundedRect: cardRect,
            cornerRadius: ChromeMetrics.sidebarCardCornerRadius
        )
        clearances.append(clearance)
        print(String(format: "  %-11s frame=(%.1f, %.1f, %.1fx%.1f) centerY=%.1fpt inwardClearance=%+.2fpt",
                     (name as NSString).utf8String!,
                     frame.minX, frame.minY, frame.width, frame.height,
                     frame.midY, clearance))
    }

    let minClearance = clearances.min() ?? -.greatestFiniteMagnitude
    let avgCenterY = (closeFrame.midY + minFrame.midY + zoomFrame.midY) / 3.0
    let sidebarCenterDelta = abs(avgCenterY - ChromeMetrics.sidebarHeaderCenterY)
    let topHeaderCenterDelta = abs(avgCenterY - ChromeMetrics.topHeaderBarCenterY)
    let zoomMaxX = max(closeFrame.maxX, max(minFrame.maxX, zoomFrame.maxX))
    let expandedLeadingClearance = (ChromeMetrics.sidebarCardLeadingInset + ChromeMetrics.expandedSidebarHeaderLeadingPadding) - zoomMaxX
    let collapsedLeadingClearance = ChromeMetrics.collapsedNavLeadingPadding - zoomMaxX

    print(String(format: "  centerY=%.2fpt (sidebarDelta=%.2fpt, topHeaderDelta=%.2fpt)",
                 avgCenterY, sidebarCenterDelta, topHeaderCenterDelta))
    print(String(format: "  zoom.maxX=%.1fpt | expandedLeadingClearance=%+.1fpt | collapsedNavClearance=%+.1fpt",
                 zoomMaxX, expandedLeadingClearance, collapsedLeadingClearance))

    var violations: [String] = []
    if minClearance < ChromeMetrics.minimumTrafficLightClearance {
        violations.append(String(format: "minInwardClearance %.2fpt < %.2fpt", minClearance, ChromeMetrics.minimumTrafficLightClearance))
    }
    if sidebarCenterDelta > ChromeMetrics.maximumCenterlineDelta {
        violations.append(String(format: "sidebarHeaderCenterDelta %.2fpt > %.2fpt", sidebarCenterDelta, ChromeMetrics.maximumCenterlineDelta))
    }
    if topHeaderCenterDelta > ChromeMetrics.maximumCenterlineDelta {
        violations.append(String(format: "topHeaderBarCenterDelta %.2fpt > %.2fpt", topHeaderCenterDelta, ChromeMetrics.maximumCenterlineDelta))
    }
    if expandedLeadingClearance < ChromeMetrics.minimumExpandedSidebarLeadingClearance {
        violations.append(String(format: "expandedLeadingClearance %.2fpt < %.2fpt", expandedLeadingClearance, ChromeMetrics.minimumExpandedSidebarLeadingClearance))
    }
    if collapsedLeadingClearance < ChromeMetrics.minimumCollapsedNavLeadingClearance {
        violations.append(String(format: "collapsedLeadingClearance %.2fpt < %.2fpt", collapsedLeadingClearance, ChromeMetrics.minimumCollapsedNavLeadingClearance))
    }

    window.close()

    if violations.isEmpty {
        print("LIVE APPKIT CHROME AUDIT: PASS")
        return true
    } else {
        for v in violations {
            fputs("FAIL: \(v)\n", stderr)
        }
        return false
    }
}

// MARK: - 1:1 Pixel-Sharp Screenshot Chrome Cropper

func detectScale(imageSource: CGImageSource, cgImage: CGImage, explicitScale: CGFloat?) -> CGFloat {
    if let explicitScale {
        return explicitScale
    }
    if let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
       let dpiWidth = props[kCGImagePropertyDPIWidth] as? Double,
       dpiWidth >= 72.0 {
        let inferred = round(dpiWidth / 72.0)
        if inferred >= 1.0 && inferred <= 3.0 {
            return CGFloat(inferred)
        }
    }
    return cgImage.width >= 1600 ? 2.0 : 1.0
}

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "verify-chrome", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination at \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "verify-chrome", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG to \(url.path)"])
    }
}

func cropScreenshot(path: String, outDirPath: String, explicitScale: CGFloat?) -> Bool {
    let inputURL = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        fputs("FAIL: Unable to load PNG image at \(inputURL.path)\n", stderr)
        return false
    }

    let scale = detectScale(imageSource: source, cgImage: cgImage, explicitScale: explicitScale)
    let imgW = CGFloat(cgImage.width)
    let imgH = CGFloat(cgImage.height)
    let fullBounds = CGRect(x: 0, y: 0, width: imgW, height: imgH)

    let outDirURL = URL(fileURLWithPath: outDirPath, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: outDirURL, withIntermediateDirectories: true)
    } catch {
        fputs("FAIL: Could not create output directory \(outDirURL.path): \(error)\n", stderr)
        return false
    }

    let zones: [(String, CGRect)] = [
        (
            "top-left-traffic-lights.png",
            CGRect(x: 0, y: 0, width: 260 * scale, height: 110 * scale)
        ),
        (
            "top-right-toolbar.png",
            CGRect(x: max(0, imgW - 340 * scale), y: 0, width: 340 * scale, height: 80 * scale)
        ),
        (
            "bottom-left-sidebar-footer.png",
            CGRect(x: 0, y: max(0, imgH - 90 * scale), width: 260 * scale, height: 90 * scale)
        ),
        (
            "top-bar-full-strip.png",
            CGRect(x: 0, y: 0, width: imgW, height: 80 * scale)
        )
    ]

    print("=== 1:1 Chrome Crop Harness ===")
    print(String(format: "Source: %@ (%dx%dpx, scale=%.0fx)", inputURL.path, cgImage.width, cgImage.height, scale))

    for (filename, desiredRect) in zones {
        let clamped = desiredRect.intersection(fullBounds).integral
        guard !clamped.isEmpty, let cropped = cgImage.cropping(to: clamped) else {
            fputs("FAIL: Could not crop zone \(filename) from \(inputURL.path)\n", stderr)
            return false
        }
        let destURL = outDirURL.appendingPathComponent(filename)
        do {
            try savePNG(cropped, to: destURL)
            print("  wrote \(destURL.path) (\(cropped.width)x\(cropped.height)px)")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    print("1:1 CHROME CROP HARNESS: PASS")
    return true
}

// MARK: - Main Entry Point

@MainActor
func main() {
    let options = CLIOptions.parse(CommandLine.arguments)
    var ok = true

    if !options.skipLive {
        if !runLiveAppKitAudit() {
            ok = false
        }
    }

    if let screenshotPath = options.screenshotPath {
        if !cropScreenshot(path: screenshotPath, outDirPath: options.outDirPath, explicitScale: options.explicitScale) {
            ok = false
        }
    }

    exit(ok ? 0 : 1)
}

MainActor.assumeIsolated {
    main()
}
