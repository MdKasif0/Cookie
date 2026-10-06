import Foundation
import SpriteKit

/// A named fur palette the user can pick in Appearance settings.
enum CookieAppearance: String, CaseIterable, Codable, Identifiable {
    case classicCream
    case warmSand
    case sageMist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classicCream: return "Classic Cream"
        case .warmSand: return "Warm Sand"
        case .sageMist: return "Sage Mist"
        }
    }
}

/// The full set of colors the character renderer needs, derived from an
/// appearance. Keeping this in one struct makes re-skinning trivial when
/// the final artwork arrives.
struct CharacterPalette: Equatable {
    let fur: SKColor
    let furShade: SKColor
    let outline: SKColor
    let innerEar: SKColor
    let blush: SKColor
    let stripe: SKColor
    let eye: SKColor
    /// Applied as a subtle source-atop tint over the shipped artwork so
    /// the Appearance setting stays meaningful; `nil` leaves art untouched.
    var artTint: SKColor? = nil

    static func standard(for appearance: CookieAppearance) -> CharacterPalette {
        switch appearance {
        case .classicCream:
            return CharacterPalette(
                fur: SKColor(hex: 0xF7ECD9),
                furShade: SKColor(hex: 0xEDE0C8),
                outline: SKColor(hex: 0x7B6A57),
                innerEar: SKColor(hex: 0xF0B98A),
                blush: SKColor(hex: 0xF2B48C),
                stripe: SKColor(hex: 0xC89A67),
                eye: SKColor(hex: 0x3B342E)
            )
        case .warmSand:
            return CharacterPalette(
                fur: SKColor(hex: 0xF1DDBE),
                furShade: SKColor(hex: 0xE5CFA9),
                outline: SKColor(hex: 0x77624A),
                innerEar: SKColor(hex: 0xE9A97B),
                blush: SKColor(hex: 0xEDAE85),
                stripe: SKColor(hex: 0xBC8452),
                eye: SKColor(hex: 0x3B342E),
                artTint: SKColor(hex: 0xE8B77D)
            )
        case .sageMist:
            return CharacterPalette(
                fur: SKColor(hex: 0xE9EBDF),
                furShade: SKColor(hex: 0xDBDEC9),
                outline: SKColor(hex: 0x6E7260),
                innerEar: SKColor(hex: 0xE3C6A2),
                blush: SKColor(hex: 0xE9C1A0),
                stripe: SKColor(hex: 0x9CA97F),
                eye: SKColor(hex: 0x36342C),
                artTint: SKColor(hex: 0xB7C4A4)
            )
        }
    }
}
