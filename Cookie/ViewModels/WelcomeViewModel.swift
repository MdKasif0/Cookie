import Foundation
import Combine

/// Backs the first-run welcome window: holds the in-progress name and personality,
/// directs Cookie's reactions on the stage, then hands the choices to the app on continue.
@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published var name: String {
        didSet {
            guard name != oldValue else { return }
            stage.reactToTyping()
            playThrottled(.chirp)
        }
    }

    @Published var personality: CookiePersonality {
        didSet {
            guard personality != oldValue else { return }
            stage.actOut(personality)
            playThrottled(personality.greetingSound)
        }
    }

    @Published private(set) var hasArrived = false

    let stage: WelcomeStageScene

    private let onContinue: (String, CookiePersonality) -> Void
    private let audioManager: AudioManager?
    private var lastSound: Date = .distantPast

    init(store: CookieStore,
         audioManager: AudioManager? = nil,
         onContinue: @escaping (String, CookiePersonality) -> Void) {
        self.name = store.profile.name
        self.personality = store.profile.personality
        self.audioManager = audioManager
        self.onContinue = onContinue
        self.stage = WelcomeStageScene(config: store.profile.customization)
    }

    /// Never empty: falls back to "Cookie" like the profile does.
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cookie" : trimmed
    }

    var greeting: String {
        "Hi, I'm \(resolvedName)!"
    }

    /// Starts Cookie's entrance. Safe to call more than once.
    func begin() {
        stage.walkIn { [weak self] in
            self?.hasArrived = true
            self?.playThrottled(.welcome)
        }
    }

    func continueTapped() {
        onContinue(resolvedName, personality)
    }

    /// Keeps a burst of typing from chirping on every key.
    private func playThrottled(_ sound: SoundEffect) {
        let now = Date()
        guard now.timeIntervalSince(lastSound) > 1.2 else { return }
        lastSound = now
        audioManager?.play(sound)
    }
}

extension CookiePersonality {
    /// The sprite sheet that shows this personality on its welcome card.
    var previewSheet: (category: String, name: String) {
        switch self {
        case .sleepy: return ("Sleep", "sleep")
        case .playful: return ("Emotions", "playful")
        case .affectionate: return ("Interaction", "pet")
        case .energetic: return ("Run", "run")
        case .curious: return ("Emotions", "curious")
        case .grumpy: return ("Emotions", "annoyed")
        }
    }

    var greetingSound: SoundEffect {
        switch self {
        case .sleepy: return .sleep
        case .playful: return .toy
        case .affectionate: return .purr
        case .energetic: return .happy
        case .curious: return .chirp
        case .grumpy: return .meow
        }
    }
}
