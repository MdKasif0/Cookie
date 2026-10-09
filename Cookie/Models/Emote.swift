import Foundation

/// Unique identifier for each predefined Cookie emote.
enum EmoteId: String, CaseIterable, Identifiable, Codable {
    case wave
    case happy
    case love
    case sleepy
    case playful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wave: return "Wave"
        case .happy: return "Happy"
        case .love: return "Love"
        case .sleepy: return "Sleepy"
        case .playful: return "Playful"
        }
    }

    var emoji: String {
        switch self {
        case .wave: return "👋"
        case .happy: return "✨"
        case .love: return "🧡"
        case .sleepy: return "💤"
        case .playful: return "🧶"
        }
    }
}

/// Explicit lifecycle phases of an emote sequence.
enum EmotePlaybackPhase: String, CaseIterable, Equatable {
    case ready
    case starting
    case playing
    case finishing
    case returning
}

/// Reusable model describing a complete Cookie emote.
///
/// Contains metadata, identifiers, durations, cooldowns, and priority.
/// Execution and animation logic remain in the animation controller and
/// behavior state machine.
struct Emote: Identifiable, Equatable, Hashable {
    let id: EmoteId
    let name: String
    let description: String
    /// SF Symbol name representing this emote in native UI.
    let icon: String
    /// Associated animation sequence in the animation catalog.
    let animationIdentifier: CookieAnimationId
    /// Baseline sequence duration in seconds.
    let duration: TimeInterval
    /// Associated sound effect vocalization or cue.
    let soundIdentifier: SoundEffect?
    /// Minimum cooldown in seconds before this emote can be triggered again.
    let cooldown: TimeInterval
    /// Animation priority tier.
    let priority: CookieAnimationPriority
    /// Representative emoji symbol.
    var emoji: String { id.emoji }

    // MARK: - Predefined Catalog

    static let wave = Emote(
        id: .wave,
        name: "Wave",
        description: "Cookie says hello.",
        icon: "hand.wave.fill",
        animationIdentifier: .wave,
        duration: 2.0,
        soundIdentifier: .mew,
        cooldown: 2.0,
        priority: .emote
    )

    static let happy = Emote(
        id: .happy,
        name: "Happy",
        description: "Cookie is feeling happy.",
        icon: "sparkles",
        animationIdentifier: .happyEmote,
        duration: 1.8,
        soundIdentifier: .happy,
        cooldown: 1.8,
        priority: .emote
    )

    static let love = Emote(
        id: .love,
        name: "Love",
        description: "Cookie sends you some love.",
        icon: "heart.fill",
        animationIdentifier: .love,
        duration: 2.0,
        soundIdentifier: .purr,
        cooldown: 2.0,
        priority: .emote
    )

    static let sleepy = Emote(
        id: .sleepy,
        name: "Sleepy",
        description: "Cookie needs a little nap.",
        icon: "moon.zzz.fill",
        animationIdentifier: .sleepy,
        duration: 4.0,
        soundIdentifier: .sleep,
        cooldown: 3.0,
        priority: .emote
    )

    static let playful = Emote(
        id: .playful,
        name: "Playful",
        description: "Cookie wants to play.",
        icon: "pawprint.fill",
        animationIdentifier: .playfulEmote,
        duration: 2.2,
        soundIdentifier: .toy,
        cooldown: 2.0,
        priority: .emote
    )

    /// Complete ordered list of the five initial emotes.
    static let allEmotes: [Emote] = [
        .wave,
        .happy,
        .love,
        .sleepy,
        .playful
    ]

    static func find(_ id: EmoteId) -> Emote {
        allEmotes.first { $0.id == id } ?? .wave
    }
}
