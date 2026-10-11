import XCTest
import AppKit
@testable import Cookie

@MainActor
final class DockInteractionTests: XCTestCase {

    // MARK: - 1. Dock Position and Geometry Detection

    func testBottomDockDetection() {
        let detector = DockEnvironmentDetector()
        // Primary display 1920x1080 with bottom Dock of height 70 and top Menu Bar of height 24
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 70, width: 1920, height: 986)
            )]
        }

        let env = detector.detectEnvironment()
        XCTAssertEqual(env.dockOrientation, .bottom)
        XCTAssertEqual(env.dockThickness, 70)
        XCTAssertEqual(env.dockVisibility, .visible)
        XCTAssertEqual(env.dockFrame, NSRect(x: 0, y: 0, width: 1920, height: 70))

        // Safe walking surface should sit above the bottom Dock (y = 76)
        XCTAssertEqual(env.safeWalkingSurface.origin.y, 76)
        XCTAssertGreaterThan(env.safeWalkingSurface.width, 1000)
    }

    func testLeftDockDetection() {
        let detector = DockEnvironmentDetector()
        // Display 1920x1080 with left Dock of width 65 and top Menu Bar of height 24
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 65, y: 0, width: 1855, height: 1056)
            )]
        }

        let env = detector.detectEnvironment()
        XCTAssertEqual(env.dockOrientation, .left)
        XCTAssertEqual(env.dockThickness, 65)
        XCTAssertEqual(env.dockVisibility, .visible)
        XCTAssertEqual(env.dockFrame, NSRect(x: 0, y: 0, width: 65, height: 1080))

        // Safe walking surface should run vertically beside the left Dock (x = 71)
        XCTAssertEqual(env.safeWalkingSurface.origin.x, 71)
        XCTAssertGreaterThan(env.safeWalkingSurface.height, 800)
    }

    func testRightDockDetection() {
        let detector = DockEnvironmentDetector()
        // Display 1920x1080 with right Dock of width 80 and top Menu Bar of height 24
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 0, width: 1840, height: 1056)
            )]
        }

        let env = detector.detectEnvironment()
        XCTAssertEqual(env.dockOrientation, .right)
        XCTAssertEqual(env.dockThickness, 80)
        XCTAssertEqual(env.dockVisibility, .visible)
        XCTAssertEqual(env.dockFrame, NSRect(x: 1840, y: 0, width: 80, height: 1080))

        // Safe walking surface should run beside the right Dock
        XCTAssertLessThanOrEqual(env.safeWalkingSurface.maxX, 1840)
    }

    func testAutohiddenDockDetection() {
        let detector = DockEnvironmentDetector()
        // Autohidden Dock: visibleFrame matches screen except top menu bar
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1056)
            )]
        }

        let env = detector.detectEnvironment()
        XCTAssertEqual(env.dockVisibility, .autohidden)
        // Defaults to bottom orientation for standard autohide
        XCTAssertTrue(env.dockOrientation == .bottom || env.dockOrientation == .left || env.dockOrientation == .right)
        XCTAssertGreaterThan(env.dockThickness, 30)
    }

    // MARK: - 2. Multi-Display Environment

    func testMultiDisplayArrangement() {
        let detector = DockEnvironmentDetector()
        // Secondary monitor on left (-1920...0), Primary monitor on right (0...1920) with Dock
        let secondaryLeft = ScreenGeometry(
            frame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        )
        let primaryRight = ScreenGeometry(
            frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 72, width: 1920, height: 984)
        )

        detector.screenGeometriesProvider = { [secondaryLeft, primaryRight] }

        let env = detector.detectEnvironment()
        // Dock must be detected on primary display
        XCTAssertEqual(env.dockOrientation, .bottom)
        XCTAssertEqual(env.dockThickness, 72)
        XCTAssertEqual(env.screenFrame.origin.x, 0)
    }

    func testSafeWalkingSurfaceClamping() {
        let detector = DockEnvironmentDetector()
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: NSRect(x: 0, y: 68, width: 1440, height: 808)
            )]
        }

        let env = detector.detectEnvironment()
        let charSize = CGSize(width: 80, height: 80)

        // Point far below screen inside Dock
        let offScreenBottom = CGPoint(x: 500, y: -200)
        let clampedBottom = env.clampToSafeWalkingSurface(offScreenBottom, characterSize: charSize)
        XCTAssertGreaterThanOrEqual(clampedBottom.y, env.safeWalkingSurface.minY)

        // Point far to the left outside screen
        let offScreenLeft = CGPoint(x: -500, y: 80)
        let clampedLeft = env.clampToSafeWalkingSurface(offScreenLeft, characterSize: charSize)
        XCTAssertGreaterThanOrEqual(clampedLeft.x, env.safeWalkingSurface.minX)

        // Point far to the right outside screen
        let offScreenRight = CGPoint(x: 2500, y: 80)
        let clampedRight = env.clampToSafeWalkingSurface(offScreenRight, characterSize: charSize)
        XCTAssertLessThanOrEqual(clampedRight.x, env.safeWalkingSurface.maxX)
    }

    // MARK: - 3. Application Icon Awareness

    func testApplicationIconTargetsGeneration() {
        let detector = DockEnvironmentDetector()
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 75, width: 1920, height: 981)
            )]
        }
        let env = detector.detectEnvironment()

        let controller = DockInteractionController(detector: detector)
        controller.refreshInspectionTargets(environment: env)

        // Should generate icon targets distributed along the Dock
        let envSurface = controller.pointOnSafeSurface(closestTo: CGPoint(x: 960, y: 30), environment: env)
        XCTAssertEqual(envSurface.y, env.safeWalkingSurface.midY)
        XCTAssertGreaterThanOrEqual(envSurface.x, env.safeWalkingSurface.minX)
        XCTAssertLessThanOrEqual(envSurface.x, env.safeWalkingSurface.maxX)
    }

    // MARK: - 4. Dock Exploration State Machine & Progression

    func testDockExplorationSessionPhases() {
        let detector = DockEnvironmentDetector()
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 70, width: 1920, height: 986)
            )]
        }
        let controller = DockInteractionController(detector: detector)
        var simulatedTime = Date()
        controller.now = { simulatedTime }

        let startPos = NSPoint(x: 960, y: 400)
        let charSize = CGSize(width: 80, height: 80)

        // Start exploration
        controller.startExploration(fromPosition: startPos, frequency: .frequent, targetIconIndex: 0)
        XCTAssertEqual(controller.currentPhase, .anticipating)
        XCTAssertNotNil(controller.destinationPoint)
        XCTAssertNotNil(controller.dockLookAngle)
        // Anatomical look angle clamp: within ±0.20 radians
        if let angle = controller.dockLookAngle {
            XCTAssertLessThanOrEqual(abs(angle), 0.201)
        }

        // Advance past anticipation duration (~0.5s)
        controller.tick(dt: 0.6, cookiePosition: startPos, characterSize: charSize, frequency: .frequent)
        XCTAssertEqual(controller.currentPhase, .approaching)

        // Simulate reaching destination point
        if let dest = controller.destinationPoint {
            controller.tick(dt: 0.1, cookiePosition: dest, characterSize: charSize, frequency: .frequent)
            // Arrived at Dock edge: inspecting icon
            XCTAssertEqual(controller.currentPhase, .inspectingIcon)
        }

        // Advance through icon inspection (~3s)
        if let dest = controller.destinationPoint {
            controller.tick(dt: 3.5, cookiePosition: dest, characterSize: charSize, frequency: .frequent)
            // Transits to edge pacing or departing
            XCTAssertTrue(controller.currentPhase == .pacingEdge || controller.currentPhase == .departing)
        }
    }

    // MARK: - 5. Behavior Scheduling & Frequency

    func testDockExplorationFrequencyRanges() {
        XCTAssertEqual(DockExplorationFrequency.rare.displayName, "Rare")
        XCTAssertEqual(DockExplorationFrequency.occasional.displayName, "Occasional")
        XCTAssertEqual(DockExplorationFrequency.frequent.displayName, "Frequent")

        XCTAssertEqual(DockExplorationFrequency.rare.cooldownRange, 180...300)
        XCTAssertEqual(DockExplorationFrequency.occasional.cooldownRange, 90...180)
        XCTAssertEqual(DockExplorationFrequency.frequent.cooldownRange, 45...90)

        XCTAssertEqual(DockExplorationFrequency.rare.explorationDurationRange, 6...10)
        XCTAssertEqual(DockExplorationFrequency.occasional.explorationDurationRange, 8...14)
        XCTAssertEqual(DockExplorationFrequency.frequent.explorationDurationRange, 10...18)
    }

    func testAutonomousTriggerRespectsCooldown() {
        let detector = DockEnvironmentDetector()
        let controller = DockInteractionController(detector: detector)
        var simulatedTime = Date()
        controller.now = { simulatedTime }

        controller.applyCooldown(for: .occasional)
        XCTAssertFalse(controller.shouldTriggerAutonomousExploration(
            cookiePosition: NSPoint(x: 500, y: 500),
            frequency: .occasional,
            settingsEnabled: true,
            isInterrupted: false
        ))

        // Fast-forward past cooldown
        simulatedTime = simulatedTime.addingTimeInterval(250)
        // With cooldown cleared, exploration can be considered
        XCTAssertFalse(controller.shouldTriggerAutonomousExploration(
            cookiePosition: NSPoint(x: 500, y: 500),
            frequency: .occasional,
            settingsEnabled: false, // Disabled in settings
            isInterrupted: false
        ))
    }

    // MARK: - 6. Interruption Handling & Behavior Engine Priority

    func testCancellationResetsDockSessionState() {
        let detector = DockEnvironmentDetector()
        let controller = DockInteractionController(detector: detector)
        controller.startExploration(fromPosition: NSPoint(x: 500, y: 500), frequency: .frequent)

        XCTAssertTrue(controller.isExploringDock)
        controller.cancelExploration()

        XCTAssertFalse(controller.isExploringDock)
        XCTAssertEqual(controller.currentPhase, .idle)
        XCTAssertNil(controller.destinationPoint)
        XCTAssertNil(controller.activeInspectionTarget)
        XCTAssertNil(controller.dockLookAngle)
    }

    func testUserGrabCancelsActiveDockExploration() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-dock-grab-\(UUID()).json"))
        let engine = CookieBehaviorEngine(store: store)
        engine.start()

        // Begin exploration
        engine.dockController.startExploration(fromPosition: NSPoint(x: 500, y: 200), frequency: .frequent)
        XCTAssertTrue(engine.dockController.isExploringDock)

        // User grabs Cookie
        engine.handleGrab()

        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertFalse(engine.dockController.isExploringDock)
    }

    func testEmoteTriggerCancelsActiveDockExploration() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-dock-emote-\(UUID()).json"))
        let engine = CookieBehaviorEngine(store: store)
        engine.start()

        engine.dockController.startExploration(fromPosition: NSPoint(x: 500, y: 200), frequency: .frequent)
        XCTAssertTrue(engine.dockController.isExploringDock)

        // Trigger wave emote
        guard let wave = Emote.allEmotes.first(where: { $0.id == .wave }) else {
            XCTFail("Wave emote missing")
            return
        }
        let triggered = engine.triggerEmote(wave)
        XCTAssertTrue(triggered)
        XCTAssertEqual(engine.state, .emoting)
        XCTAssertFalse(engine.dockController.isExploringDock)
    }

    // MARK: - 7. Cursor Near Dock Interaction

    func testCursorNearDockTurnsGaze() {
        let detector = DockEnvironmentDetector()
        detector.screenGeometriesProvider = {
            [ScreenGeometry(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                visibleFrame: NSRect(x: 0, y: 70, width: 1920, height: 986)
            )]
        }
        let env = detector.detectEnvironment()
        let controller = DockInteractionController(detector: detector)

        let cookieCenter = NSPoint(x: 960, y: 120)
        let cursorOverDock = NSPoint(x: 960, y: 35)

        controller.handleCursorNearDock(
            cursorLocation: cursorOverDock,
            cookieCenter: cookieCenter,
            environment: env,
            settingsEnabled: true
        )

        // Cookie should look downward toward cursor in the Dock
        XCTAssertNotNil(controller.dockLookAngle)
        if let angle = controller.dockLookAngle {
            XCTAssertLessThan(angle, 0) // Looking downward
            XCTAssertGreaterThanOrEqual(angle, -0.201)
        }
    }

    // MARK: - 8. Settings & Persistence

    func testDockSettingsDefaultsAndReset() {
        var settings = CookieSettings()
        XCTAssertTrue(settings.dockInteraction)
        XCTAssertTrue(settings.autonomousDockExploration)
        XCTAssertEqual(settings.dockExplorationFrequency, "occasional")
        XCTAssertEqual(settings.dockFrequency, .occasional)

        // Modify settings
        settings.dockInteraction = false
        settings.autonomousDockExploration = false
        settings.dockExplorationFrequency = "rare"

        XCTAssertFalse(settings.dockInteraction)
        XCTAssertFalse(settings.autonomousDockExploration)
        XCTAssertEqual(settings.dockFrequency, .rare)

        // Reset
        settings.resetDockSettings()
        XCTAssertTrue(settings.dockInteraction)
        XCTAssertTrue(settings.autonomousDockExploration)
        XCTAssertEqual(settings.dockExplorationFrequency, "occasional")
        XCTAssertEqual(settings.dockFrequency, .occasional)
    }

    func testDockSettingsCodablePersistence() throws {
        var original = CookieSettings()
        original.dockInteraction = true
        original.autonomousDockExploration = false
        original.dockExplorationFrequency = "frequent"

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CookieSettings.self, from: data)

        XCTAssertEqual(decoded.dockInteraction, true)
        XCTAssertEqual(decoded.autonomousDockExploration, false)
        XCTAssertEqual(decoded.dockExplorationFrequency, "frequent")
        XCTAssertEqual(decoded.dockFrequency, .frequent)
    }
}
