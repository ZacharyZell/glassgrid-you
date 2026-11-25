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
5. **Website Sync, Release Log & Appcast Integrity**
   - Every pushed update that adds, changes, or fixes user-facing behavior MUST update `glassgridyou.com` under `docs/` (`docs/index.html`, `docs/styles.css`, `docs/privacy.html`, `docs/terms.html`, and `docs/screenshots/` when UI, services, shortcuts, or privacy boundaries change) and prepend or update a structured Release Log entry in `docs/changelog.html` showing exact differences (`Added`, `Changed`, `Fixed`, `Security & Privacy`) relative to the previous version.
   - Maintain strict version honesty: clearly distinguish **Preview · Source (`main`)** changes from the **Latest Signed & Notarized `.dmg`** until a notarized installer is actually published. Never fabricate or hand-edit `docs/appcast.xml` `<item>` entries, `sparkle:edSignature`, or byte `length` before a real signed & notarized `.dmg` is produced by `./scripts/release-dmg.sh` and `sign_update`.
   - Keep `docs/` strictly zero-JS, zero-cookie, zero-tracker, zero-external-font, link only verified GitHub commits or tags (never nonexistent tags), and verify desktop (`1440px`), tablet (`900px`), and mobile (`390px`) layouts before pushing.
