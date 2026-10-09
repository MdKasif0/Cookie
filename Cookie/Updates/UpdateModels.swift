import Foundation
import Security

/// Details of an available software update parsed from the appcast.
struct UpdateInfo: Identifiable, Equatable, Hashable {
    var id: String { version }
    let version: String
    let buildNumber: String
    let title: String
    let releaseNotes: String
    let downloadURL: URL
    let fileSize: Int64
    let edSignature: String?
    let minimumSystemVersion: String?
    let isCritical: Bool
    let publishedDate: Date?

    var displayVersion: String {
        if buildNumber.isEmpty || buildNumber == version {
            return version
        }
        return "\(version) (\(buildNumber))"
    }
}

/// Detailed lifecycle states of the in-app update engine.
enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(lastChecked: Date)
    case updateAvailable(info: UpdateInfo)
    case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case readyToInstall(info: UpdateInfo)
    case installing
    case error(title: String, message: String)

    var isCheckingOrBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    var isUpdateAvailable: Bool {
        if case .updateAvailable = self {
            return true
        }
        return false
    }
}

/// Identifies whether the running binary is signed with an Apple Developer ID or ad-hoc / unsigned.
enum CodeSigningStatus: Equatable, CustomStringConvertible {
    case developerId(teamId: String)
    case adHocOrUnsigned

    var description: String {
        switch self {
        case .developerId(let teamId):
            return "Developer ID Signed (Team: \(teamId))"
        case .adHocOrUnsigned:
            return "Ad-Hoc / Unsigned (Self-distributed DMG)"
        }
    }

    /// Inspects the running application's static code signature via the Security framework.
    static func current() -> CodeSigningStatus {
        guard let bundleURL = Bundle.main.bundleURL as CFURL? else {
            return .adHocOrUnsigned
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else {
            return .adHocOrUnsigned
        }

        var cfDict: CFDictionary?
        let flags: SecCSFlags = [SecCSFlags(rawValue: kSecCSSigningInformation)]
        guard SecCodeCopySigningInformation(code, flags, &cfDict) == errSecSuccess,
              let dict = cfDict as? [String: Any] else {
            return .adHocOrUnsigned
        }

        // Check if there is an Apple Team ID present
        if let teamId = dict[kSecCodeInfoTeamIdentifier as String] as? String, !teamId.isEmpty {
            return .developerId(teamId: teamId)
        }

        return .adHocOrUnsigned
    }
}

/// Comparison utility for semantic app versions and build numbers.
enum VersionComparator {
    /// Returns true if `remote` is strictly newer than `current`.
    static func isNewer(remoteVersion: String, remoteBuild: String, currentVersion: String, currentBuild: String) -> Bool {
        // Compare semantic version strings
        let vResult = compareVersionStrings(remoteVersion, currentVersion)
        if vResult == .orderedDescending {
            return true
        } else if vResult == .orderedAscending {
            return false
        }

        // If semantic versions match, compare integer build numbers
        if let rBuild = Int(remoteBuild), let cBuild = Int(currentBuild) {
            return rBuild > cBuild
        }

        return compareVersionStrings(remoteBuild, currentBuild) == .orderedDescending
    }

    private static func compareVersionStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rightParts = rhs.split(separator: ".").compactMap { Int($0) }

        let count = max(leftParts.count, rightParts.count)
        for i in 0..<count {
            let left = i < leftParts.count ? leftParts[i] : 0
            let right = i < rightParts.count ? rightParts[i] : 0
            if left > right { return .orderedDescending }
            if left < right { return .orderedAscending }
        }

        return .orderedSame
    }
}
