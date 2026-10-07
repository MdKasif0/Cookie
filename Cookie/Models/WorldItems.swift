import Foundation
import CoreGraphics

/// The toys Cookie can play with. Drawn as small vector items that sit
/// on the desktop next to her.
enum ToyKind: String, CaseIterable, Codable, Identifiable {
    case yarnBall
    case feather
    case toyMouse
    case fishToy
    case ball
    case box

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yarnBall: return "Yarn Ball"
        case .feather: return "Feather"
        case .toyMouse: return "Toy Mouse"
        case .fishToy: return "Fish Toy"
        case .ball: return "Ball"
        case .box: return "Cardboard Box"
        }
    }
}

/// The foods the user can offer Cookie from the menu bar.
enum FoodKind: String, CaseIterable, Codable, Identifiable {
    case fish
    case milk
    case chicken
    case cookie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fish: return "Fish"
        case .milk: return "Milk"
        case .chicken: return "Chicken"
        case .cookie: return "Cookie"
        }
    }

    var symbolName: String {
        switch self {
        case .fish: return "fish"
        case .milk: return "drop"
        case .chicken: return "drumstick"
        case .cookie: return "circle.hexagongrid"
        }
    }
}

/// Anything placed on Cookie's desktop for a while.
enum WorldItemKind: Equatable, Codable {
    case toy(ToyKind)
    case food(FoodKind)
    case box

    var isBox: Bool { self == .box }
}

/// A spawned world item: what it is and where its center sits on screen.
/// The presenter turns this into a small panel; the engine owns its
/// lifetime.
struct WorldItem: Equatable, Identifiable {
    let id: UUID
    let kind: WorldItemKind
    let x: CGFloat

    init(kind: WorldItemKind, x: CGFloat) {
        self.id = UUID()
        self.kind = kind
        self.x = x
    }
}
