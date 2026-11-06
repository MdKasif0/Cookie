import Foundation
import CoreGraphics

/// The comfortable spots Cookie can be given: places she returns to on her own.
enum CozyKind: String, CaseIterable, Codable, Identifiable {
    case bed
    case sunbeam
    case scratchingPost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bed: return "Cat Bed"
        case .sunbeam: return "Sunbeam Spot"
        case .scratchingPost: return "Scratching Post"
        }
    }

    /// File name of the art under Sprites/Cookie/Items.
    var assetName: String { "cozy-\(rawValue)" }
    var iconName: String { "item-\(assetName)" }

    /// Side of the square panel that shows it, in points at Cookie's default size.
    var panelSide: CGFloat {
        switch self {
        case .bed: return 130
        case .sunbeam: return 170
        case .scratchingPost: return 120
        }
    }

    /// How close she stands to it before settling in.
    var arrivalDistance: CGFloat { 14 }
}

/// A placed cozy item. Position is a fraction of the main screen's width, so it
/// survives resolution changes and display swaps.
struct CozyPlacement: Codable, Equatable, Identifiable {
    var kind: CozyKind
    var position: Double

    var id: String { kind.rawValue }

    init(kind: CozyKind, position: Double) {
        self.kind = kind
        self.position = min(max(position, 0.04), 0.96)
    }
}
