import Foundation

/// An accessory Cookie can wear. Accessories unlock in a later milestone;
/// the catalog and persistence for them ship now so unlocking is a data
/// change, not an architecture change.
struct Accessory: Identifiable, Equatable {
    let id: String
    let displayName: String
    let symbolName: String
}

/// Everything the Customization UI can offer, in one place.
enum AppearanceCatalog {
    static let appearances: [CookieAppearance] = CookieAppearance.allCases

    /// Accessories ship in a future update; the UI shows an honest
    /// empty state until the first ones are drawn.
    static let accessories: [Accessory] = []

    static func isUnlocked(_ accessory: Accessory, profile: CookieProfile) -> Bool {
        profile.unlockedAccessories.contains(accessory.id)
    }
}
