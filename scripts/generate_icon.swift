import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let specs: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

/// Renders an original Liquid Glass macOS squircle icon featuring a deep obsidian-ruby glass tile,
/// concentric frosted glass lens ring, liquid specular dome arc, and a luminous rounded glass play prism.
func renderIcon(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    rep.size = NSSize(width: pixels, height: pixels)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let cg = context.cgContext
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Standard macOS icon squircle inset (~9.5%)
    let inset = size * 0.095
    let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = iconRect.width * 0.225
    let squirclePath = CGPath(
        roundedRect: iconRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // Soft outer ambient shadow
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.022),
        blur: size * 0.048,
        color: NSColor.black.withAlphaComponent(0.36).cgColor
    )
    cg.addPath(squirclePath)
    cg.setFillColor(NSColor(calibratedRed: 0.12, green: 0.06, blue: 0.09, alpha: 1.0).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Clipped Liquid Glass squircle interior
    cg.saveGState()
    cg.addPath(squirclePath)
    cg.clip()

    // 1. Deep obsidian-to-ruby vertical base gradient
    let baseColors = [
        NSColor(calibratedRed: 0.20, green: 0.08, blue: 0.12, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.11, green: 0.05, blue: 0.08, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.07, green: 0.04, blue: 0.06, alpha: 1.0).cgColor
    ] as CFArray
    if let baseGrad = CGGradient(colorsSpace: colorSpace, colors: baseColors, locations: [0.0, 0.52, 1.0]) {
        cg.drawLinearGradient(
            baseGrad,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.minY),
            options: []
        )
    }

    // 2. Luminous crimson-coral subsurface glow radiating behind the glass lens
    let glowCenter = CGPoint(x: iconRect.midX, y: iconRect.midY - iconRect.height * 0.04)
    let glowColors = [
        NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.26, alpha: 0.92).cgColor,
        NSColor(calibratedRed: 0.85, green: 0.09, blue: 0.17, alpha: 0.56).cgColor,
        NSColor(calibratedRed: 0.45, green: 0.05, blue: 0.14, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.48, 1.0]) {
        cg.drawRadialGradient(
            glowGrad,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: iconRect.width * 0.62,
            options: [.drawsAfterEndLocation]
        )
    }

    // 3. Subtle cool-cyan liquid refraction tint at upper-left corner for authentic Liquid Glass depth
    let coolCenter = CGPoint(x: iconRect.minX + iconRect.width * 0.22, y: iconRect.maxY - iconRect.height * 0.18)
    let coolColors = [
        NSColor(calibratedRed: 0.72, green: 0.88, blue: 1.00, alpha: 0.26).cgColor,
        NSColor(calibratedRed: 0.72, green: 0.88, blue: 1.00, alpha: 0.0).cgColor
    ] as CFArray
    if let coolGrad = CGGradient(colorsSpace: colorSpace, colors: coolColors, locations: [0.0, 1.0]) {
        cg.drawRadialGradient(
            coolGrad,
            startCenter: coolCenter,
            startRadius: 0,
            endCenter: coolCenter,
            endRadius: iconRect.width * 0.48,
            options: []
        )
    }

    // 4. Upper liquid glass specular dome reflection
    let domeRect = CGRect(
        x: iconRect.minX - iconRect.width * 0.18,
        y: iconRect.midY + iconRect.height * 0.06,
        width: iconRect.width * 1.36,
        height: iconRect.height * 0.72
    )
    cg.saveGState()
    cg.addEllipse(in: domeRect)
    cg.clip()
    let domeColors = [
        NSColor.white.withAlphaComponent(0.28).cgColor,
        NSColor.white.withAlphaComponent(0.06).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let domeGrad = CGGradient(colorsSpace: colorSpace, colors: domeColors, locations: [0.0, 0.55, 1.0]) {
        cg.drawLinearGradient(
            domeGrad,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: domeRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // 5. Concentric frosted Liquid Glass circular lens
    let lensDiameter = iconRect.width * 0.64
    let lensRect = CGRect(
        x: iconRect.midX - lensDiameter / 2,
        y: iconRect.midY - lensDiameter / 2,
        width: lensDiameter,
        height: lensDiameter
    )

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.014),
        blur: size * 0.036,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )
    cg.addEllipse(in: lensRect)
    cg.setFillColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Lens interior soft glass sheen
    cg.saveGState()
    cg.addEllipse(in: lensRect)
    cg.clip()
    let lensFillColors = [
        NSColor.white.withAlphaComponent(0.34).cgColor,
        NSColor.white.withAlphaComponent(0.12).cgColor,
        NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.50, alpha: 0.16).cgColor
    ] as CFArray
    if let lensGrad = CGGradient(colorsSpace: colorSpace, colors: lensFillColors, locations: [0.0, 0.55, 1.0]) {
        cg.drawLinearGradient(
            lensGrad,
            start: CGPoint(x: lensRect.midX, y: lensRect.maxY),
            end: CGPoint(x: lensRect.midX, y: lensRect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Crisp specular lens rim
    cg.saveGState()
    cg.addEllipse(in: lensRect)
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.46).cgColor)
    cg.setLineWidth(max(1.0, size * 0.011))
    cg.strokePath()
    cg.restoreGState()

    // 6. Luminous rounded frosted-glass play prism centered optically inside the lens
    let prismRadius = lensDiameter * 0.285
    let prismCenter = CGPoint(x: lensRect.midX + prismRadius * 0.14, y: lensRect.midY)
    let angles: [CGFloat] = [0, 2.0 * .pi / 3.0, 4.0 * .pi / 3.0]
    let vertices = angles.map { angle in
        CGPoint(
            x: prismCenter.x + cos(angle) * prismRadius,
            y: prismCenter.y + sin(angle) * prismRadius
        )
    }
    let vertexCorner = prismRadius * 0.24
    let prismPath = CGMutablePath()
    let mid01 = CGPoint(x: (vertices[0].x + vertices[1].x) * 0.5, y: (vertices[0].y + vertices[1].y) * 0.5)
    prismPath.move(to: mid01)
    prismPath.addArc(tangent1End: vertices[1], tangent2End: vertices[2], radius: vertexCorner)
    prismPath.addArc(tangent1End: vertices[2], tangent2End: vertices[0], radius: vertexCorner)
    prismPath.addArc(tangent1End: vertices[0], tangent2End: vertices[1], radius: vertexCorner)
    prismPath.closeSubpath()

    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.028,
        color: NSColor(calibratedRed: 0.35, green: 0.02, blue: 0.06, alpha: 0.48).cgColor
    )
    cg.addPath(prismPath)
    cg.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Prism top-to-bottom pearl glass sheen
    cg.saveGState()
    cg.addPath(prismPath)
    cg.clip()
    let prismColors = [
        NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.98).cgColor,
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 1.00, alpha: 0.88).cgColor
    ] as CFArray
    if let prismGrad = CGGradient(colorsSpace: colorSpace, colors: prismColors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            prismGrad,
            start: CGPoint(x: prismCenter.x, y: prismCenter.y + prismRadius),
            end: CGPoint(x: prismCenter.x, y: prismCenter.y - prismRadius),
            options: []
        )
    }
    cg.restoreGState()

    cg.restoreGState() // End squircle clip

    // Outer squircle crisp glass rim stroke
    cg.saveGState()
    cg.addPath(squirclePath)
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    cg.setLineWidth(max(1.0, size * 0.009))
    cg.strokePath()
    cg.restoreGState()

    return rep.representation(using: .png, properties: [:])
}

for spec in specs {
    guard let pngData = renderIcon(pixels: spec.pixels) else {
        fputs("Failed to render \(spec.filename)\n", stderr)
        exit(1)
    }
    let fileURL = outputDir.appendingPathComponent(spec.filename)
    try pngData.write(to: fileURL)
}

print("Generated iconset at \(outputDir.path)")
