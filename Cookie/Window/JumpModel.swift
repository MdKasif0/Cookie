import AppKit
import CoreGraphics

/// Visual and motion style for a window jump.
enum JumpStyle: String, CaseIterable, Identifiable, Codable {
    case gentle
    case playful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle: return "Gentle"
        case .playful: return "Playful"
        }
    }
}

/// User preference governing how frequently Cookie considers window-to-window jumps.
enum JumpFrequency: String, CaseIterable, Identifiable, Codable {
    case rare
    case balanced
    case playful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rare: return "Rare"
        case .balanced: return "Balanced"
        case .playful: return "Playful"
        }
    }

    /// Cooldown in seconds before another jump is considered.
    var cooldownRange: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 120...240
        case .balanced: return 60...120
        case .playful: return 30...60
        }
    }

    /// Autonomous roll probability when reaching an edge corner or transition point.
    var triggerProbability: Double {
        switch self {
        case .rare: return 0.20
        case .balanced: return 0.45
        case .playful: return 0.70
        }
    }
}

/// Type of surface Cookie can jump onto.
enum JumpSurfaceKind: String, Codable, Equatable {
    case windowTopEdge
    case windowCorner
    case desktopGround
    case dockEdge

    var isWindowSurface: Bool {
        self == .windowTopEdge || self == .windowCorner
    }
}

/// Observable target surface representation for jump planning.
struct JumpTargetSurface: Identifiable, Equatable {
    let id: String
    let windowId: CGWindowID?
    let ownerName: String
    let surfaceKind: JumpSurfaceKind
    let bounds: NSRect
    let landingPoint: CGPoint
    let landingWidth: CGFloat
    let footOffset: CGFloat
    let isTraversable: Bool

    init(
        id: String,
        windowId: CGWindowID? = nil,
        ownerName: String = "",
        surfaceKind: JumpSurfaceKind,
        bounds: NSRect,
        landingPoint: CGPoint,
        landingWidth: CGFloat,
        footOffset: CGFloat = 14.0,
        isTraversable: Bool = true
    ) {
        self.id = id
        self.windowId = windowId
        self.ownerName = ownerName
        self.surfaceKind = surfaceKind
        self.bounds = bounds
        self.landingPoint = landingPoint
        self.landingWidth = landingWidth
        self.footOffset = footOffset
        self.isTraversable = isTraversable
    }
}

/// Result of evaluating a potential jump between two surfaces.
struct JumpProposal: Equatable {
    let startPoint: CGPoint
    let targetSurface: JumpTargetSurface
    let horizontalDistance: CGFloat
    let verticalDifference: CGFloat
    let jumpDuration: TimeInterval
    let apexHeight: CGFloat
    let style: JumpStyle
    let isSafe: Bool
    let rejectionReason: String?

    var totalEuclideanDistance: CGFloat {
        hypot(horizontalDistance, verticalDifference)
    }
}

/// Reusable time-based parabolic jump trajectory model.
struct JumpTrajectory: Equatable {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let duration: TimeInterval
    let apexHeight: CGFloat
    let style: JumpStyle

    init(
        startPoint: CGPoint,
        endPoint: CGPoint,
        duration: TimeInterval,
        apexHeight: CGFloat,
        style: JumpStyle = .gentle
    ) {
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.duration = max(0.2, duration)
        self.apexHeight = max(10, apexHeight)
        self.style = style
    }

    /// Evaluates 2D position along the trajectory at normalized progress in [0.0, 1.0].
    func point(at progress: CGFloat) -> CGPoint {
        let p = max(0.0, min(1.0, progress))
        // Monotonic horizontal displacement
        let x = startPoint.x + p * (endPoint.x - startPoint.x)
        // Linear vertical interpolation + parabolic height hump
        let linearY = startPoint.y + p * (endPoint.y - startPoint.y)
        let parabolicHump = 4.0 * apexHeight * p * (1.0 - p)
        let y = linearY + parabolicHump
        return CGPoint(x: x, y: y)
    }

    /// Evaluates instantaneous 2D velocity in points per second at progress p in [0.0, 1.0].
    func velocity(at progress: CGFloat) -> CGVector {
        let p = max(0.0, min(1.0, progress))
        let T = CGFloat(duration)
        guard T > 0.001 else { return .zero }

        let vx = (endPoint.x - startPoint.x) / T
        let linearVy = (endPoint.y - startPoint.y) / T
        let parabolicVy = (4.0 * apexHeight * (1.0 - 2.0 * p)) / T
        return CGVector(dx: vx, dy: linearVy + parabolicVy)
    }

    /// Dynamic shadow scale factor based on flight altitude [0.75 ... 1.0].
    func shadowScale(at progress: CGFloat) -> CGFloat {
        let p = max(0.0, min(1.0, progress))
        let hump = 4.0 * p * (1.0 - p)
        return 1.0 - 0.25 * hump
    }

    /// Dynamic shadow opacity based on flight altitude [0.055 ... 0.09].
    func shadowAlpha(at progress: CGFloat) -> CGFloat {
        let p = max(0.0, min(1.0, progress))
        let hump = 4.0 * p * (1.0 - p)
        return 0.09 * (1.0 - 0.35 * hump)
    }
}
