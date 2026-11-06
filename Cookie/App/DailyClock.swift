import Foundation
import Combine

/// Tells the app when the calendar day changes while it keeps running, so seasonal outfits
/// switch at midnight and each new day counts as a visit.
@MainActor
final class DailyClock: ObservableObject {
    static let shared = DailyClock()

    @Published private(set) var day: Date
    private var timer: Timer?
    var now: () -> Date = { Date() }

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
        day = Calendar.current.startOfDay(for: now())
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    /// Public so waking from sleep and tests can force a check.
    func check() {
        let today = Calendar.current.startOfDay(for: now())
        if today != day { day = today }
    }
}
