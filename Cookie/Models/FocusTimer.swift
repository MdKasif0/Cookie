import Foundation

/// A focus session and the break after it. Pure state: the caller supplies elapsed time,
/// so it can be driven by a real clock or by a test.
struct FocusTimer: Equatable {
    enum Phase: Equatable {
        case idle
        case focusing
        case onBreak
    }

    enum Event: Equatable {
        case focusCompleted(minutes: Int)
        case breakCompleted
    }

    private(set) var phase: Phase = .idle
    private(set) var total: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0

    var isActive: Bool { phase != .idle }
    var remaining: TimeInterval { max(0, total - elapsed) }

    /// 0...1 through the current phase.
    var progress: Double {
        total > 0 ? min(1, elapsed / total) : 0
    }

    /// "24:10", or "1:05:00" past an hour.
    var remainingLabel: String {
        Self.format(remaining)
    }

    static func format(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    mutating func startFocus(minutes: Int) {
        begin(.focusing, minutes: minutes)
    }

    mutating func startBreak(minutes: Int) {
        begin(.onBreak, minutes: minutes)
    }

    mutating func cancel() {
        phase = .idle
        total = 0
        elapsed = 0
    }

    /// Moves the clock forward. Returns an event when a phase finishes, after which the
    /// timer is idle and the caller decides what comes next.
    mutating func advance(by seconds: TimeInterval) -> Event? {
        guard isActive, seconds > 0 else { return nil }
        elapsed += seconds
        guard elapsed >= total else { return nil }

        let finished = phase
        let minutes = Int((total / 60).rounded())
        cancel()
        return finished == .focusing ? .focusCompleted(minutes: minutes) : .breakCompleted
    }

    private mutating func begin(_ newPhase: Phase, minutes: Int) {
        phase = newPhase
        total = TimeInterval(max(1, minutes)) * 60
        elapsed = 0
    }
}
