import Foundation
import AppKit
import os

/// Cookie's behavior state machine — the single source of truth for what
/// she is doing and why.
///
/// The machine is tick-driven: the companion scene calls `tick(dt:)`
/// every frame with her current position and the cursor's, and the engine
/// advances state timers, locomotion phases, and scheduled sequences.
/// The scene stays a dumb executor: it reads `state`/`facing`/`reaction`
/// for animation and `locomotionVelocity` for movement, and reports
/// events (pet, grab, release, screen edges).
///
/// Everything time-based flows through the injectable `now` clock and
/// `visibleXRange` seam, so the whole machine can be exercised in tests
/// without a screen.
@MainActor
final class CookieBehaviorEngine: ObservableObject {
    @Published private(set) var state: CookieState = .idle
    @Published private(set) var facing: CookieDirection = .right
    @Published private(set) var reaction: CookieReaction = .happy
    private(set) var isRunning = false
    /// Signed panel speed in points per second (0 when not moving).
    private(set) var locomotionVelocity: CGFloat = 0

    // Seams for determinism in tests.
    var now: () -> Date = { Date() }
    var visibleXRange: () -> ClosedRange<Double>? = {
        guard let frame = NSScreen.main?.visibleFrame else { return nil }
        return Double(frame.minX)...Double(frame.maxX)
    }

    private let store: CookieStore
    private let log = Logger(subsystem: "com.cookie.mac", category: "Behavior")

    // State machine bookkeeping
    /// Internal so the compiled-in test harness can assert on it.
    private(set) var stateElapsed: TimeInterval = 0
    private var currentDuration: TimeInterval = 8
    private var sequenceQueue: [(state: CookieState, duration: TimeInterval?)] = []
    private var plan: LocomotionPlan?
    private var lastKnownX: CGFloat = 0
    private var lastCursorX: CGFloat?

    // Interaction memory (never annoying)
    private var recentPets: [Date] = []
    private var sleepCooldownUntil = Date.distantPast
    private var followCooldownUntil = Date.distantPast
    /// Internal so the compiled-in test harness can assert on it.
    private(set) var edgeCooldownUntil = Date.distantPast
    /// Internal so the compiled-in test harness can assert on it.
    private(set) var sulksUntil = Date.distantPast
    /// Test-visible: set once a reaction has turned annoyed.
    private(set) var usedAnnoyedReaction = false
    private var lastTapDate = Date.distantPast
    private var hoverCheckElapsed: TimeInterval = 0
    private var hoverCooldownUntil = Date.distantPast
    /// Test-visible: where a stroll is currently headed.
    private(set) var currentTargetX: CGFloat?
    /// True between mouse-down and mouse-up. While pressed, Cookie never
    /// starts strolling — she must not slide out from under the pointer.
    private(set) var isPressed = false
    /// Increments when she notices the cursor nearby — the scene answers
    /// with a tiny chirp.
    @Published private(set) var noticeCount = 0

    // MARK: World interactions (toys, food, the box)

    /// The item currently on Cookie's desktop, if any. The presenter
    /// renders it as a small panel; the engine owns its lifetime.
    @Published private(set) var worldItem: WorldItem?
    /// True while Cookie pokes her head out of the cardboard box.
    @Published private(set) var isPeeking = false

    private var sessionTargetX: CGFloat?
    private var nextPeekAt = Date.distantPast
    private var peekUntil = Date.distantPast
    private var specialCooldownUntil = Date.distantPast

    private struct LocomotionPlan {
        var targetX: CGFloat
        var isPaused = false
        var pauseRemaining: TimeInterval = 0
        var timeUntilNextPause: TimeInterval = 3
    }

    init(store: CookieStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        recentPets.removeAll()
        // Mornings begin with a wake-up stretch; the rest of the day
        // just starts quietly.
        enter(timeOfDay(now()) == .morning ? .stretching : .idle)
    }

    func stop() {
        isRunning = false
    }

    // MARK: - Tick

    func tick(dt: TimeInterval, currentX: CGFloat, cursorX: CGFloat?) {
        guard isRunning, dt > 0 else { return }
        lastKnownX = currentX
        if let cursorX { lastCursorX = cursorX }
        stateElapsed += dt
        pruneRecentPets()
        maybeNoticeCursor(dt: dt)

        switch state {
        case .beingDragged:
            locomotionVelocity = 0
            return // held by the user; time does not advance
        case .walking, .running, .followingCursor:
            advanceLocomotion(dt: dt, currentX: currentX)
        default:
            locomotionVelocity = 0
        }

        // Box peeking: while she is inside, she occasionally pokes her
        // head over the rim for a moment.
        if state == .inBox {
            let date = now()
            if isPeeking {
                if date >= peekUntil {
                    isPeeking = false
                    nextPeekAt = date.addingTimeInterval(Double.random(in: 5...11))
                }
            } else if date >= nextPeekAt {
                isPeeking = true
                peekUntil = date.addingTimeInterval(Double.random(in: 1.2...1.9))
            }
        }

        // Session walks end by arrival, not by timer.
        if (state == .walking || state == .running),
           let target = sessionTargetX, abs(lastKnownX - target) < 16 {
            sessionTargetX = nil
            stateElapsed = currentDuration
        }

        if stateElapsed >= currentDuration {
            stateExpired()
        }
    }

    // MARK: - Events

    /// Mouse down. Pressing only pauses strolling — a real drag commits
    /// to being carried later (via `handleGrab`), and a clean release
    /// becomes a click.
    func handlePress() {
        guard isRunning else { return }
        isPressed = true
        if state.isLocomotion {
            enter(.idle)
        }
    }

    private func endPress() {
        isPressed = false
    }

    /// A single click on some part of Cookie. The zone decides the flavor:
    /// nose taps surprise her, tail touches startle her, head and body
    /// pets delight her — with some variety so she stays unpredictable.
    func handleClick(zone: CookieZone?) {
        guard isRunning else { return }
        if state == .beingDragged {
            // Safety: a click that arrives while carried ends the carry.
            enter(.idle)
        }
        if state == .inBox {
            petThroughBox()
            endPress()
            return
        }
        endPress()
        sequenceQueue = []
        let date = now()
        if date.timeIntervalSince(lastTapDate) < 0.4 {
            // Second tap in quick succession — playful double click.
            lastTapDate = date
            handleDoubleClick()
            return
        }
        lastTapDate = date
        recentPets.append(date)

        if isOverPetted(date) {
            reactAnnoyed()
            enter(.reacting)
            return
        }

        switch zone {
        case .nose:
            reaction = .surprised
            enter(.reacting)
        case .tail:
            reaction = .surprised
            enter(.reacting)
        case .head:
            store.statistics.affection += 2
            store.statistics.petsReceived += 1
            // Affectionate cats melt when their head is petted.
            reaction = store.profile.personality == .affectionate ? .shy : .happy
            enter(.reacting)
        case .feet:
            reaction = .meow
            enter(.reacting)
        case .body, .none:
            store.statistics.petsReceived += 1
            let roll = Double.random(in: 0...1)
            if roll < 0.25 {
                reaction = .embarrassed
                enter(.reacting)
            } else if roll < 0.5 {
                enter(.curious, duration: Double.random(in: 2...3.2)) // looks up at you
            } else {
                reaction = roll < 0.75 ? .meow : .happy
                enter(.reacting)
            }
        }
    }

    /// A double click — the playful one: a short burst of play.
    func handleDoubleClick() {
        guard isRunning else { return }
        if state == .beingDragged {
            enter(.idle)
        }
        endPress()
        sequenceQueue = []
        if isOverPetted(now()) {
            reactAnnoyed()
            enter(.reacting)
            return
        }
        store.statistics.affection += 1
        enter(.playing, duration: Double.random(in: 2.2...3.4))
    }

    /// One stroke while dragging across a pettable zone. Strokes warm her
    /// up (affection), count toward tolerance, and sound like purring —
    /// the audio itself is played by the scene as it happens.
    func handlePetStroke(zone: CookieZone) {
        guard isRunning else { return }
        store.statistics.affection += 1
        recentPets.append(now())
        if isOverPetted(now()) {
            reactAnnoyed()
        }
    }

    /// The user let go: a small landing, then back to normal.
    func handleDrop() {
        guard isRunning, state == .beingDragged else { return }
        endPress()
        sequenceQueue = []
        reaction = isOverPetted(now()) ? .annoyed : .dropped
        enter(.reacting, duration: Double.random(in: 0.9...1.2))
    }

    /// The cursor drifted close. Cookie notices occasionally — never
    /// every time — glancing over for a moment.
    private func maybeNoticeCursor(dt: TimeInterval) {
        guard state != .beingDragged, store.profile.settings.cursorInteraction else { return }
        hoverCheckElapsed += dt
        guard hoverCheckElapsed >= 0.5 else { return }
        hoverCheckElapsed = 0
        let date = now()
        guard date >= hoverCooldownUntil, let cursorX = lastCursorX else { return }
        let distance = abs(cursorX - lastKnownX)
        guard distance > 30, distance < 130 else { return }
        switch state {
        case .sleeping, .eating, .drinking, .reacting, .special, .grooming, .stretching:
            return // calmly busy, or mid-animation
        default:
            break
        }
        if Double.random(in: 0...1) < 0.3 {
            hoverCooldownUntil = date.addingTimeInterval(Double.random(in: 20...45))
            noticeCount += 1
            log.debug("Noticed the cursor nearby")
            enter(.curious, duration: Double.random(in: 2...3.5))
            setFacing(cursorX >= lastKnownX ? .right : .left)
        } else {
            // Chose not to react — a short pause before considering again.
            hoverCooldownUntil = date.addingTimeInterval(Double.random(in: 5...12))
        }
    }

    private func isOverPetted(_ date: Date) -> Bool {
        recentPets.count > store.profile.personality.petTolerance || date < sulksUntil
    }

    /// Mild, cute annoyance: a hmph while looking away, then a brief
    /// sulk during which she avoids playful antics and walks away from
    /// the cursor if she moves at all.
    private func reactAnnoyed() {
        reaction = .annoyed
        usedAnnoyedReaction = true
        sulksUntil = now().addingTimeInterval(Double.random(in: 30...60))
        if let cursorX = lastCursorX {
            // Look away from the cursor.
            setFacing(cursorX >= lastKnownX ? .left : .right)
        }
        log.info("Over-petted — reacting grumpily for a while")
    }

    func handleGrab(zone: CookieZone? = nil) {
        guard isRunning else { return }
        endPress()
        sequenceQueue = []
        if worldItem != nil { clearSession() }
        enter(.beingDragged, duration: .infinity)
    }

    func handleRelease() {
        guard isRunning, state == .beingDragged else { return }
        enter(.idle)
    }

    /// Menu bar commands — the same reactions as touching her, triggered
    /// from a distance.
    /// Petting the box gets a peek from inside — she stays put.
    private func petThroughBox() {
        isPeeking = true
        peekUntil = now().addingTimeInterval(2.0)
        store.statistics.affection += 1
        store.statistics.petsReceived += 1
        recentPets.append(now())
    }

    func handleMenuPet() {
        guard isRunning, state != .beingDragged else { return }
        if state == .inBox {
            petThroughBox()
            return
        }
        sequenceQueue = []
        store.statistics.petsReceived += 1
        store.statistics.affection += 2
        recentPets.append(now())
        if isOverPetted(now()) {
            reactAnnoyed()
        } else {
            reaction = store.profile.personality == .affectionate ? .shy : .happy
        }
        if state == .sleeping {
            enter(.stretching)
        } else {
            enter(.reacting)
        }
    }

    func handleFeed() {
        guard isRunning, state != .beingDragged else { return }
        sequenceQueue = []
        enter(.eating)
    }

    func handlePlayCommand() {
        guard isRunning, state != .beingDragged else { return }
        sequenceQueue = []
        if isOverPetted(now()) { reactAnnoyed() }
        enter(.playing, duration: Double.random(in: 2.4...3.6))
    }

    func handleEdgeReached(_ edge: CookieEdge) {
        guard isRunning, state.isLocomotion else { return }
        log.info("Reached the \(edge == .left ? "left" : "right", privacy: .public) edge")
        edgeCooldownUntil = now().addingTimeInterval(Double.random(in: 25...50))
        let roll = Double.random(in: 0...1)
        if roll < 0.5 {
            enter(.walking)
            // Turn around and head back the way she came.
            let away: CGFloat = edge == .left ? 1 : -1
            plan = LocomotionPlan(
                targetX: clampX(lastKnownX + away * 320),
                timeUntilNextPause: Double.random(in: 2.5...5)
            )
        } else if roll < 0.72 {
            enter(.sitting)
        } else {
            enter(.idle)
        }
    }

    // MARK: - State machine internals

    private func stateExpired() {
        if !sequenceQueue.isEmpty {
            let (next, duration) = sequenceQueue.removeFirst()
            enter(next, duration: duration)
            return
        }
        // A finished session takes its item with it.
        if worldItem != nil { clearSession() }
        pickNextState()
    }

    private func clearSession() {
        worldItem = nil
        sessionTargetX = nil
        isPeeking = false
    }

    /// The current behavior weight table, tuned by personality, local
    /// time, and cooldowns. Internal so tests can assert on it directly.
    func behaviorWeights() -> [CookieState: Double] {
        var weights: [CookieState: Double] = [
            .idle: 45, .walking: 15, .running: 1, .sitting: 8,
            .grooming: 7, .stretching: 6, .curious: 5, .playing: 5,
            .sleeping: 4, .special: 3, .eating: 1, .drinking: 0.5,
            .followingCursor: 0.5
        ]
        for (candidate, factor) in store.profile.personality.weightMultipliers {
            weights[candidate]? *= factor
        }
        for (candidate, factor) in store.profile.settings.activity.weightMultipliers {
            weights[candidate]? *= factor
        }
        let settings = store.profile.settings
        if !settings.randomInteractions {
            // The user prefers a quiet companion: no autonomous antics.
            weights[.walking] = 0; weights[.running] = 0; weights[.playing] = 0
            weights[.special] = 0; weights[.eating] = 0; weights[.drinking] = 0
            weights[.followingCursor] = 0
        }
        if !settings.cursorInteraction { weights[.followingCursor] = 0 }
        if settings.sleep == .none { weights[.sleeping] = 0 }
        for (candidate, factor) in timeOfDay(now()).weightMultipliers {
            weights[candidate]? *= factor
        }
        let date = now()
        if date < sleepCooldownUntil { weights[.sleeping] = 0 }
        if date < followCooldownUntil { weights[.followingCursor] = 0 }
        if date < sulksUntil {
            // Grumpy sulk: calm activities only.
            weights[.followingCursor] = 0
            weights[.playing] = 0
            weights[.special] = 0
        }
        if date < edgeCooldownUntil { weights[.walking] = 0; weights[.running] = 0 }
        // A little reluctance to immediately repeat a non-idle state.
        if state != .idle { weights[state]? *= 0.3 }
        return weights
    }

    private func pickNextState() {
        let weights = behaviorWeights()
        let total = weights.values.reduce(0, +)
        guard total > 0 else {
            enter(.idle)
            return
        }
        var roll = Double.random(in: 0..<total)
        var picked: CookieState?
        for candidate in CookieState.allCases {
            guard let weight = weights[candidate], weight > 0 else { continue }
            roll -= weight
            if roll < 0 {
                picked = candidate
                break
            }
        }
        let resolved = picked ?? .idle
        // While the user is holding the mouse down on her, she must not
        // stroll off from under the pointer.
        if isPressed && resolved.isLocomotion {
            enter(.idle)
            return
        }
        // Cats talk when they feel like it: a rare spontaneous meow
        // while resting, more from chatty personalities.
        if resolved == .idle, !isOverPetted(now()),
           Double.random(in: 0...1) < spontaneousMeowChance {
            reaction = .meow
            enter(.reacting)
            return
        }
        enterPicked(resolved)
    }

    private var spontaneousMeowChance: Double {
        switch store.profile.personality {
        case .affectionate: return 0.09
        case .curious: return 0.07
        case .playful: return 0.06
        case .energetic: return 0.05
        case .sleepy: return 0.03
        case .grumpy: return 0.035
        }
    }

    private func enterPicked(_ picked: CookieState) {
        switch picked {
        case .sleeping:
            // The full ritual: yawn, settle, sleep… and stretch on waking.
            sleepCooldownUntil = now().addingTimeInterval(Double.random(in: 120...200))
            let sleepDuration = sampledSleepDuration()
            enter(.yawning, sequence: [
                (.sitting, Double.random(in: 1.5...3)),
                (.sleeping, sleepDuration),
                (.stretching, nil)
            ])
        case .followingCursor:
            followCooldownUntil = now().addingTimeInterval(Double.random(in: 90...150))
            enter(.followingCursor)
        default:
            enter(picked)
        }
    }

    private func enter(_ newState: CookieState, sequence: [(state: CookieState, duration: TimeInterval?)]? = nil, duration: TimeInterval? = nil) {
        state = newState
        stateElapsed = 0
        // Passing no sequence keeps the existing queue, so multi-step
        // rituals (yawn → sit → sleep → stretch) survive their own steps.
        if let sequence {
            sequenceQueue = sequence
        }
        currentDuration = duration ?? sampledDuration(for: newState)
        locomotionVelocity = 0
        plan = makeLocomotionPlan(for: newState)
        currentTargetX = plan?.targetX
        if let plan {
            setFacing(plan.targetX >= lastKnownX ? .right : .left)
        }
        log.debug("State → \(newState.rawValue, privacy: .public) (~\(String(format: "%.1f", self.currentDuration), privacy: .public)s)")
    }

    // MARK: - Locomotion

    private func advanceLocomotion(dt: TimeInterval, currentX: CGFloat) {
        guard var plan else {
            handleArrived()
            return
        }
        if state == .followingCursor, let lastCursorX {
            plan.targetX = clampX(lastCursorX)
        }
        let direction: CGFloat
        if plan.targetX > currentX + 3 {
            direction = 1
        } else if plan.targetX < currentX - 3 {
            direction = -1
        } else {
            direction = 0
        }
        if direction == 0 {
            handleArrived()
            return
        }

        if plan.isPaused {
            plan.pauseRemaining -= dt
            locomotionVelocity = 0
            if plan.pauseRemaining <= 0 {
                plan.isPaused = false
                plan.timeUntilNextPause = Double.random(in: 2.5...6)
            }
        } else {
            plan.timeUntilNextPause -= dt
            let speed = currentWalkSpeed
            locomotionVelocity = direction * speed
            setFacing(direction > 0 ? .right : .left)
            // Walks include little pauses; runs do not.
            if state == .walking, plan.timeUntilNextPause <= 0 {
                plan.isPaused = true
                plan.pauseRemaining = Double.random(in: 0.6...1.6)
                locomotionVelocity = 0
            }
        }
        self.plan = plan
    }

    private func handleArrived() {
        plan = nil
        locomotionVelocity = 0
        switch state {
        case .followingCursor:
            enter(.curious) // arrived near you — look up
        case .walking, .running:
            let roll = Double.random(in: 0...1)
            if roll < 0.35 {
                enter(.curious)
            } else if roll < 0.6 {
                enter(.sitting)
            } else {
                enter(.idle)
            }
        default:
            break
        }
    }

    private var currentWalkSpeed: CGFloat {
        var speed = store.profile.personality.walkSpeed
        if state == .running { speed *= 1.9 }
        switch timeOfDay(now()) {
        case .evening, .lateNight: speed *= 0.85
        default: break
        }
        return speed
    }

    private func makeLocomotionPlan(for state: CookieState) -> LocomotionPlan? {
        guard state.isLocomotion else { return nil }
        let target: CGFloat
        switch state {
        case .followingCursor:
            guard let lastCursorX else { return nil }
            target = clampX(lastCursorX)
        default:
            guard visibleXRange() != nil else { return nil }
            var candidate: CGFloat
            if now() < sulksUntil, let lastCursorX {
                // Sulking: if she moves at all, she drifts away from you.
                candidate = lastKnownX + (lastCursorX > lastKnownX ? -340 : 340)
            } else {
                candidate = lastKnownX + CGFloat.random(in: -420...420)
                if abs(candidate - lastKnownX) < 140 {
                    candidate = lastKnownX + (candidate >= lastKnownX ? 220 : -220)
                }
            }
            target = clampX(candidate)
        }
        if abs(target - lastKnownX) < 24 {
            return nil // nowhere interesting to go
        }
        return LocomotionPlan(targetX: target, timeUntilNextPause: Double.random(in: 2.5...6))
    }

    // MARK: - Durations & helpers

    private func sampledDuration(for state: CookieState) -> TimeInterval {
        let base: ClosedRange<Double>
        switch state {
        case .idle: base = 4...12
        case .walking: base = 6...14
        case .running: base = 2...4.5
        case .sitting: base = 8...22
        case .sleeping: base = 25...60

        case .yawning: base = 1.6...2.2
        case .stretching: base = 1.8...2.2
        case .grooming: base = 2.2...3
        case .curious: base = 4...9
        case .playing: base = 3.5...8
        case .eating: base = 4...7
        case .drinking: base = 2.5...4.5
        case .followingCursor: base = 3...6
        case .beingDragged: base = 0...0
        case .reacting: base = 1.2...1.8
        case .special: base = 1.2...1.6
        }
        var value = Double.random(in: base)
        if state == .idle { value /= max(0.5, store.profile.settings.activity.idleDurationFactor) }
        return value
    }

    private func lateNightFactor() -> Double {
        timeOfDay(now()) == .lateNight ? 1.5 : 1
    }

    private func sleepPersonalityFactor() -> Double {
        store.profile.personality == .sleepy ? 1.15 : 1
    }

    private func sleepDurationCap() -> Double {
        store.profile.settings.sleep == .longer ? 120 : 90
    }

    private func sampledSleepDuration() -> Double {
        let cap = sleepDurationCap()
        var value = Double.random(in: 25...60) * lateNightFactor() * sleepPersonalityFactor()
        if store.profile.settings.sleep == .longer { value *= 1.3 }
        return min(cap, value)
    }

    private func timeOfDay(_ date: Date) -> TimeOfDay {
        TimeOfDay.at(date)
    }

    private func clampX(_ x: CGFloat) -> CGFloat {
        guard let range = visibleXRange() else { return x }
        return min(max(x, CGFloat(range.lowerBound) + 20), CGFloat(range.upperBound) - 20)
    }

    private func setFacing(_ newFacing: CookieDirection) {
        guard facing != newFacing else { return }
        facing = newFacing
    }

    private func pruneRecentPets() {
        let cutoff = now().addingTimeInterval(-60)
        recentPets.removeAll { $0 < cutoff }
    }
}
