import Foundation

/// Backs the first-run welcome window: holds the in-progress name and
/// personality, then hands them to the app environment on continue.
@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published var name: String
    @Published var personality: CookiePersonality

    private let onContinue: (String, CookiePersonality) -> Void

    init(store: CookieStore, onContinue: @escaping (String, CookiePersonality) -> Void) {
        self.name = store.profile.name
        self.personality = store.profile.personality
        self.onContinue = onContinue
    }

    /// Never empty: falls back to "Cookie" like the profile does.
    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cookie" : trimmed
    }

    func continueTapped() {
        onContinue(resolvedName, personality)
    }
}
