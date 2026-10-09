import SwiftUI

/// Warm, cozy color palette matching Cookie's signature design system.
/// Zero purple, zero blue.
private enum UpdateColors {
    static let warmWhite = Color(nsColor: NSColor(calibratedRed: 0.984, green: 0.976, blue: 0.961, alpha: 1.0))
    static let cream = Color(nsColor: NSColor(calibratedRed: 0.961, green: 0.937, blue: 0.902, alpha: 1.0))
    static let beige = Color(nsColor: NSColor(calibratedRed: 0.918, green: 0.863, blue: 0.788, alpha: 1.0))
    static let warmPeach = Color(nsColor: NSColor(calibratedRed: 0.973, green: 0.886, blue: 0.820, alpha: 1.0))
    static let softOrange = Color(nsColor: NSColor(calibratedRed: 0.878, green: 0.478, blue: 0.373, alpha: 1.0))
    static let softOrangeHover = Color(nsColor: NSColor(calibratedRed: 0.918, green: 0.525, blue: 0.420, alpha: 1.0))
    static let mutedSage = Color(nsColor: NSColor(calibratedRed: 0.459, green: 0.522, blue: 0.435, alpha: 1.0))
    static let darkCharcoal = Color(nsColor: NSColor(calibratedRed: 0.169, green: 0.149, blue: 0.145, alpha: 1.0))
    static let neutralGray = Color(nsColor: NSColor(calibratedRed: 0.541, green: 0.510, blue: 0.478, alpha: 1.0))
    static let subtleBorder = Color(nsColor: NSColor(calibratedRed: 0.878, green: 0.835, blue: 0.776, alpha: 0.6))
}

/// Small, premium native macOS update interface designed specifically for Cookie.
struct UpdatePromptView: View {
    @ObservedObject var updateManager: UpdateManager
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().overlay(UpdateColors.subtleBorder)
            contentSection
            Divider().overlay(UpdateColors.subtleBorder)
            footerSection
        }
        .frame(width: 380)
        .background(UpdateColors.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(UpdateColors.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            // Cute Cookie Icon Preview
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(UpdateColors.warmPeach)
                    .frame(width: 44, height: 44)

                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 34, height: 34)
                } else {
                    Text("🐱")
                        .font(.system(size: 24))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("A little update for Cookie")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(UpdateColors.darkCharcoal)

                Text("Cookie has something new for you.")
                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                    .foregroundStyle(UpdateColors.neutralGray)
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(UpdateColors.neutralGray)
                        .padding(5)
                        .background(Circle().fill(UpdateColors.cream))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(UpdateColors.cream)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var contentSection: some View {
        VStack(spacing: 12) {
            switch updateManager.state {
            case .idle, .checking:
                checkingView

            case .upToDate:
                upToDateView

            case .updateAvailable(let info):
                updateAvailableView(info: info)

            case .downloading(let progress, let downloaded, let total):
                downloadingView(progress: progress, downloaded: downloaded, total: total)

            case .readyToInstall(let info):
                readyToInstallView(info: info)

            case .installing:
                installingView

            case .error(let title, let message):
                errorView(title: title, message: message)
            }
        }
        .padding(16)
        .background(UpdateColors.warmWhite)
    }

    // MARK: - Subviews

    private var checkingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(UpdateColors.softOrange)

            Text("Checking for updates…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(UpdateColors.neutralGray)
        }
        .frame(height: 120)
    }

    private var upToDateView: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(UpdateColors.warmPeach)
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(UpdateColors.mutedSage)
            }

            Text("Cookie is Up to Date")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)

            Text("Version \(updateManager.currentVersion) (\(updateManager.currentBuildNumber)) is the latest release.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(UpdateColors.neutralGray)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
    }

    private func updateAvailableView(info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Version Comparison Badge
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("CURRENT")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(UpdateColors.neutralGray)
                    Text("v\(updateManager.currentVersion)")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UpdateColors.darkCharcoal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(UpdateColors.cream))

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(UpdateColors.softOrange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NEW VERSION")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(UpdateColors.softOrange)
                    Text("v\(info.displayVersion)")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(UpdateColors.darkCharcoal)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(UpdateColors.warmPeach))

                Spacer()
            }

            // Release Notes Card
            VStack(alignment: .leading, spacing: 4) {
                Text("Release Notes")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(UpdateColors.neutralGray)

                ScrollView(.vertical, showsIndicators: true) {
                    Text(info.releaseNotes)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(UpdateColors.darkCharcoal)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 85)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(UpdateColors.cream.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(UpdateColors.subtleBorder, lineWidth: 1))
                )
            }

            // Ad-hoc signature notice if applicable
            if updateManager.codeSigningStatus == .adHocOrUnsigned {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(UpdateColors.mutedSage)
                    Text("Ad-hoc distribution: Installing opens the verified disk image to safely drag into Applications.")
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundStyle(UpdateColors.neutralGray)
                }
            }
        }
    }

    private func downloadingView(progress: Double, downloaded: Int64, total: Int64) -> some View {
        VStack(spacing: 8) {
            Text("Downloading update…")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)

            ProgressView(value: progress, total: 1.0)
                .tint(UpdateColors.softOrange)

            if total > 0 {
                let mbDownloaded = Double(downloaded) / 1_048_576.0
                let mbTotal = Double(total) / 1_048_576.0
                Text(String(format: "%.1f MB of %.1f MB", mbDownloaded, mbTotal))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(UpdateColors.neutralGray)
            }
        }
        .frame(height: 120)
    }

    private func readyToInstallView(info: UpdateInfo) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(UpdateColors.softOrange)

            Text("Update Downloaded & Verified")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)

            Text("Ready to complete update to \(info.displayVersion).")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(UpdateColors.neutralGray)
        }
        .frame(height: 120)
    }

    private var installingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(UpdateColors.softOrange)
            Text("Installing update…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)
        }
        .frame(height: 120)
    }

    private func errorView(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(UpdateColors.softOrange)

            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)

            Text(message)
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(UpdateColors.neutralGray)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            switch updateManager.state {
            case .updateAvailable(let info):
                Button("Skip This Version") {
                    updateManager.skipVersion(info.version)
                }
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(UpdateColors.neutralGray)
                .buttonStyle(.plain)

                Spacer()

                Button("Later") {
                    updateManager.postponeUpdate()
                }
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(UpdateColors.cream))
                .buttonStyle(.plain)

                Button("Install Update") {
                    updateManager.installUpdate()
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(UpdateColors.softOrange))
                .buttonStyle(.plain)

            case .upToDate, .error:
                Spacer()
                Button("Done") {
                    updateManager.dismissPrompt()
                    onDismiss?()
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(UpdateColors.softOrange))
                .buttonStyle(.plain)

            default:
                Spacer()
                Button("Cancel") {
                    updateManager.dismissPrompt()
                    onDismiss?()
                }
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(UpdateColors.darkCharcoal)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(UpdateColors.cream)
    }
}
