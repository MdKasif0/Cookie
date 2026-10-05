import Foundation
import os

/// The persistence layer. Owns the profile and statistics, publishes
/// changes to SwiftUI, and writes them as JSON to Application Support.
/// Everything stays local to the Mac.
@MainActor
final class CookieStore: ObservableObject {
    private static let subsystem = "com.cookie.mac"

    @Published var profile: CookieProfile {
        didSet { schedulePersist() }
    }

    @Published var statistics: CookieStatistics {
        didSet { schedulePersist() }
    }

    private let storageURL: URL
    private var persistTimer: Timer?

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let supportDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cookie", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            self.storageURL = supportDirectory.appendingPathComponent("cookie-store.json")
        }

        if let data = try? Data(contentsOf: self.storageURL),
           let decoder = Self.makeDecoder(),
           let decoded = try? decoder.decode(StoredData.self, from: data) {
            profile = decoded.profile
            statistics = decoded.statistics
        } else {
            // A file we cannot read must not be silently destroyed —
            // keep it aside for recovery and start fresh.
            if FileManager.default.fileExists(atPath: self.storageURL.path) {
                let backupURL = self.storageURL.appendingPathExtension("unreadable")
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.moveItem(at: self.storageURL, to: backupURL)
            }
            profile = CookieProfile()
            statistics = CookieStatistics()
        }
    }

    /// Wipes everything and returns Cookie to a fresh first-run state.
    func reset() {
        profile = CookieProfile()
        statistics = CookieStatistics()
        persistNow()
    }

    /// Writes immediately; called on quit so nothing is lost.
    func flush() {
        persistTimer?.invalidate()
        persistTimer = nil
        persistNow()
    }

    // MARK: - Persistence

    private struct StoredData: Codable {
        var profile: CookieProfile
        var statistics: CookieStatistics
    }

    /// Encoder and decoder must use identical date strategies, or every
    /// relaunch would silently fail to read what the last launch wrote.
    private static func makeDecoder() -> JSONDecoder? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistTimer = nil
                self?.persistNow()
            }
        }
    }

    private func persistNow() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(StoredData(profile: profile, statistics: statistics))
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Logger(subsystem: Self.subsystem, category: "Persistence")
                .error("Could not save store: \(error.localizedDescription)")
        }
    }
}
