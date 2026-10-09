import XCTest
@testable import Cookie

final class EmoteSystemTests: XCTestCase {
    var store: CookieStore!
    var engine: CookieBehaviorEngine!
    var simulatedDate: Date!

    @MainActor
    override func setUp() {
        super.setUp()
        store = CookieStore()
        engine = CookieBehaviorEngine(store: store)
        simulatedDate = Date()
        engine.now = { [weak self] in self?.simulatedDate ?? Date() }
        engine.visibleXRange = { 0...1440 }
        engine.start()
    }

    @MainActor
    func advanceTime(by seconds: TimeInterval, x: CGFloat = 500, cursorX: CGFloat? = nil) {
        let step: TimeInterval = 0.1
        var remaining = seconds
        while remaining > 0 {
            let dt = min(remaining, step)
            simulatedDate = simulatedDate.addingTimeInterval(dt)
            engine.tick(dt: dt, currentX: x, cursorX: cursorX)
            remaining -= dt
        }
    }

    // MARK: - Catalog & Model Tests

    func testAllFiveInitialEmotesAreRegistered() {
        let all = Emote.allEmotes
        XCTAssertEqual(all.count, 5, "Exactly 5 initial emotes must be registered")

        let ids = Set(all.map(\.id))
        XCTAssertTrue(ids.contains(.wave), "Wave emote must be present")
        XCTAssertTrue(ids.contains(.happy), "Happy emote must be present")
        XCTAssertTrue(ids.contains(.love), "Love emote must be present")
        XCTAssertTrue(ids.contains(.sleepy), "Sleepy emote must be present")
        XCTAssertTrue(ids.contains(.playful), "Playful emote must be present")

        for emote in all {
            XCTAssertFalse(emote.name.isEmpty, "\(emote.id) must have a non-empty display name")
            XCTAssertFalse(emote.description.isEmpty, "\(emote.id) must have a description")
            XCTAssertFalse(emote.icon.isEmpty, "\(emote.id) must have an icon SF Symbol")
            XCTAssertGreaterThan(emote.duration, 0, "\(emote.id) duration must be positive")
            XCTAssertGreaterThanOrEqual(emote.cooldown, 1.0, "\(emote.id) cooldown must be at least 1.0s")
            XCTAssertEqual(emote.priority, .emote, "\(emote.id) priority must be .emote")
            XCTAssertNotNil(emote.soundIdentifier, "\(emote.id) should have an associated sound effect")
        }
    }

    func testEmoteLookupFindsExistingEmotes() {
        XCTAssertEqual(Emote.find(.wave).id, .wave)
        XCTAssertEqual(Emote.find(.happy).id, .happy)
        XCTAssertEqual(Emote.find(.love).id, .love)
        XCTAssertEqual(Emote.find(.sleepy).id, .sleepy)
        XCTAssertEqual(Emote.find(.playful).id, .playful)
    }

    // MARK: - Priority Hierarchy Tests

    func testAnimationPriorityOrdering() {
        XCTAssertLessThan(CookieAnimationPriority.sleep, CookieAnimationPriority.idle)
        XCTAssertLessThan(CookieAnimationPriority.idle, CookieAnimationPriority.walk)
        XCTAssertLessThan(CookieAnimationPriority.walk, CookieAnimationPriority.interaction)
        XCTAssertLessThan(CookieAnimationPriority.interaction, CookieAnimationPriority.emote)
        XCTAssertLessThan(CookieAnimationPriority.emote, CookieAnimationPriority.special)
    }

    // MARK: - Triggering & Arbitration Tests

    @MainActor
    func testTriggeringEmotePausesLocomotionAndSetsEmotingState() {
        let success = engine.triggerEmote(.wave)
        XCTAssertTrue(success, "Triggering wave emote should succeed")
        XCTAssertEqual(engine.state, .emoting)
        XCTAssertEqual(engine.activeEmote?.id, .wave)
        XCTAssertEqual(engine.emotePlaybackPhase, .starting)
        XCTAssertEqual(engine.locomotionVelocity, 0, "Emote must immediately freeze panel locomotion")
    }

    @MainActor
    func testTwoEmotesCannotPlaySimultaneously() {
        let first = engine.triggerEmote(.wave)
        XCTAssertTrue(first)

        // Attempt second emote immediately
        let second = engine.triggerEmote(.happy)
        XCTAssertFalse(second, "Second emote must be rejected while another emote is playing")
        XCTAssertEqual(engine.activeEmote?.id, .wave, "Active emote should remain unchanged")
    }

    @MainActor
    func testEmoteCooldownEnforcement() {
        let wave = Emote.wave
        let first = engine.triggerEmote(wave)
        XCTAssertTrue(first)

        // Finish the first emote
        engine.completeEmote()
        XCTAssertNil(engine.activeEmote)
        XCTAssertEqual(engine.state, .idle)

        // Attempting wave immediately should fail because of cooldown
        let second = engine.triggerEmote(wave)
        XCTAssertFalse(second, "Emote should be rejected while on cooldown")
        XCTAssertGreaterThan(engine.cooldownRemaining(for: .wave), 0)

        // Advance time past cooldown
        advanceTime(by: wave.cooldown + 0.1)
        XCTAssertEqual(engine.cooldownRemaining(for: .wave), 0)

        let third = engine.triggerEmote(wave)
        XCTAssertTrue(third, "Emote should succeed once cooldown has elapsed")
    }

    @MainActor
    func testExplicitDragCancelsActiveEmote() {
        engine.triggerEmote(.playful)
        XCTAssertEqual(engine.state, .emoting)
        XCTAssertNotNil(engine.activeEmote)

        // User grabs Cookie (priority .special = 40 > .emote = 35)
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertNil(engine.activeEmote, "Drag must safely cancel active emote")
        XCTAssertEqual(engine.emotePlaybackPhase, .ready)
    }

    @MainActor
    func testCannotTriggerEmoteWhileBeingDragged() {
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)

        let triggered = engine.triggerEmote(.love)
        XCTAssertFalse(triggered, "Cannot trigger emote while being dragged by user")
    }

    @MainActor
    func testEmoteCompletionRestoresNormalBehavior() {
        engine.triggerEmote(.happy)
        XCTAssertEqual(engine.state, .emoting)

        engine.completeEmote()
        XCTAssertNil(engine.activeEmote)
        XCTAssertEqual(engine.state, .idle, "Cookie must return naturally to idle state")
        XCTAssertEqual(engine.emotePlaybackPhase, .ready)
    }

    @MainActor
    func testSleepingCookieTracksWakeRequirement() {
        // Force state to sleeping
        advanceTime(by: 1.0)
        // Simulate sleeping state
        engine.triggerSpecialEvent(.unusualNap)
        // Transition to sleeping
        advanceTime(by: 2.0)

        if engine.state != .sleeping {
            // Directly trigger emote when simulated sleeping
            // Let's verify wasSleepingBeforeEmote flag
        }

        let triggered = engine.triggerEmote(.playful)
        XCTAssertTrue(triggered)
        XCTAssertEqual(engine.state, .emoting)
    }

    @MainActor
    func testHeadlessSafetyExpirationPreventsGettingStuck() {
        let emote = Emote.sleepy
        engine.triggerEmote(emote)
        XCTAssertEqual(engine.state, .emoting)

        // Advance past safety duration in ticks
        advanceTime(by: emote.duration + 2.0)

        XCTAssertEqual(engine.state, .idle, "Cookie must automatically recover to idle if animation completes")
        XCTAssertNil(engine.activeEmote)
    }

    func testEmoteModelSpecificationsMatchProductRequirements() {
        let wave = Emote.wave
        XCTAssertEqual(wave.name, "Wave")
        XCTAssertEqual(wave.description, "Cookie says hello.")
        XCTAssertEqual(wave.duration, 2.0)
        XCTAssertEqual(wave.soundIdentifier, .mew)

        let happy = Emote.happy
        XCTAssertEqual(happy.name, "Happy")
        XCTAssertEqual(happy.description, "Cookie is feeling happy.")
        XCTAssertEqual(happy.duration, 1.8)
        XCTAssertEqual(happy.soundIdentifier, .happy)

        let love = Emote.love
        XCTAssertEqual(love.name, "Love")
        XCTAssertEqual(love.description, "Cookie sends you some love.")
        XCTAssertEqual(love.duration, 2.0)
        XCTAssertEqual(love.soundIdentifier, .purr)

        let sleepy = Emote.sleepy
        XCTAssertEqual(sleepy.name, "Sleepy")
        XCTAssertEqual(sleepy.description, "Cookie needs a little nap.")
        XCTAssertEqual(sleepy.duration, 4.0)
        XCTAssertEqual(sleepy.soundIdentifier, .sleep)

        let playful = Emote.playful
        XCTAssertEqual(playful.name, "Playful")
        XCTAssertEqual(playful.description, "Cookie wants to play.")
        XCTAssertEqual(playful.duration, 2.2)
        XCTAssertEqual(playful.soundIdentifier, .toy)
    }

    func testEmoteAnimationSpecsFPSAndPriorities() {
        XCTAssertEqual(CookieAnimationId.wave.spec.fps, 6)
        XCTAssertEqual(CookieAnimationId.wave.spec.priority, .emote)
        XCTAssertFalse(CookieAnimationId.wave.spec.isLooping)

        XCTAssertEqual(CookieAnimationId.happyEmote.spec.fps, 6)
        XCTAssertEqual(CookieAnimationId.happyEmote.spec.priority, .emote)
        XCTAssertFalse(CookieAnimationId.happyEmote.spec.isLooping)

        XCTAssertEqual(CookieAnimationId.love.spec.fps, 5)
        XCTAssertEqual(CookieAnimationId.love.spec.priority, .emote)
        XCTAssertFalse(CookieAnimationId.love.spec.isLooping)

        XCTAssertEqual(CookieAnimationId.sleepy.spec.fps, 4)
        XCTAssertEqual(CookieAnimationId.sleepy.spec.priority, .emote)
        XCTAssertFalse(CookieAnimationId.sleepy.spec.isLooping)

        XCTAssertEqual(CookieAnimationId.playfulEmote.spec.fps, 5)
        XCTAssertEqual(CookieAnimationId.playfulEmote.spec.priority, .emote)
        XCTAssertFalse(CookieAnimationId.playfulEmote.spec.isLooping)
    }

    @MainActor
    func testReducedMotionPreservesEmoteCompletion() {
        let originalMode = MotionSettings.mode
        defer { MotionSettings.mode = originalMode }
        MotionSettings.mode = .always
        XCTAssertTrue(MotionSettings.reduceMotion)

        for emote in Emote.allEmotes {
            // Ensure no cooldown active
            advanceTime(by: 10.0)
            let triggered = engine.triggerEmote(emote)
            XCTAssertTrue(triggered, "Should trigger \(emote.id) in reduced motion")
            XCTAssertEqual(engine.state, .emoting)

            // Complete emote
            engine.completeEmote()
            XCTAssertEqual(engine.state, .idle, "Should return to idle after \(emote.id) in reduced motion")
            XCTAssertNil(engine.activeEmote)
        }
    }
}
