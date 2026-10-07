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

    var emoji: String {
        switch self {
        case .yarnBall: return "🧶"
        case .feather: return "🪶"
        case .toyMouse: return "🐭"
        case .fishToy: return "🐟"
        case .ball: return "🎾"
        case .box: return "📦"
        }
    }

    var isBox: Bool { self == .box }
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

    var emoji: String {
        switch self {
        case .fish: return "🐟"
        case .milk: return "🥛"
        case .chicken: return "🍗"
        case .cookie: return "🍪"
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

    var isLiquid: Bool { self == .milk }
}

/// Anything placed on Cookie's desktop for a while.
enum WorldItemKind: Equatable, Codable {
    case toy(ToyKind)
    case food(FoodKind)
    case box

    var isBox: Bool {
        switch self {
        case .box: return true
        case .toy(let kind): return kind == .box
        default: return false
        }
    }

    var isFood: Bool {
        if case .food = self { return true }
        return false
    }

    var isToy: Bool {
        if case .toy = self { return true }
        if case .box = self { return true }
        return false
    }

    var toyKind: ToyKind? {
        switch self {
        case .toy(let toy): return toy
        case .box: return .box
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .toy(let toy): return toy.displayName
        case .food(let food): return food.displayName
        case .box: return "Cardboard Box"
        }
    }

    var emoji: String {
        switch self {
        case .toy(let toy): return toy.emoji
        case .food(let food): return food.emoji
        case .box: return "📦"
        }
    }
}

/// A spawned world item: what it is and where its center sits on screen.
/// The presenter turns this into a small panel; the engine owns its
/// lifetime.
struct WorldItem: Equatable, Identifiable {
    let id: UUID
    let kind: WorldItemKind
    var x: CGFloat
    var isConsumed: Bool = false
    var isInteracting: Bool = false

    init(id: UUID = UUID(), kind: WorldItemKind, x: CGFloat, isConsumed: Bool = false, isInteracting: Bool = false) {
        self.id = id
        self.kind = kind
        self.x = x
        self.isConsumed = isConsumed
        self.isInteracting = isInteracting
    }
}
