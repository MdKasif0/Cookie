import XCTest
import AppKit
@testable import Cookie

@MainActor
final class AutonomousBehaviorTests: XCTestCase {

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

    // MARK: - 1. Application Context Classification

    func testApplicationContextClassification() {
        // Browsers
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.Safari", appName: "Safari"), .browser)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.google.Chrome", appName: "Google Chrome"), .browser)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "org.mozilla.firefox", appName: "Firefox"), .browser)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "company.thebrowser.Browser", appName: "Arc"), .browser)

        // Code editors
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.dt.Xcode", appName: "Xcode"), .codeEditor)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.microsoft.VSCode", appName: "Code"), .codeEditor)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.todesktop.230313mzl4w4u92", appName: "Cursor"), .codeEditor)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.TextEdit", appName: "TextEdit"), .codeEditor)

        // Creative
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.figma.Desktop", appName: "Figma"), .creative)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "org.blenderfoundation.blender", appName: "Blender"), .creative)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.adobe.Photoshop", appName: "Adobe Photoshop"), .creative)

        // Communication
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack"), .communication)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.hnc.Discord", appName: "Discord"), .communication)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.MobileSMS", appName: "Messages"), .communication)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.mail", appName: "Mail"), .communication)

        // File manager
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.apple.finder", appName: "Finder"), .fileManager)

        // Other and Unknown
        XCTAssertEqual(ApplicationCategory.classify(bundleId: "com.example.randomtool", appName: "MyTool"), .other)
        XCTAssertEqual(ApplicationCategory.classify(bundleId: nil, appName: nil), .unknown)
    }

    // MARK: - 2. Active Application Switching Detection

    func testActiveApplicationSwitchingDetection() {
        let detector = ApplicationContextDetector()
        var simDate = Date()
        detector.now = { simDate }

        // Start with Xcode active
        detector.frontmostAppProvider = {
            ("com.apple.dt.Xcode", "Xcode", 1234, false)
        }
        let initial = detector.refreshContext()
        XCTAssertEqual(initial.category, .codeEditor)
        XCTAssertEqual(initial.applicationName, "Xcode")
        XCTAssertFalse(initial.isCookieActive)
        XCTAssertEqual(initial.state, .externalAppFrontmost)

        // Switch to Safari
        simDate = simDate.addingTimeInterval(5)
        detector.frontmostAppProvider = {
            ("com.apple.Safari", "Safari", 5678, false)
        }
        var callbackReceived = false
        detector.onApplicationSwitched = { newContext in
            callbackReceived = true
            XCTAssertEqual(newContext.category, .browser)
            XCTAssertEqual(newContext.applicationName, "Safari")
        }

        let updated = detector.refreshContext()
        XCTAssertTrue(callbackReceived)
        XCTAssertEqual(updated.category, .browser)
        XCTAssertEqual(detector.previousContext?.applicationName, "Xcode")
    }

    // MARK: - 3. App Switch Glance and Cooldowns

    func testAppSwitchGlanceTowardsActiveWindowAndCooldown() {
        let store = CookieStore()
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [self.makeRawWindowDict(id: 101, ownerPID: 5001, ownerName: "Xcode", layer: 0, x: 700, y: 100, width: 600, height: 700)]
        }
        var simDate = Date()
        provider.now = { simDate }
        provider.refreshWindows(force: true)

        let engine = CookieBehaviorEngine(store: store, windowProvider: provider)
        engine.now = { simDate }
        engine.start()

        // Place Cookie on the left (x: 200)
        engine.tick(dt: 0.1, currentPosition: CGPoint(x: 200, y: 100), cursorPosition: nil)

        // Simulate app switch to Xcode (window bounds midX = 1000 > 200)
        let context = ApplicationContext(
            state: .externalAppFrontmost,
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode",
            processIdentifier: 5001,
            category: .codeEditor,
            isCookieActive: false,
            frontmostWindowBounds: NSRect(x: 700, y: 280, width: 600, height: 700),
            timestamp: simDate
        )

        engine.handleApplicationSwitched(context)
        // Cookie should glance right toward the window and enter curious state
        XCTAssertEqual(engine.facing, .right)
        XCTAssertEqual(engine.state, .curious)

        // Rapid subsequent switch within 5s (cooldown is 25s)
        simDate = simDate.addingTimeInterval(5)
        let rapidContext = ApplicationContext(
            state: .externalAppFrontmost,
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            processIdentifier: 5002,
            category: .browser,
            isCookieActive: false,
            frontmostWindowBounds: NSRect(x: 100, y: 280, width: 400, height: 700),
            timestamp: simDate
        )

        // Reset to idle to test if rapid switch re-triggers
        engine.enter(.idle)
        engine.handleApplicationSwitched(rapidContext)
        // Should remain idle because of cooldown (no spamming reactions!)
        XCTAssertEqual(engine.state, .idle)

        // After cooldown passes (30s > 25s)
        simDate = simDate.addingTimeInterval(30)
        engine.handleApplicationSwitched(rapidContext)
        XCTAssertEqual(engine.state, .curious)
    }

    // MARK: - 4. Returning to Cookie

    func testReturningToCookieTriggersFriendlyReaction() {
        let store = CookieStore()
        let engine = CookieBehaviorEngine(store: store)
        var simDate = Date()
        engine.now = { simDate }
        engine.start()
        engine.enter(.idle)

        let initialNotices = engine.noticeCount
        let cookieFocusContext = ApplicationContext(
            state: .cookieFrontmost,
            bundleIdentifier: "com.cookie.mac",
            applicationName: "Cookie",
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            category: .other,
            isCookieActive: true,
            frontmostWindowBounds: nil,
            timestamp: simDate
        )

        engine.handleApplicationSwitched(cookieFocusContext)
        XCTAssertEqual(engine.reaction, .happy)
        XCTAssertEqual(engine.noticeCount, initialNotices + 1)
    }

    // MARK: - 5. Behavior Memory Anti-Repetition

    func testBehaviorMemoryAntiRepetition() {
        let memory = BehaviorMemory()
        var simDate = Date()
        memory.now = { simDate }

        // Window visit cooldown
        XCTAssertFalse(memory.isWindowOnCooldown(42))
        memory.recordWindowVisit(windowId: 42)
        XCTAssertTrue(memory.isWindowOnCooldown(42))
        simDate = simDate.addingTimeInterval(50) // Past 45s cooldown
        XCTAssertFalse(memory.isWindowOnCooldown(42))

        // Dock region cooldown
        XCTAssertFalse(memory.isDockRegionOnCooldown(400))
        memory.recordDockVisit(regionX: 400)
        XCTAssertTrue(memory.isDockRegionOnCooldown(400))
        simDate = simDate.addingTimeInterval(45) // Past 40s cooldown
        XCTAssertFalse(memory.isDockRegionOnCooldown(400))

        // Emote repetition cooldown
        XCTAssertTrue(memory.canPlayEmote(id: "wave"))
        memory.recordEmote(id: "wave")
        XCTAssertFalse(memory.canPlayEmote(id: "wave"))
        simDate = simDate.addingTimeInterval(35) // Past 30s cooldown
        XCTAssertTrue(memory.canPlayEmote(id: "wave"))

        // Repetitive action history
        XCTAssertFalse(memory.isActionRepetitive("patrol"))
        memory.recordAutonomousAction("patrol")
        XCTAssertTrue(memory.isActionRepetitive("patrol")) // Immediate repeat
        memory.recordAutonomousAction("inspect")
        XCTAssertFalse(memory.isActionRepetitive("patrol")) // Different action followed
    }

    // MARK: - 6. Autonomous Settings and Pausing

    func testAutonomousSettingsAndPausing() {
        let store = CookieStore()
        let engine = CookieBehaviorEngine(store: store)
        var simDate = Date()
        engine.now = { simDate }
        engine.start()

        // 1. When autonomous behavior is enabled
        store.profile.settings.autonomousBehaviorEnabled = true
        store.profile.settings.pauseAutonomousBehavior = false
        var weights = engine.behaviorWeights()
        XCTAssertGreaterThan(weights[.walking] ?? 0, 0)
        XCTAssertGreaterThan(weights[.running] ?? 0, 0)

        // 2. When autonomous behavior is toggled off
        store.profile.settings.autonomousBehaviorEnabled = false
        weights = engine.behaviorWeights()
        XCTAssertEqual(weights[.walking], 0)
        XCTAssertEqual(weights[.running], 0)
        XCTAssertEqual(weights[.playing], 0)

        // 3. When autonomous behavior is paused
        store.profile.settings.autonomousBehaviorEnabled = true
        store.profile.settings.pauseAutonomousBehavior = true
        weights = engine.behaviorWeights()
        XCTAssertEqual(weights[.walking], 0)
        XCTAssertEqual(weights[.running], 0)
        XCTAssertEqual(weights[.playing], 0)
    }

    // MARK: - 7. Activity Level Cadence

    func testActivityLevelCadence() {
        let memory = BehaviorMemory()
        let scheduler = BehaviorScheduler(memory: memory)
        var simDate = Date()
        memory.now = { simDate }
        scheduler.now = { simDate }

        var settings = CookieSettings()
        settings.autonomousBehaviorEnabled = true
        settings.pauseAutonomousBehavior = false

        // Last action was 10 seconds ago
        memory.recordAutonomousAction("test")
        simDate = simDate.addingTimeInterval(10)

        // Calm requires 28s -> should return nil
        settings.activityLevel = "calm"
        let calmResult = scheduler.selectNextAmbientBehavior(
            currentState: .idle,
            cookiePosition: CGPoint(x: 200, y: 100),
            cursorPosition: nil,
            cursorVelocity: 0,
            cursorZone: .departure,
            context: .unknown,
            settings: settings,
            isPressed: false,
            isEmoting: false,
            worldItemActive: false
        )
        XCTAssertNil(calmResult)

        // Balanced requires 14s -> should return nil at 10s
        settings.activityLevel = "balanced"
        let balancedResult = scheduler.selectNextAmbientBehavior(
            currentState: .idle,
            cookiePosition: CGPoint(x: 200, y: 100),
            cursorPosition: nil,
            cursorVelocity: 0,
            cursorZone: .departure,
            context: .unknown,
            settings: settings,
            isPressed: false,
            isEmoting: false,
            worldItemActive: false
        )
        XCTAssertNil(balancedResult)

        // Playful / Lively requires only 7s -> at 10s, can schedule!
        settings.activityLevel = "lively"
        let playfulResult = scheduler.selectNextAmbientBehavior(
            currentState: .idle,
            cookiePosition: CGPoint(x: 200, y: 100),
            cursorPosition: nil,
            cursorVelocity: 0,
            cursorZone: .departure,
            context: .unknown,
            settings: settings,
            isPressed: false,
            isEmoting: false,
            worldItemActive: false
        )
        XCTAssertNotNil(playfulResult)
    }

    // MARK: - 8. Cursor Activity Suppresses Autonomous Wandering

    func testCursorMovementSuppressesAutonomousWandering() {
        let memory = BehaviorMemory()
        let scheduler = BehaviorScheduler(memory: memory)
        var simDate = Date()
        memory.now = { simDate }
        scheduler.now = { simDate }

        var settings = CookieSettings()
        settings.autonomousBehaviorEnabled = true
        settings.pauseAutonomousBehavior = false
        settings.activityLevel = "lively"

        // Advance 30s past last action
        simDate = simDate.addingTimeInterval(30)

        // Fast moving cursor in awareness zone
        let fastMovingResult = scheduler.selectNextAmbientBehavior(
            currentState: .idle,
            cookiePosition: CGPoint(x: 200, y: 100),
            cursorPosition: CGPoint(x: 280, y: 100),
            cursorVelocity: 350,
            cursorZone: .awareness,
            context: .unknown,
            settings: settings,
            isPressed: false,
            isEmoting: false,
            worldItemActive: false
        )
        // Wandering is suppressed
        XCTAssertNil(fastMovingResult)
    }

    // MARK: - 9. Direct User Interaction Suspension & Resumption

    func testDirectUserInteractionSuspensionAndDragPriority() {
        let store = CookieStore()
        let engine = CookieBehaviorEngine(store: store)
        var simDate = Date()
        engine.now = { simDate }
        engine.start()

        // 1. User grabs Cookie (drag)
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertEqual(engine.locomotionVelocity, 0)
        XCTAssertEqual(engine.locomotionVelocity2D, .zero)
        XCTAssertFalse(engine.windowController.isExploringWindow)
        XCTAssertFalse(engine.dockController.isExploringDock)

        // Ticking while being dragged keeps movement zero
        engine.tick(dt: 0.5, currentPosition: CGPoint(x: 200, y: 100), cursorPosition: CGPoint(x: 200, y: 100))
        XCTAssertEqual(engine.locomotionVelocity, 0)
        XCTAssertEqual(engine.locomotionVelocity2D, .zero)

        // 2. User releases Cookie
        engine.handleRelease()
        XCTAssertEqual(engine.state, .idle)

        // 3. Emotes are not interrupted by scheduler
        let emote = Emote.wave
        XCTAssertTrue(engine.triggerEmote(emote))
        XCTAssertEqual(engine.state, .emoting)

        // Ticking during emote advances emote phase without interrupting
        engine.tick(dt: 1.0, currentPosition: CGPoint(x: 200, y: 100), cursorPosition: nil)
        XCTAssertEqual(engine.state, .emoting)
    }

    // MARK: - 10. Display Parameter Changes Refresh Windows

    func testDisplayParameterChangesRefreshWindows() {
        let provider = WindowEnvironmentProvider()
        var scanCount = 0
        provider.windowListProvider = {
            scanCount += 1
            return []
        }

        let initialScans = scanCount
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        XCTAssertGreaterThan(scanCount, initialScans)
    }

    // MARK: - 11. Personality & Activity Settings Reset

    func testPersonalityAndActivitySettingsReset() {
        var settings = CookieSettings()
        XCTAssertTrue(settings.autonomousBehaviorEnabled)
        XCTAssertFalse(settings.pauseAutonomousBehavior)
        XCTAssertEqual(settings.activityLevel, "balanced")

        // Mutate
        settings.autonomousBehaviorEnabled = false
        settings.pauseAutonomousBehavior = true
        settings.activityLevel = "calm"
        settings.cursorInteraction = false
        settings.dockInteraction = false
        settings.windowInteraction = false
        settings.windowJumpingEnabled = false

        // Reset
        settings.resetPersonalityAndActivitySettings()
        XCTAssertTrue(settings.autonomousBehaviorEnabled)
        XCTAssertFalse(settings.pauseAutonomousBehavior)
        XCTAssertEqual(settings.activityLevel, "balanced")
        XCTAssertTrue(settings.cursorInteraction)
        XCTAssertTrue(settings.dockInteraction)
        XCTAssertTrue(settings.windowInteraction)
        XCTAssertTrue(settings.windowJumpingEnabled)
    }
}
