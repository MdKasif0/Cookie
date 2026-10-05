import Foundation

/// Everything persisted about the user's cat: identity, customization,
/// sound preferences, companion state, and unlocks. The single source of
/// truth for Cookie's configuration — no view keeps its own copy.
struct CookieProfile: Codable, Equatable {
    var name: String = "Cookie"
    var personality: CookiePersonality = .playful
    var appearance: CookieAppearance = .classicCream
    var accessories: [String] = []
    var unlockedAccessories: [String] = []
    var soundEnabled: Bool = true
    var soundVolume: Double = 0.7
    var isCompanionVisible: Bool = true
    var hasCompletedWelcome: Bool = false
    var companionPosition: CGPoint?

    init() {}

    /// Name shown in the menu bar and settings; never empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cookie" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case name, personality, appearance, accessories, unlockedAccessories
        case soundEnabled, soundVolume, isCompanionVisible, hasCompletedWelcome, companionPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Cookie"
        personality = try container.decodeIfPresent(CookiePersonality.self, forKey: .personality) ?? .playful
        appearance = try container.decodeIfPresent(CookieAppearance.self, forKey: .appearance) ?? .classicCream
        accessories = try container.decodeIfPresent([String].self, forKey: .accessories) ?? []
        unlockedAccessories = try container.decodeIfPresent([String].self, forKey: .unlockedAccessories) ?? []
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        soundVolume = try container.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.7
        isCompanionVisible = try container.decodeIfPresent(Bool.self, forKey: .isCompanionVisible) ?? true
        hasCompletedWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedWelcome) ?? false
        companionPosition = try container.decodeIfPresent(CGPoint?.self, forKey: .companionPosition) ?? nil
    }
}
