import AppKit
import Combine
import CoreGraphics

/// The little jobs Cookie does for you: reminders and timers, break nudges, the focus guard and
/// the bedtime wind-down. It checks the clock every few seconds; the decisions themselves live in
/// the pure models in `Helpers.swift`.
@MainActor
final class HelpersController: ObservableObject {
    /// Upcoming reminders, soonest first. Mirrors the store so menus can read it cheaply.
    var reminders: [CookieReminder] {
        store.profile.reminders.sorted { $0.dueAt < $1.dueAt }
    }

    private let store: CookieStore
    private let engine: CookieBehaviorEngine
    private let say: (String, TimeInterval) -> Void
    private let play: (SoundEffect) -> Void
    /// Puts her beside your cursor, showing her if she was hidden and stepping over a
    /// full-screen app for a moment.
    private let bringToCursor: () -> Void

    private var ticker: Timer?
    private var nudges: BreakNudgeSchedule
    private var guardCooldownUntil = Date.distantPast
    private var contextWatch: AnyCancellable?

    // Seams for tests.
    var now: () -> Date = { Date() }
    /// Seconds since the last keyboard or mouse input. Reading it needs no permission.
    var idleSeconds: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
    var isQuiet: () -> Bool = { false }
    var isFocusing: () -> Bool = { false }
    var frontmostBundleId: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    static let focusGuardCooldown: TimeInterval = 90

    init(store: CookieStore,
         engine: CookieBehaviorEngine,
         say: @escaping (String, TimeInterval) -> Void,
         play: @escaping (SoundEffect) -> Void,
         bringToCursor: @escaping () -> Void) {
        self.store = store
        self.engine = engine
        self.say = say
        self.play = play
        self.bringToCursor = bringToCursor
        self.nudges = BreakNudgeSchedule(start: Date())
    }

    func start() {
        guard ticker == nil else { return }
        nudges.restart(at: now())
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 1
        contextWatch = engine.contextDetector.$currentContext
            .map(\.bundleIdentifier)
            .removeDuplicates()
            .sink { [weak self] bundleId in self?.appDidSwitch(to: bundleId) }
        tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        contextWatch = nil
    }

    // MARK: - Reminders

    @discardableResult
    func addReminder(text: String, minutes: Int) -> CookieReminder {
        let reminder = CookieReminder(text: text, dueAt: now().addingTimeInterval(TimeInterval(max(1, minutes)) * 60))
        store.profile.reminders.append(reminder)
        let what = reminder.text.trimmingCharacters(in: .whitespacesAndNewlines)
        say(what.isEmpty
            ? "Timer set for \(CookieReminder.label(forMinutes: minutes))."
            : "Okay! I'll remind you in \(CookieReminder.label(forMinutes: minutes)).", 4)
        objectWillChange.send()
        return reminder
    }

    func cancelReminder(id: UUID) {
        store.profile.reminders.removeAll { $0.id == id }
        objectWillChange.send()
    }

    // MARK: - The clock

    /// Runs every few seconds, and directly from tests.
    func tick() {
        let date = now()
        deliverDueReminders(at: date)
        checkBreakNudges(at: date)
        checkBedtime(at: date)
    }

    /// A reminder always gets through: she comes to your cursor, meows and says it, even over a
    /// full-screen app, because you asked for it. Several due at once are said together.
    private func deliverDueReminders(at date: Date) {
        let (due, waiting) = ReminderQueue.split(store.profile.reminders, at: date)
        guard !due.isEmpty else { return }
        store.profile.reminders = waiting
        objectWillChange.send()

        bringToCursor()
        engine.summon()
        play(.meow)
        let text = due.count == 1
            ? due[0].message
            : due.map { "• \($0.message)" }.joined(separator: "\n")
        say(text, 12)
    }

    private func checkBreakNudges(at date: Date) {
        let enabled = store.profile.settings.enabledBreakNudges
        // Stepping away counts as a break, so the clocks start again.
        if idleSeconds() >= BreakNudgeSchedule.idleReset {
            nudges.restart(at: date)
            return
        }
        guard !enabled.isEmpty, let nudge = nudges.due(at: date, enabled: enabled) else { return }
        // Not now: she waits, and the nudge stays due until a better moment.
        guard canInterrupt else { return }
        nudges.markShown(nudge, at: date)
        engine.performNudge(nudge)
        play(nudge == .water ? .chirp : .mew)
        say(nudge.message(name: store.profile.displayName), 8)
    }

    private func checkBedtime(at date: Date) {
        let settings = store.profile.settings
        guard settings.bedtimeEnabled,
              Bedtime.shouldWindDown(now: date, minutes: settings.bedtimeMinutes, lastWindDown: store.profile.lastBedtimeWindDown),
              idleSeconds() < BreakNudgeSchedule.idleReset,
              canInterrupt else { return }
        store.profile.lastBedtimeWindDown = date
        engine.windDown()
        play(.sleep)
        say(Bedtime.message(name: store.profile.displayName), 8)
    }

    /// Nudges and bedtime hold off while she is hidden, a full-screen app or video call is in front,
    /// or a focus session is running.
    private var canInterrupt: Bool {
        store.profile.isCompanionVisible
            && !isQuiet()
            && !isFocusing()
            && !MeetingApps.isMeeting(bundleId: frontmostBundleId())
    }

    // MARK: - Focus guard

    func appDidSwitch(to bundleId: String?) {
        let settings = store.profile.settings
        let date = now()
        guard settings.focusGuardEnabled,
              isFocusing(),
              !isQuiet(),
              date >= guardCooldownUntil,
              let app = DistractingApp.matches(settings.distractingApps, bundleId: bundleId) else { return }
        guardCooldownUntil = date.addingTimeInterval(Self.focusGuardCooldown)
        // She sits down right in front of what you opened.
        bringToCursor()
        engine.noticeDistraction()
        play(.mew)
        say(DistractingApp.scolding(appName: app.name), 5)
    }
}
