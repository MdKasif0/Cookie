import XCTest
import AppKit
@testable import Cookie

@MainActor
final class JumpInteractionTests: XCTestCase {

    // MARK: - Helper Mock Factories

    private func makeRawWindowDict(
        id: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        layer: Int = 0,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> [String: Any] {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let boundsDict = rect.dictionaryRepresentation as NSDictionary
        return [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: ownerPID,
            kCGWindowOwnerName as String: ownerName,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: boundsDict
        ]
    }

    // MARK: - 1. Trajectory Mathematical Plausibility

    func testJumpTrajectoryParabolicMath() {
        let start = CGPoint(x: 100, y: 200)
        let end = CGPoint(x: 300, y: 250)
        let duration: TimeInterval = 0.8
        let apexHeight: CGFloat = 40.0

        let trajectory = JumpTrajectory(
            startPoint: start,
            endPoint: end,
            duration: duration,
            apexHeight: apexHeight,
            style: .gentle
        )

        // 1. Boundary conditions at progress 0.0 (launch)
        let p0 = trajectory.point(at: 0.0)
        XCTAssertEqual(p0.x, 100, accuracy: 0.001)
        XCTAssertEqual(p0.y, 200, accuracy: 0.001)
        XCTAssertEqual(trajectory.shadowScale(at: 0.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(trajectory.shadowAlpha(at: 0.0), 0.09, accuracy: 0.001)

        // Initial launch velocity should be upward
        let v0 = trajectory.velocity(at: 0.0)
        XCTAssertGreaterThan(v0.dx, 0)
        XCTAssertGreaterThan(v0.dy, 0)

        // 2. Apex midpoint at progress 0.5
        let pMid = trajectory.point(at: 0.5)
        XCTAssertEqual(pMid.x, 200, accuracy: 0.001) // Midpoint of 100 and 300
        // Expected Y: linear chord (225) + apexHeight (40) = 265
        XCTAssertEqual(pMid.y, 265, accuracy: 0.001)
        // Shadow should be slightly smaller and diffused at peak flight
        XCTAssertEqual(trajectory.shadowScale(at: 0.5), 0.75, accuracy: 0.01)
        XCTAssertLessThan(trajectory.shadowAlpha(at: 0.5), 0.07)

        // 3. Boundary conditions at progress 1.0 (touchdown)
        let p1 = trajectory.point(at: 1.0)
        XCTAssertEqual(p1.x, 300, accuracy: 0.001)
        XCTAssertEqual(p1.y, 250, accuracy: 0.001)
        XCTAssertEqual(trajectory.shadowScale(at: 1.0), 1.0, accuracy: 0.001)
        XCTAssertEqual(trajectory.shadowAlpha(at: 1.0), 0.09, accuracy: 0.001)

        // Final touchdown velocity should be downward
        let v1 = trajectory.velocity(at: 1.0)
        XCTAssertGreaterThan(v1.dx, 0)
        XCTAssertLessThan(v1.dy, 0)

        // 4. Monotonic X displacement
        var prevX = p0.x
        for step in 1...10 {
            let prog = CGFloat(step) / 10.0
            let pt = trajectory.point(at: prog)
            XCTAssertGreaterThanOrEqual(pt.x, prevX)
            prevX = pt.x
        }
    }

    // MARK: - 2. JumpPlanner Feasibility Tests

    func testJumpPlannerAcceptsShortHorizontalJump() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 480, y: 994) // Near right edge of Window A

        // Target surface on adjacent Window B (top edge at x: 580...1000, y: 994)
        let targetSurface = JumpTargetSurface(
            id: "win-2-top",
            windowId: 2,
            ownerName: "Safari",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 560, y: 380, width: 440, height: 600),
            landingPoint: CGPoint(x: 600, y: 994),
            landingWidth: 400
        )

        let proposals = planner.evaluateAllJumps(
            from: start,
            currentWindowId: 1,
            surfaces: [targetSurface],
            style: .gentle
        )

        XCTAssertEqual(proposals.count, 1)
        let prop = proposals[0]
        XCTAssertTrue(prop.isSafe)
        XCTAssertNil(prop.rejectionReason)
        XCTAssertEqual(prop.horizontalDistance, 120, accuracy: 1.0)
        XCTAssertGreaterThan(prop.apexHeight, 20)
        XCTAssertGreaterThan(prop.jumpDuration, 0.5)
    }

    func testJumpPlannerAcceptsJumpToHigherSurface() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 480, y: 900)

        // Target surface 90 pt higher (within maxVerticalUp = 175)
        let targetSurface = JumpTargetSurface(
            id: "win-higher",
            windowId: 3,
            ownerName: "Notes",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 580, y: 390, width: 400, height: 600),
            landingPoint: CGPoint(x: 620, y: 990),
            landingWidth: 360
        )

        let proposal = planner.evaluateBestJump(
            from: start,
            currentWindowId: 1,
            surfaces: [targetSurface],
            style: .playful
        )

        guard let prop = proposal else {
            XCTFail("Proposal expected")
            return
        }
        XCTAssertTrue(prop.isSafe)
        XCTAssertEqual(prop.verticalDifference, 90, accuracy: 1.0)
    }

    func testJumpPlannerAcceptsJumpToLowerSurface() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 480, y: 990)

        // Target surface 140 pt lower (within maxVerticalDown = 260)
        let targetSurface = JumpTargetSurface(
            id: "win-lower",
            windowId: 4,
            ownerName: "Calendar",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 580, y: 250, width: 400, height: 600),
            landingPoint: CGPoint(x: 620, y: 850),
            landingWidth: 360
        )

        let proposal = planner.evaluateBestJump(
            from: start,
            currentWindowId: 1,
            surfaces: [targetSurface]
        )

        guard let prop = proposal else {
            XCTFail("Proposal expected")
            return
        }
        XCTAssertTrue(prop.isSafe)
        XCTAssertEqual(prop.verticalDifference, -140, accuracy: 1.0)
    }

    func testJumpPlannerRejectsExcessiveDistance() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 100, y: 900)

        // Window far across desktop (dx = 550 > maxHorizontalDistance = 340)
        let farSurface = JumpTargetSurface(
            id: "win-far",
            windowId: 5,
            ownerName: "Xcode",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 650, y: 300, width: 500, height: 600),
            landingPoint: CGPoint(x: 650, y: 900),
            landingWidth: 460
        )

        let proposals = planner.evaluateAllJumps(
            from: start,
            currentWindowId: 1,
            surfaces: [farSurface]
        )

        XCTAssertFalse(proposals[0].isSafe)
        XCTAssertTrue(proposals[0].rejectionReason?.contains("Horizontal distance exceeds reach") ?? false)
    }

    func testJumpPlannerRejectsNarrowLandingSurface() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 400, y: 900)

        // Narrow window (landingWidth = 50 < minLandingWidth = 75)
        let narrowSurface = JumpTargetSurface(
            id: "win-narrow",
            windowId: 6,
            ownerName: "Palette",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 500, y: 300, width: 50, height: 600),
            landingPoint: CGPoint(x: 525, y: 900),
            landingWidth: 50
        )

        let proposals = planner.evaluateAllJumps(
            from: start,
            currentWindowId: 1,
            surfaces: [narrowSurface]
        )

        XCTAssertFalse(proposals[0].isSafe)
        XCTAssertTrue(proposals[0].rejectionReason?.contains("narrow") ?? false)
    }

    func testJumpPlannerRejectsExcessiveVerticalDropOrLeap() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 400, y: 500)

        // Upward leap 240 pt > maxVerticalUp 175
        let tooHigh = JumpTargetSurface(
            id: "win-too-high",
            windowId: 7,
            ownerName: "HighWin",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 500, y: 400, width: 300, height: 340),
            landingPoint: CGPoint(x: 550, y: 740),
            landingWidth: 260
        )

        let highProposal = planner.evaluateAllJumps(from: start, currentWindowId: 1, surfaces: [tooHigh])[0]
        XCTAssertFalse(highProposal.isSafe)
        XCTAssertTrue(highProposal.rejectionReason?.contains("Upward vertical leap too high") ?? false)

        // Downward drop 300 pt > maxVerticalDown 260
        let tooLow = JumpTargetSurface(
            id: "win-too-low",
            windowId: 8,
            ownerName: "LowWin",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 500, y: 50, width: 300, height: 150),
            landingPoint: CGPoint(x: 550, y: 200),
            landingWidth: 260
        )

        let lowProposal = planner.evaluateAllJumps(from: start, currentWindowId: 1, surfaces: [tooLow])[0]
        XCTAssertFalse(lowProposal.isSafe)
        XCTAssertTrue(lowProposal.rejectionReason?.contains("Downward drop exceeds safe limit") ?? false)
    }

    // MARK: - 3. Anti-Bounce and Memory Cooldown

    func testAntiBounceMemoryPreventsImmediatePingPong() {
        let planner = JumpPlanner()
        var simDate = Date()
        planner.now = { simDate }

        let start = CGPoint(x: 480, y: 900)
        let targetSurface = JumpTargetSurface(
            id: "win-target",
            windowId: 42,
            ownerName: "Safari",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 550, y: 300, width: 400, height: 600),
            landingPoint: CGPoint(x: 600, y: 900),
            landingWidth: 360
        )

        // First evaluation is safe
        let initial = planner.evaluateBestJump(from: start, currentWindowId: 1, surfaces: [targetSurface])
        XCTAssertTrue(initial?.isSafe ?? false)

        // Complete jump onto window #42
        planner.recordJumpCompleted(to: 42)
        XCTAssertTrue(planner.isWindowOnCooldown(42))

        // Evaluating jump back onto window #42 should be rejected by cooldown
        let repeated = planner.evaluateBestJump(from: start, currentWindowId: 1, surfaces: [targetSurface])
        XCTAssertNil(repeated) // No safe proposals

        let allRepeated = planner.evaluateAllJumps(from: start, currentWindowId: 1, surfaces: [targetSurface])
        XCTAssertFalse(allRepeated[0].isSafe)
        XCTAssertTrue(allRepeated[0].rejectionReason?.contains("anti-bounce") ?? false)

        // Advance time past cooldown (45s)
        simDate = simDate.addingTimeInterval(50)
        XCTAssertFalse(planner.isWindowOnCooldown(42))
        let afterCooldown = planner.evaluateBestJump(from: start, currentWindowId: 1, surfaces: [targetSurface])
        // consecutiveJumpCount would still need reset if limit was hit, let's verify reset
        planner.resetConsecutiveJumps()
        XCTAssertTrue(planner.evaluateBestJump(from: start, currentWindowId: 1, surfaces: [targetSurface])?.isSafe ?? false)
    }

    func testConsecutiveJumpLimitEnforced() {
        let planner = JumpPlanner()
        let start = CGPoint(x: 480, y: 900)
        let surface = JumpTargetSurface(
            id: "win-next",
            windowId: 101,
            ownerName: "Notes",
            surfaceKind: .windowTopEdge,
            bounds: NSRect(x: 550, y: 300, width: 400, height: 600),
            landingPoint: CGPoint(x: 600, y: 900),
            landingWidth: 360
        )

        // 2 consecutive jumps completed
        planner.recordJumpCompleted(to: 10)
        planner.recordJumpCompleted(to: 20)
        XCTAssertEqual(planner.consecutiveJumpCount, 2)

        // 3rd jump should be rejected
        let proposal = planner.evaluateAllJumps(from: start, currentWindowId: 1, surfaces: [surface])[0]
        XCTAssertFalse(proposal.isSafe)
        XCTAssertTrue(proposal.rejectionReason?.contains("Consecutive jump limit") ?? false)

        // Reset restores ability to jump
        planner.resetConsecutiveJumps()
        XCTAssertEqual(planner.consecutiveJumpCount, 0)
        XCTAssertTrue(planner.evaluateAllJumps(from: start, currentWindowId: 1, surfaces: [surface])[0].isSafe)
    }

    // MARK: - 4. Pre-Launch Validation and Interruption

    func testPreLaunchCancellationOnWindowClosing() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }

        var targetWindowPresent = true
        provider.windowListProvider = {
            var list = [
                self.makeRawWindowDict(id: 201, ownerPID: 2001, ownerName: "WindowA", layer: 0, x: 100, y: 100, width: 400, height: 600)
            ]
            if targetWindowPresent {
                list.append(self.makeRawWindowDict(id: 202, ownerPID: 2002, ownerName: "WindowB", layer: 0, x: 550, y: 100, width: 400, height: 600))
            }
            return list
        }
        var simDate = Date()
        provider.now = { simDate }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simDate }

        // Start Cookie on Window A
        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)

        // Prepare jump to Window B
        let proposal = JumpProposal(
            startPoint: CGPoint(x: 480, y: 994),
            targetSurface: JumpTargetSurface(
                id: "win-202-top",
                windowId: 202,
                ownerName: "WindowB",
                surfaceKind: .windowTopEdge,
                bounds: NSRect(x: 550, y: 380, width: 400, height: 600),
                landingPoint: CGPoint(x: 600, y: 994),
                landingWidth: 360
            ),
            horizontalDistance: 120,
            verticalDifference: 0,
            jumpDuration: 0.8,
            apexHeight: 40,
            style: .gentle,
            isSafe: true,
            rejectionReason: nil
        )

        controller.startJump(proposal: proposal)
        XCTAssertEqual(controller.currentPhase, .preparingJump)

        // Target Window B closes while Cookie is crouching/preparing!
        targetWindowPresent = false

        // Tick past preparation duration (~0.6s)
        simDate = simDate.addingTimeInterval(0.7)
        controller.tick(
            dt: 0.7,
            cookiePosition: CGPoint(x: 480, y: 994),
            characterSize: CGSize(width: 80, height: 80),
            frequency: .frequent,
            verticalClimbingEnabled: false
        )

        // Cookie should cancel launch safely and return to top-edge walk or safe dismount
        XCTAssertNotEqual(controller.currentPhase, .jumping)
        XCTAssertNil(controller.activeJumpTrajectory)
    }

    // MARK: - 5. Complete Flight and Landing Execution

    func testInFlightTrajectoryAndLandingOnNewWindow() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                self.makeRawWindowDict(id: 301, ownerPID: 3001, ownerName: "WindowA", layer: 0, x: 100, y: 100, width: 400, height: 600),
                self.makeRawWindowDict(id: 302, ownerPID: 3002, ownerName: "WindowB", layer: 0, x: 550, y: 100, width: 400, height: 600)
            ]
        }
        var simDate = Date()
        provider.now = { simDate }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simDate }

        let proposal = JumpProposal(
            startPoint: CGPoint(x: 480, y: 994),
            targetSurface: JumpTargetSurface(
                id: "win-302-top",
                windowId: 302,
                ownerName: "WindowB",
                surfaceKind: .windowTopEdge,
                bounds: NSRect(x: 550, y: 380, width: 400, height: 600),
                landingPoint: CGPoint(x: 650, y: 994),
                landingWidth: 360
            ),
            horizontalDistance: 170,
            verticalDifference: 0,
            jumpDuration: 0.8,
            apexHeight: 45,
            style: .gentle,
            isSafe: true,
            rejectionReason: nil
        )

        controller.startJump(proposal: proposal)
        XCTAssertEqual(controller.currentPhase, .preparingJump)

        // 1. Advance through preparation to launch
        simDate = simDate.addingTimeInterval(0.65)
        controller.tick(dt: 0.65, cookiePosition: CGPoint(x: 480, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .jumping)
        XCTAssertTrue(controller.isJumping)

        // 2. Mid-flight checkpoint at 0.4s (progress ~ 0.5)
        simDate = simDate.addingTimeInterval(0.4)
        controller.tick(dt: 0.4, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .jumping)
        XCTAssertEqual(controller.jumpProgress, 0.5, accuracy: 0.05)
        XCTAssertLessThan(controller.jumpShadowScale, 0.85) // Shadow scaled down at peak

        // 3. Touchdown at 0.45s more (total flight ~ 0.85s >= 0.8s)
        simDate = simDate.addingTimeInterval(0.45)
        controller.tick(dt: 0.45, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .landing)
        let destX = controller.destinationPoint?.x ?? 0
        XCTAssertEqual(destX, 650, accuracy: 2.0)
        XCTAssertEqual(controller.jumpShadowScale, 1.0) // Restored on touchdown

        // 4. Recovery absorption completes -> transitions to walking on Window B!
        simDate = simDate.addingTimeInterval(0.4)
        controller.tick(dt: 0.4, cookiePosition: CGPoint(x: 650, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .walkingTopEdge)
        XCTAssertEqual(controller.activeWindow?.id, 302) // Now exploring Window B!
    }

    // MARK: - 6. In-Flight Target Invalidation & Recovery

    func testInFlightWindowLossCompletesFlightAndDismountsSafely() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }

        var targetWindowPresent = true
        provider.windowListProvider = {
            var list = [
                self.makeRawWindowDict(id: 401, ownerPID: 4001, ownerName: "WindowA", layer: 0, x: 100, y: 100, width: 400, height: 600)
            ]
            if targetWindowPresent {
                list.append(self.makeRawWindowDict(id: 402, ownerPID: 4002, ownerName: "WindowB", layer: 0, x: 550, y: 100, width: 400, height: 600))
            }
            return list
        }
        var simDate = Date()
        provider.now = { simDate }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simDate }

        let proposal = JumpProposal(
            startPoint: CGPoint(x: 480, y: 994),
            targetSurface: JumpTargetSurface(
                id: "win-402-top",
                windowId: 402,
                ownerName: "WindowB",
                surfaceKind: .windowTopEdge,
                bounds: NSRect(x: 550, y: 380, width: 400, height: 600),
                landingPoint: CGPoint(x: 650, y: 994),
                landingWidth: 360
            ),
            horizontalDistance: 170,
            verticalDifference: 0,
            jumpDuration: 0.8,
            apexHeight: 45,
            style: .gentle,
            isSafe: true,
            rejectionReason: nil
        )

        controller.startJump(proposal: proposal)

        // Launch
        simDate = simDate.addingTimeInterval(0.65)
        controller.tick(dt: 0.65, cookiePosition: CGPoint(x: 480, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .jumping)

        // Window B closes in mid-flight!
        targetWindowPresent = false

        // Flight continues to destination coordinate (no sudden freeze or teleportation)
        simDate = simDate.addingTimeInterval(0.85)
        controller.tick(dt: 0.85, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .landing)

        // Post-landing: detects that surface is gone, gracefully recovers by departing to ground
        simDate = simDate.addingTimeInterval(0.45)
        controller.tick(dt: 0.45, cookiePosition: CGPoint(x: 650, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .departing)
    }

    // MARK: - 7. User Interruption

    func testUserGrabInterruptsMidJump() {
        let store = CookieStore()
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [self.makeRawWindowDict(id: 501, ownerPID: 5001, ownerName: "WindowA", layer: 0, x: 100, y: 100, width: 400, height: 600)]
        }
        var simDate = Date()
        provider.now = { simDate }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simDate }
        let engine = CookieBehaviorEngine(
            store: store,
            windowProvider: provider,
            windowController: controller
        )
        engine.now = { simDate }
        engine.start()

        let proposal = JumpProposal(
            startPoint: CGPoint(x: 480, y: 994),
            targetSurface: JumpTargetSurface(
                id: "win-target",
                windowId: 502,
                ownerName: "Target",
                surfaceKind: .windowTopEdge,
                bounds: NSRect(x: 550, y: 380, width: 400, height: 600),
                landingPoint: CGPoint(x: 650, y: 994),
                landingWidth: 360
            ),
            horizontalDistance: 170,
            verticalDifference: 0,
            jumpDuration: 0.8,
            apexHeight: 45,
            style: .gentle,
            isSafe: true,
            rejectionReason: nil
        )

        controller.startJump(proposal: proposal)
        XCTAssertEqual(controller.currentPhase, .preparingJump)

        // User drags Cookie
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertFalse(controller.isExploringWindow)
        XCTAssertEqual(controller.currentPhase, .idle)
        XCTAssertNil(controller.activeJumpTrajectory)
    }

    // MARK: - 8. Settings and Preferences

    func testJumpSettingsDefaultsAndResets() {
        var settings = CookieSettings()
        XCTAssertTrue(settings.windowJumpingEnabled)
        XCTAssertEqual(settings.jumpFrequency, "balanced")
        XCTAssertEqual(settings.jumpStyle, "gentle")
        XCTAssertEqual(settings.jumpFrequencySetting, .balanced)
        XCTAssertEqual(settings.jumpStyleSetting, .gentle)

        // Mutate
        settings.windowJumpingEnabled = false
        settings.jumpFrequency = "playful"
        settings.jumpStyle = "playful"
        XCTAssertEqual(settings.jumpFrequencySetting, .playful)
        XCTAssertEqual(settings.jumpStyleSetting, .playful)

        // Reset
        settings.resetJumpSettings()
        XCTAssertTrue(settings.windowJumpingEnabled)
        XCTAssertEqual(settings.jumpFrequency, "balanced")
        XCTAssertEqual(settings.jumpStyle, "gentle")
    }
}
