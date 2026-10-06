import Foundation

/// What Cookie is doing right now, as decided by the behavior engine.
/// The sprite layer maps each activity onto animations via the
/// `SpriteAnimationController`.
enum CookieActivity: String, Codable, Equatable, CaseIterable {
    /// Resting loop: breathing, blinking, tail sway.
    case idle
    /// Glancing side to side, watching the desktop.
    case watching
    /// Transient reaction to being petted.
    case delighted
    /// Sitting still — a calmer flavor of idle.
    case sitting
    /// One-shot: a long, satisfying stretch.
    case stretching
    /// One-shot: a wide yawn.
    case yawning
    /// One-shot: licking a paw and tidying up.
    case grooming
}
