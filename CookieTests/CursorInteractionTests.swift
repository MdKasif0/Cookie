import XCTest
import AppKit
import SpriteKit
@testable import Cookie

@MainActor
final class CursorInteractionTests: XCTestCase {

    // MARK: - Proximity Zones & Scaling

    func testProximityZoneDefinitions() {
        XCTAssertEqual(CursorProximityZone.departure.displayName, "Departure")
        XCTAssertEqual(CursorProximityZone.awareness.displayName, "Awareness")
        XCTAssertEqual(CursorProximityZone.interaction.displayName, "Interaction")
        XCTAssertEqual(CursorProximityZone.closeContact.displayName, "Close Contact")
    }

    func testProximityZoneRadiiScaling() {
        let controller = CursorInteractionController()
        
        // Base scale 1.0
        XCTAssertEqual(controller.awarenessRadius(forScale: 1.0), 250.0)
        XCTAssertEqual(controller.interactionRadius(forScale: 1.0), 120.0)
        XCTAssertEqual(controller.closeContactRadius(forScale: 1.0), 55.0)
        XCTAssertEqual(controller.departureRadius(forScale: 1.0), 350.0)

        // Scaled up 1.4
        XCTAssertEqual(controller.awarenessRadius(forScale: 1.4), 250.0 * 1.4)
        XCTAssertEqual(controller.interactionRadius(forScale: 1.4), 120.0 * 1.4)
        XCTAssertEqual(controller.closeContactRadius(forScale: 1.4), 55.0 * 1.4)
        XCTAssertEqual(controller.departureRadius(forScale: 1.4), 350.0 * 1.4)
    }

    // MARK: - Coordinate Conversion & Multi-Display Support

    func testConvertScreenPointToScene() {
        let controller = CursorInteractionController()
        let windowFrame = CGRect(x: 200, y: 300, width: 220, height: 180)
        let sceneSize = CGSize(width: 220, height: 180)

        // Mouse directly at window center (310, 390)
        let mouseAtCenter = CGPoint(x: 310, y: 390)
        let scenePos = controller.convertScreenPointToScene(
            mouseAtCenter,
            windowFrame: windowFrame,
            sceneSize: sceneSize
        )

        // In SpriteKit scene centered around (0,0), window center maps to (0,0)
        XCTAssertEqual(scenePos.x, 0, accuracy: 0.001)
        XCTAssertEqual(scenePos.y, 0, accuracy: 0.001)

        // Mouse 50 pt to the right and 30 pt higher
        let mouseOffset = CGPoint(x: 360, y: 420)
        let offsetScenePos = controller.convertScreenPointToScene(
            mouseOffset,
            windowFrame: windowFrame,
            sceneSize: sceneSize
        )
        XCTAssertEqual(offsetScenePos.x, 50, accuracy: 0.001)
        XCTAssertEqual(offsetScenePos.y, 30, accuracy: 0.001)
    }

    func testMultiDisplayNegativeCoordinates() {
        let controller = CursorInteractionController()
        // External monitor to the left of main screen with negative x coordinates
        let windowFrame = CGRect(x: -1920, y: 100, width: 220, height: 180)
        let sceneSize = CGSize(width: 220, height: 180)

        let mouseOnLeftScreen = CGPoint(x: -1920 + 110, y: 100 + 90)
        let scenePos = controller.convertScreenPointToScene(
            mouseOnLeftScreen,
            windowFrame: windowFrame,
            sceneSize: sceneSize
        )

        XCTAssertEqual(scenePos.x, 0, accuracy: 0.001)
        XCTAssertEqual(scenePos.y, 0, accuracy: 0.001)
    }

    // MARK: - Movement Interpolator

    func testMovementInterpolatorAccelerationAndArrival() {
        var interpolator = MovementInterpolator(
            initialPosition: 0,
            acceleration: 400,
            deceleration: 500,
            maxSpeed: 200,
            arrivalThreshold: 2.0
        )

        XCTAssertEqual(interpolator.currentPosition, 0)
        XCTAssertEqual(interpolator.currentVelocity, 0)
        XCTAssertFalse(interpolator.isMoving)

        // Set target 100 pt away
        interpolator.setTarget(100)
        XCTAssertTrue(interpolator.isMoving)

        // Advance 0.1s
        _ = interpolator.update(deltaTime: 0.1)
        XCTAssertGreaterThan(interpolator.currentVelocity, 0)
        XCTAssertGreaterThan(interpolator.currentPosition, 0)
        XCTAssertLessThanOrEqual(interpolator.currentVelocity, 200)

        // Advance until arrival
        var totalTime: TimeInterval = 0
        while interpolator.isMoving && totalTime < 3.0 {
            _ = interpolator.update(deltaTime: 0.016)
            totalTime += 0.016
        }

        XCTAssertFalse(interpolator.isMoving)
        XCTAssertEqual(interpolator.currentPosition, 100, accuracy: 2.0)
        XCTAssertEqual(interpolator.currentVelocity, 0, accuracy: 0.001)
    }

    func testMovementInterpolatorMaxSpeedCap() {
        var interpolator = MovementInterpolator(
            initialPosition: 0,
            acceleration: 1000,
            deceleration: 1000,
            maxSpeed: 150,
            arrivalThreshold: 1.0
        )

        interpolator.setTarget(1000)
        // Run for 1.0s with high acceleration
        for _ in 0..<60 {
            _ = interpolator.update(deltaTime: 0.016)
            XCTAssertLessThanOrEqual(interpolator.currentVelocity, 150.001)
        }
    }

    func testMovementInterpolatorSnap() {
        var interpolator = MovementInterpolator(initialPosition: 50)
        interpolator.setTarget(200)
        _ = interpolator.update(deltaTime: 0.05)
        XCTAssertTrue(interpolator.isMoving)

        interpolator.snap(to: 350)
        XCTAssertEqual(interpolator.currentPosition, 350)
        XCTAssertEqual(interpolator.currentVelocity, 0)
        XCTAssertFalse(interpolator.isMoving)
    }

    // MARK: - Look Angle & Anatomical Limits

    func testLookAngleClampedToSafeLimits() {
        let controller = CursorInteractionController()
        let cookiePosition = CGPoint(x: 100, y: 100)

        // Mouse way up high and far (steep angle > 45 degrees)
        let mouseSteep = CGPoint(x: 120, y: 500)
        let angle = controller.calculateLookAngle(
            fromCookie: cookiePosition,
            toCursor: mouseSteep,
            facingRight: true
        )

        // Must be clamped to ±0.20 radians (~11.5 degrees)
        XCTAssertLessThanOrEqual(angle, 0.201)
        XCTAssertGreaterThanOrEqual(angle, -0.201)
    }

    func testLookAngleFacingDirection() {
        let controller = CursorInteractionController()
        let cookiePosition = CGPoint(x: 200, y: 200)

        // Mouse to the right and above
        let mouseRight = CGPoint(x: 300, y: 250)
        let angleRight = controller.calculateLookAngle(
            fromCookie: cookiePosition,
            toCursor: mouseRight,
            facingRight: true
        )
        XCTAssertGreaterThan(angleRight, 0)

        // Mouse to the left and above
        let mouseLeft = CGPoint(x: 100, y: 250)
        let angleLeft = controller.calculateLookAngle(
            fromCookie: cookiePosition,
            toCursor: mouseLeft,
            facingRight: false
        )
        XCTAssertGreaterThan(angleLeft, 0)
    }

    // MARK: - Intensity Levels

    func testFollowingIntensityPresets() {
        XCTAssertEqual(CursorFollowingIntensity.subtle.maxSpeed, 110)
        XCTAssertEqual(CursorFollowingIntensity.subtle.trailingDistance, 95)
        XCTAssertEqual(CursorFollowingIntensity.subtle.anticipationDelay, 0.6)

        XCTAssertEqual(CursorFollowingIntensity.balanced.maxSpeed, 160)
        XCTAssertEqual(CursorFollowingIntensity.balanced.trailingDistance, 75)
        XCTAssertEqual(CursorFollowingIntensity.balanced.anticipationDelay, 0.4)

        XCTAssertEqual(CursorFollowingIntensity.playful.maxSpeed, 220)
        XCTAssertEqual(CursorFollowingIntensity.playful.trailingDistance, 60)
        XCTAssertEqual(CursorFollowingIntensity.playful.anticipationDelay, 0.25)
    }

    // MARK: - Settings Persistence & Defaults

    func testCursorSettingsDefaultsAndReset() {
        var settings = CookieSettings()
        XCTAssertTrue(settings.cursorInteraction)
        XCTAssertTrue(settings.cursorFollowingEnabled)
        XCTAssertTrue(settings.cursorDodgingEnabled)
        XCTAssertEqual(settings.cursorFollowingIntensity, "balanced")

        // Mutate settings
        settings.cursorInteraction = false
        settings.cursorFollowingEnabled = false
        settings.cursorDodgingEnabled = false
        settings.cursorFollowingIntensity = "playful"

        XCTAssertFalse(settings.cursorInteraction)
        XCTAssertFalse(settings.cursorFollowingEnabled)

        // Reset
        settings.resetCursorInteractionSettings()
        XCTAssertTrue(settings.cursorInteraction)
        XCTAssertTrue(settings.cursorFollowingEnabled)
        XCTAssertTrue(settings.cursorDodgingEnabled)
        XCTAssertEqual(settings.cursorFollowingIntensity, "balanced")
    }

    // MARK: - Behavior Engine Priority & Interruption

    @MainActor
    func testBehaviorPriorityDraggingOverridesCursor() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-cursor-drag.json"))
        let engine = CookieBehaviorEngine(store: store)

        // Start following cursor
        engine.enter(.followingCursor)
        XCTAssertEqual(engine.state, .followingCursor)

        // User starts dragging Cookie (Priority 1)
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertFalse(engine.movementInterpolator.isMoving)
    }

    @MainActor
    func testBehaviorPriorityEmoteOverridesCursor() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("test-cursor-emote.json"))
        let engine = CookieBehaviorEngine(store: store)

        engine.enter(.followingCursor)
        XCTAssertEqual(engine.state, .followingCursor)

        // User triggers wave emote (Priority 2)
        engine.triggerEmote(.wave)
        XCTAssertEqual(engine.state, .emoting)
        XCTAssertEqual(engine.activeEmote?.id, .wave)
        XCTAssertFalse(engine.movementInterpolator.isMoving)
    }

    @MainActor
    func testRapidCursorMovementDoesNotTriggerChasing() {
        let controller = CursorInteractionController()
        
        // Rapid cursor movement simulation (> 600 pt/s)
        let rapidVelocity = CGVector(dx: 750, dy: 300)
        let state = controller.classifyMotion(velocity: rapidVelocity)
        XCTAssertEqual(state, .rapid)
    }

    // MARK: - Lifecycle Teardown

    func testTeardownCleansMonitorsAndObservers() {
        let controller = CursorInteractionController()
        controller.startTracking()
        // Teardown should be safe and idempotent
        controller.teardown()
        controller.teardown()
        XCTAssertFalse(controller.isCursorNear)
    }
}
