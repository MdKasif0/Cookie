import Foundation

/// What Cookie is doing, as decided by the behavior state machine. The
/// sprite layer maps each state (plus a facing and a reaction flavor)
/// onto animations.
enum CookieState: String, Codable, CaseIterable {
    case idle
    case walking
    case running
    case sitting
    case sleeping
    case yawning
    case stretching
    case grooming
    case curious
    case playing
    case eating
    case drinking
    case followingCursor
    case beingDragged
    case reacting
    case special

    /// States that move the companion panel across the desktop.
    var isLocomotion: Bool {
        switch self {
        case .walking, .running, .followingCursor: return true
        default: return false
        }
    }
}

/// Flavor of a reaction. Each maps to a distinct animation or expression
/// pose and sound.
enum CookieReaction: String, Codable, CaseIterable {
    case happy          // joyful closed-eye pose, purring
    case annoyed        // hmph — arms crossed, looks away
    case surprised      // wide eyes, little gasp
    case meow           // a plain meow
    case shy            // hearts and hidden face — deep affection
    case embarrassed    // blushing paws-up moment
    case dropped        // the swirly-eyed landing after being let go
}

/// Which part of Cookie is being touched. Zones are normalized regions
/// over the artwork, so they scale with the sprite.
enum CookieZone: String, Codable, CaseIterable {
    case nose
    case head
    case tail
    case feet
    case body

    /// Zones where stroking counts as petting.
    var isPettable: Bool {
        self == .head || self == .body
    }
}

/// Coarse local-time bucket used to shift behavior weights.
enum TimeOfDay {
    case morning    // 05:00–10:00 — wake up, stretch, gentle exploring
    case day        // 10:00–17:00 — the baseline
    case evening    // 17:00–22:00 — calmer, more sitting and grooming
    case lateNight  // 22:00–05:00 — sleepy, slow, long naps

    static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<10: return .morning
        case 10..<17: return .day
        case 17..<22: return .evening
        default: return .lateNight
        }
    }

    /// Behavior weight multipliers for this time of day. Mornings favor
    /// stretching and strolling; late nights are sleepy and slow.
    var weightMultipliers: [CookieState: Double] {
        switch self {
        case .morning:
            return [.stretching: 1.8, .walking: 1.15, .sleeping: 0.5, .sitting: 0.9]
        case .day:
            return [:]
        case .evening:
            return [.sitting: 1.3, .grooming: 1.2, .walking: 0.85, .running: 0.5]
        case .lateNight:
            return [.sleeping: 3.2, .sitting: 1.4, .walking: 0.6, .running: 0.2,
                    .playing: 0.5, .special: 0.5]
        }
    }
}
