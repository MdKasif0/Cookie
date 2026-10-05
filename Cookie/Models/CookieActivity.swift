import Foundation

/// What Cookie is doing right now. The behavior engine publishes changes;
/// the sprite layer maps each activity onto animations.
enum CookieActivity: String, Codable, Equatable {
    /// Resting loop: breathing, blinking, tail sway.
    case idle
    /// Glancing side to side, watching the desktop.
    case watching
    /// Transient reaction to being petted.
    case delighted
}
