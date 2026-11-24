# Releasing GlassGrid You for macOS

This guide walks through signing, notarizing, and publishing a Gatekeeper-approved `.dmg` release of **GlassGrid You** with optional **Sparkle 2** silent auto-updates.

---

## Prerequisites

1. **Apple Developer Program membership** (required for `Developer ID Application` signing & Apple Notarization).
2. **Xcode 16+** installed locally with your Apple ID signed in.
3. *(Optional, for Sparkle 2 silent auto-updates)* **Sparkle CLI tools** (`generate_keys`, `sign_update`):
   ```bash
   brew install sparkle
   ```
   *(Or download `Sparkle-2.x.tar.xz` from [sparkle-project/Sparkle Releases](https://github.com/sparkle-project/Sparkle/releases) and use `bin/generate_keys` & `bin/sign_update`.)*

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

## 3. *(Optional)* Generate a Sparkle 2 EdDSA Keypair

Generate an Ed25519 keypair once. Sparkle stores the **private key strictly inside your macOS login Keychain** (**never** commit a private key to Git) and prints the public key (`SUPublicEDKey`):

```bash
generate_keys
```

Copy the printed base64 `<key>` value to pass via `--sparkle-public-key` (or `SPARKLE_PUBLIC_ED_KEY`).

> **Fork & Source Build Safety:** If `SUPublicEDKey` is omitted, GlassGrid You automatically disables Sparkle and falls back cleanly to its zero-dependency GitHub Releases `UpdateChecker` with zero error dialogs.

---

## 4. Build, Sign Inside-Out, Package & Notarize the `.dmg`

Run the release script with the target semantic version and build number:

```bash
./scripts/release-dmg.sh \
  --version 1.1.0 \
  --build 2 \
  --sparkle-public-key "<YOUR_BASE64_ED25519_PUBLIC_KEY>"
```

What `release-dmg.sh` does automatically:
1. Builds the Swift 6 release binary, embeds `Sparkle.framework` via `ditto` (preserving `Versions/Current` symlinks), adds `@executable_path/../Frameworks` rpath before signing, generates the Liquid Glass `AppIcon.icns`, and injects version/Sparkle metadata into `Info.plist` via `scripts/bundle.sh`.
2. Strips extended attributes (`xattr -cr`) and signs strictly **inside-out** with **Hardened Runtime** (`--options runtime --timestamp`, never `--deep`):
   - `Sparkle.framework/Versions/B/XPCServices/Downloader.xpc` (`--preserve-metadata=entitlements`)
   - `Sparkle.framework/Versions/B/XPCServices/Installer.xpc`
   - `Sparkle.framework/Versions/B/Autoupdate`
   - `Sparkle.framework/Versions/B/Updater.app`
   - `Sparkle.framework`
   - `GlassGrid You.app` (with minimal non-sandboxed [`scripts/entitlements.plist`](../scripts/entitlements.plist))
3. Verifies strict signature integrity (`codesign --verify --deep --strict --verbose=2`) and Hardened Runtime flags.
4. Packages a drag-to-Applications compressed `UDZO` disk image at `build/release/GlassGrid-You-<version>.dmg`.
5. Signs the `.dmg` container itself, submits to Apple Notarization (`xcrun notarytool submit --wait`), staples the ticket (`xcrun stapler staple`), and verifies Gatekeeper acceptance (`spctl --assess`).
6. Writes and verifies a portable `GlassGrid-You-<version>.dmg.sha256` checksum (and if `sign_update` is installed, emits `build/release/appcast-item-<version>.xml` ready to paste into `docs/appcast.xml`).

### Local Dry-Run (No Developer ID Certificate Needed)

To verify inside-out Hardened Runtime signing, `Sparkle.framework` embedding, `.dmg` creation, and SHA-256 checksum generation locally without notarization:

```bash
./scripts/release-dmg.sh --version 1.1.0 --ad-hoc --skip-notarize
```

---

## 5. Publish the Release

1. Tag and create a GitHub Release (`v1.1.0`) on [`ZacharyZell/glassgrid-you`](https://github.com/ZacharyZell/glassgrid-you/releases):
   ```bash
   git tag -a v1.1.0 -m "GlassGrid You v1.1.0"
   git push origin v1.1.0
   gh release create v1.1.0 \
     build/release/GlassGrid-You-1.1.0.dmg \
     build/release/GlassGrid-You-1.1.0.dmg.sha256 \
     --title "GlassGrid You v1.1.0" \
     --generate-notes
   ```
2. If using Sparkle 2 silent auto-updates, paste `build/release/appcast-item-1.1.0.xml` into `docs/appcast.xml` (served via GitHub Pages at `https://glassgridyou.com/appcast.xml`) on `main` and push.
3. Optionally mirror the signed & notarized `.dmg` on **Lemon Squeezy** or **Gumroad** for supporters who prefer a direct download store.
