import Foundation

/// User preferences from the Settings window. Lives in the profile and
/// persists with it; every consumer reads it live from the store.
struct CookieSettings: Codable, Equatable {
    // General
    var launchAtLogin: Bool = false
    var showOnStartup: Bool = true
    var rememberPosition: Bool = true

    // Appearance
    /// Scale applied to the companion panel and character (0.7…1.4).
    var cookieSize: Double = 1.0
    /// Animation liveliness multiplier (0.5…1.5): frame rate and bobs.
    var animationIntensity: Double = 1.0
    /// "system", "always", or "never".
    var reducedMotionMode: String = ReducedMotionMode.system.rawValue

    // Sound
    var soundEnabled: Bool = true
    var masterVolume: Double = 0.7
    var meowVolume: Double = 0.8
    var interactionSounds: Bool = true
    var purringSounds: Bool = true

    // Behavior
    /// "calm", "balanced", or "lively".
    var activityLevel: String = ActivityLevel.balanced.rawValue
    var randomInteractions: Bool = true
    var cursorInteraction: Bool = true
    /// Reserved for the upcoming window-interaction milestone.
    var windowInteraction: Bool = false
    /// "normal", "longer", or "none".
    var sleepBehavior: String = SleepBehavior.normal.rawValue

    var reducedMotion: ReducedMotionMode {
        ReducedMotionMode(rawValue: reducedMotionMode) ?? .system
    }

    var activity: ActivityLevel {
        ActivityLevel(rawValue: activityLevel) ?? .balanced
    }

    var sleep: SleepBehavior {
        SleepBehavior(rawValue: sleepBehavior) ?? .normal
    }
}

enum ReducedMotionMode: String, CaseIterable, Identifiable {
    case system
    case always
    case never

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Follow System Setting"
        case .always: return "Always Reduce"
        case .never: return "Never Reduce"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case calm
    case balanced
    case lively

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .balanced: return "Balanced"
        case .lively: return "Lively"
        }
    }

    /// Multipliers applied to the locomotion/play weights.
    var weightMultipliers: [CookieState: Double] {
        switch self {
        case .calm:
            return [.walking: 0.6, .running: 0.5, .playing: 0.8, .idle: 1.15]
        case .balanced:
            return [:]
        case .lively:
            return [.walking: 1.4, .running: 1.6, .playing: 1.3, .idle: 0.85]
        }
    }

    /// Idle stretches longer when she is calm, shorter when lively.
    var idleDurationFactor: Double {
        switch self {
        case .calm: return 1.3
        case .balanced: return 1.0
        case .lively: return 0.75
        }
    }
}

enum SleepBehavior: String, CaseIterable, Identifiable {
    case normal
    case longer
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal Naps"
        case .longer: return "Longer Naps"
        case .none: return "Never Sleeps"
        }
    }
}
