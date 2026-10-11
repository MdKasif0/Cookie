import AppKit
import CoreGraphics
import os

/// Evaluates reachability, feasibility, safety limits, and anti-bounce routing
/// for Cookie's window-to-window and surface jumping maneuvers.
final class JumpPlanner {

    // MARK: - Tuned Physical Limits

    /// Maximum horizontal travel distance for a believable, grounded leap.
    var maxHorizontalDistance: CGFloat = 340.0

    /// Minimum horizontal distance before a jump is warranted (closer is a stroll).
    var minHorizontalDistance: CGFloat = 35.0

    /// Maximum vertical reach when jumping up to a higher surface.
    var maxVerticalUp: CGFloat = 175.0

    /// Maximum vertical drop when jumping down to a lower surface or desktop ground.
    var maxVerticalDown: CGFloat = 260.0

    /// Minimum landing width required so Cookie does not land off an edge.
    var minLandingWidth: CGFloat = 75.0

    /// Cookie's effective collision width.
    var cookieCollisionWidth: CGFloat = 60.0

    /// Cookie's effective collision height.
    var cookieCollisionHeight: CGFloat = 70.0

    /// Maximum consecutive jumps before Cookie takes a rest or strolls.
    var maxConsecutiveJumps: Int = 2

    /// Anti-ping-pong cooldown in seconds for recently visited windows.
    var windowVisitCooldown: TimeInterval = 45.0

    // MARK: - State Memory & Clocks

    private(set) var recentlyVisitedWindows: [CGWindowID: Date] = [:]
    private(set) var consecutiveJumpCount: Int = 0
    private(set) var lastJumpTime: Date = .distantPast

    /// Seam for deterministic testing.
    var now: () -> Date = { Date() }

    private let log = Logger(subsystem: "com.cookie.mac", category: "JumpPlanner")

    init() {}

    // MARK: - Surface Extraction

    /// Extracts valid jump target surfaces from candidate windows, desktop ground, and dock.
    func extractJumpSurfaces(
        from windows: [ObservableWindow],
        screenVisibleFrame: NSRect? = nil,
        dockSurface: NSRect? = nil
    ) -> [JumpTargetSurface] {
        var surfaces: [JumpTargetSurface] = []

        for win in windows where !win.isOccluded {
            let b = win.bounds
            let footOffset: CGFloat = 14.0
            let cornerInset: CGFloat = 25.0
            let availableWidth = max(0, b.width - (cornerInset * 2))

            // 1. Top Edge Landing Zone
            let topLandingPoint = CGPoint(x: b.midX, y: b.maxY + footOffset)
            surfaces.append(JumpTargetSurface(
                id: "win-\(win.id)-topLanding",
                windowId: win.id,
                ownerName: win.ownerName,
                surfaceKind: .windowTopEdge,
                bounds: b,
                landingPoint: topLandingPoint,
                landingWidth: availableWidth,
                footOffset: footOffset
            ))

            // 2. Top-Left Corner
            let tlPoint = CGPoint(x: b.minX + cornerInset, y: b.maxY + footOffset)
            surfaces.append(JumpTargetSurface(
                id: "win-\(win.id)-tlCorner",
                windowId: win.id,
                ownerName: win.ownerName,
                surfaceKind: .windowCorner,
                bounds: b,
                landingPoint: tlPoint,
                landingWidth: availableWidth,
                footOffset: footOffset
            ))

            // 3. Top-Right Corner
            let trPoint = CGPoint(x: b.maxX - cornerInset, y: b.maxY + footOffset)
            surfaces.append(JumpTargetSurface(
                id: "win-\(win.id)-trCorner",
                windowId: win.id,
                ownerName: win.ownerName,
                surfaceKind: .windowCorner,
                bounds: b,
                landingPoint: trPoint,
                landingWidth: availableWidth,
                footOffset: footOffset
            ))
        }

        // 4. Desktop Ground Surface
        if let vis = screenVisibleFrame {
            let groundY = vis.minY + 20
            surfaces.append(JumpTargetSurface(
                id: "desktop-ground",
                windowId: nil,
                ownerName: "Desktop",
                surfaceKind: .desktopGround,
                bounds: vis,
                landingPoint: CGPoint(x: vis.midX, y: groundY),
                landingWidth: vis.width,
                footOffset: 0
            ))
        }

        // 5. Dock-Adjacent Surface
        if let dock = dockSurface {
            surfaces.append(JumpTargetSurface(
                id: "dock-surface",
                windowId: nil,
                ownerName: "Dock",
                surfaceKind: .dockEdge,
                bounds: dock,
                landingPoint: CGPoint(x: dock.midX, y: dock.maxY + 10),
                landingWidth: dock.width,
                footOffset: 10
            ))
        }

        return surfaces
    }

    // MARK: - Feasibility Evaluation

    /// Evaluates candidate surfaces and produces the best safe jump proposal, if one exists.
    func evaluateBestJump(
        from startPoint: CGPoint,
        currentWindowId: CGWindowID?,
        surfaces: [JumpTargetSurface],
        style: JumpStyle = .gentle,
        force: Bool = false
    ) -> JumpProposal? {
        let proposals = evaluateAllJumps(
            from: startPoint,
            currentWindowId: currentWindowId,
            surfaces: surfaces,
            style: style,
            force: force
        )

        // Select the safest, most visually appealing proposal (prefer short, feasible window jumps)
        return proposals.filter(\.isSafe).min(by: { a, b in
            // Prioritize window surfaces over ground dismounts when both are reachable
            if a.targetSurface.surfaceKind.isWindowSurface != b.targetSurface.surfaceKind.isWindowSurface {
                return a.targetSurface.surfaceKind.isWindowSurface
            }
            return a.totalEuclideanDistance < b.totalEuclideanDistance
        })
    }

    /// Evaluates all candidate surfaces and returns proposals with safety status and diagnostics.
    func evaluateAllJumps(
        from startPoint: CGPoint,
        currentWindowId: CGWindowID?,
        surfaces: [JumpTargetSurface],
        style: JumpStyle = .gentle,
        force: Bool = false
    ) -> [JumpProposal] {
        pruneStaleCooldowns()

        var results: [JumpProposal] = []

        for surface in surfaces {
            // 1. Exclude surfaces belonging to the window Cookie is currently on
            if let curId = currentWindowId, let targetId = surface.windowId, curId == targetId {
                continue
            }

            // 2. Adjust landing target within safe edge corridor
            var landingPt = surface.landingPoint
            if surface.surfaceKind == .windowTopEdge && surface.bounds.width > 0 {
                let inset: CGFloat = 25.0
                let minX = surface.bounds.minX + inset
                let maxX = surface.bounds.maxX - inset
                if minX <= maxX {
                    landingPt.x = max(minX, min(maxX, surface.landingPoint.x))
                }
            } else if surface.surfaceKind == .desktopGround {
                landingPt = CGPoint(x: startPoint.x, y: surface.landingPoint.y)
            }

            let dx = landingPt.x - startPoint.x
            let dy = landingPt.y - startPoint.y
            let horizDist = abs(dx)
            let vertDiff = dy
            let totalDist = hypot(dx, dy)

            // Rejection checks
            var rejectionReason: String?

            if surface.landingWidth < minLandingWidth {
                rejectionReason = "Landing surface too narrow (\(Int(surface.landingWidth)) < \(Int(minLandingWidth)))"
            } else if horizDist > maxHorizontalDistance {
                rejectionReason = "Horizontal distance exceeds reach (\(Int(horizDist)) > \(Int(maxHorizontalDistance)))"
            } else if horizDist < minHorizontalDistance && abs(dy) < 25 {
                rejectionReason = "Distance too short for a jump — prefer walking"
            } else if vertDiff > 0 && vertDiff > maxVerticalUp {
                rejectionReason = "Upward vertical leap too high (\(Int(vertDiff)) > \(Int(maxVerticalUp)))"
            } else if vertDiff < 0 && abs(vertDiff) > maxVerticalDown {
                rejectionReason = "Downward drop exceeds safe limit (\(Int(abs(vertDiff))) > \(Int(maxVerticalDown)))"
            } else if !force, let targetWinId = surface.windowId, isWindowOnCooldown(targetWinId) {
                rejectionReason = "Target window recently visited (anti-bounce cooldown active)"
            } else if !force && consecutiveJumpCount >= maxConsecutiveJumps {
                rejectionReason = "Consecutive jump limit reached (\(consecutiveJumpCount)/\(maxConsecutiveJumps))"
            }

            // Trajectory duration & apex calculations
            let duration: TimeInterval
            let apexHeight: CGFloat

            switch style {
            case .gentle:
                duration = max(0.65, min(0.92, 0.45 + Double(totalDist) * 0.0014))
                apexHeight = max(28, min(65, 28 + totalDist * 0.11))
            case .playful:
                duration = max(0.60, min(0.85, 0.40 + Double(totalDist) * 0.0012))
                apexHeight = max(45, min(95, 45 + totalDist * 0.17))
            }

            let proposal = JumpProposal(
                startPoint: startPoint,
                targetSurface: JumpTargetSurface(
                    id: surface.id,
                    windowId: surface.windowId,
                    ownerName: surface.ownerName,
                    surfaceKind: surface.surfaceKind,
                    bounds: surface.bounds,
                    landingPoint: landingPt,
                    landingWidth: surface.landingWidth,
                    footOffset: surface.footOffset,
                    isTraversable: surface.isTraversable
                ),
                horizontalDistance: horizDist,
                verticalDifference: vertDiff,
                jumpDuration: duration,
                apexHeight: apexHeight,
                style: style,
                isSafe: (rejectionReason == nil),
                rejectionReason: rejectionReason
            )

            results.append(proposal)
        }

        return results
    }

    // MARK: - Jump History & Memory

    /// Records successful landing on a target surface.
    func recordJumpCompleted(to windowId: CGWindowID?) {
        let date = now()
        consecutiveJumpCount += 1
        lastJumpTime = date
        if let wid = windowId {
            recentlyVisitedWindows[wid] = date
            log.info("Recorded jump onto window #\(wid, privacy: .public). Consecutive count: \(self.consecutiveJumpCount)")
        }
    }

    /// Resets consecutive jump count when Cookie rests, strolls, or is petted.
    func resetConsecutiveJumps() {
        consecutiveJumpCount = 0
    }

    /// Checks if a window is currently in anti-bounce cooldown.
    func isWindowOnCooldown(_ windowId: CGWindowID) -> Bool {
        guard let visitedAt = recentlyVisitedWindows[windowId] else { return false }
        return now().timeIntervalSince(visitedAt) < windowVisitCooldown
    }

    /// Clears expired window cooldown entries.
    private func pruneStaleCooldowns() {
        let date = now()
        recentlyVisitedWindows = recentlyVisitedWindows.filter { _, visitedAt in
            date.timeIntervalSince(visitedAt) < windowVisitCooldown
        }
    }

    /// Clears all jump history (e.g. on settings reset or engine restart).
    func clearHistory() {
        recentlyVisitedWindows.removeAll()
        consecutiveJumpCount = 0
        lastJumpTime = .distantPast
    }
}
