import Foundation
import os

/// Decides what Cookie does next. This is the foundation layer — it moves
/// between resting activities at a personality-driven cadence and emits a
/// delighted reaction when Cookie is petted. The sprite layer turns each
/// activity into animations; movement behaviors (wandering, playing) plug
/// in here later.
@MainActor
final class CookieBehaviorEngine: ObservableObject {
    @Published private(set) var activity: CookieActivity = .idle
    private(set) var isRunning = false

    private let store: CookieStore
    private var timer: Timer?
    /// After reaching a screen edge, walking picks are suppressed for a
    /// while so Cookie does not ping-pong between the boundaries.
    private var edgeCooldownUntil = Date.distantPast

    private let log = Logger(subsystem: "com.cookie.mac", category: "Behavior")

    init(store: CookieStore) {
        self.store = store
    }

    func start() {
        isRunning = true
        scheduleNextActivity()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Called by the scene when the user clicks Cookie.
    func registerPet() {
        store.statistics.petsReceived += 1
        transition(to: .delighted)
        scheduleTransition(after: 1.5) { [weak self] in
            self?.transition(to: .idle)
            self?.scheduleNextActivity()
        }
    }

    /// Called when the user grabs Cookie (mouse down). Locomotion stops
    /// and the regular cadence pauses until she is released.
    func handleGrab() {
        timer?.invalidate()
        timer = nil
        transition(to: .idle)
    }

    /// Called on mouse up. Resumes the activity cadence unless a pet
    /// reaction already scheduled one.
    func resumeAfterRelease() {
        guard isRunning, timer == nil else { return }
        scheduleNextActivity()
    }

    /// Called by the scene when a walk reaches the screen boundary.
    /// Cookie stops, then turns around, idles, or sits near the edge —
    /// weighted by personality — and walking stays suppressed for a
    /// while afterward.
    func handleEdgeReached(_ edge: CookieEdge) {
        guard isRunning else { return }
        log.info("Reached the \(edge == .left ? "left" : "right", privacy: .public) edge")
        edgeCooldownUntil = Date().addingTimeInterval(Double.random(in: 25...50))

        let turnProbability: Double
        let sitProbability: Double
        switch store.profile.personality {
        case .playful: turnProbability = 0.55; sitProbability = 0.15
        case .calm: turnProbability = 0.35; sitProbability = 0.35
        case .curious: turnProbability = 0.50; sitProbability = 0.20
        }
        let roll = Double.random(in: 0...1)
        if roll < turnProbability {
            transition(to: edge == .left ? .walkingRight : .walkingLeft)
        } else if roll < turnProbability + sitProbability {
            transition(to: .sitting)
        } else {
            transition(to: .idle)
        }
        scheduleNextActivity()
    }

    // MARK: - Scheduling

    private func scheduleNextActivity() {
        timer?.invalidate()
        let interval = store.profile.personality.activitySwitchInterval
        let delay = Double.random(in: interval)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pickNextActivity()
            }
        }
        timer?.tolerance = 0.3
    }

    private func pickNextActivity() {
        guard isRunning else { return }
        transition(to: weightedNextActivity())
        scheduleNextActivity()
    }

    /// Personality-weighted choice of the next activity. One-shots
    /// (stretch, yawn, groom) play once and the sprite layer returns to
    /// the previous resting state on its own; walks move the companion
    /// panel until the cadence or a screen edge ends them.
    private func weightedNextActivity() -> CookieActivity {
        let weights: [(CookieActivity, Double)]
        switch store.profile.personality {
        case .playful:
            weights = [(.idle, 0.28), (.watching, 0.22), (.sitting, 0.05),
                       (.stretching, 0.14), (.yawning, 0.04), (.grooming, 0.08),
                       (.walkingLeft, 0.095), (.walkingRight, 0.095)]
        case .calm:
            weights = [(.idle, 0.29), (.watching, 0.13), (.sitting, 0.19),
                       (.stretching, 0.04), (.yawning, 0.14), (.grooming, 0.12),
                       (.walkingLeft, 0.045), (.walkingRight, 0.045)]
        case .curious:
            weights = [(.idle, 0.25), (.watching, 0.27), (.sitting, 0.05),
                       (.stretching, 0.04), (.yawning, 0.04), (.grooming, 0.13),
                       (.walkingLeft, 0.11), (.walkingRight, 0.11)]
        }
        let roll = Double.random(in: 0...1)
        var cumulative = 0.0
        var picked = CookieActivity.idle
        for (activity, weight) in weights {
            cumulative += weight
            if roll <= cumulative {
                picked = activity
                break
            }
        }
        // No ping-ponging between edges: walks rest during the cooldown.
        if (picked == .walkingLeft || picked == .walkingRight) && Date() < edgeCooldownUntil {
            picked = .idle
        }
        return picked
    }

    private func scheduleTransition(after seconds: Double, action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
    }

    private func transition(to newActivity: CookieActivity) {
        guard newActivity != activity else { return }
        log.debug("Activity: \(self.activity.rawValue) → \(newActivity.rawValue)")
        activity = newActivity
    }
}
