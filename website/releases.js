// ==============================================================================
// Cookie Desktop Companion — Centralized Platform Release Configuration
// Single Source of Truth for Windows & macOS versions, download URLs, and specs.
// ==============================================================================

const CookieReleases = {
  mac: {
    id: "mac",
    name: "macOS",
    displayName: "macOS",
    version: "1.1.0",
    releaseDate: "2026-10-11",
    formattedReleaseDate: "October 11, 2026",
    installerType: "Mac Disk Image (.dmg)",
    artifactName: "Cookie-1.1.0.dmg",
    downloadUrl: "downloads/Cookie-1.1.0.dmg",
    fileSizeBytes: 24332011,
    formattedSize: "23.2 MB",
    architecture: "Universal Binary (Apple Silicon & Intel 64-bit)",
    minimumOS: "macOS 14 Sonoma, macOS 15 Sequoia or later",
    isAvailable: true,
    sha256: "758add0f71d907ca32ad41abec2f49f5acc2569d9e5bcda62efb81a57d2b7447",
    signatureStatus: "Cryptographically verified via Sparkle EdDSA signature",
    heroButtonLabel: "Download for macOS",
    heroReleaseTag: "Version 1.1.0 · 23 MB Disk Image · Apple Silicon & Intel",
    cardMeta: "Version 1.1.0 · macOS 14 Sonoma & later",
    specs: [
      {
        title: "Apple Silicon",
        desc: "Native arm64 build optimized for M1 through M4 Macs with near-zero idle CPU impact.",
        pill: "Universal arm64"
      },
      {
        title: "Intel Macs",
        desc: "Full 64-bit support running smoothly on all supported Intel-based Macs.",
        pill: "Intel x86_64"
      },
      {
        title: "System Requirements",
        desc: "Requires macOS 14 Sonoma or macOS 15 Sequoia. No setup or root access needed.",
        pill: "macOS 14.0+"
      },
      {
        title: "Download Size",
        desc: "Compact ~23 MB disk image. 100% offline with zero background daemons.",
        pill: "23 MB DMG"
      }
    ],
    installSteps: [
      {
        step: 1,
        title: "Download the Disk Image",
        desc: "Click the download button to save Cookie-1.1.0.dmg directly from our official site."
      },
      {
        step: 2,
        title: "Open the Disk Image",
        desc: "Double-click the downloaded .dmg file in your Downloads folder to mount the installer."
      },
      {
        step: 3,
        title: "Drag to Applications",
        desc: "Drag the Cookie icon into your macOS Applications folder shortcut inside the window."
      },
      {
        step: 4,
        title: "Launch Cookie",
        desc: "Open Cookie from Applications or Spotlight (Cmd + Space). Cookie will spawn directly onto your desktop."
      },
      {
        step: 5,
        title: "Interact & Enjoy",
        desc: "Click Cookie to pet her, drag to reposition, or right-click to access emotes and settings."
      }
    ],
    securityNotes: {
      title: "macOS Security & Integrity",
      desc: "Built with native Swift and SpriteKit. Includes Sparkle automatic updates protected by cryptographic EdDSA signature verification. Free and MIT open source."
    }
  },

  windows: {
    id: "windows",
    name: "Windows",
    displayName: "Windows",
    version: "1.1.0",
    releaseDate: "2026-10-15",
    formattedReleaseDate: "October 15, 2026",
    installerType: "Windows Installer (.exe)",
    artifactName: "Cookie-Setup.exe",
    downloadUrl: "downloads/Cookie-Setup.exe",
    isInstallerAvailable: false, // Inno Setup compiler requires Windows CI runner
    installerStatusText: "Installer (.exe) Packaging",
    installerNote: "The official Inno Setup installer (Cookie-Setup.exe) is prepared and awaiting Windows CI build. In the meantime, the verified standalone portable package is available below.",
    
    // Verified portable release built in Phase 5
    portable: {
      isAvailable: true,
      name: "Portable 64-bit (.zip)",
      artifactName: "Cookie-Windows-1.1.0-win-x64-Portable.zip",
      downloadUrl: "downloads/Cookie-Windows-1.1.0-win-x64-Portable.zip",
      fileSizeBytes: 77247713,
      formattedSize: "73.6 MB",
      sha256: "474777092e9f4303a5255c518650537f7a5dc20c855560e84e728a0b7db41f0a",
      desc: "Self-contained standalone package. Extract and run Cookie.exe directly without installation."
    },

    architecture: "64-bit (x64)",
    minimumOS: "Windows 10 (version 19041+) & Windows 11",
    heroButtonLabel: "Download for Windows",
    heroReleaseTag: "Version 1.1.0 · 64-bit (x64) · Windows 10 & 11 · 100% Offline",
    cardMeta: "Version 1.1.0 · Windows 10 (build 19041+) & Windows 11",
    specs: [
      {
        title: "64-bit Architecture",
        desc: "Native x64 WPF application built on .NET 8 for modern Windows desktops and laptops.",
        pill: "Windows x64"
      },
      {
        title: "System Requirements",
        desc: "Requires Windows 10 (version 2004 / build 19041+) or Windows 11. No extra runtime needed.",
        pill: "Windows 10 / 11"
      },
      {
        title: "Privacy & Elevation",
        desc: "Runs completely per-user with zero administrative elevation required. 100% offline companion.",
        pill: "No Admin Required"
      },
      {
        title: "Package Size",
        desc: "Self-contained standalone build (~74 MB) including all sprite sheets and audio effects.",
        pill: "74 MB Zip"
      }
    ],
    installSteps: [
      {
        step: 1,
        title: "Download the Package",
        desc: "Download the official Cookie for Windows package from the button above."
      },
      {
        step: 2,
        title: "Extract the Archive",
        desc: "Right-click the downloaded zip file and select 'Extract All…' to your preferred location (e.g. AppData or Documents)."
      },
      {
        step: 3,
        title: "Run Cookie.exe",
        desc: "Double-click Cookie.exe in the extracted folder to launch your desktop companion."
      },
      {
        step: 4,
        title: "Notification Area Icon",
        desc: "Cookie will appear on your desktop and create a discreet icon in your Windows notification area (System Tray)."
      },
      {
        step: 5,
        title: "Customize & Interact",
        desc: "Click Cookie to pet her, drag to relocate, or right-click the system tray icon to configure sound, wander cadence, and coat colors."
      }
    ],
    securityNotes: {
      title: "Windows SmartScreen & Publisher Verification",
      desc: "Cookie is an independent, 100% offline open-source project. Initial releases without accumulated download history may trigger a standard Windows Defender SmartScreen notice ('Windows protected your PC'). Click 'More info' → 'Run anyway'. We recommend downloading solely from official Cookie releases."
    }
  }
};

// Export for node/testing if applicable
if (typeof module !== "undefined" && module.exports) {
  module.exports = CookieReleases;
}
