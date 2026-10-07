# Cookie — Distribution, Code Signing & Notarization Guide

This document describes the distribution architecture, Apple Developer ID signing, notarization, and Gatekeeper behavior for direct distribution of **Cookie** outside the Mac App Store.

---

## 1. Distribution Overview

| Property | Value |
| :--- | :--- |
| **Application Name** | Cookie |
| **Bundle Identifier** | `com.cookie.mac` |
| **Marketing Version** | `1.0.0` |
| **Minimum System Version** | macOS 14.0 (Sonoma) or later |
| **Architecture** | Universal 2 (Apple Silicon `arm64` + Intel `x86_64`) |
| **Distribution Format** | Compressed Apple Disk Image (`Cookie-1.0.0.dmg`, UDZO) |
| **Current Build Signature** | Ad-hoc signed (`-`) with Hardened Runtime compatibility |

---

## 2. Gatekeeper Behavior & First-Launch

### A. Ad-hoc Signed Development Builds (Current Status)
When Cookie is downloaded from the web or shared without an Apple Developer ID signature and notarization ticket, macOS Gatekeeper attaches the `com.apple.quarantine` extended attribute:

1. **Standard Double-Click**: macOS will present an alert stating:
   > *"Cookie" cannot be opened because Apple cannot check it for malicious software.*
2. **Standard User Resolution (No Insecure Bypasses)**:
   - **Method 1**: Right-click (or Control-click) **Cookie.app** in Finder, choose **Open** from the contextual menu, and click **Open** in the dialog.
   - **Method 2**: Open macOS **System Settings → Privacy & Security**, scroll to the **Security** section, and click **Open Anyway** next to the notification about Cookie.

> [!NOTE]
> Cookie does not implement insecure scripts or unauthorized background overrides to strip quarantine flags. Gatekeeper operates as Apple intended to protect user security until Developer ID signing and notarization are completed.

### B. Notarized Developer ID Builds (Production Status)
Once signed with a valid Apple Developer ID and notarized by Apple's Notary Service:
- Gatekeeper verifies the stapled ticket immediately, even offline.
- The user is presented with a standard, trustworthy first-launch prompt:
  > *"Cookie" is an app downloaded from the Internet. Are you sure you want to open it?*
- Clicking **Open** launches Cookie seamlessly.

---

## 3. Production Code Signing Workflow

To sign Cookie for direct public distribution, an active **Apple Developer Program** membership is required.

### Step 1: Obtain Developer ID Application Certificate
1. Generate and install your **Developer ID Application** certificate from [developer.apple.com](https://developer.apple.com).
2. Verify the certificate exists in your Keychain:
   ```bash
   security find-identity -p codesigning -v
   ```
   *Expected output includes: `Developer ID Application: Your Name (TEAM_ID)`*

### Step 2: Sign the Application Bundle
Sign the application bundle with Hardened Runtime enabled (`--options runtime`) and secure timestamping (`--timestamp`):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme Cookie \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  build \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
  ENABLE_HARDENED_RUNTIME="YES"

# Manually verify or deep sign embedded binaries if needed:
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  .build/DerivedData/Build/Products/Release/Cookie.app

# Verify signing
codesign --verify --deep --strict --verbose=2 .build/DerivedData/Build/Products/Release/Cookie.app
spctl --assess --type execute --verbose .build/DerivedData/Build/Products/Release/Cookie.app
```

---

## 4. Packaging & Disk Image Signing

Generate the distribution disk image using the automated packaging script:

```bash
./Packaging/build_dmg.sh
```

Sign the resulting `.dmg` with the Developer ID Application certificate:

```bash
codesign --timestamp \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  dist/Cookie-1.0.0.dmg
```

---

## 5. Apple Notarization Workflow

Notarization is Apple's automated malware scanning service for macOS software distributed outside the Mac App Store.

### Step 1: Store Notary Credentials Securely
Configure an App Store Connect API key or app-specific password:

```bash
# Using App-Specific Password:
xcrun notarytool store-credentials "CookieNotary" \
  --apple-id "developer@example.com" \
  --team-id "TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Step 2: Submit DMG for Notarization
Submit the disk image to the Apple Notary Service and wait for the verdict:

```bash
xcrun notarytool submit dist/Cookie-1.0.0.dmg \
  --keychain-profile "CookieNotary" \
  --wait
```

### Step 3: Staple the Notarization Ticket
Once notarization succeeds, staple the cryptographic ticket directly to the disk image and the application bundle:

```bash
# Staple the DMG
xcrun stapler staple dist/Cookie-1.0.0.dmg

# Verify the staple
spctl -a -t open --context context:primary-signature -v dist/Cookie-1.0.0.dmg
```

---

## 6. Verification Checklist Before Release

- [x] Bundle contains native `AppIcon.icns` with warm cream aesthetic.
- [x] `CFBundleShortVersionString` is `1.0.0` and `CFBundleVersion` is `1`.
- [x] No debug flags, test arguments, or absolute local file paths in Release build.
- [x] Sprites and audio are cleanly bundled in `Contents/Resources`.
- [x] DMG contains `Cookie.app` and `Applications` shortcut with custom warm background.
- [x] All 19 unit tests pass in continuous integration.
- [x] Zero purple and zero blue colors across the entire user experience.
