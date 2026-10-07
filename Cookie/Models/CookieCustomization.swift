import Foundation
import CoreGraphics
import SpriteKit

// MARK: - Appearance dimensions

/// Fur colors drawn from the warm Cookie palette. Each color applies a
/// subtle tint over the shipped artwork; `warmWhite` leaves it untouched.
enum FurColor: String, CaseIterable, Codable, Identifiable {
    case warmWhite
    case cream
    case ivory
    case softBeige
    case mutedSage
    case softGreen
    case warmPeach
    case softOrange
    case mutedBrown
    case charcoal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warmWhite: return "Warm White"
        case .cream: return "Cream"
        case .ivory: return "Ivory"
        case .softBeige: return "Soft Beige"
        case .mutedSage: return "Muted Sage"
        case .softGreen: return "Soft Green"
        case .warmPeach: return "Warm Peach"
        case .softOrange: return "Soft Orange"
        case .mutedBrown: return "Muted Brown"
        case .charcoal: return "Charcoal"
        }
    }

    /// Swatch color for the customization UI.
    var swatch: CGColor {
        switch self {
        case .warmWhite: return CGColor(srgbRed: 0.98, green: 0.96, blue: 0.93, alpha: 1)
        case .cream: return CGColor(srgbRed: 0.97, green: 0.91, blue: 0.78, alpha: 1)
        case .ivory: return CGColor(srgbRed: 0.99, green: 0.96, blue: 0.89, alpha: 1)
        case .softBeige: return CGColor(srgbRed: 0.91, green: 0.84, blue: 0.71, alpha: 1)
        case .mutedSage: return CGColor(srgbRed: 0.72, green: 0.77, blue: 0.64, alpha: 1)
        case .softGreen: return CGColor(srgbRed: 0.66, green: 0.75, blue: 0.63, alpha: 1)
        case .warmPeach: return CGColor(srgbRed: 0.96, green: 0.79, blue: 0.66, alpha: 1)
        case .softOrange: return CGColor(srgbRed: 0.94, green: 0.69, blue: 0.48, alpha: 1)
        case .mutedBrown: return CGColor(srgbRed: 0.55, green: 0.44, blue: 0.31, alpha: 1)
        case .charcoal: return CGColor(srgbRed: 0.29, green: 0.27, blue: 0.25, alpha: 1)
        }
    }

    /// Multiply tint baked over the artwork. Multiply scales luminance,
    /// so the coat takes the color while the shading and contrast of the
    /// user's artwork are preserved exactly.
    var multiplyColor: CGColor? {
        switch self {
        case .warmWhite: return nil
        case .cream: return CGColor(srgbRed: 0.965, green: 0.895, blue: 0.76, alpha: 1)
        case .ivory: return CGColor(srgbRed: 0.985, green: 0.955, blue: 0.885, alpha: 1)
        case .softBeige: return CGColor(srgbRed: 0.90, green: 0.81, blue: 0.66, alpha: 1)
        case .mutedSage: return CGColor(srgbRed: 0.72, green: 0.77, blue: 0.62, alpha: 1)
        case .softGreen: return CGColor(srgbRed: 0.66, green: 0.75, blue: 0.62, alpha: 1)
        case .warmPeach: return CGColor(srgbRed: 0.95, green: 0.77, blue: 0.62, alpha: 1)
        case .softOrange: return CGColor(srgbRed: 0.92, green: 0.66, blue: 0.44, alpha: 1)
        case .mutedBrown: return CGColor(srgbRed: 0.48, green: 0.38, blue: 0.27, alpha: 1)
        case .charcoal: return CGColor(srgbRed: 0.30, green: 0.28, blue: 0.26, alpha: 1)
        }
    }

    /// Vector-renderer palette, derived so the placeholder cat matches.
    var palette: CharacterPalette {
        let fur: (CGFloat, CGFloat, CGFloat)
        let furShade: (CGFloat, CGFloat, CGFloat)
        let outline: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .warmWhite:
            fur = (0.97, 0.94, 0.88); furShade = (0.92, 0.87, 0.78); outline = (0.48, 0.42, 0.35)
        case .cream, .ivory:
            fur = (0.96, 0.90, 0.77); furShade = (0.90, 0.82, 0.66); outline = (0.45, 0.39, 0.32)
        case .softBeige:
            fur = (0.90, 0.82, 0.68); furShade = (0.82, 0.73, 0.57); outline = (0.42, 0.36, 0.29)
        case .mutedSage, .softGreen:
            fur = (0.76, 0.80, 0.67); furShade = (0.66, 0.71, 0.57); outline = (0.38, 0.42, 0.33)
        case .warmPeach, .softOrange:
            fur = (0.95, 0.78, 0.62); furShade = (0.89, 0.68, 0.50); outline = (0.47, 0.34, 0.24)
        case .mutedBrown:
            fur = (0.62, 0.51, 0.38); furShade = (0.52, 0.42, 0.30); outline = (0.26, 0.21, 0.16)
        case .charcoal:
            fur = (0.42, 0.40, 0.38); furShade = (0.34, 0.32, 0.30); outline = (0.16, 0.15, 0.14)
        }
        return CharacterPalette(
            fur: SKColor(srgbRed: fur.0, green: fur.1, blue: fur.2, alpha: 1),
            furShade: SKColor(srgbRed: furShade.0, green: furShade.1, blue: furShade.2, alpha: 1),
            outline: SKColor(srgbRed: outline.0, green: outline.1, blue: outline.2, alpha: 1),
            innerEar: SKColor(srgbRed: 0.94, green: 0.70, blue: 0.60, alpha: 1),
            blush: SKColor(srgbRed: 0.95, green: 0.72, blue: 0.63, alpha: 1),
            stripe: SKColor(srgbRed: 0.72, green: 0.58, blue: 0.42, alpha: 1),
            eye: SKColor(srgbRed: 0.23, green: 0.20, blue: 0.18, alpha: 1)
        )
    }
}

/// Coat patterns rendered as soft overlays on the base pose.
enum FurPattern: String, CaseIterable, Codable, Identifiable {
    case none
    case tuxedo
    case points
    case tabby

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .tuxedo: return "Tuxedo"
        case .points: return "Points"
        case .tabby: return "Tabby"
        }
    }
}

enum EyeColor: String, CaseIterable, Codable, Identifiable {
    case charcoal
    case warmBrown
    case honey
    case moss
    case rust

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .charcoal: return "Charcoal"
        case .warmBrown: return "Warm Brown"
        case .honey: return "Honey"
        case .moss: return "Moss"
        case .rust: return "Rust"
        }
    }

    var renderColor: CGColor? {
        switch self {
        case .charcoal: return nil
        case .warmBrown: return CGColor(srgbRed: 0.36, green: 0.24, blue: 0.14, alpha: 1)
        case .honey: return CGColor(srgbRed: 0.66, green: 0.44, blue: 0.18, alpha: 1)
        case .moss: return CGColor(srgbRed: 0.42, green: 0.46, blue: 0.28, alpha: 1)
        case .rust: return CGColor(srgbRed: 0.62, green: 0.32, blue: 0.20, alpha: 1)
        }
    }

    var swatch: CGColor {
        renderColor ?? CGColor(srgbRed: 0.23, green: 0.20, blue: 0.18, alpha: 1)
    }
}

enum EyeStyle: String, CaseIterable, Codable, Identifiable {
    case round
    case sleepy
    case sparkle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .round: return "Round"
        case .sleepy: return "Sleepy"
        case .sparkle: return "Sparkle"
        }
    }
}

enum BodyVariation: String, CaseIterable, Codable, Identifiable {
    case classic
    case chubby
    case petite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .chubby: return "Chubby"
        case .petite: return "Petite"
        }
    }

    var scale: (x: CGFloat, y: CGFloat) {
        switch self {
        case .classic: return (1, 1)
        case .chubby: return (1.05, 1.02)
        case .petite: return (0.94, 0.96)
        }
    }
}

enum EarVariation: String, CaseIterable, Codable, Identifiable {
    case normal
    case rounded
    case tufted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .rounded: return "Rounded"
        case .tufted: return "Tufted"
        }
    }
}

enum TailVariation: String, CaseIterable, Codable, Identifiable {
    case normal
    case fluffy
    case curly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .fluffy: return "Fluffy"
        case .curly: return "Curly"
        }
    }
}

// MARK: - Accessories

/// The seasonal or thematic grouping for an accessory.
enum AccessoryTheme: String, CaseIterable, Codable, Identifiable {
    case classic
    case winter
    case holiday
    case autumn
    case party

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .winter: return "Winter"
        case .holiday: return "Holiday"
        case .autumn: return "Autumn"
        case .party: return "Party"
        }
    }

    var icon: String {
        switch self {
        case .classic: return "sparkles"
        case .winter: return "snowflake"
        case .holiday: return "gift"
        case .autumn: return "leaf"
        case .party: return "party.popper"
        }
    }
}

/// The accessory kinds Cookie can wear. Each is drawn as a crisp vector
/// layer anchored to the artwork, so it tracks the sprite.
enum AccessoryKind: String, CaseIterable, Codable, Identifiable {
    case collar
    case bow
    case hat
    case glasses
    case scarf
    case crown
    case bandana
    case pumpkin
    case santaHat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .collar: return "Collar"
        case .bow: return "Bow"
        case .hat: return "Party Hat"
        case .glasses: return "Glasses"
        case .scarf: return "Winter Scarf"
        case .crown: return "Crown"
        case .bandana: return "Bandana"
        case .pumpkin: return "Pumpkin"
        case .santaHat: return "Santa Hat"
        }
    }

    var theme: AccessoryTheme {
        switch self {
        case .collar, .bow, .glasses, .bandana: return .classic
        case .scarf: return .winter
        case .santaHat: return .holiday
        case .pumpkin: return .autumn
        case .hat, .crown: return .party
        }
    }

    var isSeasonal: Bool {
        theme != .classic
    }

    /// Anchor in artwork-normalized coordinates (top-left origin).
    var anchor: CGPoint {
        switch self {
        case .collar: return CGPoint(x: 0.47, y: 0.62)
        case .bow: return CGPoint(x: 0.27, y: 0.10)
        case .hat: return CGPoint(x: 0.46, y: 0.03)
        case .glasses: return CGPoint(x: 0.46, y: 0.415)
        case .scarf: return CGPoint(x: 0.47, y: 0.635)
        case .crown: return CGPoint(x: 0.46, y: 0.045)
        case .bandana: return CGPoint(x: 0.47, y: 0.60)
        case .pumpkin: return CGPoint(x: 0.46, y: 0.04)
        case .santaHat: return CGPoint(x: 0.46, y: 0.03)
        }
    }
}

/// Per-accessory customization: on/off plus gentle scale and vertical
/// placement so everything can sit just right.
struct AccessoryConfig: Codable, Equatable, Identifiable {
    var kind: AccessoryKind
    var isEnabled: Bool = false
    var scale: CGFloat = 1
    /// Normalized vertical nudge (-0.08…0.08 of the artwork height).
    var offsetY: CGFloat = 0

    var id: String { kind.rawValue }
}

// MARK: - Full configuration

/// Everything the customization window edits. Lives in the profile,
/// persists automatically, and drives every render layer.
struct CookieAppearanceConfig: Codable, Equatable {
    var furColor: FurColor = .warmWhite
    var furPattern: FurPattern = .none
    var eyeColor: EyeColor = .charcoal
    var eyeStyle: EyeStyle = .round
    var bodyVariation: BodyVariation = .classic
    var earVariation: EarVariation = .normal
    var tailVariation: TailVariation = .normal
    var accessories: [AccessoryConfig] = AccessoryKind.allCases.map {
        AccessoryConfig(kind: $0)
    }

    /// Stable key for texture caches.
    var renderKey: String {
        "\(furColor.rawValue)|\(furPattern.rawValue)|\(eyeColor.rawValue)|\(eyeStyle.rawValue)|\(bodyVariation.rawValue)"
    }

    func accessory(for kind: AccessoryKind) -> AccessoryConfig {
        accessories.first { $0.kind == kind } ?? AccessoryConfig(kind: kind)
    }

    mutating func setAccessory(_ config: AccessoryConfig) {
        if let index = accessories.firstIndex(where: { $0.kind == config.kind }) {
            accessories[index] = config
        } else {
            accessories.append(config)
        }
    }

    /// Restores the previous three-palette choices from before the
    /// customization system existed.
    static func from(legacyAppearance: String?) -> CookieAppearanceConfig {
        var config = CookieAppearanceConfig()
        switch legacyAppearance {
        case "warmSand": config.furColor = .cream
        case "sageMist": config.furColor = .mutedSage
        default: break
        }
        return config
    }
}

// MARK: - Vector palette

/// Colors the vector-drawn placeholder and accessory layers use, derived
/// from the customization configuration.
struct CharacterPalette {
    let fur: SKColor
    let furShade: SKColor
    let outline: SKColor
    let innerEar: SKColor
    let blush: SKColor
    let stripe: SKColor
    let eye: SKColor

    init(fur: SKColor, furShade: SKColor, outline: SKColor,
         innerEar: SKColor, blush: SKColor, stripe: SKColor, eye: SKColor) {
        self.fur = fur
        self.furShade = furShade
        self.outline = outline
        self.innerEar = innerEar
        self.blush = blush
        self.stripe = stripe
        self.eye = eye
    }

    init(config: CookieAppearanceConfig) {
        self.init(furColor: config.furColor)
    }

    init(furColor: FurColor) {
        self = furColor.palette
    }
}
