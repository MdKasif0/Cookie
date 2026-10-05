import Foundation
import os

/// Decides what Cookie does next. This is the foundation layer — it
/// alternates idle activities at a personality-driven cadence and emits
/// a delighted reaction when Cookie is petted. Advanced behaviors
/// (wandering, sleeping, playing) plug in here later.
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
        let next: CookieActivity
        if activity == .watching {
            next = .idle
        } else if Double.random(in: 0...1) < 0.55 {
            next = .watching
        } else {
            next = .idle
        }
        transition(to: next)
        scheduleNextActivity()
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
