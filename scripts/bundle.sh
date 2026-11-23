#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="GlassGrid You"
EXECUTABLE_NAME="GlassGridYou"
BUNDLE_ID="com.glassgridyou.mac"
APP_VERSION="${APP_VERSION:-1.1.0}"
APP_BUILD="${APP_BUILD:-2}"
SKIP_INSTALL="${SKIP_INSTALL:-0}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/ZacharyZell/glassgrid-you/main/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ENTITLEMENTS_PATH="$ROOT_DIR/scripts/entitlements.plist"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "==> Building release binary..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
RELEASE_BIN="$BIN_DIR/YouTubeMac"

if [[ ! -f "$RELEASE_BIN" ]]; then
    echo "Error: Release binary not found at $RELEASE_BIN" >&2
    exit 1
fi

SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -path "*/Sparkle.xcframework/macos-*/Sparkle.framework" -type d -print -quit 2>/dev/null || true)"
if [[ -z "$SPARKLE_FRAMEWORK" || ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found under $ROOT_DIR/.build/artifacts" >&2
    exit 1
fi

echo "==> Preparing .app bundle structure (v$APP_VERSION, build $APP_BUILD)..."
rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"

echo "==> Generating macOS Liquid Glass app icon..."
swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Copying executable, Sparkle.framework, and metadata..."
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

# Preserve Sparkle.framework internal Versions/Current symlinks via ditto.
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Ensure @executable_path/../Frameworks rpath is present BEFORE signing (never mutate Mach-O post-sign).
if ! otool -l "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
fi

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

SPARKLE_PLIST_ENTRIES=""
if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    SPARKLE_PLIST_ENTRIES="    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.video</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
$SPARKLE_PLIST_ENTRIES
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>glassgridyou</string>
                <string>youtubemac</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Open in GlassGrid You</string>
            </dict>
            <key>NSMessage</key>
            <string>openYouTubeURLService</string>
            <key>NSPortName</key>
            <string>$EXECUTABLE_NAME</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
                <string>NSURLPboardType</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> Signing embedded Sparkle.framework and app bundle strictly inside-out..."
xattr -cr "$APP_BUNDLE"

BASE_SIGN_ARGS=(--force)
if [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
    BASE_SIGN_ARGS+=(--options runtime)
fi
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    BASE_SIGN_ARGS+=(--timestamp)
fi

sign_item() {
    local target="$1"
    shift
    if [[ -e "$target" ]]; then
        codesign "${BASE_SIGN_ARGS[@]}" "$@" --sign "$CODESIGN_IDENTITY" "$target"
    fi
}

SPARKLE_DST="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="$SPARKLE_DST/Versions/B"

# 1. XPC Services (preserve Sparkle's built-in entitlements on Downloader.xpc)
sign_item "$SPARKLE_VER/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
sign_item "$SPARKLE_VER/XPCServices/Installer.xpc"

# 2. Nested updater binaries & helper app
sign_item "$SPARKLE_VER/Autoupdate"
sign_item "$SPARKLE_VER/Updater.app"

# 3. Sparkle.framework bundle itself
sign_item "$SPARKLE_DST"

# 4. Top-level app bundle (with minimal Hardened Runtime entitlements when enabled; never --deep)
if [[ "$ENABLE_HARDENED_RUNTIME" == "1" && -f "$ENTITLEMENTS_PATH" ]]; then
    sign_item "$APP_BUNDLE" --entitlements "$ENTITLEMENTS_PATH"
else
    sign_item "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if ! otool -L "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME" | grep -q "@rpath/Sparkle.framework"; then
    echo "Error: Executable does not link @rpath/Sparkle.framework" >&2
    exit 1
fi

if [[ "$SKIP_INSTALL" == "1" ]]; then
    echo "==> Built signed bundle at $APP_BUNDLE (SKIP_INSTALL=1)"
    exit 0
fi

echo "==> Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
ditto "$APP_BUNDLE" "$INSTALL_PATH"
touch "$INSTALL_PATH"
codesign --verify --deep --strict "$INSTALL_PATH"

echo "==> Successfully installed $INSTALL_PATH"
