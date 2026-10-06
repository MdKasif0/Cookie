import Foundation

/// Cookie's temperament. Drives behavior cadence today and richer
/// behavior patterns in later milestones.
enum CookiePersonality: String, CaseIterable, Codable, Identifiable {
    case playful
    case calm
    case curious

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playful: return "Playful"
        case .calm: return "Calm"
        case .curious: return "Curious"
        }
    }

    var summary: String {
        switch self {
        case .playful: return "Hops around and loves attention."
        case .calm: return "Slow blinks, long naps, quiet company."
        case .curious: return "Watches you work and glances around."
        }
    }

    /// How long Cookie stays in one activity before picking a new one.
    var activitySwitchInterval: ClosedRange<Double> {
        switch self {
        case .playful: return 4...9
        case .calm: return 12...24
        case .curious: return 6...12
        }
    }

    /// Desktop strolling speed in points per second.
    var walkSpeed: CGFloat {
        switch self {
        case .playful: return 36
        case .calm: return 22
        case .curious: return 28
        }
    }
}
