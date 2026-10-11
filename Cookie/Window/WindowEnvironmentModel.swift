import AppKit
import CoreGraphics

/// Observable representation of an external application window on the macOS desktop.
struct ObservableWindow: Identifiable, Equatable {
    /// System window identifier from Quartz Window Services.
    let id: CGWindowID
    /// Name of the owning application process (e.g. "Safari", "Xcode", "Finder").
    let ownerName: String
    /// Owning process identifier.
    let ownerPID: pid_t
    /// Window layer (0 represents standard application windows).
    let layer: Int
    /// Window bounding frame in AppKit global screen coordinates.
    let bounds: NSRect
    /// Approximate occlusion flag determined from window stacking order.
    var isOccluded: Bool
    /// Timestamp when this window's geometry was last observed.
    var lastObserved: Date

    init(
        id: CGWindowID,
        ownerName: String,
        ownerPID: pid_t,
        layer: Int,
        bounds: NSRect,
        isOccluded: Bool = false,
        lastObserved: Date = Date()
    ) {
        self.id = id
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.isOccluded = isOccluded
        self.lastObserved = lastObserved
    }

    /// Top horizontal edge segment suitable for walking.
    var topEdgeY: CGFloat {
        bounds.maxY
    }

    /// Left vertical edge X coordinate.
    var leftEdgeX: CGFloat {
        bounds.minX
    }

    /// Right vertical edge X coordinate.
    var rightEdgeX: CGFloat {
        bounds.maxX
    }
}

/// Type of navigable edge on a window.
enum WindowEdgeType: String, Codable, CaseIterable, Equatable {
    case topHorizontal
    case leftVertical
    case rightVertical
    case bottomHorizontal

    var isHorizontal: Bool {
        self == .topHorizontal || self == .bottomHorizontal
    }

    var isVertical: Bool {
        self == .leftVertical || self == .rightVertical
    }
}

/// Navigable edge corridor along which Cookie can walk or climb.
struct WindowEdgePath: Identifiable, Equatable {
    let id: String
    let windowId: CGWindowID
    let ownerName: String
    let edgeType: WindowEdgeType
    let startPoint: CGPoint
    let endPoint: CGPoint
    let windowBounds: NSRect
    let footOffset: CGFloat
    let isTraversable: Bool

    init(
        id: String,
        windowId: CGWindowID,
        ownerName: String,
        edgeType: WindowEdgeType,
        startPoint: CGPoint,
        endPoint: CGPoint,
        windowBounds: NSRect,
        footOffset: CGFloat = 16.0,
        isTraversable: Bool = true
    ) {
        self.id = id
        self.windowId = windowId
        self.ownerName = ownerName
        self.edgeType = edgeType
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.windowBounds = windowBounds
        self.footOffset = footOffset
        self.isTraversable = isTraversable
    }

    /// Length of this edge path in points.
    var length: CGFloat {
        hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
    }

    /// Evaluates a point along this path at parametric progress t in [0, 1].
    func pointAt(progress: CGFloat) -> CGPoint {
        let t = max(0, min(1, progress))
        let x = startPoint.x + (endPoint.x - startPoint.x) * t
        let y = startPoint.y + (endPoint.y - startPoint.y) * t
        return CGPoint(x: x, y: y)
    }

    /// Finds the closest point and progress along this edge path to an arbitrary screen point.
    func closestPoint(to queryPoint: CGPoint) -> (point: CGPoint, progress: CGFloat) {
        let len = length
        guard len > 0.001 else { return (startPoint, 0) }

        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let u = ((queryPoint.x - startPoint.x) * dx + (queryPoint.y - startPoint.y) * dy) / (len * len)
        let t = max(0, min(1, u))
        return (pointAt(progress: t), t)
    }
}

/// Node in Cookie's lightweight navigation graph.
struct WindowNavNode: Identifiable, Equatable {
    let id: String
    let point: CGPoint
    let windowId: CGWindowID?
    let isCorner: Bool
    let cornerEdgeTypes: [WindowEdgeType]

    init(
        id: String,
        point: CGPoint,
        windowId: CGWindowID? = nil,
        isCorner: Bool = false,
        cornerEdgeTypes: [WindowEdgeType] = []
    ) {
        self.id = id
        self.point = point
        self.windowId = windowId
        self.isCorner = isCorner
        self.cornerEdgeTypes = cornerEdgeTypes
    }
}

/// Directed edge in Cookie's lightweight navigation graph.
struct WindowNavEdge: Identifiable, Equatable {
    let id: String
    let fromNodeId: String
    let toNodeId: String
    let edgeType: WindowEdgeType
    let path: WindowEdgePath
    let isJump: Bool

    init(
        id: String,
        fromNodeId: String,
        toNodeId: String,
        edgeType: WindowEdgeType,
        path: WindowEdgePath,
        isJump: Bool = false
    ) {
        self.id = id
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.edgeType = edgeType
        self.path = path
        self.isJump = isJump
    }
}

/// Lightweight navigation graph representing accessible window perimeters and desktop transitions.
struct WindowNavGraph: Equatable {
    var nodes: [String: WindowNavNode] = [:]
    var edges: [WindowNavEdge] = []

    mutating func addNode(_ node: WindowNavNode) {
        nodes[node.id] = node
    }

    mutating func addEdge(_ edge: WindowNavEdge) {
        edges.append(edge)
    }

    func node(for id: String) -> WindowNavNode? {
        nodes[id]
    }

    func outgoingEdges(from nodeId: String) -> [WindowNavEdge] {
        edges.filter { $0.fromNodeId == nodeId }
    }
}

/// State machine tracking Cookie's active window exploration and jumping phases.
enum WindowExplorationPhase: String, Equatable {
    /// Not exploring any window.
    case idle
    /// Anticipation pause: observing the target window edge curiously before approaching.
    case anticipating
    /// Walking toward the selected access point on the window.
    case approaching
    /// Walking along the top horizontal edge.
    case walkingTopEdge
    /// Transitioning around a corner with orientation adjustment.
    case cornerTransition
    /// Simulated climb along a vertical edge (when enabled).
    case climbingVerticalEdge
    /// Brief observation pause on the edge or corner.
    case pausing
    /// Preparing to launch a jump: crouch anticipation, orientation alignment, target re-verification.
    case preparingJump
    /// Airborne along a parabolic jump trajectory.
    case jumping
    /// Touchdown landing absorption and surface stabilization.
    case landing
    /// Concluding exploration and safely returning to desktop ground.
    case departing
}

/// User preference for how frequently Cookie autonomously explores window edges.
enum WindowExplorationFrequency: String, CaseIterable, Identifiable, Codable {
    case rare
    case occasional
    case frequent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rare: return "Rare"
        case .occasional: return "Occasional"
        case .frequent: return "Frequent"
        }
    }

    /// Minimum cooldown in seconds between window visits.
    var cooldownRange: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 180...300
        case .occasional: return 90...180
        case .frequent: return 45...90
        }
    }

    /// Maximum duration in seconds for each window exploration session.
    var explorationDurationRange: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 8...14
        case .occasional: return 10...18
        case .frequent: return 14...24
        }
    }

    /// Probability factor for autonomous curiosity toward nearby windows.
    var triggerProbability: Double {
        switch self {
        case .rare: return 0.015
        case .occasional: return 0.035
        case .frequent: return 0.075
        }
    }
}
