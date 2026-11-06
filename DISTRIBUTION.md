# Cookie — Distribution, Code Signing & Notarization Guide

This document describes the distribution architecture, Apple Developer ID signing, notarization, and Gatekeeper behavior for direct distribution of **Cookie** outside the Mac App Store.

---

## 1. Distribution Overview

| Property | Value |
| :--- | :--- |
| **Application Name** | Cookie |
| **Bundle Identifier** | `com.cookie.mac` |
| **Marketing Version** | `1.2.0` |
| **Minimum System Version** | macOS 14.0 (Sonoma) or later |
| **Architecture** | Universal 2 (Apple Silicon `arm64` + Intel `x86_64`) |
| **Distribution Format** | Compressed Apple Disk Image (`Cookie-1.2.0.dmg`, UDZO) |
| **Current Build Signature** | Ad-hoc signed (`-`), Hardened Runtime off, not notarized |

---

## 2. Gatekeeper Behavior & First-Launch

### A. Ad-hoc Signed Development Builds (Current Status)
When Cookie is downloaded from the web or shared without an Apple Developer ID signature and notarization ticket, macOS Gatekeeper attaches the `com.apple.quarantine` extended attribute:

1. **Standard Double-Click**: macOS blocks the app and offers no way to open it from the alert.
2. **Standard User Resolution (No Insecure Bypasses)**:
   - **macOS 15 Sequoia and later**: try to open Cookie once, then go to **System Settings → Privacy & Security**, scroll to the **Security** section, click **Open Anyway** next to the notice about Cookie, and authenticate. The right-click → **Open** shortcut no longer bypasses Gatekeeper on these versions.
   - **macOS 14 Sonoma**: right-click (or Control-click) **Cookie.app** in Finder, choose **Open**, and click **Open** in the dialog. **Open Anyway** in System Settings also works.

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

### Step 2: Store Notary Credentials Securely
Store an app-specific password from [account.apple.com](https://account.apple.com) in your Keychain:

```bash
xcrun notarytool store-credentials "CookieNotary" \
  --apple-id "developer@example.com" \
  --team-id "TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### Step 3: Build, Sign, Notarize and Staple
`Packaging/build_dmg.sh` does all of this when these variables are set. It enables Hardened Runtime, signs Sparkle's nested helpers inside-out, signs the DMG, submits it to Apple, staples the ticket, and fails if Apple rejects the build.

```bash
COOKIE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
COOKIE_TEAM_ID="TEAM_ID" \
COOKIE_NOTARY_PROFILE="CookieNotary" \
./Packaging/build_dmg.sh
```

Without these variables the script produces an ad-hoc development DMG, and its last line of output says so. Hardened Runtime stays off in `project.yml` because ad-hoc builds cannot load Sparkle with it enabled.

### Step 4: Verify on a Clean Mac
Download the DMG through a browser so it gets the quarantine flag, then open it on a Mac that has never run Cookie. If a build is rejected, read Apple's reason with `xcrun notarytool log <submission-id> --keychain-profile "CookieNotary"`.

---

## 4. Windows Code Signing

An unsigned installer shows a blue SmartScreen warning. Choose one route, then add its secrets under **GitHub → Settings → Secrets and variables → Actions**. `.github/workflows/build-windows.yml` signs `Cookie.exe`, `Cookie.dll`, `Cookie.Windows.Core.dll` and the installer when the secrets exist, and otherwise builds unsigned.

| Route | Secrets to add | Notes |
| :--- | :--- | :--- |
| **Azure Artifact Signing** | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT`, `AZURE_SIGNING_PROFILE` | Monthly subscription with no hardware token. Check that your country and account type are eligible before relying on it. |
| **PFX certificate** | `WINDOWS_CERT_PFX_BASE64`, `WINDOWS_CERT_PASSWORD` | Only for a certificate you can export as a PFX. Most public certificate authorities now keep keys on hardware tokens or in the cloud, so check before buying. |
| **Microsoft Store** | None in this workflow | The Store signs the package for you, but it needs a separate MSIX package and listing, which this repo does not build yet. |

A signature identifies the publisher, but SmartScreen also weighs download reputation. A new certificate can still show a warning until it builds up history.

---

## 5. After the First Trusted Release

Update the website only after a signed build has been checked on a clean machine:

1. In `website/releases.js`, remove the Gatekeeper step and security note from `mac`, and the SmartScreen wording from `windows`.
2. Update each release's size and `sha256` in the same file.
3. Update the status table at the top of this document.

---

## 6. Publishing a Release

Binaries are never committed to this repository. `dist/` and `website/downloads/` are ignored, and every download is a **GitHub Release** asset. The website's `/download/...` addresses (`website/_redirects`) redirect to them.

The two platforms release independently, with different tags:

| | Tag | Marked "latest"? | Notes file |
| :--- | :--- | :--- | :--- |
| **Mac** | `v1.2.0` | No (`--latest=false`) | `release-notes/1.2.0.md` |
| **Windows** | `windows-v1.2.0` | Yes | `release-notes/windows-1.2.0.md` |

The website's Windows download and the Windows update feed follow `releases/latest`, so a Mac release must never become "latest". The Mac appcast and `/download/mac` name their release by tag.

**Mac**

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and `VERSION` in `Packaging/build_dmg.sh`. Write the release notes.
2. `./Packaging/build_dmg.sh` builds the DMG into `dist/`.
3. `./scripts/release_update.sh <version> <build> dist/Cookie-<version>.dmg` Sparkle-signs it and prints the appcast `<item>`.
4. `./scripts/publish-release.sh mac <version> --dry-run`, then without `--dry-run`, uploads it.
5. Add the `<item>` to `website/appcast.xml`, set the new version in `website/_redirects` and `website/releases.js` (the size and SHA-256 come from the published file), then commit and push.

**Windows**

1. Write `release-notes/windows-<version>.md`, and set the version in `Cookie.Windows.csproj` and `CookieSetup.iss`.
2. Push a tag such as `windows-v1.2.0`. The *Build Cookie for Windows* workflow builds, signs, creates the signed update manifest, and publishes the installer, the portable zip, the checksums and the update feed. (Pushes to `main` without a tag only build and keep the files as a workflow artifact.)
3. Update the version text in `website/releases.js`, then commit and push.

Publish the release **before** pushing website changes that redirect to it, or the download buttons point at files that do not exist yet.

---

## 7. Windows Update Signing

The Windows app checks for updates by downloading a small manifest (`windows-update.json`) that names the new installer and its SHA-256 checksum. That checksum only protects the download if the manifest itself can be trusted, so the manifest is **signed**:

- The signature is an ECDSA P-256 / SHA-256 signature over the manifest's exact bytes, stored beside it as `windows-update.json.sig` (base64).
- The app contains the matching **public key** (`UpdateSigning.TrustedPublicKeys`) and checks the signature before it reads anything in the manifest. A missing, malformed or wrong signature means the update information is ignored, and Settings says it could not be verified.
- Downloads must use HTTPS, and the installer is still checked against the signed SHA-256.
- The hosted feed (`https://cookie-v1.netlify.app/updates/windows/release.json`) redirects to the newest release's `windows-update.json`.

### The private key

`Tools/CookieUpdateTool` creates and uses the key. The current private key was generated at `~/.cookie-release-keys/windows-update-signing.pem` (readable only by you). **Whoever holds this file can publish updates that every installed Cookie will accept.**

1. Back it up somewhere private (a password manager), then store the file's text as the GitHub secret **`WINDOWS_UPDATE_SIGNING_KEY`** (Settings → Secrets and variables → Actions). Tag builds fail if it is missing.
2. Never commit it. `*.pem` is ignored, but keep it out of the repository folder anyway.
3. If you lose it, nobody can sign updates for already-installed copies, and they would have to be reinstalled by hand. If it leaks, rotate it.

### Rotating the key

The app trusts a list of keys, so a rotation does not strand anyone:

1. `dotnet run --project Tools/CookieUpdateTool -- keygen ~/.cookie-release-keys/new-key.pem` and copy the printed public key.
2. Add it to `UpdateSigning.TrustedPublicKeys` **next to** the old one and ship that version, signed with the old key.
3. Once most people have updated, sign with the new key, then remove the old public key in a later release.

### Useful commands

```bash
# Check a published manifest against the app's trusted key
curl -sLO https://cookie-v1.netlify.app/updates/windows/release.json
curl -sLO https://cookie-v1.netlify.app/updates/windows/release.json.sig
dotnet run --project Tools/CookieUpdateTool -- verify release.json
```

The first time this protects anyone is the release *after* the one that contains it: copies of Cookie 1.1.0 already installed do not check signatures. They update to the first signed version over the unsigned path, and are protected from then on.

---

## 8. Shrinking the Repository

Earlier releases were committed to git, so `.git` carries every binary version ever added: about **224 MB of its 293 MB** is `dist/` and `website/downloads/`. Untracking them (this change) stops it growing but does not shrink history. Shrinking needs a **history rewrite**, which is destructive and was deliberately *not* done for you:

- Every commit id changes, so existing clones and forks break and must be re-cloned.
- It requires a force-push, and open pull requests are lost.

If you decide you want it (it should bring `.git` to roughly 70 MB):

```bash
brew install git-filter-repo
git clone --mirror git@github.com:MdKasif0/Cookie.git cookie-clean.git   # work on a copy
cd cookie-clean.git
git filter-repo --invert-paths --path dist --path website/downloads
# check the result, then (only then) push it over the original:
git push --force --mirror
```

Publish the GitHub Release assets first (section 6), because the old binaries disappear from history. Tags and releases themselves are not affected.

Until then, anything you need from before this change can be restored with, for example, `git show <old-commit>:website/downloads/Cookie-Setup.exe > Cookie-Setup.exe`.

---

## 9. Verification Checklist Before Release

- [ ] Version numbers match in `project.yml`, `Cookie.Windows.csproj`, `CookieSetup.iss`, `website/releases.js`, `website/_redirects` and the appcast.
- [ ] `release-notes/<version>.md` exists.
- [ ] `WINDOWS_UPDATE_SIGNING_KEY` is set, and `verify` passes on the published manifest.
- [ ] macOS and Windows test suites pass.
- [ ] `codesign --verify --deep --strict` passes and `xcrun stapler validate` succeeds on the DMG.
- [ ] `signtool verify /pa` passes on `Cookie-Setup.exe`.
- [ ] Both downloads open without a security warning on a clean machine.
- [ ] No debug flags, test arguments, or absolute local file paths in the Release build.
- [ ] Sprites and audio are bundled in the app.
