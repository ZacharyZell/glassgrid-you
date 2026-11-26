import AppKit
import Observation
import QuartzCore
import SwiftUI
import YouTubeMacCore

// MARK: - Chrome Ambient Glow Overlay

/// Subtle, chrome-only seasonal radial/linear wash layered behind header and sidebar Liquid Glass.
/// Automatically yields to `Classic` theme, `accessibilityReduceTransparency`, and fullscreen/focus pauses.
struct HolidayAmbientGlowView: View {
    let surface: HolidayEffectSurface
    let isPaused: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(surface: HolidayEffectSurface, isPaused: Bool) {
        self.surface = surface
        self.isPaused = isPaused
    }

    var body: some View {
        let palette = AppleTheme.activeHolidayPalette
        if palette.id == .classic || reduceTransparency || isPaused {
            EmptyView()
        } else {
            let glowColor = AppleTheme.ambientGlow
            let peakOpacity = colorScheme == .dark ? 0.19 : 0.13
            let midOpacity = colorScheme == .dark ? 0.08 : 0.05

            ZStack {
                if surface == .headerBar {
                    RadialGradient(
                        colors: [
                            glowColor.opacity(peakOpacity),
                            glowColor.opacity(midOpacity),
                            .clear
                        ],
                        center: UnitPoint(x: 0.14, y: 0.0),
                        startRadius: 8,
                        endRadius: 340
                    )

                    LinearGradient(
                        colors: [
                            glowColor.opacity(colorScheme == .dark ? 0.17 : 0.11),
                            glowColor.opacity(colorScheme == .dark ? 0.06 : 0.03),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    RadialGradient(
                        colors: [
                            glowColor.opacity(peakOpacity),
                            glowColor.opacity(midOpacity),
                            .clear
                        ],
                        center: UnitPoint(x: 0.18, y: 0.08),
                        startRadius: 6,
                        endRadius: 240
                    )

                    LinearGradient(
                        colors: [
                            glowColor.opacity(colorScheme == .dark ? 0.17 : 0.11),
                            glowColor.opacity(colorScheme == .dark ? 0.05 : 0.03),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Core Animation Particle Sprite Cache

private struct SpriteCacheKey: Hashable {
    let shape: HolidayParticleShape
    let scaleTenths: Int
}

/// Renders crisp pure-white `#FFFFFF` vector `CGImage` sprites (`32×32pt` at `backingScale`) once per `(shape, scale)`
/// so `CAEmitterCell.color` tints them cleanly for Day and Night contrast without runtime CoreGraphics churn.
@MainActor
private enum HolidayParticleSpriteCache {
    private static var cache: [SpriteCacheKey: CGImage] = [:]

    static func sprite(for shape: HolidayParticleShape, backingScale: CGFloat) -> CGImage? {
        guard shape != .none else { return nil }
        let effectiveScale = max(1.0, backingScale)
        let key = SpriteCacheKey(
            shape: shape,
            scaleTenths: Int((effectiveScale * 10.0).rounded())
        )
        if let existing = cache[key] {
            return existing
        }
        guard let rendered = renderSprite(shape: shape, backingScale: effectiveScale) else {
            return nil
        }
        cache[key] = rendered
        return rendered
    }

    private static func renderSprite(shape: HolidayParticleShape, backingScale: CGFloat) -> CGImage? {
        let logicalSize: CGFloat = 32.0
        let pixelDimension = max(32, Int((logicalSize * backingScale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelDimension,
            height: pixelDimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let scaleFactor = CGFloat(pixelDimension) / logicalSize
        // Flip to top-left origin matching `HolidayEmitterNSView.isFlipped == true`.
        ctx.translateBy(x: 0, y: CGFloat(pixelDimension))
        ctx.scaleBy(x: scaleFactor, y: -scaleFactor)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ctx.setFillColor(white)
        ctx.setStrokeColor(white)

        switch shape {
        case .none:
            return nil
        case .autumnLeaf:
            drawAutumnLeaf(in: ctx)
        case .snowflake:
            drawSnowflake(in: ctx)
        case .confettiStar:
            drawConfettiStar(in: ctx)
        case .heart:
            drawHeart(in: ctx)
        case .shamrock:
            drawShamrock(in: ctx)
        case .blossomPetal:
            drawBlossomPetal(in: ctx)
        case .starSpark:
            drawStarSpark(in: ctx)
        case .batEmber:
            drawBatEmber(in: ctx)
        }

        return ctx.makeImage()
    }

    private static func drawAutumnLeaf(in ctx: CGContext) {
        let path = CGMutablePath()
        // Asymmetric classic 5-lobe maple leaf silhouette that reads crisply even at 11pt rotation.
        path.move(to: CGPoint(x: 16.0, y: 2.8))
        // Top center lobe (left -> tip -> right)
        path.addLine(to: CGPoint(x: 18.0, y: 8.6))
        path.addLine(to: CGPoint(x: 20.4, y: 7.6))
        path.addLine(to: CGPoint(x: 19.6, y: 12.6))
        // Right upper lobe
        path.addLine(to: CGPoint(x: 25.4, y: 9.2))
        path.addLine(to: CGPoint(x: 24.8, y: 12.2))
        path.addLine(to: CGPoint(x: 29.0, y: 12.8))
        path.addLine(to: CGPoint(x: 26.2, y: 15.8))
        path.addLine(to: CGPoint(x: 27.2, y: 17.8))
        path.addLine(to: CGPoint(x: 20.6, y: 19.6))
        // Right lower base lobe
        path.addLine(to: CGPoint(x: 24.4, y: 22.8))
        path.addLine(to: CGPoint(x: 17.0, y: 22.4))
        // Stem
        path.addLine(to: CGPoint(x: 16.9, y: 29.5))
        path.addLine(to: CGPoint(x: 15.1, y: 29.5))
        path.addLine(to: CGPoint(x: 15.0, y: 22.4))
        // Left lower base lobe
        path.addLine(to: CGPoint(x: 7.6, y: 22.8))
        path.addLine(to: CGPoint(x: 11.4, y: 19.6))
        // Left upper lobe
        path.addLine(to: CGPoint(x: 4.8, y: 17.8))
        path.addLine(to: CGPoint(x: 5.8, y: 15.8))
        path.addLine(to: CGPoint(x: 3.0, y: 12.8))
        path.addLine(to: CGPoint(x: 7.2, y: 12.2))
        path.addLine(to: CGPoint(x: 6.6, y: 9.2))
        path.addLine(to: CGPoint(x: 12.4, y: 12.6))
        path.addLine(to: CGPoint(x: 11.6, y: 7.6))
        path.addLine(to: CGPoint(x: 14.0, y: 8.6))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func drawSnowflake(in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 16.0, y: 16.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for i in 0..<6 {
            ctx.saveGState()
            ctx.rotate(by: CGFloat(i) * (.pi / 3.0))

            // Main radial crystal spine
            ctx.setLineWidth(1.9)
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: -12.2))
            ctx.strokePath()

            // Outer chevron branch
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: -3.2, y: -9.8))
            ctx.addLine(to: CGPoint(x: 0, y: -7.2))
            ctx.addLine(to: CGPoint(x: 3.2, y: -9.8))
            ctx.strokePath()

            // Inner chevron branch
            ctx.move(to: CGPoint(x: -2.4, y: -6.0))
            ctx.addLine(to: CGPoint(x: 0, y: -4.0))
            ctx.addLine(to: CGPoint(x: 2.4, y: -6.0))
            ctx.strokePath()

            ctx.restoreGState()
        }

        ctx.fillEllipse(in: CGRect(x: -2.0, y: -2.0, width: 4.0, height: 4.0))
        ctx.restoreGState()
    }

    private static func drawConfettiStar(in ctx: CGContext) {
        // Faceted 4-point celebration star + small accompanying diamond confetti accent.
        let star = CGMutablePath()
        star.move(to: CGPoint(x: 15.0, y: 4.0))
        star.addQuadCurve(to: CGPoint(x: 26.0, y: 15.0), control: CGPoint(x: 16.8, y: 13.2))
        star.addQuadCurve(to: CGPoint(x: 15.0, y: 26.0), control: CGPoint(x: 16.8, y: 16.8))
        star.addQuadCurve(to: CGPoint(x: 4.0, y: 15.0), control: CGPoint(x: 13.2, y: 16.8))
        star.addQuadCurve(to: CGPoint(x: 15.0, y: 4.0), control: CGPoint(x: 13.2, y: 13.2))
        star.closeSubpath()

        ctx.addPath(star)
        ctx.fillPath()

        let ribbon = CGMutablePath()
        ribbon.move(to: CGPoint(x: 24.5, y: 21.5))
        ribbon.addLine(to: CGPoint(x: 27.5, y: 24.5))
        ribbon.addLine(to: CGPoint(x: 24.5, y: 27.5))
        ribbon.addLine(to: CGPoint(x: 21.5, y: 24.5))
        ribbon.closeSubpath()
        ctx.addPath(ribbon)
        ctx.fillPath()
    }

    private static func drawHeart(in ctx: CGContext) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16.0, y: 26.5))
        path.addCurve(
            to: CGPoint(x: 4.5, y: 12.2),
            control1: CGPoint(x: 10.2, y: 22.2),
            control2: CGPoint(x: 4.5, y: 17.6)
        )
        path.addCurve(
            to: CGPoint(x: 16.0, y: 10.0),
            control1: CGPoint(x: 4.5, y: 6.4),
            control2: CGPoint(x: 12.4, y: 5.4)
        )
        path.addCurve(
            to: CGPoint(x: 27.5, y: 12.2),
            control1: CGPoint(x: 19.6, y: 5.4),
            control2: CGPoint(x: 27.5, y: 6.4)
        )
        path.addCurve(
            to: CGPoint(x: 16.0, y: 26.5),
            control1: CGPoint(x: 27.5, y: 17.6),
            control2: CGPoint(x: 21.8, y: 22.2)
        )
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func drawShamrock(in ctx: CGContext) {
        ctx.saveGState()
        // Three rounded heart-like clover leaflets arranged at 120° around (16, 14.5).
        let center = CGPoint(x: 16.0, y: 14.5)
        let angles: [CGFloat] = [-.pi / 2.0, .pi / 6.0, 5.0 * .pi / 6.0]
        for angle in angles {
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: angle + .pi / 2.0)

            let lobe = CGMutablePath()
            lobe.move(to: CGPoint(x: 0, y: 0))
            lobe.addCurve(
                to: CGPoint(x: -5.2, y: -7.5),
                control1: CGPoint(x: -2.0, y: -2.2),
                control2: CGPoint(x: -5.8, y: -4.4)
            )
            lobe.addCurve(
                to: CGPoint(x: 0, y: -8.6),
                control1: CGPoint(x: -4.4, y: -11.0),
                control2: CGPoint(x: -1.0, y: -11.0)
            )
            lobe.addCurve(
                to: CGPoint(x: 5.2, y: -7.5),
                control1: CGPoint(x: 1.0, y: -11.0),
                control2: CGPoint(x: 4.4, y: -11.0)
            )
            lobe.addCurve(
                to: CGPoint(x: 0, y: 0),
                control1: CGPoint(x: 5.8, y: -4.4),
                control2: CGPoint(x: 2.0, y: -2.2)
            )
            lobe.closeSubpath()
            ctx.addPath(lobe)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Curved shamrock stem
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 16.0, y: 15.0))
        ctx.addQuadCurve(to: CGPoint(x: 18.8, y: 28.0), control: CGPoint(x: 15.5, y: 23.0))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawBlossomPetal(in ctx: CGContext) {
        // Curved sakura blossom petal with characteristic soft cleft at the tip.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 15.8, y: 27.0))
        path.addCurve(
            to: CGPoint(x: 8.0, y: 8.6),
            control1: CGPoint(x: 8.2, y: 22.0),
            control2: CGPoint(x: 5.6, y: 14.5)
        )
        path.addQuadCurve(to: CGPoint(x: 14.2, y: 6.4), control: CGPoint(x: 10.6, y: 4.5))
        path.addLine(to: CGPoint(x: 16.0, y: 9.2))
        path.addLine(to: CGPoint(x: 17.8, y: 6.4))
        path.addQuadCurve(to: CGPoint(x: 24.0, y: 8.6), control: CGPoint(x: 21.4, y: 4.5))
        path.addCurve(
            to: CGPoint(x: 15.8, y: 27.0),
            control1: CGPoint(x: 26.4, y: 14.5),
            control2: CGPoint(x: 23.8, y: 22.0)
        )
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()
    }

    private static func drawStarSpark(in ctx: CGContext) {
        // Sharp 4-point starlight sparkle + subtle satellite spark dot.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16.0, y: 3.0))
        path.addQuadCurve(to: CGPoint(x: 29.0, y: 16.0), control: CGPoint(x: 17.6, y: 14.4))
        path.addQuadCurve(to: CGPoint(x: 16.0, y: 29.0), control: CGPoint(x: 17.6, y: 17.6))
        path.addQuadCurve(to: CGPoint(x: 3.0, y: 16.0), control: CGPoint(x: 14.4, y: 17.6))
        path.addQuadCurve(to: CGPoint(x: 16.0, y: 3.0), control: CGPoint(x: 14.4, y: 14.4))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()

        ctx.fillEllipse(in: CGRect(x: 24.5, y: 5.0, width: 3.2, height: 3.2))
    }

    private static func drawBatEmber(in ctx: CGContext) {
        // Stylized Halloween bat silhouette with pointed ears and scalloped wings.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16.0, y: 11.5))
        // Right ear & wing
        path.addLine(to: CGPoint(x: 18.2, y: 8.2))
        path.addLine(to: CGPoint(x: 19.2, y: 12.2))
        path.addQuadCurve(to: CGPoint(x: 29.5, y: 10.6), control: CGPoint(x: 24.5, y: 9.2))
        path.addQuadCurve(to: CGPoint(x: 24.8, y: 18.4), control: CGPoint(x: 28.0, y: 15.4))
        path.addQuadCurve(to: CGPoint(x: 20.6, y: 19.2), control: CGPoint(x: 22.8, y: 17.2))
        path.addQuadCurve(to: CGPoint(x: 16.0, y: 23.8), control: CGPoint(x: 18.2, y: 19.8))
        // Left wing & ear
        path.addQuadCurve(to: CGPoint(x: 11.4, y: 19.2), control: CGPoint(x: 13.8, y: 19.8))
        path.addQuadCurve(to: CGPoint(x: 7.2, y: 18.4), control: CGPoint(x: 9.2, y: 17.2))
        path.addQuadCurve(to: CGPoint(x: 2.5, y: 10.6), control: CGPoint(x: 4.0, y: 15.4))
        path.addQuadCurve(to: CGPoint(x: 12.8, y: 12.2), control: CGPoint(x: 7.5, y: 9.2))
        path.addLine(to: CGPoint(x: 13.8, y: 8.2))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.fillPath()
    }
}

// MARK: - Zero-CPU Core Animation Particle View

/// Chrome-scoped Core Animation `CAEmitterLayer` overlay driven off-main-thread by WindowServer.
/// Zero SwiftUI animation ticks (`TimelineView`), zero hit-testing interception, and zero cell rebuild churn.
struct HolidayParticlesView: View {
    let palette: HolidayThemePalette
    let intensity: HolidayEffectsIntensity
    let surface: HolidayEffectSurface
    let isHardStopped: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        palette: HolidayThemePalette,
        intensity: HolidayEffectsIntensity,
        surface: HolidayEffectSurface,
        isHardStopped: Bool
    ) {
        self.palette = palette
        self.intensity = intensity
        self.surface = surface
        self.isHardStopped = isHardStopped
    }

    var body: some View {
        let effectiveHardStop = isHardStopped
            || reduceMotion
            || intensity == .off
            || palette.particleShape == .none

        HolidayEmitterRepresentable(
            palette: palette,
            intensity: intensity,
            surface: surface,
            isDark: colorScheme == .dark,
            isHardStopped: effectiveHardStop
        )
        .allowsHitTesting(false)
    }
}

private struct HolidayEmitterRepresentable: NSViewRepresentable {
    let palette: HolidayThemePalette
    let intensity: HolidayEffectsIntensity
    let surface: HolidayEffectSurface
    let isDark: Bool
    let isHardStopped: Bool

    func makeNSView(context: Context) -> HolidayEmitterNSView {
        let view = HolidayEmitterNSView(frame: .zero)
        view.applyConfiguration(
            palette: palette,
            intensity: intensity,
            surface: surface,
            isDark: isDark,
            isHardStopped: isHardStopped
        )
        return view
    }

    func updateNSView(_ nsView: HolidayEmitterNSView, context: Context) {
        nsView.applyConfiguration(
            palette: palette,
            intensity: intensity,
            surface: surface,
            isDark: isDark,
            isHardStopped: isHardStopped
        )
    }
}

@MainActor
final class HolidayEmitterNSView: NSView {
    private struct CellConfigKey: Equatable {
        let paletteID: HolidayThemeID
        let intensity: HolidayEffectsIntensity
        let isDark: Bool
        let backingScaleTenths: Int
        let surface: HolidayEffectSurface
    }

    private var currentPalette: HolidayThemePalette = HolidayThemeCatalog.classic
    private var currentIntensity: HolidayEffectsIntensity = .off
    private var currentSurface: HolidayEffectSurface = .headerBar
    private var currentIsDark: Bool = false
    private var currentIsHardStopped: Bool = true
    private var appliedCellKey: CellConfigKey?

    private var isWindowOccluded: Bool = false
    private var isWindowMiniaturized: Bool = false
    private var isAppInactive: Bool = false

    // Stored as nonisolated(unsafe) strictly so `deinit` can unconditionally remove all
    // NotificationCenter tokens under Swift 6 strict concurrency.
    nonisolated(unsafe) private var windowObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var appObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }

    private var emitterLayer: CAEmitterLayer? {
        layer as? CAEmitterLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let center = NotificationCenter.default
        for token in windowObservers {
            center.removeObserver(token)
        }
        for token in appObservers {
            center.removeObserver(token)
        }
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAEmitterLayer()
        layer.masksToBounds = true
        layer.birthRate = 0
        return layer
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updateEmitterGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reconcileEmitterState(forceGeometry: true)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        detachWindowObservers()
        detachAppObservers()
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            isWindowOccluded = true
            reconcileEmitterState(forceGeometry: false)
            return
        }

        attachWindowObservers(to: window)
        attachAppObservers()

        isWindowOccluded = !window.occlusionState.contains(.visible)
        isWindowMiniaturized = window.isMiniaturized
        isAppInactive = !NSApplication.shared.isActive

        reconcileEmitterState(forceGeometry: true)
    }

    func applyConfiguration(
        palette: HolidayThemePalette,
        intensity: HolidayEffectsIntensity,
        surface: HolidayEffectSurface,
        isDark: Bool,
        isHardStopped: Bool
    ) {
        currentPalette = palette
        currentIntensity = intensity
        currentSurface = surface
        currentIsDark = isDark
        currentIsHardStopped = isHardStopped
        reconcileEmitterState(forceGeometry: false)
    }

    // MARK: - Window & App Lifecycle Observers

    private func attachWindowObservers(to window: NSWindow) {
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let win = self.window else { return }
                    self.isWindowOccluded = !win.occlusionState.contains(.visible)
                    self.reconcileEmitterState(forceGeometry: false)
                }
            },
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isWindowMiniaturized = true
                    self.reconcileEmitterState(forceGeometry: false)
                }
            },
            center.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isWindowMiniaturized = false
                    if let win = self.window {
                        self.isWindowOccluded = !win.occlusionState.contains(.visible)
                    }
                    self.reconcileEmitterState(forceGeometry: false)
                }
            }
        ]
    }

    private func detachWindowObservers() {
        let center = NotificationCenter.default
        for token in windowObservers {
            center.removeObserver(token)
        }
        windowObservers.removeAll()
    }

    private func attachAppObservers() {
        let center = NotificationCenter.default
        appObservers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isAppInactive = true
                    self.reconcileEmitterState(forceGeometry: false)
                }
            },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isAppInactive = false
                    if let win = self.window {
                        self.isWindowOccluded = !win.occlusionState.contains(.visible)
                        self.isWindowMiniaturized = win.isMiniaturized
                    }
                    self.reconcileEmitterState(forceGeometry: false)
                }
            }
        ]
    }

    private func detachAppObservers() {
        let center = NotificationCenter.default
        for token in appObservers {
            center.removeObserver(token)
        }
        appObservers.removeAll()
    }

    // MARK: - Emitter Reconciliation

    private func reconcileEmitterState(forceGeometry: Bool) {
        guard let emitterLayer else { return }

        let hardStop = currentIsHardStopped
            || currentIntensity == .off
            || currentPalette.particleShape == .none

        if hardStop {
            if emitterLayer.birthRate != 0 || emitterLayer.emitterCells != nil || appliedCellKey != nil {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                emitterLayer.birthRate = 0
                emitterLayer.emitterCells = nil
                CATransaction.commit()
                appliedCellKey = nil
            }
            return
        }

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let scaleTenths = Int((max(1.0, backingScale) * 10.0).rounded())
        let targetKey = CellConfigKey(
            paletteID: currentPalette.id,
            intensity: currentIntensity,
            isDark: currentIsDark,
            backingScaleTenths: scaleTenths,
            surface: currentSurface
        )

        let cellsChanged = appliedCellKey != targetKey
        if cellsChanged {
            let cells = buildEmitterCells(
                palette: currentPalette,
                intensity: currentIntensity,
                surface: currentSurface,
                isDark: currentIsDark,
                backingScale: backingScale
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitterLayer.emitterCells = cells
            CATransaction.commit()
            appliedCellKey = targetKey
        }

        if cellsChanged || forceGeometry {
            updateEmitterGeometry()
        }

        let shouldPause = window == nil || isWindowOccluded || isWindowMiniaturized || isAppInactive
        if shouldPause {
            if emitterLayer.birthRate != 0 {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                emitterLayer.birthRate = 0
                CATransaction.commit()
            }
        } else if emitterLayer.birthRate == 0 || cellsChanged {
            // Reset `beginTime` immediately before enabling `birthRate` so WindowServer never
            // emits an accumulated backlog burst across paused duration.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitterLayer.beginTime = CACurrentMediaTime()
            emitterLayer.birthRate = 1.0
            CATransaction.commit()
        }
    }

    private func updateEmitterGeometry() {
        guard let emitterLayer else { return }
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let width = max(1.0, bounds.width)
        let emitterY: CGFloat = currentPalette.risesUpward ? (bounds.height + 6.0) : -6.0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitterLayer.contentsScale = backingScale
        emitterLayer.emitterShape = .line
        emitterLayer.emitterMode = .outline
        emitterLayer.emitterPosition = CGPoint(x: width / 2.0, y: emitterY)
        emitterLayer.emitterSize = CGSize(width: width, height: 1.0)
        CATransaction.commit()
    }

    private func buildEmitterCells(
        palette: HolidayThemePalette,
        intensity: HolidayEffectsIntensity,
        surface: HolidayEffectSurface,
        isDark: Bool,
        backingScale: CGFloat
    ) -> [CAEmitterCell] {
        guard let sprite = HolidayParticleSpriteCache.sprite(
            for: palette.particleShape,
            backingScale: backingScale
        ) else {
            return []
        }

        let hexes = isDark ? palette.particleHexesDark : palette.particleHexesLight
        guard !hexes.isEmpty else { return [] }

        let totalBirthRate: Float
        switch (surface, intensity) {
        case (_, .off):
            return []
        case (.headerBar, .subtle):
            totalBirthRate = 2.4
        case (.sidebar, .subtle):
            totalBirthRate = 2.2
        case (.headerBar, .festive):
            totalBirthRate = 5.8
        case (.sidebar, .festive):
            totalBirthRate = 5.6
        }

        let cellBirthRate = totalBirthRate / Float(hexes.count)
        let isHeader = surface == .headerBar
        let lifetime: Float = isHeader ? 2.6 : (intensity == .festive ? 5.2 : 6.0)
        let lifetimeRange: Float = isHeader ? 0.6 : 1.0

        let directionSign: CGFloat = palette.risesUpward ? -1.0 : 1.0
        let emissionAngle: CGFloat = palette.risesUpward ? -.pi / 2.0 : .pi / 2.0
        let velocity: CGFloat = isHeader ? 16.0 : 32.0
        let velocityRange: CGFloat = isHeader ? 6.0 : 14.0
        let yAccel: CGFloat = (isHeader ? 6.0 : 10.0) * directionSign

        let baseAlpha: CGFloat
        switch (isDark, intensity) {
        case (false, .subtle): baseAlpha = 0.48
        case (false, .festive): baseAlpha = 0.62
        case (true, .subtle): baseAlpha = 0.54
        case (true, .festive): baseAlpha = 0.70
        case (_, .off): baseAlpha = 0.0
        }

        let baseScale: CGFloat = isHeader ? 0.34 : 0.40
        let keepMostlyUpright = (palette.particleShape == .heart || palette.particleShape == .starSpark)

        return hexes.enumerated().map { index, hex in
            let cell = CAEmitterCell()
            cell.name = "\(palette.id.rawValue)-\(index)"
            cell.contents = sprite
            cell.birthRate = cellBirthRate
            cell.lifetime = lifetime
            cell.lifetimeRange = lifetimeRange
            cell.emissionLongitude = emissionAngle
            cell.emissionRange = .pi / 8.0
            cell.velocity = velocity
            cell.velocityRange = velocityRange
            cell.yAcceleration = yAccel
            cell.xAcceleration = (index.isMultiple(of: 2) ? 1.0 : -1.0) * (isHeader ? 4.0 : 6.0)
            cell.scale = baseScale
            cell.scaleRange = 0.12
            cell.scaleSpeed = -0.012
            cell.spin = keepMostlyUpright ? 0.0 : (index.isMultiple(of: 2) ? 0.24 : -0.24)
            cell.spinRange = keepMostlyUpright ? 0.25 : 0.60

            let tinted = resolvedParticleNSColor(hex: hex, alpha: baseAlpha)
            cell.color = tinted.cgColor
            cell.alphaRange = 0.14
            cell.alphaSpeed = -Float(baseAlpha) / max(1.0, lifetime) * 0.85

            return cell
        }
    }

    private func resolvedParticleNSColor(hex: String, alpha: CGFloat) -> NSColor {
        guard let (r, g, b) = DesignSystemMetrics.rgbComponents(fromHex: hex) else {
            return NSColor.white.withAlphaComponent(alpha)
        }
        return NSColor(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Holiday Theme Switcher Popover

/// Keeps an `NSPopover`'s backing `NSWindow` appearance locked to the app's resolved Day/Night state.
private struct PopoverAppearanceSyncView: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> PopoverAppearanceHostNSView {
        let view = PopoverAppearanceHostNSView()
        view.isDark = isDark
        return view
    }

    func updateNSView(_ nsView: PopoverAppearanceHostNSView, context: Context) {
        nsView.isDark = isDark
        nsView.syncWindowAppearance()
    }
}

@MainActor
private final class PopoverAppearanceHostNSView: NSView {
    var isDark: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncWindowAppearance()
    }

    func syncWindowAppearance() {
        guard let window else { return }
        let targetName: NSAppearance.Name = isDark ? .darkAqua : .aqua
        if window.appearance?.name != targetName {
            window.appearance = NSAppearance(named: targetName)
        }
    }
}

/// Crisp `312pt` Inter Liquid Glass popover for inspecting today's calendar holiday,
/// pinning any of the 9 seasonal WCAG 2.1 AA palettes, and configuring ambient effects.
struct HolidayThemePopoverView: View {
    @Bindable var controller: AppController
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(controller: AppController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
    }

    private var isPopoverDark: Bool {
        switch controller.settings.appearance {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    private var primaryInk: Color {
        AppleTheme.color(hex: isPopoverDark ? "#F5F5F7" : "#161619")
    }

    private var secondaryInk: Color {
        AppleTheme.color(hex: isPopoverDark ? DesignSystemMetrics.textSecondaryDark : DesignSystemMetrics.textSecondaryLight)
    }

    private var mutedInk: Color {
        AppleTheme.color(hex: isPopoverDark ? DesignSystemMetrics.textMutedDark : DesignSystemMetrics.textMutedLight)
    }

    private var accentInk: Color {
        AppleTheme.color(hex: isPopoverDark ? activePalette.accentTextDark : activePalette.accentTextLight)
    }

    private var subtleFill: Color {
        primaryInk.opacity(isPopoverDark ? 0.10 : 0.07)
    }

    private var activePalette: HolidayThemePalette {
        controller.settings.activeHolidayPalette
    }

    private var calendarPalette: HolidayThemePalette {
        HolidayThemeCatalog.palette(for: controller.settings.calendarHolidayThemeID)
    }

    private var calendarStatusCaption: String {
        if controller.settings.holidayThemeSelection == .auto {
            if calendarPalette.id == .classic {
                return "Seasonal Calendar · Classic today"
            }
            return "Auto today · \(calendarPalette.displayName)"
        }
        if calendarPalette.id == .classic {
            return "Manual preset · Classic day"
        }
        return "Manual preset · Today is \(calendarPalette.shortName)"
    }

    private var autoRowTitle: String {
        let suffix = calendarPalette.id == .classic ? "Classic" : calendarPalette.shortName
        return "Auto · \(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Active Holiday Header
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(accentInk.opacity(0.14))
                        .frame(width: 28, height: 28)
                    Image(systemName: activePalette.symbolName)
                        .font(AppIconFont.toolbar(weight: .semibold))
                        .foregroundStyle(accentInk)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(activePalette.displayName)
                        .font(AppFont.body(weight: .semibold))
                        .foregroundStyle(primaryInk)
                        .lineLimit(1)
                    Text(calendarStatusCaption)
                        .font(AppFont.caption)
                        .foregroundStyle(secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.xs)
            }

            Divider()

            // Auto (Calendar) Row
            let isAutoSelected = controller.settings.holidayThemeSelection == .auto
            Button {
                controller.setHolidayThemeSelection(.auto, showFeedback: true)
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "calendar")
                        .font(AppIconFont.md(weight: .semibold))
                        .foregroundStyle(isAutoSelected ? accentInk : secondaryInk)
                        .frame(width: 18, alignment: .center)

                    Text(autoRowTitle)
                        .font(AppFont.callout(weight: isAutoSelected ? .semibold : .regular))
                        .foregroundStyle(primaryInk)
                        .lineLimit(1)

                    Spacer(minLength: AppSpacing.xs)

                    if isAutoSelected {
                        Image(systemName: "checkmark")
                            .font(AppIconFont.xs(weight: .semibold))
                            .foregroundStyle(accentInk)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        .fill(isAutoSelected ? accentInk.opacity(0.12) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)

            // Scrollable 9-Palette List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: AppSpacing.xxs) {
                    ForEach(HolidayThemeCatalog.allPalettes, id: \.id) { palette in
                        paletteRow(palette)
                    }
                }
            }
            .frame(maxHeight: 248)

            Divider()

            // Bottom Ambient Effects Segmented Control + Accessibility Note
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Text("Ambient Effects")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(secondaryInk)

                    Spacer(minLength: AppSpacing.xs)

                    Text(activePalette.id == .classic ? "Classic" : activePalette.effectTitle)
                        .font(AppFont.micro(weight: .medium))
                        .foregroundStyle(mutedInk)
                }

                HStack(spacing: AppSpacing.xs) {
                    ForEach(HolidayEffectsIntensity.allCases) { option in
                        let isSelected = controller.settings.holidayEffectsIntensity == option
                        Button {
                            controller.setHolidayEffectsIntensity(option, showFeedback: true)
                        } label: {
                            Text(segmentLabel(for: option))
                                .font(AppFont.caption(weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.white : primaryInk)
                                .frame(maxWidth: .infinity)
                                .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(isSelected ? AppleTheme.color(hex: activePalette.accentFill) : subtleFill)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Chrome-only Core Animation effects pause in Fullscreen, Focus Mode, and Reduce Motion.")
                    .font(AppFont.micro(weight: .regular))
                    .foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 312)
        .background {
            PopoverAppearanceSyncView(isDark: isPopoverDark)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func paletteRow(_ palette: HolidayThemePalette) -> some View {
        let targetSelection = selection(for: palette.id)
        let isSelected = controller.settings.holidayThemeSelection == targetSelection
        let outerHex = palette.accentFill
        let innerHex = isPopoverDark ? palette.accentTextDark : palette.accentTextLight
        let badgeText = palette.particleShape == .none ? "Default" : palette.effectTitle

        Button {
            controller.setHolidayThemeSelection(targetSelection, showFeedback: true)
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Concentric holiday color swatch
                ZStack {
                    Circle()
                        .fill(AppleTheme.color(hex: outerHex))
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(AppleTheme.color(hex: innerHex))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.75), lineWidth: 0.75)
                        )
                }

                Text(palette.displayName)
                    .font(AppFont.callout(weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(primaryInk)
                    .lineLimit(1)

                Spacer(minLength: AppSpacing.xs)

                Text(badgeText)
                    .font(AppFont.micro(weight: .medium))
                    .foregroundStyle(secondaryInk)
                    .lineLimit(1)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(subtleFill)
                    )

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppIconFont.xs(weight: .semibold))
                        .foregroundStyle(accentInk)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .minHitTarget(28, shape: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(isSelected ? accentInk.opacity(0.12) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func segmentLabel(for intensity: HolidayEffectsIntensity) -> String {
        switch intensity {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .festive: return "Festive"
        }
    }

    private func selection(for id: HolidayThemeID) -> HolidayThemeSelection {
        switch id {
        case .classic: return .classic
        case .thanksgiving: return .thanksgiving
        case .winter: return .winter
        case .newYear: return .newYear
        case .valentines: return .valentines
        case .stPatricks: return .stPatricks
        case .springEaster: return .springEaster
        case .independence: return .independence
        case .halloween: return .halloween
        }
    }
}
