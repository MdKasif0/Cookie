import Foundation

// Pure models for the little jobs Cookie does for you: reminders, break nudges, the focus guard
// and bedtime. They hold no timers and read no clock, so the controller and the tests drive them.

// MARK: - Reminders and timers

/// "Remind me in 20 minutes to call Mom." Persisted, so a reminder survives a relaunch.
struct CookieReminder: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var dueAt: Date

    /// What she says when it is time. A timer without words still gets a line.
    var message: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Time's up!" : trimmed
    }

    /// The lengths offered in the menu and the new-reminder sheet, in minutes.
    static let presetMinutes = [1, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]

    static func label(forMinutes minutes: Int) -> String {
        if minutes < 60 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        if minutes % 60 == 0 { return minutes == 60 ? "1 hour" : "\(minutes / 60) hours" }
        return String(format: "%.1f hours", Double(minutes) / 60)
    }

    /// "in 12 min", "in 1 h 05 min", or "now".
    func remainingLabel(from now: Date) -> String {
        let minutes = Int((dueAt.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        return String(format: "in %d h %02d min", minutes / 60, minutes % 60)
    }
}

enum ReminderQueue {
    /// Splits reminders into those due at `now`, soonest first, and those still waiting.
    static func split(_ reminders: [CookieReminder], at now: Date) -> (due: [CookieReminder], waiting: [CookieReminder]) {
        let sorted = reminders.sorted { $0.dueAt < $1.dueAt }
        return (sorted.filter { $0.dueAt <= now }, sorted.filter { $0.dueAt > now })
    }
}

// MARK: - Break nudges

enum BreakNudge: String, CaseIterable, Codable, Identifiable {
    case eyes
    case posture
    case water

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eyes: return "Rest your eyes"
        case .posture: return "Check your posture"
        case .water: return "Drink some water"
        }
    }

    /// How long you use the Mac between nudges of this kind.
    var interval: TimeInterval {
        switch self {
        case .eyes: return 20 * 60      // the 20-20-20 rule
        case .posture: return 45 * 60
        case .water: return 60 * 60
        }
    }

    var settingsHint: String {
        switch self {
        case .eyes: return "Every 20 minutes: look at something 20 feet away for 20 seconds"
        case .posture: return "Every 45 minutes: sit up and roll your shoulders"
        case .water: return "Every hour: a reminder to have a drink"
        }
    }

    func message(name: String) -> String {
        switch self {
        case .eyes: return "Look at something far away for 20 seconds. I'll wait."
        case .posture: return "Stretch with me! Sit up tall and roll your shoulders."
        case .water: return "\(name) is having a drink. You should too!"
        }
    }
}

/// When each nudge is next due. Time only counts while you are using the Mac: after a long
/// idle stretch everything starts over, because you have already had your break.
struct BreakNudgeSchedule: Equatable {
    /// Nudges never come closer together than this, so two never arrive at once.
    static let minimumGap: TimeInterval = 5 * 60
    /// Idle for this long counts as a break.
    static let idleReset: TimeInterval = 5 * 60

    private(set) var lastShown: [BreakNudge: Date] = [:]
    private(set) var lastAny: Date = .distantPast

    init(start: Date) { restart(at: start) }

    mutating func restart(at date: Date) {
        for nudge in BreakNudge.allCases { lastShown[nudge] = date }
    }

    /// The nudge to show now, if any. The most overdue enabled one wins.
    func due(at now: Date, enabled: Set<BreakNudge>) -> BreakNudge? {
        guard now.timeIntervalSince(lastAny) >= Self.minimumGap else { return nil }
        return enabled
            .map { ($0, now.timeIntervalSince(lastShown[$0] ?? now) - $0.interval) }
            .filter { $0.1 >= 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    mutating func markShown(_ nudge: BreakNudge, at date: Date) {
        lastShown[nudge] = date
        lastAny = date
    }
}

// MARK: - Meetings

enum MeetingApps {
    /// Video-call apps. A nudge or bedtime chat never interrupts while one of them is in front.
    private static let tokens = ["us.zoom.", "zoom.us", "com.microsoft.teams", "com.apple.facetime", "webex", "com.cisco", "gotomeeting", "bluejeans", "around", "tuple", "pop.com"]

    static func isMeeting(bundleId: String?) -> Bool {
        guard let id = bundleId?.lowercased(), !id.isEmpty else { return false }
        return tokens.contains { id.contains($0) }
    }
}

// MARK: - Focus guard

/// An app you've told Cookie distracts you. She can only see which app is in front, never
/// which website or document is open.
struct DistractingApp: Codable, Equatable, Hashable, Identifiable {
    var bundleId: String
    var name: String

    var id: String { bundleId }

    static func matches(_ apps: [DistractingApp], bundleId: String?) -> DistractingApp? {
        guard let id = bundleId?.lowercased(), !id.isEmpty else { return nil }
        return apps.first { $0.bundleId.lowercased() == id }
    }

    /// The lines she uses when you wander off mid-session.
    static func scolding(appName: String) -> String {
        ["Hey… weren't we focusing?",
         "\(appName)? Already?",
         "I saw that. Back to work!",
         "Just a peek, then back to it, okay?"].randomElement()!
    }
}

// MARK: - Bedtime

enum Bedtime {
    /// How long after bedtime she still brings it up. After that the night is over.
    static let window: TimeInterval = 3 * 3600

    /// The bedtime moment this `now` belongs to, if we are inside its window.
    /// `minutes` is minutes after midnight, so 23:30 is 1410.
    static func currentBedtime(now: Date, minutes: Int, calendar: Calendar = .current) -> Date? {
        let startOfToday = calendar.startOfDay(for: now)
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        guard let today = calendar.date(byAdding: .minute, value: clamped, to: startOfToday),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        for candidate in [today, yesterday] where candidate <= now && now.timeIntervalSince(candidate) < window {
            return candidate
        }
        return nil
    }

    /// True when it is past bedtime tonight and she hasn't said so yet.
    static func shouldWindDown(now: Date, minutes: Int, lastWindDown: Date?, calendar: Calendar = .current) -> Bool {
        guard let bedtime = currentBedtime(now: now, minutes: minutes, calendar: calendar) else { return false }
        guard let last = lastWindDown else { return true }
        return last < bedtime
    }

    /// "11:30 PM" in the user's own clock style.
    static func label(minutes: Int) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func message(name: String) -> String {
        ["It's getting late. Time to wrap up?",
         "\(name) is sleepy… are you?",
         "Bedtime soon. Save your work and rest up!"].randomElement()!
    }
}
