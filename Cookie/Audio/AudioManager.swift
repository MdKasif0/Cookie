import AppKit

/// Cookie's vocalizations and effects, synthesized as small WAV files in
/// the bundle's Sounds folder (real recordings can replace them by name —
/// see Resources/Sounds/README.md). Sounds are cached, throttled per
/// effect, and respect the per-category volume settings.
enum SoundEffect: String, CaseIterable {
    case purr = "cookie-purr"
    case meow = "cookie-meow"
    case happy = "cookie-happy"       // the rising "mrrp!"
    case mew = "cookie-mew"           // the tiny shy mew
    case chirp = "cookie-chirp"       // two little pips when she notices you
    case surprise = "cookie-surprise"
    case eat = "cookie-eat"
    case toy = "cookie-toy"
    case drop = "cookie-drop"
    case sleep = "cookie-sleep"
    case welcome = "cookie-welcome"   // a soft two-note mew

    var fallbackSystemSoundName: String {
        switch self {
        case .purr: return "Purr"      // a real purr ships with macOS
        case .meow: return "Pop"
        case .happy: return "Bottle"
        case .mew: return "Tink"
        case .chirp: return "Ping"
        case .surprise: return "Tink"
        case .eat: return "Blow"
        case .toy: return "Bottle"
        case .drop: return "Blow"
        case .sleep: return "Submarine"
        case .welcome: return "Glass"
        }
    }

    /// Minimum seconds between two plays of the same effect.
    var minimumInterval: TimeInterval {
        self == .purr ? 1.0 : 0.35
    }

    /// Click/hover/land feedback, gated by "interaction sounds".
    var isInteractionSound: Bool {
        switch self {
        case .meow, .mew, .happy, .chirp, .surprise, .toy, .drop, .eat: return true
        default: return false
        }
    }

    /// Vocalizations follow the meow volume slider.
    var usesMeowVolume: Bool {
        switch self {
        case .meow, .mew, .happy, .chirp: return true
        default: return false
        }
    }
}

@MainActor
final class AudioManager {
    private let store: CookieStore
    /// Cached players — one per effect, replayed in place.
    private var players: [SoundEffect: NSSound] = [:]
    private var lastPlayed: [SoundEffect: Date] = [:]

    init(store: CookieStore) {
        self.store = store
    }

    func play(_ effect: SoundEffect) {
        let settings = store.profile.settings
        guard settings.soundEnabled else { return }
        guard effect.isInteractionSound == false || settings.interactionSounds else { return }
        if effect == .purr || effect == .sleep {
            guard settings.purringSounds else { return }
        }

        let date = Date()
        if let last = lastPlayed[effect], date.timeIntervalSince(last) < effect.minimumInterval {
            return
        }
        lastPlayed[effect] = date

        let volume = effect.usesMeowVolume
            ? min(settings.meowVolume, settings.masterVolume)
            : settings.masterVolume
        guard volume > 0.01 else { return }

        let sound = player(for: effect)
        sound.volume = Float(volume)
        sound.play()
    }

    private func player(for effect: SoundEffect) -> NSSound {
        if let cached = players[effect] {
            return cached
        }
        let sound: NSSound?
        if let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        } else {
            sound = NSSound(named: NSSound.Name(effect.rawValue))
        }
        let resolved = sound ?? NSSound(named: NSSound.Name(effect.fallbackSystemSoundName)) ?? NSSound()
        players[effect] = resolved
        return resolved
    }
}
