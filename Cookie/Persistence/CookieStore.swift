import Foundation
import os

/// Versioned persistence envelope for Cookie's local state.
struct VersionedStoreEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var savedAt: Date
    var profile: CookieProfile
    var statistics: CookieStatistics

    init(schemaVersion: Int = Self.currentSchemaVersion,
         savedAt: Date = Date(),
         profile: CookieProfile,
         statistics: CookieStatistics) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.profile = profile
        self.statistics = statistics
    }
}

/// Legacy unversioned container (Schema 1) for seamless migration.
private struct LegacyStoredData: Codable {
    var profile: CookieProfile
    var statistics: CookieStatistics
}

/// The persistence layer. Owns the profile and statistics, publishes
/// changes to SwiftUI, and writes them safely as JSON to Application Support.
/// Everything stays 100% local to the user's Mac with zero external telemetry.
@MainActor
final class CookieStore: ObservableObject {
    private static let subsystem = "com.cookie.mac"
    private static let log = Logger(subsystem: subsystem, category: "Persistence")

    @Published var profile: CookieProfile {
        didSet { schedulePersist() }
    }

    @Published var statistics: CookieStatistics {
        didSet { schedulePersist() }
    }

    private(set) var schemaVersion: Int = VersionedStoreEnvelope.currentSchemaVersion
    private(set) var lastSavedAt: Date?

    let storageURL: URL
    private var persistTimer: Timer?

    init(storageURL: URL? = nil) {
        let resolvedURL: URL
        if let storageURL {
            resolvedURL = storageURL
        } else {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
            let cookieDir = appSupport.appendingPathComponent("Cookie", isDirectory: true)
            try? fileManager.createDirectory(at: cookieDir, withIntermediateDirectories: true)
            resolvedURL = cookieDir.appendingPathComponent("cookie-store.json")
        }
        self.storageURL = resolvedURL

        // Attempt load with resilient decoding and automatic migration.
        let loaded = Self.loadStore(from: resolvedURL)
        self.profile = loaded.profile
        self.statistics = loaded.statistics
        self.schemaVersion = loaded.schemaVersion
        self.lastSavedAt = loaded.savedAt
    }

    /// Wipes everything and returns Cookie to a fresh first-run state.
    func reset() {
        profile = CookieProfile()
        statistics = CookieStatistics()
        schemaVersion = VersionedStoreEnvelope.currentSchemaVersion
        lastSavedAt = Date()
        persistNow()
    }

    /// Writes immediately; called on quit/backgrounding so nothing is lost.
    func flush() {
        persistTimer?.invalidate()
        persistTimer = nil
        persistNow()
    }

    // MARK: - Loading & Migration Pipeline

    private static func loadStore(from url: URL) -> (profile: CookieProfile, statistics: CookieStatistics, schemaVersion: Int, savedAt: Date?) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            log.info("First launch or clean store: starting with defaults at \(url.path, privacy: .public)")
            return (CookieProfile(), CookieStatistics(), VersionedStoreEnvelope.currentSchemaVersion, nil)
        }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            quarantineCorruptFile(at: url, reason: "empty or unreadable file")
            return (CookieProfile(), CookieStatistics(), VersionedStoreEnvelope.currentSchemaVersion, nil)
        }

        let decoder = makeDecoder()

        // 1. Try decoding the current versioned envelope.
        if let envelope = try? decoder.decode(VersionedStoreEnvelope.self, from: data) {
            let migrated = applyMigrationsIfNeeded(envelope: envelope)
            return (migrated.profile, migrated.statistics, migrated.schemaVersion, migrated.savedAt)
        }

        // 2. Try decoding legacy unversioned structure (Schema 1).
        if let legacy = try? decoder.decode(LegacyStoredData.self, from: data) {
            log.info("Migrated unversioned store (Schema 1) to Schema \(VersionedStoreEnvelope.currentSchemaVersion, privacy: .public)")
            return (legacy.profile, legacy.statistics, VersionedStoreEnvelope.currentSchemaVersion, Date())
        }

        // 3. Data is corrupted or unrecognized: quarantine to preserve user state and start clean.
        quarantineCorruptFile(at: url, reason: "json decoding failed")
        return (CookieProfile(), CookieStatistics(), VersionedStoreEnvelope.currentSchemaVersion, nil)
    }

    private static func applyMigrationsIfNeeded(envelope: VersionedStoreEnvelope) -> VersionedStoreEnvelope {
        var current = envelope
        if current.schemaVersion < VersionedStoreEnvelope.currentSchemaVersion {
            log.info("Upgrading store from schema v\(current.schemaVersion, privacy: .public) to v\(VersionedStoreEnvelope.currentSchemaVersion, privacy: .public)")
            // Future schema-specific field migrations go here:
            current.schemaVersion = VersionedStoreEnvelope.currentSchemaVersion
        }
        return current
    }

    private static func quarantineCorruptFile(at url: URL, reason: String) {
        log.warning("Quarantining corrupt store file (\(reason, privacy: .public)): \(url.path, privacy: .public)")
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantineURL = url.deletingPathExtension().appendingPathExtension("corrupted-\(timestamp).json")
        try? FileManager.default.removeItem(at: quarantineURL)
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
    }

    // MARK: - Encoders / Decoders

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Debounced & Atomic Persistence

    private func schedulePersist() {
        persistTimer?.invalidate()
        persistTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistTimer = nil
                self?.persistNow()
            }
        }
    }

    func persistNow() {
        let envelope = VersionedStoreEnvelope(
            schemaVersion: VersionedStoreEnvelope.currentSchemaVersion,
            savedAt: Date(),
            profile: profile,
            statistics: statistics
        )
        lastSavedAt = envelope.savedAt

        do {
            let encoder = Self.makeEncoder()
            let data = try encoder.encode(envelope)

            let parentDir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Safe atomic write: write to temp file first, then atomically replace.
            let tempURL = storageURL.deletingLastPathComponent()
                .appendingPathComponent("cookie-store-\(UUID().uuidString).tmp")
            try data.write(to: tempURL, options: .atomic)

            _ = try FileManager.default.replaceItemAt(
                storageURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: .withoutDeletingBackupItem
            )
        } catch {
            Self.log.error("Could not atomically save store: \(error.localizedDescription, privacy: .public)")
        }
    }
}
