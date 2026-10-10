import Foundation
import CoreGraphics

/// Discrete proximity zones around Cookie based on rendered size.
enum CursorProximityZone: String, CaseIterable, Equatable {
    /// Outside all interaction range (> 350 pt adjusted).
    case departure
    /// Cookie senses the pointer and glances toward it (<= 250 pt adjusted).
    case awareness
    /// Cookie is engaged and may choose to approach or follow (<= 120 pt adjusted).
    case interaction
    /// The pointer is right next to or touching Cookie (<= 55 pt adjusted).
    case closeContact

    var displayName: String {
        switch self {
        case .departure: return "Departure"
        case .awareness: return "Awareness"
        case .interaction: return "Interaction"
        case .closeContact: return "Close Contact"
        }
    }
}

/// Categorization of cursor movement dynamics.
enum CursorMotionState: String, Equatable {
    /// Pointer is virtually still (< 30 pt/s).
    case stationary
    /// Pointer is moving smoothly and gently (30...450 pt/s) — ideal for following.
    case slow
    /// Pointer is moving rapidly (> 600 pt/s) — Cookie watches or pauses, never chases.
    case rapid
}

/// Playful deterministic reactions Cookie can exhibit during cursor play.
enum CursorPlayfulReaction: String, Equatable {
    /// Gentle curious gaze toward the pointer.
    case glance
    /// Adorable subtle head tilt toward cursor position.
    case headTilt
    /// Gentle step toward the interaction zone.
    case approach
    /// Playful paw reach or investigative tap.
    case pawReach
    /// Gentle step backward when cursor approaches swiftly.
    case dodge
    /// Joyful purr or happy chirp after successful play.
    case happyChirp
}

/// User preference for cursor following liveliness.
enum CursorFollowingIntensity: String, CaseIterable, Identifiable, Codable {
    case subtle
    case balanced
    case playful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .playful: return "Playful"
        }
    }

    /// Maximum following speed in points per second.
    var maxSpeed: CGFloat {
        switch self {
        case .subtle: return 110
        case .balanced: return 160
        case .playful: return 220
        }
    }

    /// Desired trailing distance from the cursor in points.
    var trailingDistance: CGFloat {
        switch self {
        case .subtle: return 95
        case .balanced: return 75
        case .playful: return 60
        }
    }

    /// Anticipation pause before beginning to follow in seconds.
    var anticipationDelay: TimeInterval {
        switch self {
        case .subtle: return 0.6
        case .balanced: return 0.4
        case .playful: return 0.25
        }
    }
}
