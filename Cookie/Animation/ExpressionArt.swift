import Foundation

/// Whole-pose expression artwork supplied by the user. Each sticker
/// replaces Cookie's derived animation for one state or reaction — the
/// angry pose plays when she is annoyed, the dizzy one when she lands
/// after a fall, and so on. When a sticker is unavailable (or a future
/// artwork set removes it), the derived animation runs instead.
enum CookieExpressionArt: String, CaseIterable {
    case angry
    case cool
    case dizzy
    case embarrassed
    case eyesClose = "eyes-close"
    case hungry
    case mischievous
    case scared
    case shy
    case sleep
    case walk

    var assetName: String { "cookie-\(rawValue)" }

    var displayName: String {
        switch self {
        case .angry: return "Angry"
        case .cool: return "Cool"
        case .dizzy: return "Dizzy"
        case .embarrassed: return "Embarrassed"
        case .eyesClose: return "Joyful"
        case .hungry: return "Hungry"
        case .mischievous: return "Mischievous"
        case .scared: return "Scared"
        case .shy: return "Shy"
        case .sleep: return "Asleep"
        case .walk: return "Strolling"
        }
    }

    /// Stickers whose silhouette differs a lot from the base pose —
    /// accessories stay hidden while they play so nothing floats.
    static var poseFarFromBase: Set<CookieExpressionArt> {
        [.sleep, .walk, .dizzy]
    }

    /// Which sticker plays for a given state and reaction. `nil` means
    /// the derived animation handles it.
    static func forState(_ state: CookieState, reaction: CookieReaction) -> CookieExpressionArt? {
        switch state {
        case .reacting:
            switch reaction {
            case .annoyed: return .angry
            case .surprised: return .scared
            case .happy: return .eyesClose
            case .dropped: return .dizzy
            case .embarrassed: return .embarrassed
            case .shy: return .shy
            case .meow: return nil
            }
        case .playing: return .mischievous
        case .eating: return .hungry
        case .special: return .cool
        case .sleeping: return .sleep
        case .walking, .followingCursor: return .walk
        default: return nil
        }
    }
}
