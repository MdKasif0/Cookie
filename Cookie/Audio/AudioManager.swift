import AppKit

/// Cookie's sound effects. Effects live in Resources/Sounds and are looked
/// up by name; until the final audio ships, each effect falls back to a
/// gentle system sound so feedback is never missing. Sound preferences are
/// owned by the store — this class only reads them.
enum SoundEffect: String, CaseIterable {
    case pet = "cookie-pet"
    case welcome = "cookie-welcome"

    var fallbackSystemSoundName: String {
        switch self {
        case .pet: return "Pop"
        case .welcome: return "Glass"
        }
    }
}

@MainActor
final class AudioManager {
    private let store: CookieStore

    init(store: CookieStore) {
        self.store = store
    }

    func play(_ effect: SoundEffect) {
        guard store.profile.soundEnabled else { return }
        // NSSound(named:) searches the app bundle first, then the system
        // sound directories — so bundled effects win once they ship.
        let sound = NSSound(named: NSSound.Name(effect.rawValue))
            ?? NSSound(named: NSSound.Name(effect.fallbackSystemSoundName))
        sound?.volume = Float(store.profile.soundVolume)
        sound?.play()
    }
}
