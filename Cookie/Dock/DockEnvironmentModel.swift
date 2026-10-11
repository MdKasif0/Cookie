import Foundation
import CoreGraphics
import AppKit

/// Physical orientation of the macOS Dock relative to the display.
public enum DockOrientation: String, Codable, CaseIterable, Equatable {
    case bottom
    case left
    case right
    case unknown

    public var displayName: String {
        switch self {
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .unknown: return "Unknown"
        }
    }

    /// Whether this orientation is aligned along the horizontal screen axis.
    public var isHorizontal: Bool {
        self == .bottom
    }

    /// Whether this orientation is aligned along the vertical screen axis.
    public var isVertical: Bool {
        self == .left || self == .right
    }
}

/// Visibility status of the macOS Dock.
public enum DockVisibilityState: String, Codable, Equatable {
    case visible
    case autohidden
}

/// User preference for how frequently Cookie autonomously visits and explores the Dock.
public enum DockExplorationFrequency: String, CaseIterable, Identifiable, Codable {
    case rare
    case occasional
    case frequent

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rare: return "Rare"
        case .occasional: return "Occasional"
        case .frequent: return "Frequent"
        }
    }

    /// Minimum cooldown in seconds between autonomous visits to the Dock.
    public var cooldownRange: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 180...300
        case .occasional: return 90...180
        case .frequent: return 45...90
        }
    }

    /// Exploration duration in seconds for each visit.
    public var explorationDurationRange: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 6...10
        case .occasional: return 8...14
        case .frequent: return 10...18
        }
    }

    /// Probability factor for triggering autonomous curiosity toward the Dock.
    public var triggerProbability: Double {
        switch self {
        case .rare: return 0.015
        case .occasional: return 0.035
        case .frequent: return 0.070
        }
    }
}

/// State machine tracking Cookie's active Dock exploration phases.
public enum DockSessionPhase: String, Equatable {
    /// Not currently interacting with the Dock.
    case idle
    /// Cookie notices the Dock or cursor near it; brief anticipation pause with head glance.
    case anticipating
    /// Walking smoothly toward a reachable target on the Dock-adjacent edge.
    case approaching
    /// Pausing near a specific application icon region, observing curiously.
    case inspectingIcon
    /// Walking gently along the safe edge parallel to the Dock.
    case pacingEdge
    /// Concluding exploration and heading back toward the central workspace.
    case departing
}

/// Inspection target representing an application icon region or item along the Dock.
public struct DockInspectionTarget: Equatable {
    /// Global screen coordinate where the icon region is centered.
    public let screenPoint: CGPoint
    /// Human-readable label (e.g. application name).
    public let label: String
    /// Optional bundle identifier of a running application.
    public let bundleIdentifier: String?

    public init(screenPoint: CGPoint, label: String, bundleIdentifier: String? = nil) {
        self.screenPoint = screenPoint
        self.label = label
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Comprehensive, reusable representation of the desktop environment and safe reachability areas.
public struct DesktopEnvironment: Equatable {
    /// Full frame of the screen containing the Dock (or active display).
    public let screenFrame: NSRect
    /// Usable visible frame excluding the Dock and Menu Bar.
    public let visibleFrame: NSRect
    /// Estimated or observed bounding rectangle of the Dock in screen coordinates.
    public let dockFrame: NSRect
    /// Orientation of the Dock (bottom, left, right, or unknown).
    public let dockOrientation: DockOrientation
    /// Whether the Dock is currently visible or autohidden.
    public let dockVisibility: DockVisibilityState
    /// Safe adjacent walking boundary along which Cookie may safely navigate without clipping or obstruction.
    public let safeWalkingSurface: NSRect
    /// Thickness (height or width) of the Dock in points.
    public let dockThickness: CGFloat

    public init(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        dockFrame: NSRect,
        dockOrientation: DockOrientation,
        dockVisibility: DockVisibilityState,
        safeWalkingSurface: NSRect,
        dockThickness: CGFloat
    ) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        self.dockFrame = dockFrame
        self.dockOrientation = dockOrientation
        self.dockVisibility = dockVisibility
        self.safeWalkingSurface = safeWalkingSurface
        self.dockThickness = dockThickness
    }

    /// Empty fallback environment used when no screens are connected.
    public static var fallback: DesktopEnvironment {
        let defaultRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleRect = NSRect(x: 0, y: 70, width: 1440, height: 805)
        let dockRect = NSRect(x: 0, y: 0, width: 1440, height: 70)
        let surface = NSRect(x: 80, y: 78, width: 1280, height: 40)
        return DesktopEnvironment(
            screenFrame: defaultRect,
            visibleFrame: visibleRect,
            dockFrame: dockRect,
            dockOrientation: .bottom,
            dockVisibility: .visible,
            safeWalkingSurface: surface,
            dockThickness: 70
        )
    }

    /// Checks if a global screen point is within proximity of the Dock.
    public func isPointNearDock(_ point: CGPoint, threshold: CGFloat = 80) -> Bool {
        switch dockOrientation {
        case .bottom:
            return point.y <= visibleFrame.minY + threshold &&
                   point.x >= screenFrame.minX - threshold &&
                   point.x <= screenFrame.maxX + threshold
        case .left:
            return point.x <= visibleFrame.minX + threshold &&
                   point.y >= screenFrame.minY - threshold &&
                   point.y <= screenFrame.maxY + threshold
        case .right:
            return point.x >= visibleFrame.maxX - threshold &&
                   point.y >= screenFrame.minY - threshold &&
                   point.y <= screenFrame.maxY + threshold
        case .unknown:
            return false
        }
    }

    /// Clamps a proposed target coordinate strictly within the safe walking surface.
    public func clampToSafeWalkingSurface(_ point: CGPoint, characterSize: CGSize) -> CGPoint {
        let halfWidth = characterSize.width / 2
        let halfHeight = characterSize.height / 2

        let clampedX = min(max(point.x, safeWalkingSurface.minX + halfWidth), safeWalkingSurface.maxX - halfWidth)
        let clampedY = min(max(point.y, safeWalkingSurface.minY + halfHeight), safeWalkingSurface.maxY - halfHeight)

        return CGPoint(x: clampedX, y: clampedY)
    }
}
