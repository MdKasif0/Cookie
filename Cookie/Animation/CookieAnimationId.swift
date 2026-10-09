import Foundation

/// How forcefully an animation competes to play. Higher tiers interrupt
/// lower ones: sleep < idle < walk < interaction < special.
enum CookieAnimationPriority: Int, Comparable {
    case sleep = 0
    case idle = 10
    case walk = 20
    case interaction = 30
    case emote = 35
    case special = 40

    static func < (lhs: CookieAnimationPriority, rhs: CookieAnimationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Bundle folder an animation's sprite sheet lives in, under
/// `Sprites/Cookie/<Category>/<sheet name>`.
enum CookieAnimationCategory: String, CaseIterable {
    case idle = "Idle"
    case walk = "Walk"
    case run = "Run"
    case sleep = "Sleep"
    case interaction = "Interaction"
    case emotions = "Emotions"
    case special = "Special"
    case emotes = "Emotes"
}

/// Everything the animation system needs to know about one animation.
struct CookieAnimationSpec {
    let category: CookieAnimationCategory
    /// Resource name inside the category folder. Directional animations
    /// (walkLeft/walkRight, runLeft/runRight) share one base name.
    let sheetName: String
    let priority: CookieAnimationPriority
    let isLooping: Bool
    let fps: Double
    /// Set when playing this animation implies a facing direction.
    let direction: CookieDirection?

    /// Resources that ship no sheet for this animation fall back to idle
    /// once, with a warning; callers never need to check availability.
    static func standard(
        _ category: CookieAnimationCategory,
        _ sheetName: String,
        priority: CookieAnimationPriority,
        looping: Bool,
        fps: Double,
        direction: CookieDirection? = nil
    ) -> CookieAnimationSpec {
        CookieAnimationSpec(
            category: category,
            sheetName: sheetName,
            priority: priority,
            isLooping: looping,
            fps: fps,
            direction: direction
        )
    }
}

/// The full animation catalog. Not every animation needs artwork: the
/// controller falls back to idle for any whose sheet and placeholder
/// frames are both absent, so new animations can be added gradually.
enum CookieAnimationId: String, CaseIterable {
    case idle
    case idleBlink
    case walkLeft
    case walkRight
    case runLeft
    case runRight
    case sit
    case sleep
    case wake
    case stretch
    case yawn
    case groom
    case happy
    case surprised
    case curious
    case annoyed
    case scared
    case playful
    case eat
    case drink
    case jump
    case fall
    case pickedUp
    case dropped
    case pet
    case meow
    case investigate
    case tired
    case inBox
    case boxPeek
    // User-triggered emotes (priority .emote)
    case wave
    case happyEmote
    case love
    case sleepy
    case playfulEmote

    var spec: CookieAnimationSpec {
        switch self {
        case .idle:
            return .standard(.idle, "idle", priority: .idle, looping: true, fps: 5)
        case .idleBlink:
            return .standard(.idle, "idleBlink", priority: .idle, looping: false, fps: 10)
        case .sit:
            return .standard(.idle, "sit", priority: .idle, looping: true, fps: 3)
        case .sleep:
            return .standard(.sleep, "sleep", priority: .sleep, looping: true, fps: 2)
        case .wake:
            return .standard(.sleep, "wake", priority: .idle, looping: false, fps: 4)
        case .stretch:
            return .standard(.idle, "stretch", priority: .idle, looping: false, fps: 4)
        case .yawn:
            return .standard(.idle, "yawn", priority: .idle, looping: false, fps: 4)
        case .groom:
            return .standard(.idle, "groom", priority: .idle, looping: false, fps: 5)
        case .walkLeft:
            return .standard(.walk, "walk", priority: .walk, looping: true, fps: 7, direction: .left)
        case .walkRight:
            return .standard(.walk, "walk", priority: .walk, looping: true, fps: 7, direction: .right)
        case .runLeft:
            return .standard(.run, "run", priority: .walk, looping: true, fps: 10, direction: .left)
        case .runRight:
            return .standard(.run, "run", priority: .walk, looping: true, fps: 10, direction: .right)
        case .curious:
            return .standard(.emotions, "curious", priority: .idle, looping: true, fps: 4)
        case .happy:
            return .standard(.emotions, "happy", priority: .interaction, looping: false, fps: 6)
        case .surprised:
            return .standard(.emotions, "surprised", priority: .interaction, looping: false, fps: 6)
        case .scared:
            return .standard(.emotions, "scared", priority: .interaction, looping: false, fps: 6)
        case .annoyed:
            return .standard(.emotions, "annoyed", priority: .idle, looping: true, fps: 4)
        case .playful:
            return .standard(.emotions, "playful", priority: .interaction, looping: true, fps: 6)
        case .eat:
            return .standard(.interaction, "eat", priority: .interaction, looping: true, fps: 5)
        case .drink:
            return .standard(.interaction, "drink", priority: .interaction, looping: true, fps: 5)
        case .pet:
            return .standard(.interaction, "pet", priority: .interaction, looping: false, fps: 6)
        case .meow:
            return .standard(.interaction, "meow", priority: .interaction, looping: false, fps: 6)
        case .investigate:
            return .standard(.interaction, "investigate", priority: .interaction, looping: true, fps: 4)
        case .tired:
            return .standard(.idle, "tired", priority: .idle, looping: true, fps: 3)
        case .inBox:
            return .standard(.sleep, "inBox", priority: .sleep, looping: true, fps: 2)
        case .boxPeek:
            return .standard(.interaction, "boxPeek", priority: .interaction, looping: true, fps: 4)
        case .jump:
            return .standard(.special, "jump", priority: .special, looping: false, fps: 8)
        case .fall:
            return .standard(.special, "fall", priority: .special, looping: false, fps: 8)
        case .pickedUp:
            return .standard(.special, "pickedUp", priority: .special, looping: true, fps: 4)
        case .dropped:
            return .standard(.special, "dropped", priority: .special, looping: false, fps: 8)
        case .wave:
            return .standard(.emotes, "wave", priority: .emote, looping: false, fps: 6)
        case .happyEmote:
            return .standard(.emotes, "happy", priority: .emote, looping: false, fps: 6)
        case .love:
            return .standard(.emotes, "love", priority: .emote, looping: false, fps: 6)
        case .sleepy:
            return .standard(.emotes, "sleepy", priority: .emote, looping: false, fps: 4)
        case .playfulEmote:
            return .standard(.emotes, "playful", priority: .emote, looping: false, fps: 6)
        }
    }

    /// SpriteKit key under which the frame animation action runs, so it
    /// can be replaced without touching unrelated node actions.
    static let actionKey = "cookie.frames"
}
