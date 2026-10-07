import XCTest
@testable import Cookie

final class CookieStoreTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CookieStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    @MainActor
    func testFirstLaunchInitializesDefaults() {
        let storeURL = tempDirectory.appendingPathComponent("store.json")
        let store = CookieStore(storageURL: storeURL)

        XCTAssertEqual(store.profile.name, "Cookie")
        XCTAssertEqual(store.profile.personality, .playful)
        XCTAssertTrue(store.profile.isCompanionVisible)
        XCTAssertFalse(store.profile.hasCompletedWelcome)
        XCTAssertEqual(store.statistics.launchCount, 0)
        XCTAssertEqual(store.schemaVersion, VersionedStoreEnvelope.currentSchemaVersion)
    }

    @MainActor
    func testRoundTripAtomicPersistence() {
        let storeURL = tempDirectory.appendingPathComponent("store.json")
        let store = CookieStore(storageURL: storeURL)

        store.profile.name = "Biscuit"
        store.profile.personality = .curious
        store.statistics.petsReceived = 15
        store.statistics.recordToyPlayed(.yarnBall)
        store.statistics.recordToyPlayed(.yarnBall)
        store.statistics.recordToyPlayed(.box)
        store.profile.lastRestingState = .sleeping
        store.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        // Reload fresh from disk
        let reloaded = CookieStore(storageURL: storeURL)
        XCTAssertEqual(reloaded.profile.name, "Biscuit")
        XCTAssertEqual(reloaded.profile.personality, .curious)
        XCTAssertEqual(reloaded.statistics.petsReceived, 15)
        XCTAssertEqual(reloaded.statistics.toysPlayedWith, 3)
        XCTAssertEqual(reloaded.statistics.favoriteToy, .yarnBall)
        XCTAssertEqual(reloaded.statistics.totalInteractions, 18)
        XCTAssertEqual(reloaded.profile.lastRestingState, .sleeping)
        XCTAssertEqual(reloaded.schemaVersion, VersionedStoreEnvelope.currentSchemaVersion)
    }

    @MainActor
    func testLegacySchema1Migration() throws {
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        // Write a legacy unversioned Schema 1 JSON
        let legacyJSON = """
        {
          "profile": {
            "name": "Mochi",
            "personality": "sleepy",
            "isCompanionVisible": true,
            "hasCompletedWelcome": true
          },
          "statistics": {
            "launchCount": 4,
            "petsReceived": 10,
            "affection": 8
          }
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: storeURL)

        let store = CookieStore(storageURL: storeURL)
        XCTAssertEqual(store.profile.name, "Mochi")
        XCTAssertEqual(store.profile.personality, .sleepy)
        XCTAssertEqual(store.statistics.launchCount, 4)
        XCTAssertEqual(store.statistics.petsReceived, 10)
        XCTAssertEqual(store.schemaVersion, VersionedStoreEnvelope.currentSchemaVersion)

        // Ensure flush writes the new versioned envelope
        store.flush()
        let rawData = try Data(contentsOf: storeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(VersionedStoreEnvelope.self, from: rawData)
        XCTAssertEqual(envelope.schemaVersion, VersionedStoreEnvelope.currentSchemaVersion)
        XCTAssertEqual(envelope.profile.name, "Mochi")
    }

    @MainActor
    func testCorruptDataIsQuarantinedGracefully() throws {
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        // Write corrupt/truncated JSON
        let corruptBytes = "{ this is corrupted json data !!!".data(using: .utf8)!
        try corruptBytes.write(to: storeURL)

        let store = CookieStore(storageURL: storeURL)
        // Must recover safely with clean defaults without crashing
        XCTAssertEqual(store.profile.name, "Cookie")
        XCTAssertEqual(store.statistics.launchCount, 0)

        // Verify quarantined file was created to safeguard user bytes
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        let hasQuarantine = contents.contains { $0.contains("corrupted-") }
        XCTAssertTrue(hasQuarantine, "Corrupted file should be safely quarantined")
    }

    @MainActor
    func testMissingFieldsFallbackGracefully() throws {
        let storeURL = tempDirectory.appendingPathComponent("store.json")

        // Minimal sparse JSON
        let sparseJSON = """
        {
          "schemaVersion": 2,
          "savedAt": "2026-10-07T12:00:00Z",
          "profile": {
            "name": "Buttercup"
          },
          "statistics": {}
        }
        """
        try sparseJSON.data(using: .utf8)!.write(to: storeURL)

        let store = CookieStore(storageURL: storeURL)
        XCTAssertEqual(store.profile.name, "Buttercup")
        XCTAssertEqual(store.profile.personality, .playful, "Missing personality defaults safely")
        XCTAssertTrue(store.profile.settings.soundEnabled, "Missing settings default safely")
    }
}
