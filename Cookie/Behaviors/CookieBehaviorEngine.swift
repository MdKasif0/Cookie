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

    private let store: CookieStore
    private var timer: Timer?
    private var isRunning = false

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
    /// the previous resting state on its own; the engine just keeps its
    /// regular cadence.
    private func weightedNextActivity() -> CookieActivity {
        let weights: [(CookieActivity, Double)]
        switch store.profile.personality {
        case .playful:
            weights = [(.idle, 0.34), (.watching, 0.26), (.sitting, 0.05),
                       (.stretching, 0.17), (.yawning, 0.04), (.grooming, 0.14)]
        case .calm:
            weights = [(.idle, 0.30), (.watching, 0.14), (.sitting, 0.22),
                       (.stretching, 0.04), (.yawning, 0.16), (.grooming, 0.14)]
        case .curious:
            weights = [(.idle, 0.30), (.watching, 0.34), (.sitting, 0.06),
                       (.stretching, 0.05), (.yawning, 0.04), (.grooming, 0.21)]
        }
        let roll = Double.random(in: 0...1)
        var cumulative = 0.0
        for (activity, weight) in weights {
            cumulative += weight
            if roll <= cumulative {
                return activity
            }
        }
        return .idle
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
