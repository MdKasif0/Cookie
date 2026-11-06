import Foundation
import Combine

/// Runs focus sessions: Cookie naps beside you while the clock counts down, then stretches and
/// tells you it is time for a break. Time advances by real elapsed time, so a Mac that sleeps
/// through the end of a session still finishes it on waking.
@MainActor
final class FocusController: ObservableObject {
    @Published private(set) var timer = FocusTimer()

    private let store: CookieStore
    private let engine: CookieBehaviorEngine
    private let say: (String) -> Void
    private let play: (SoundEffect) -> Void
    private var ticker: Timer?
    private var lastTick = Date()

    var now: () -> Date = { Date() }

    init(store: CookieStore,
         engine: CookieBehaviorEngine,
         say: @escaping (String) -> Void,
         play: @escaping (SoundEffect) -> Void) {
        self.store = store
        self.engine = engine
        self.say = say
        self.play = play
    }

    var isFocusing: Bool { timer.phase == .focusing }
    var isOnBreak: Bool { timer.phase == .onBreak }

    /// Text for the menu bar while a session runs, such as "24:10" or "Break 4:30".
    var statusTitle: String? {
        switch timer.phase {
        case .idle: return nil
        case .focusing: return timer.remainingLabel
        case .onBreak: return "Break \(timer.remainingLabel)"
        }
    }

    func startFocus(minutes: Int? = nil) {
        let length = minutes ?? store.profile.settings.focusMinutes
        if timer.isActive { stop() }
        timer.startFocus(minutes: length)
        engine.beginFocus()
        say("Okay, I'll keep you company.")
        startTicking()
    }

    /// Ends a focus session early or skips the break.
    func stop() {
        if timer.phase == .focusing { engine.endFocus(completed: false) }
        timer.cancel()
        stopTicking()
    }

    /// Advances the clock to `date`. Called once a second, and directly by tests.
    func tick(at date: Date? = nil) {
        let current = date ?? now()
        let delta = max(0, current.timeIntervalSince(lastTick))
        lastTick = current
        guard let event = timer.advance(by: delta) else {
            objectWillChange.send()
            return
        }

        switch event {
        case .focusCompleted(let minutes):
            store.statistics.recordFocusSession(minutes: minutes)
            engine.endFocus(completed: true)
            say("Time for a break! You focused for \(minutes) minutes.")
            timer.startBreak(minutes: store.profile.settings.breakMinutes)
        case .breakCompleted:
            say("Break's over. Ready for another round?")
            play(.chirp)
            stopTicking()
        }
    }

    private func startTicking() {
        lastTick = now()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }
}
