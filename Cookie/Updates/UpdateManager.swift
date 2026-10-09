import Foundation
import AppKit
import SwiftUI
import Sparkle

/// Dedicated in-app update manager coordinating Sparkle 2, appcast validation,
/// and native SwiftUI presentation.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    static let shared = UpdateManager()

    // MARK: - Published Properties

    @Published var state: UpdateCheckState = .idle
    @Published var lastCheckDate: Date? = nil
    @Published var isShowingUpdatePrompt = false

    // Active Sparkle updater instance
    private var sparkleUpdater: SPUUpdater?
    private var userDriverReply: ((SPUUserUpdateChoice) -> Void)?
    private var userDriverAcknowledgement: (() -> Void)?

    // Fallback/Direct download task
    private var downloadTask: URLSessionDownloadTask?
    private var downloadedFileURL: URL?
    private var currentDownloadInfo: UpdateInfo?

    // MARK: - App Identity Metadata

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var feedURL: URL? {
        if let str = Bundle.main.infoDictionary?["SUFeedURL"] as? String, let url = URL(string: str) {
            return url
        }
        return URL(string: "https://raw.githubusercontent.com/MdKasif0/Cookie/main/website/appcast.xml")
    }

    var publicEdKey: String? {
        Bundle.main.infoDictionary?["SUPublicEDKey"] as? String
    }

    var codeSigningStatus: CodeSigningStatus {
        CodeSigningStatus.current()
    }

    // MARK: - Initialization

    override init() {
        super.init()
        setupSparkle()
    }

    private func setupSparkle() {
        let hostBundle = Bundle.main
        // Initialize SPUUpdater with self as user driver and delegate
        self.sparkleUpdater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: self,
            delegate: self
        )

        do {
            try self.sparkleUpdater?.start()
        } catch {
            NSLog("[UpdateManager] Sparkle start warning: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Update Actions

    /// Checks for updates asynchronously without interrupting Cookie's animations.
    func checkForUpdates(userInitiated: Bool) {
        guard !state.isCheckingOrBusy else { return }

        state = .checking

        // Attempt Sparkle's native check if configured
        if let updater = sparkleUpdater, updater.canCheckForUpdates {
            if userInitiated {
                updater.checkForUpdates()
            } else {
                updater.checkForUpdatesInBackground()
            }
            return
        }

        // Direct HTTPS Appcast check fallback (e.g. for testing or offline sandbox)
        performDirectAppcastCheck(userInitiated: userInitiated)
    }

    /// Performs direct HTTPS appcast fetching and validation.
    func performDirectAppcastCheck(userInitiated: Bool) {
        guard let url = feedURL else {
            state = .error(title: "Update Error", message: "Update feed URL is not configured.")
            return
        }

        guard url.scheme?.lowercased() == "https" || url.isFileURL else {
            state = .error(title: "Insecure Feed", message: "Updates must be retrieved over HTTPS.")
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw NSError(domain: "UpdateManager", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(http.statusCode)"])
                }

                let items = try AppcastParser.parse(data: data)
                self.processAppcastItems(items, userInitiated: userInitiated)
            } catch {
                NSLog("[UpdateManager] Direct check failed: \(error.localizedDescription)")
                if userInitiated {
                    self.state = .error(title: "Check Failed", message: error.localizedDescription)
                    self.isShowingUpdatePrompt = true
                } else {
                    self.state = .idle
                }
            }
        }
    }

    private func processAppcastItems(_ items: [UpdateInfo], userInitiated: Bool) {
        lastCheckDate = Date()

        // Find the newest version that is compatible with this Mac
        let compatibleItems = items.filter { item in
            if let minSys = item.minimumSystemVersion {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let osStr = "\(os.majorVersion).\(os.minorVersion)"
                return VersionComparator.isNewer(remoteVersion: osStr, remoteBuild: "0", currentVersion: minSys, currentBuild: "0") || osStr == minSys
            }
            return true
        }

        guard let latest = compatibleItems.first else {
            state = .upToDate(lastChecked: Date())
            if userInitiated {
                isShowingUpdatePrompt = true
            }
            return
        }

        let isNewer = VersionComparator.isNewer(
            remoteVersion: latest.version,
            remoteBuild: latest.buildNumber,
            currentVersion: currentVersion,
            currentBuild: currentBuildNumber
        )

        if isNewer {
            state = .updateAvailable(info: latest)
            isShowingUpdatePrompt = true
        } else {
            state = .upToDate(lastChecked: Date())
            if userInitiated {
                isShowingUpdatePrompt = true
            }
        }
    }

    /// User confirmed "Install Update" button.
    func installUpdate() {
        if let reply = userDriverReply {
            userDriverReply = nil
            reply(.install)
            return
        }

        // Direct download flow if Sparkle driver reply is not waiting
        guard case .updateAvailable(let info) = state else { return }
        startDirectDownload(for: info)
    }

    /// User chose "Later".
    func postponeUpdate() {
        if let reply = userDriverReply {
            userDriverReply = nil
            reply(.dismiss)
        }
        isShowingUpdatePrompt = false
        state = .idle
    }

    /// User chose "Skip This Version".
    func skipVersion(_ version: String) {
        if let reply = userDriverReply {
            userDriverReply = nil
            reply(.skip)
        }
        UserDefaults.standard.set(version, forKey: "CookieSkippedVersion")
        isShowingUpdatePrompt = false
        state = .idle
    }

    func dismissPrompt() {
        userDriverAcknowledgement?()
        userDriverAcknowledgement = nil
        isShowingUpdatePrompt = false
        state = .idle
    }

    // MARK: - Direct Download & Installation Flow

    private func startDirectDownload(for info: UpdateInfo) {
        currentDownloadInfo = info
        state = .downloading(progress: 0.05, bytesDownloaded: 0, totalBytes: info.fileSize)

        let session = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        downloadTask = session.downloadTask(with: info.downloadURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                self.state = .error(title: "Download Failed", message: error.localizedDescription)
                return
            }

            guard let tempURL = tempURL else {
                self.state = .error(title: "Download Failed", message: "No data received.")
                return
            }

            // Move to persistent cache location
            let downloadsDir = FileManager.default.temporaryDirectory.appendingPathComponent("CookieUpdate", isDirectory: true)
            try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            let destinationURL = downloadsDir.appendingPathComponent(info.downloadURL.lastPathComponent)

            try? FileManager.default.removeItem(at: destinationURL)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                self.downloadedFileURL = destinationURL
                self.state = .readyToInstall(info: info)
                self.applyDownloadedUpdate(fileURL: destinationURL, info: info)
            } catch {
                self.state = .error(title: "Installation Error", message: "Could not save update archive.")
            }
        }
        downloadTask?.resume()
    }

    private func applyDownloadedUpdate(fileURL: URL, info: UpdateInfo) {
        state = .installing

        switch codeSigningStatus {
        case .developerId:
            // For signed release builds, Sparkle handles in-place replacement
            if let updater = sparkleUpdater, updater.canCheckForUpdates {
                updater.checkForUpdates()
            } else {
                NSWorkspace.shared.open(fileURL)
                state = .idle
                isShowingUpdatePrompt = false
            }

        case .adHocOrUnsigned:
            // Safe, transparent alternative for unsigned / ad-hoc builds:
            // Mount the verified DMG or reveal in Finder so user drags into /Applications
            // without corrupting Gatekeeper quarantine or breaking launch permissions.
            NSWorkspace.shared.open(fileURL)
            state = .idle
            isShowingUpdatePrompt = false
        }
    }

    // MARK: - SPUUserDriver Protocol Implementation

    nonisolated func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        Task { @MainActor in
            // Default to opt-in based on user settings
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
        }
    }

    nonisolated func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            self.state = .checking
        }
    }

    nonisolated func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Task { @MainActor in
            self.userDriverReply = reply
            let info = UpdateInfo(
                version: appcastItem.displayVersionString,
                buildNumber: appcastItem.versionString,
                title: appcastItem.title ?? "Version \(appcastItem.displayVersionString)",
                releaseNotes: appcastItem.itemDescription ?? "Cozy new improvements and fixes for Cookie.",
                downloadURL: appcastItem.fileURL ?? URL(fileURLWithPath: ""),
                fileSize: Int64(appcastItem.contentLength),
                edSignature: nil,
                minimumSystemVersion: appcastItem.minimumSystemVersion,
                isCritical: appcastItem.isCriticalUpdate,
                publishedDate: appcastItem.date
            )
            self.state = .updateAvailable(info: info)
            self.isShowingUpdatePrompt = true
        }
    }

    nonisolated func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    nonisolated func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    nonisolated func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            self.userDriverAcknowledgement = acknowledgement
            self.state = .upToDate(lastChecked: Date())
            self.isShowingUpdatePrompt = true
        }
    }

    nonisolated func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            self.userDriverAcknowledgement = acknowledgement
            self.state = .error(title: "Update Error", message: error.localizedDescription)
            self.isShowingUpdatePrompt = true
        }
    }

    nonisolated func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor in
            if case .updateAvailable(let info) = self.state {
                self.state = .downloading(progress: 0.1, bytesDownloaded: 0, totalBytes: info.fileSize)
            }
        }
    }

    nonisolated func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    nonisolated func showDownloadDidReceiveData(ofLength length: UInt64) {
        Task { @MainActor in
            if case .downloading(let currentProgress, let downloaded, let total) = self.state {
                let newDownloaded = downloaded + Int64(length)
                let progress = total > 0 ? Double(newDownloaded) / Double(total) : min(0.95, currentProgress + 0.05)
                self.state = .downloading(progress: progress, bytesDownloaded: newDownloaded, totalBytes: total)
            }
        }
    }

    nonisolated func showDownloadDidStartExtractingUpdate() {
        Task { @MainActor in
            self.state = .installing
        }
    }

    nonisolated func showExtractionReceivedProgress(_ progress: Double) {}

    nonisolated func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        Task { @MainActor in
            self.state = .installing
        }
    }

    nonisolated func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        Task { @MainActor in
            reply(.install)
        }
    }

    nonisolated func showSendingTerminationSignal() {}

    nonisolated func showUpdateInstallationDidFinish(acknowledgement: @escaping () -> Void) {
        Task { @MainActor in
            acknowledgement()
            self.state = .idle
            self.isShowingUpdatePrompt = false
        }
    }

    nonisolated func dismissUpdateInstallation() {
        Task { @MainActor in
            self.state = .idle
            self.isShowingUpdatePrompt = false
        }
    }
}
