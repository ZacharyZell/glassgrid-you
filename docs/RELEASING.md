# Releasing GlassGrid You for macOS

This guide walks through signing, notarizing, and publishing a Gatekeeper-approved `.dmg` release of **GlassGrid You** using an Apple Developer account.

---

## Prerequisites

1. **Apple Developer Program membership** (required for `Developer ID Application` signing & Apple Notarization).
2. **Xcode 16+** installed locally with your Apple ID signed in.

---

## 1. Create a `Developer ID Application` Certificate

1. Open **Xcode → Settings → Accounts**.
2. Select your Apple ID and click **Manage Certificates…**.
3. Click **`+`** → **Developer ID Application**.
4. Verify the certificate is available in your Keychain:
   ```bash
   security find-identity -v -p codesigning
   ```
   You should see a line matching `"Developer ID Application: <Your Name> (<TEAM_ID>)"`.

---

## 2. Store Notarization Credentials (`notarytool`)

Store an App Store Connect API key (recommended) or an app-specific password once in your login Keychain:

```bash
xcrun notarytool store-credentials "GlassGridYouNotary" \
  --apple-id "<your-apple-id-email>" \
  --team-id "<YOUR_10_CHAR_TEAM_ID>" \
  --password "<app-specific-password>"
```

*(Alternatively, pass `--key /path/to/AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_UUID>`.)*

---

## 3. Build, Sign, Package & Notarize the `.dmg`

Run the release script with the target semantic version and build number:

```bash
./scripts/release-dmg.sh --version 1.0.0 --build 1
```

What `release-dmg.sh` does automatically:
1. Builds the Swift 6 release binary, generates the Liquid Glass `AppIcon.icns`, and injects `CFBundleShortVersionString` / `CFBundleVersion` via `scripts/bundle.sh`.
2. Strips extended attributes (`xattr -cr`) and signs `GlassGrid You.app` with **Hardened Runtime** (`--options runtime --timestamp`) and the minimal non-sandboxed [`scripts/entitlements.plist`](../scripts/entitlements.plist).
3. Verifies strict signature integrity (`codesign --verify --deep --strict`) and Hardened Runtime flags.
4. Packages a drag-to-Applications compressed `UDZO` disk image at `build/release/GlassGrid-You-<version>.dmg`.
5. Signs the `.dmg` container itself, submits to Apple Notarization (`xcrun notarytool submit --wait`), staples the ticket (`xcrun stapler staple`), and verifies Gatekeeper acceptance (`spctl --assess`).
6. Writes and verifies a portable `GlassGrid-You-<version>.dmg.sha256` checksum.

### Local Dry-Run (No Developer ID Certificate Needed)

To verify `.app` Hardened Runtime signing, `.dmg` creation, and SHA-256 checksum generation locally without notarization:

```bash
./scripts/release-dmg.sh --version 1.0.0 --ad-hoc --skip-notarize
```

---

## 4. Publish the Release

1. Tag and create a GitHub Release (`v1.0.0`) on [`ZacharyZell/glassgrid-you`](https://github.com/ZacharyZell/glassgrid-you/releases):
   ```bash
   git tag -a v1.0.0 -m "GlassGrid You v1.0.0"
   git push origin v1.0.0
   gh release create v1.0.0 \
     build/release/GlassGrid-You-1.0.0.dmg \
     build/release/GlassGrid-You-1.0.0.dmg.sha256 \
     --title "GlassGrid You v1.0.0" \
     --generate-notes
   ```
   Once published, users clicking **GlassGrid You → Check for Updates…** in the app menu automatically detect the new release via GitHub Releases!
2. Optionally mirror the signed & notarized `.dmg` on **Lemon Squeezy** or **Gumroad** for supporters who prefer a direct download store.
