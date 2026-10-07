import Foundation
import CoreGraphics

/// Cookie's temperament. Personalities shift behavior weights and
/// reactions — they tint the same calm companion rather than creating
/// caricatures.
enum CookiePersonality: String, CaseIterable, Codable, Identifiable {
    case sleepy
    case playful
    case affectionate
    case energetic
    case curious
    case grumpy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleepy: return "Sleepy"
        case .playful: return "Playful"
        case .affectionate: return "Affectionate"
        case .energetic: return "Energetic"
        case .curious: return "Curious"
        case .grumpy: return "Grumpy"
        }
    }

    var summary: String {
        switch self {
        case .sleepy: return "Naps often, but always up for gentle company."
        case .playful: return "Little games and occasional bursts of mischief."
        case .affectionate: return "Likes being near you; sometimes follows the cursor."
        case .energetic: return "Always trotting off somewhere new."
        case .curious: return "Watches everything, investigates everything."
        case .grumpy: return "Judgmental, but secretly fond of you."
        }
    }

    /// Desktop strolling speed in points per second.
    var walkSpeed: CGFloat {
        switch self {
        case .sleepy: return 18
        case .playful: return 34
        case .affectionate: return 26
        case .energetic: return 40
        case .curious: return 28
        case .grumpy: return 20
        }
    }

    /// Pets inside a one-minute window after which reactions turn
    /// annoyed. Grumpy Cookie has a short fuse; affectionate Cookie
    /// nearly never tires of attention.
    var petTolerance: Int {
        switch self {
        case .sleepy: return 4
        case .playful: return 7
        case .affectionate: return 9
        case .energetic: return 7
        case .curious: return 6
        case .grumpy: return 2
        }
    }

    /// Multipliers applied to the base behavior weights. Values are
    /// gentle by design — personalities lean, they do not caricature.
    var weightMultipliers: [CookieState: Double] {
        switch self {
        case .sleepy:
            return [.sleeping: 3.2, .sitting: 1.5, .walking: 0.7,
                    .running: 0.15, .playing: 0.5, .special: 0.7, .curious: 0.9]
        case .playful:
            return [.playing: 2.0, .special: 1.5, .walking: 1.2,
                    .running: 1.8, .sleeping: 0.55, .sitting: 0.85]
        case .affectionate:
            return [.followingCursor: 5, .curious: 1.4, .sitting: 1.2,
                    .grooming: 1.1, .running: 0.8]
        case .energetic:
            return [.walking: 1.5, .running: 2.6, .playing: 1.7, .special: 1.2,
                    .sitting: 0.6, .sleeping: 0.45, .grooming: 0.8]
        case .curious:
            return [.curious: 2.2, .walking: 1.25, .followingCursor: 2,
                    .playing: 1.2, .sleeping: 0.7]
        case .grumpy:
            return [.sleeping: 1.4, .sitting: 1.35, .walking: 0.8,
                    .playing: 0.55, .followingCursor: 0.25, .special: 0.7, .curious: 0.9]
        }
    }
}
