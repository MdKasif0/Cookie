import XCTest
import AppKit
@testable import Cookie

final class CookieMultiDisplayTests: XCTestCase {

    func testSafeOriginOnSingleDisplay() {
        // Mock a 1440x900 screen
        let frame = NSRect(x: 100, y: 100, width: 160, height: 160)
        let screens = NSScreen.screens

        let safe = CookieScreenGeometry.safeOrigin(for: frame, in: screens)
        XCTAssertFalse(safe.x.isNaN)
        XCTAssertFalse(safe.y.isNaN)
    }

    func testExternalMonitorUnpluggingRecovery() {
        // Simulate Cookie having been at x: 2500, y: 400 on an external 4K screen
        let disconnectedPosition = CGPoint(x: 2500, y: 400)
        let size = CGSize(width: 160, height: 160)

        // When restored with only the active Mac screens
        let restored = CookieScreenGeometry.restoreOrigin(
            saved: disconnectedPosition,
            size: size,
            screens: NSScreen.screens
        )

        // Must not be stranded at x: 2500
        if let mainScreen = NSScreen.main {
            XCTAssertLessThanOrEqual(restored.x, mainScreen.visibleFrame.maxX)
            XCTAssertGreaterThanOrEqual(restored.x, mainScreen.visibleFrame.minX - 20)
        }
    }

    func testResolutionShrinkageClamping() {
        // If window is at (1800, 800) and resolution is smaller, safeOrigin clamps it
        let oversizedFrame = NSRect(x: 1800, y: 800, width: 160, height: 160)
        let safe = CookieScreenGeometry.safeOrigin(for: oversizedFrame, in: NSScreen.screens)

        if let mainScreen = NSScreen.main {
            let vis = mainScreen.visibleFrame
            XCTAssertLessThanOrEqual(safe.x, vis.maxX)
            XCTAssertLessThanOrEqual(safe.y, vis.maxY)
        }
    }

    @MainActor
    func testCompanionPanelCollectionBehaviorAcrossSpaces() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-panel.json"))
        let behaviorEngine = CookieBehaviorEngine(store: store)
        let audioManager = AudioManager(store: store)

        let controller = CompanionPanelController(
            store: store,
            behaviorEngine: behaviorEngine,
            audioManager: audioManager
        )

        guard let window = controller.window else {
            XCTFail("Companion window should exist")
            return
        }

        // Must be non-activating floating panel on all spaces
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(window.level, .floating)
    }
}
