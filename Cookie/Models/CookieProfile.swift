import Foundation

/// Everything persisted about the user's cat: identity, customization,
/// sound preferences, companion state, and unlocks. The single source of
/// truth for Cookie's configuration — no view keeps its own copy.
struct CookieProfile: Codable, Equatable {
    var name: String = "Cookie"
    var personality: CookiePersonality = .playful
    var customization: CookieAppearanceConfig = CookieAppearanceConfig()
    var settings = CookieSettings()
    var accessories: [String] = []
    /// Ids of unlocked items (see `BondItem.id`) that must stay available regardless of level.
    var unlockedAccessories: [String] = []
    var cozyItems: [CozyPlacement] = []
    var isCompanionVisible: Bool = true
    var hasCompletedWelcome: Bool = false
    var companionPosition: CGPoint?
    var lastRestingState: CookieState?
    /// Reminders and timers still to come.
    var reminders: [CookieReminder] = []
    /// When she last suggested going to bed, so she says it once a night.
    var lastBedtimeWindDown: Date?
    var stickyNotes: [StickyNote] = []
    var todos: [TodoItem] = []
    /// When she last offered to tidy screenshots, so she asks at most once a day.
    var lastScreenshotOffer: Date?
    /// Whether she has shown the helpers tour. Profiles from before the tour existed start without it,
    /// so people who update see it once.
    var hasSeenHelpersTour: Bool = false

    init() {}

    /// Name shown in the menu bar and settings; never empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cookie" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case name, personality, customization, settings, legacyAppearance = "appearance"
        case accessories, unlockedAccessories, cozyItems
        case legacySoundEnabled = "soundEnabled"
        case legacySoundVolume = "soundVolume"
        case isCompanionVisible, hasCompletedWelcome, companionPosition, lastRestingState
        case reminders, lastBedtimeWindDown, stickyNotes, todos, lastScreenshotOffer, hasSeenHelpersTour
    }

    /// Encodes everything except the legacy key, which only exists for
    /// decoding the pre-customization format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(personality, forKey: .personality)
        try container.encode(customization, forKey: .customization)
        try container.encode(settings, forKey: .settings)
        try container.encode(accessories, forKey: .accessories)
        try container.encode(unlockedAccessories, forKey: .unlockedAccessories)
        try container.encode(cozyItems, forKey: .cozyItems)
        try container.encode(isCompanionVisible, forKey: .isCompanionVisible)
        try container.encode(hasCompletedWelcome, forKey: .hasCompletedWelcome)
        try container.encode(companionPosition, forKey: .companionPosition)
        try container.encodeIfPresent(lastRestingState, forKey: .lastRestingState)
        try container.encode(reminders, forKey: .reminders)
        try container.encodeIfPresent(lastBedtimeWindDown, forKey: .lastBedtimeWindDown)
        try container.encode(stickyNotes, forKey: .stickyNotes)
        try container.encode(todos, forKey: .todos)
        try container.encodeIfPresent(lastScreenshotOffer, forKey: .lastScreenshotOffer)
        try container.encode(hasSeenHelpersTour, forKey: .hasSeenHelpersTour)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Cookie"
        // Personalities evolve across releases; an unknown stored value
        // must never take the whole profile down with it.
        if let rawPersonality = try container.decodeIfPresent(String.self, forKey: .personality) {
            personality = CookiePersonality(rawValue: rawPersonality) ?? .playful
        } else {
            personality = .playful
        }
        if let storedCustomization = try? container.decodeIfPresent(CookieAppearanceConfig.self, forKey: .customization) {
            customization = storedCustomization
        } else {
            // Migrate the pre-customization three-palette choice.
            let legacy = try container.decodeIfPresent(String.self, forKey: .legacyAppearance)
            customization = CookieAppearanceConfig.from(legacyAppearance: legacy)
        }
        accessories = try container.decodeIfPresent([String].self, forKey: .accessories) ?? []
        unlockedAccessories = try container.decodeIfPresent([String].self, forKey: .unlockedAccessories) ?? []
        cozyItems = (try? container.decodeIfPresent([CozyPlacement].self, forKey: .cozyItems)) ?? []
        // Settings decode resiliently, migrating the old top-level sound
        // fields into the settings struct.
        if let storedSettings = try container.decodeIfPresent(CookieSettings.self, forKey: .settings) {
            settings = storedSettings
        } else {
            var migrated = CookieSettings()
            migrated.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .legacySoundEnabled) ?? true
            migrated.masterVolume = try container.decodeIfPresent(Double.self, forKey: .legacySoundVolume) ?? 0.7
            settings = migrated
        }
        isCompanionVisible = try container.decodeIfPresent(Bool.self, forKey: .isCompanionVisible) ?? true
        hasCompletedWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedWelcome) ?? false
        companionPosition = try container.decodeIfPresent(CGPoint?.self, forKey: .companionPosition) ?? nil
        lastRestingState = try? container.decodeIfPresent(CookieState.self, forKey: .lastRestingState)
        reminders = (try? container.decodeIfPresent([CookieReminder].self, forKey: .reminders)) ?? []
        lastBedtimeWindDown = try? container.decodeIfPresent(Date.self, forKey: .lastBedtimeWindDown)
        stickyNotes = (try? container.decodeIfPresent([StickyNote].self, forKey: .stickyNotes)) ?? []
        todos = (try? container.decodeIfPresent([TodoItem].self, forKey: .todos)) ?? []
        lastScreenshotOffer = try? container.decodeIfPresent(Date.self, forKey: .lastScreenshotOffer)
        hasSeenHelpersTour = (try? container.decodeIfPresent(Bool.self, forKey: .hasSeenHelpersTour)) ?? false
    }
}
