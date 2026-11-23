# GlassGrid You Engineering Invariants

When modifying this repository:

1. **Performance & WebKit Stability**
   - Swift 6 strict concurrency with zero warnings/errors in debug and release.
   - Zero CSS `:has(` selectors, zero `MutationObserver`, zero `AudioContext` (`WebAudio`), zero static `ytInitialPlayerResponse`, and zero `evaluateJavaScript` feedback loops.
   - Preserve 4K 60fps HDR10 playback and hybrid WebKit DRM compatibility (YouTube TV / Primetime Channels).
2. **Single Permanent WebView Host & Fullscreen Safety**
   - Keep `TabWebViewHost` permanently mounted (never swap across SwiftUI `if/else`).
   - Never mutate `TabWebViewHost` subviews, frames, or layers while any hosted `WKWebView.fullscreenState != .notInFullscreen`.
3. **macOS Windowing & Liquid Glass UX**
   - Keep `isMovableByWindowBackground = false` so video scrubber dragging never moves windows; use explicit `WindowDragNSView` (`acceptsFirstMouse -> true`, `performDrag(with:)`).
   - Keep main windows on an empty `.unified` `NSToolbar` (`titlebarSeparatorStyle = .none`, `CommandGroup(replacing: .toolbar) {}`) with shared `WindowChromeLayout` constants so macOS traffic lights sit cleanly inside the floating sidebar's rounded corner arc on the same `26pt` vertical axis as the sidebar toggle and header controls (verified across Expanded, Collapsed, and Native Fullscreen).
   - Auto Mini-Player on app switch must respect real window occlusion (`WindowOcclusionCalculator`) so Split Screen / side-by-side windows stay docked.
   - Use native macOS 26/27 Liquid Glass (`.glassEffect` / `GlassEffectContainer` guarded by `#if compiler(>=6.2)`) with a clean macOS 14–15 `.regularMaterial` fallback, verified in both Day (Light) and Night (Dark) modes.
4. **Live Verification & 1:1 Chrome QA**
   - Actively verify `/Applications/GlassGrid You.app` (real window transitions, drags, theme switches, Multiview, Command Palette, multi-window) before shipping; run `swift test`, `scripts/verify-chrome.swift` (live `standardWindowButton` geometry + 1:1 cropped chrome close-ups inspected directly at Gate 2), `./scripts/bundle.sh`, and `codesign --verify --deep --strict "/Applications/GlassGrid You.app"`.
