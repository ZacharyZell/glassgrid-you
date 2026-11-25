#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="GlassGrid You"
VERSION="1.2.0"
BUILD_NUMBER="5"
IDENTITY=""
NOTARY_PROFILE="GlassGridYouNotary"
AD_HOC="0"
SKIP_NOTARIZE="0"
OUTPUT_DIR="$ROOT_DIR/build/release"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://glassgridyou.com/appcast.xml}"

usage() {
    cat <<'EOF'
Usage: ./scripts/release-dmg.sh [options]

Builds, embeds Sparkle 2, signs inside-out (Hardened Runtime), packages, and optionally notarizes GlassGrid You as a macOS .dmg.

Options:
  --version <semver>             CFBundleShortVersionString (default: 1.2.0)
  --build <number>               CFBundleVersion (default: 5)
  --identity <name>              Codesigning identity (auto-detects "Developer ID Application" if omitted)
  --notary-profile <name>        notarytool Keychain profile name (default: GlassGridYouNotary)
  --sparkle-public-key <base64>  Optional Sparkle Ed25519 public key (SUPublicEDKey) for signed auto-updates
  --feed-url <https-url>         Optional Sparkle appcast SUFeedURL (default: https://glassgridyou.com/appcast.xml)
  --ad-hoc                       Use ad-hoc signing (implies --skip-notarize; for local dry-run testing)
  --skip-notarize                Skip notarytool submission, stapling, and Gatekeeper spctl checks
  --output-dir <path>            Output directory for .dmg and .sha256 (default: build/release)
  -h, --help                     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:?Missing value for --version}"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="${2:?Missing value for --build}"
            shift 2
            ;;
        --identity)
            IDENTITY="${2:?Missing value for --identity}"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:?Missing value for --notary-profile}"
            shift 2
            ;;
        --sparkle-public-key)
            SPARKLE_PUBLIC_ED_KEY="${2:?Missing value for --sparkle-public-key}"
            shift 2
            ;;
        --feed-url)
            SPARKLE_FEED_URL="${2:?Missing value for --feed-url}"
            shift 2
            ;;
        --ad-hoc)
            AD_HOC="1"
            SKIP_NOTARIZE="1"
            shift
            ;;
        --skip-notarize)
            SKIP_NOTARIZE="1"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?Missing value for --output-dir}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

ENTITLEMENTS_PATH="$ROOT_DIR/scripts/entitlements.plist"
if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
    echo "Error: Missing entitlements file at $ENTITLEMENTS_PATH" >&2
    exit 1
fi

if [[ "$AD_HOC" == "1" ]]; then
    SIGN_IDENTITY="-"
    echo "==> Dry-run mode: ad-hoc Hardened Runtime inside-out signing (notarization skipped)"
else
    if [[ -z "$IDENTITY" ]]; then
        IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/Developer ID Application:/ { print $2; exit }' || true)"
    fi
    if [[ -z "$IDENTITY" ]]; then
        cat >&2 <<'EOF'
Error: No "Developer ID Application" signing certificate found in your Keychain.

To sign and notarize a public release:
  1. Open Xcode -> Settings -> Accounts -> Manage Certificates -> "+" -> "Developer ID Application"
  2. Store notarization credentials via `xcrun notarytool store-credentials "GlassGridYouNotary" ...`
  3. See docs/RELEASING.md for the complete step-by-step release guide.

To test the .dmg packaging pipeline locally without a Developer ID certificate, run:
  ./scripts/release-dmg.sh --version 1.1.0 --ad-hoc --skip-notarize
EOF
        exit 1
    fi
    SIGN_IDENTITY="$IDENTITY"
    echo "==> Using signing identity: $SIGN_IDENTITY"
fi

echo "==> Assembling $APP_NAME.app (v$VERSION, build $BUILD_NUMBER) with Hardened Runtime + Sparkle 2..."
APP_VERSION="$VERSION" \
APP_BUILD="$BUILD_NUMBER" \
SKIP_INSTALL=1 \
ENABLE_HARDENED_RUNTIME=1 \
CODESIGN_IDENTITY="$SIGN_IDENTITY" \
SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
SPARKLE_FEED_URL="$SPARKLE_FEED_URL" \
    "$ROOT_DIR/scripts/bundle.sh"

APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"

echo "==> Verifying Hardened Runtime flags on $APP_BUNDLE and embedded glassgrid..."
CODESIGN_INFO="$(codesign -dvv "$APP_BUNDLE" 2>&1)"
if ! grep -q "flags=.*runtime" <<< "$CODESIGN_INFO"; then
    echo "Error: Hardened Runtime flag not detected on $APP_BUNDLE" >&2
    echo "$CODESIGN_INFO" >&2
    exit 1
fi
CLI_CODESIGN_INFO="$(codesign -dvv "$APP_BUNDLE/Contents/MacOS/glassgrid" 2>&1)"
if ! grep -q "flags=.*runtime" <<< "$CLI_CODESIGN_INFO"; then
    echo "Error: Hardened Runtime flag not detected on $APP_BUNDLE/Contents/MacOS/glassgrid" >&2
    echo "$CLI_CODESIGN_INFO" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
DMG_NAME="GlassGrid-You-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
SHA_PATH="${DMG_PATH}.sha256"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "==> Staging drag-to-Applications DMG layout..."
ditto "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating compressed UDZO disk image: $DMG_PATH..."
rm -f "$DMG_PATH" "$SHA_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

if [[ "$AD_HOC" != "1" ]]; then
    echo "==> Signing disk image with $SIGN_IDENTITY..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    echo "==> Submitting $DMG_NAME for Apple notarization (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling and validating notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    echo "==> Verifying Gatekeeper acceptance..."
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
    spctl --assess --type execute --verbose "$APP_BUNDLE"
else
    echo "==> Skipping notarization, stapling, and Gatekeeper spctl checks (--skip-notarize)."
fi

echo "==> Generating and verifying portable SHA-256 checksum..."
(
    cd "$(dirname "$DMG_PATH")"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$SHA_PATH")"
    shasum -a 256 -c "$(basename "$SHA_PATH")"
)

# Optional Sparkle EdDSA signature & appcast <item> snippet if sign_update is installed in PATH.
SIGN_UPDATE_BIN="${SPARKLE_SIGN_UPDATE:-$(command -v sign_update || true)}"
APPCAST_SNIPPET="$OUTPUT_DIR/appcast-item-${VERSION}.xml"
if [[ "$AD_HOC" != "1" && -n "$SIGN_UPDATE_BIN" && -x "$SIGN_UPDATE_BIN" ]]; then
    echo "==> Signing DMG for Sparkle appcast using $SIGN_UPDATE_BIN..."
    ED_ATTRS="$("$SIGN_UPDATE_BIN" "$DMG_PATH" || true)"
    if [[ -n "$ED_ATTRS" ]]; then
        PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"
        DOWNLOAD_URL="https://github.com/ZacharyZell/glassgrid-you/releases/download/v${VERSION}/${DMG_NAME}"
        cat > "$APPCAST_SNIPPET" <<EOF
<item>
  <title>Version ${VERSION}</title>
  <pubDate>${PUB_DATE}</pubDate>
  <sparkle:version>${BUILD_NUMBER}</sparkle:version>
  <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure url="${DOWNLOAD_URL}" ${ED_ATTRS} type="application/octet-stream" />
</item>
EOF
        echo "    Appcast snippet: $APPCAST_SNIPPET"
    fi
fi

echo "==> Release artifacts ready:"
echo "    DMG:    $DMG_PATH"
echo "    SHA256: $SHA_PATH"
