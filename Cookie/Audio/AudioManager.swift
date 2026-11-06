import AppKit

/// Cookie's vocalizations and effects: designed WAV files in the bundle's Sounds folder
/// (recordings can replace them by name, see Resources/Sounds/README.md). Sounds are cached,
/// throttled per effect, and respect the per-category volume settings.
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

extension SoundEffect {
    /// Alternate takes, so repeated sounds don't feel mechanical.
    var fileNames: [String] {
        switch self {
        case .meow: return [rawValue, "\(rawValue)-2", "\(rawValue)-3"]
        case .mew, .happy: return [rawValue, "\(rawValue)-2"]
        default: return [rawValue]
        }
    }
}

@MainActor
final class AudioManager {
    /// How long purring continues after the last thing that made her purr.
    static let purrHoldSeconds: TimeInterval = 5
    private static let purrFadeInSeconds: TimeInterval = 0.25
    private static let purrFadeOutSeconds: TimeInterval = 0.9

    private let store: CookieStore
    /// Cached players, one per file, replayed in place.
    private var players: [String: NSSound] = [:]
    private var lastPlayed: [SoundEffect: Date] = [:]
    private var lastTake: [SoundEffect: String] = [:]

    private var purrPlayer: NSSound?
    private var purrUntil: Date = .distantPast
    private var purrStartedAt: Date = .distantPast
    private var purrFadeStartedAt: Date?
    private var purrTimer: Timer?

    /// True while the purr loop is audible.
    var isPurring: Bool { purrPlayer?.isPlaying == true }

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

        if effect == .purr {
            startOrExtendPurr()
            return
        }

        let date = Date()
        if let last = lastPlayed[effect], date.timeIntervalSince(last) < effect.minimumInterval {
            return
        }
        lastPlayed[effect] = date

        let volume = volume(for: effect)
        guard volume > 0.01 else { return }

        let sound = player(forFile: nextTake(of: effect), effect: effect)
        sound.volume = Float(volume)
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    func stopPurring() {
        purrTimer?.invalidate()
        purrTimer = nil
        purrPlayer?.stop()
        purrFadeStartedAt = nil
    }

    private func volume(for effect: SoundEffect) -> Double {
        let settings = store.profile.settings
        return effect.usesMeowVolume
            ? min(settings.meowVolume, settings.masterVolume)
            : settings.masterVolume
    }

    /// Picks a take at random, avoiding the one just heard.
    private func nextTake(of effect: SoundEffect) -> String {
        let takes = effect.fileNames
        let choices = takes.count > 1 ? takes.filter { $0 != lastTake[effect] } : takes
        let chosen = choices.randomElement() ?? effect.rawValue
        lastTake[effect] = chosen
        return chosen
    }

    // MARK: - Purring

    /// Purring is continuous: each pet keeps the loop going, and it fades when attention stops.
    private func startOrExtendPurr() {
        purrUntil = Date().addingTimeInterval(Self.purrHoldSeconds)
        purrFadeStartedAt = nil

        guard !isPurring else { return }
        guard volume(for: .purr) > 0.01 else { return }

        let sound = purrPlayer ?? player(forFile: SoundEffect.purr.rawValue, effect: .purr)
        purrPlayer = sound
        sound.loops = true
        sound.volume = 0
        purrStartedAt = Date()
        sound.play()

        purrTimer?.invalidate()
        purrTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePurrVolume()
            }
        }
    }

    private func updatePurrVolume() {
        let settings = store.profile.settings
        guard let purrPlayer, settings.soundEnabled, settings.purringSounds else {
            stopPurring()
            return
        }

        let now = Date()
        let target = Float(volume(for: .purr))
        if now < purrUntil {
            let progress = now.timeIntervalSince(purrStartedAt) / Self.purrFadeInSeconds
            purrPlayer.volume = target * Float(min(1, progress))
            return
        }

        let fadeStart = purrFadeStartedAt ?? now
        purrFadeStartedAt = fadeStart
        let progress = now.timeIntervalSince(fadeStart) / Self.purrFadeOutSeconds
        if progress >= 1 {
            stopPurring()
        } else {
            purrPlayer.volume = target * Float(1 - progress)
        }
    }

    // MARK: - Files

    private func player(forFile name: String, effect: SoundEffect) -> NSSound {
        if let cached = players[name] {
            return cached
        }
        let sound: NSSound?
        if let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        } else {
            sound = NSSound(named: NSSound.Name(name))
        }
        let resolved = sound ?? NSSound(named: NSSound.Name(effect.fallbackSystemSoundName)) ?? NSSound()
        players[name] = resolved
        return resolved
    }
}
