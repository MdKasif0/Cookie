import XCTest
import CryptoKit
@testable import Cookie

final class UpdateSystemTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateSystemTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - 1. Version Comparison Tests

    func testVersionComparisonNewerVersions() {
        XCTAssertTrue(VersionComparator.isNewer(remoteVersion: "1.0.1", remoteBuild: "2", currentVersion: "1.0.0", currentBuild: "1"))
        XCTAssertTrue(VersionComparator.isNewer(remoteVersion: "1.1.0", remoteBuild: "1", currentVersion: "1.0.9", currentBuild: "1"))
        XCTAssertTrue(VersionComparator.isNewer(remoteVersion: "2.0.0", remoteBuild: "1", currentVersion: "1.9.9", currentBuild: "1"))
        XCTAssertTrue(VersionComparator.isNewer(remoteVersion: "1.0.0", remoteBuild: "5", currentVersion: "1.0.0", currentBuild: "1"))
    }

    func testVersionComparisonSameOrOlderVersions() {
        XCTAssertFalse(VersionComparator.isNewer(remoteVersion: "1.0.0", remoteBuild: "1", currentVersion: "1.0.0", currentBuild: "1"))
        XCTAssertFalse(VersionComparator.isNewer(remoteVersion: "0.9.9", remoteBuild: "9", currentVersion: "1.0.0", currentBuild: "1"))
        XCTAssertFalse(VersionComparator.isNewer(remoteVersion: "1.0.0", remoteBuild: "1", currentVersion: "1.0.0", currentBuild: "2"))
    }

    // MARK: - 2. Appcast Parser Tests

    func testAppcastParserValidFeed() throws {
        let sampleXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>Cookie Feed</title>
            <item>
              <title>Cookie 1.0.1</title>
              <pubDate>Sat, 10 Oct 2026 12:00:00 +0000</pubDate>
              <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
              <description><![CDATA[
                <p>Cozy updates for Cookie.</p>
                <ul>
                  <li>New animations.</li>
                </ul>
              ]]></description>
              <enclosure
                url="https://github.com/MdKasif0/Cookie/releases/download/v1.0.1/Cookie-1.0.1.dmg"
                sparkle:version="2"
                sparkle:shortVersionString="1.0.1"
                length="15672083"
                type="application/octet-stream"
                sparkle:edSignature="8OO3ejvZ4CsDUt6QB1NLcg60vC0yDP/oG7zJdpVHPPcA3RFwaqeBd9AdHwXSG6oaLIk9N+vW7PWE2InZSxKJAA=="/>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let items = try AppcastParser.parse(data: sampleXML)
        XCTAssertEqual(items.count, 1)

        let item = items[0]
        XCTAssertEqual(item.version, "1.0.1")
        XCTAssertEqual(item.buildNumber, "2")
        XCTAssertEqual(item.downloadURL.absoluteString, "https://github.com/MdKasif0/Cookie/releases/download/v1.0.1/Cookie-1.0.1.dmg")
        XCTAssertEqual(item.fileSize, 15672083)
        XCTAssertEqual(item.minimumSystemVersion, "14.0")
        XCTAssertEqual(item.edSignature, "8OO3ejvZ4CsDUt6QB1NLcg60vC0yDP/oG7zJdpVHPPcA3RFwaqeBd9AdHwXSG6oaLIk9N+vW7PWE2InZSxKJAA==")
        XCTAssertFalse(item.releaseNotes.contains("<p>"))
    }

    func testAppcastParserEmptyOrInvalidFeed() {
        let emptyXML = "<rss></rss>".data(using: .utf8)!
        let items = (try? AppcastParser.parse(data: emptyXML)) ?? []
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - 3. Cryptographic EdDSA Public Key Integrity

    func testEdDSAPublicKeyConfigured() throws {
        let expectedPublicKeyBase64 = "K/cA2KeUVBekRx1d1+DA0Fnhaj20UWK0DG7Ij8mPiBU="
        guard let data = Data(base64Encoded: expectedPublicKeyBase64) else {
            XCTFail("Public key is not valid base64")
            return
        }
        // Ed25519 public keys are strictly 32 bytes
        XCTAssertEqual(data.count, 32, "Ed25519 public key must be exactly 32 bytes")

        // Check Info.plist value in bundle
        let plistKey = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String
        if let plistKey = plistKey {
            XCTAssertEqual(plistKey, expectedPublicKeyBase64)
        }
    }

    func testEdDSASignatureTamperDetection() throws {
        // Create an Ed25519 keypair for cryptographic verification test
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let testPayload = "Cookie-1.0.1.dmg-payload".data(using: .utf8)!
        let validSignature = try privateKey.signature(for: testPayload)

        // Valid signature verifies
        XCTAssertTrue(publicKey.isValidSignature(validSignature, for: testPayload))

        // Tampered payload fails verification
        let tamperedPayload = "Cookie-1.0.1-malicious.dmg".data(using: .utf8)!
        XCTAssertFalse(publicKey.isValidSignature(validSignature, for: tamperedPayload))

        // Tampered signature fails verification
        var badSigData = validSignature
        badSigData[0] ^= 0xFF
        XCTAssertFalse(publicKey.isValidSignature(badSigData, for: testPayload))
    }

    // MARK: - 4. Code Signing & Distribution Compatibility

    func testCodeSigningStatusIdentification() {
        let status = CodeSigningStatus.current()
        // In unit testing environment / current repo setup, status should be identifiable
        switch status {
        case .adHocOrUnsigned:
            XCTAssertEqual(status.description, "Ad-Hoc / Unsigned (Self-distributed DMG)")
        case .developerId:
            XCTAssertEqual(status.description, "Developer ID Signed")
        }
    }

    // MARK: - 5. Settings Preservation Tests

    @MainActor
    func testUpdateSettingsPreservation() {
        let storeURL = tempDirectory.appendingPathComponent("store.json")
        let store = CookieStore(storageURL: storeURL)

        // Initial default is false
        XCTAssertFalse(store.profile.settings.automaticallyCheckForUpdates)

        // Change setting and persist
        store.profile.settings.automaticallyCheckForUpdates = true
        store.profile.name = "Mocha"
        store.flush()

        // Reload fresh from disk
        let reloaded = CookieStore(storageURL: storeURL)
        XCTAssertTrue(reloaded.profile.settings.automaticallyCheckForUpdates)
        XCTAssertEqual(reloaded.profile.name, "Mocha")
    }

    // MARK: - 6. UpdateManager States

    @MainActor
    func testUpdateCheckStates() {
        let manager = UpdateManager.shared

        // Initial state should be idle or checking
        XCTAssertFalse(manager.state.isUpdateAvailable)

        let testInfo = UpdateInfo(
            version: "2.0.0",
            buildNumber: "10",
            title: "Major Cookie Update",
            releaseNotes: "Exciting new treats and toys!",
            downloadURL: URL(string: "https://cookiecat.app/Cookie-2.0.0.dmg")!,
            fileSize: 15_000_000,
            edSignature: "test-sig",
            minimumSystemVersion: "14.0",
            isCritical: false,
            publishedDate: Date()
        )

        manager.state = .updateAvailable(info: testInfo)
        XCTAssertTrue(manager.state.isUpdateAvailable)

        manager.state = .upToDate(lastChecked: Date())
        XCTAssertFalse(manager.state.isUpdateAvailable)
        XCTAssertFalse(manager.state.isCheckingOrBusy)

        manager.state = .error(title: "Network Error", message: "Failed to fetch feed")
        if case .error(let title, _) = manager.state {
            XCTAssertEqual(title, "Network Error")
        } else {
            XCTFail("Expected error state")
        }
    }
}
