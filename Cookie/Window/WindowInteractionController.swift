import AppKit
import Combine
import os

/// Dedicated controller governing Cookie's window edge exploration, approach,
/// top-edge traversal, corner transitions, simulated vertical climbing,
/// intelligent window-to-window jumping, and safe departure.
@MainActor
final class WindowInteractionController: ObservableObject {
    // MARK: - Published Properties

    /// Current phase in the window exploration state machine.
    @Published private(set) var currentPhase: WindowExplorationPhase = .idle

    /// Target destination in AppKit global screen coordinates.
    @Published private(set) var destinationPoint: CGPoint?

    /// Active window currently being explored.
    @Published private(set) var activeWindow: ObservableWindow?

    /// Active edge path currently being traversed.
    @Published private(set) var activeEdgePath: WindowEdgePath?

    /// Parametric progress along the active edge path [0.0 ... 1.0].
    @Published private(set) var edgeProgress: CGFloat = 0.0

    /// Direction of traversal along active edge (1 = start-to-end, -1 = end-to-start).
    @Published private(set) var traversalDirection: CGFloat = 1.0

    /// Anatomically plausible look angle in radians toward window edge or corner.
    @Published private(set) var windowLookAngle: CGFloat?

    /// Playful one-shot reaction produced during window play (e.g. curious glance, proud pose).
    @Published private(set) var playfulReaction: CookieReaction?

    /// Active jump trajectory when Cookie is airborne.
    @Published private(set) var activeJumpTrajectory: JumpTrajectory?

    /// Progress along active jump trajectory in [0.0 ... 1.0].
    @Published private(set) var jumpProgress: CGFloat = 0.0

    /// Subtle shadow scale factor during flight [0.75 ... 1.0].
    @Published private(set) var jumpShadowScale: CGFloat = 1.0

    /// Subtle shadow opacity factor during flight [0.055 ... 0.09].
    @Published private(set) var jumpShadowAlpha: CGFloat = 0.09

    /// Whether Cookie is currently engaged in any window exploration activity.
    var isExploringWindow: Bool {
        currentPhase != .idle
    }

    /// Whether Cookie is currently airborne during a jump.
    var isJumping: Bool {
        currentPhase == .jumping
    }

    // MARK: - Dependencies & Seams

    let provider: WindowEnvironmentProvider
    let jumpPlanner: JumpPlanner

    var now: () -> Date = { Date() } {
        didSet {
            provider.now = now
            jumpPlanner.now = now
        }
    }

    private let log = Logger(subsystem: "com.cookie.mac", category: "WindowInteraction")

    // MARK: - Internal Timers & Memory

    private(set) var cooldownUntil: Date = .distantPast
    private var phaseElapsed: TimeInterval = 0
    private var phaseDuration: TimeInterval = 0
    private var sessionElapsed: TimeInterval = 0
    private var sessionMaxDuration: TimeInterval = 14
    private var lastReconcileTime = Date.distantPast
    private(set) var pendingJumpProposal: JumpProposal?

    // MARK: - Initialization

    init(
        provider: WindowEnvironmentProvider? = nil,
        jumpPlanner: JumpPlanner? = nil
    ) {
        let prov = provider ?? WindowEnvironmentProvider()
        self.provider = prov
        let planner = jumpPlanner ?? JumpPlanner()
        self.jumpPlanner = planner
        planner.now = now
    }

    // MARK: - Lifecycle & Interruption

    /// Immediately cancels any active window exploration session (e.g. user dragged Cookie or triggered an emote).
    func cancelExploration() {
        if currentPhase != .idle {
            log.info("Window exploration cancelled")
        }
        currentPhase = .idle
        destinationPoint = nil
        activeWindow = nil
        activeEdgePath = nil
        windowLookAngle = nil
        playfulReaction = nil
        activeJumpTrajectory = nil
        pendingJumpProposal = nil
        jumpProgress = 0.0
        jumpShadowScale = 1.0
        jumpShadowAlpha = 0.09
        phaseElapsed = 0
        edgeProgress = 0
    }

    /// Sets the cooldown timer based on user frequency preference.
    func applyCooldown(for frequency: WindowExplorationFrequency) {
        let range = frequency.cooldownRange
        let interval = Double.random(in: range)
        cooldownUntil = now().addingTimeInterval(interval)
    }

    // MARK: - Exploration Triggering

    /// Evaluates whether Cookie should autonomously begin exploring a nearby window.
    func shouldTriggerAutonomousExploration(
        cookiePosition: NSPoint,
        frequency: WindowExplorationFrequency,
        settingsEnabled: Bool,
        isInterrupted: Bool
    ) -> Bool {
        guard settingsEnabled, !isInterrupted, currentPhase == .idle else { return false }
        let date = now()
        guard date >= cooldownUntil else { return false }

        // Frequency-tuned probability check
        let roll = Double.random(in: 0...1)
        guard roll < frequency.triggerProbability else {
            cooldownUntil = date.addingTimeInterval(Double.random(in: 15...30))
            return false
        }

        // Must have at least one reachable candidate window nearby
        provider.refreshWindows()
        return provider.findClosestCandidate(to: cookiePosition, maxDistance: 650) != nil
    }

    /// Begins a structured window exploration session targeting the nearest candidate window.
    func startExploration(
        fromPosition cookiePosition: NSPoint,
        frequency: WindowExplorationFrequency,
        targetWindow: ObservableWindow? = nil
    ) {
        provider.refreshWindows(force: true)

        let candidate = targetWindow ?? provider.findClosestCandidate(to: cookiePosition, maxDistance: 650)
        guard let win = candidate else {
            log.debug("No suitable window found within exploration reach")
            return
        }

        guard let topPath = provider.navigablePaths.first(where: { $0.windowId == win.id && $0.edgeType == .topHorizontal }) else {
            log.debug("No traversable top edge path found for window \(win.ownerName, privacy: .public)")
            return
        }

        self.activeWindow = win
        self.activeEdgePath = topPath

        let durationRange = frequency.explorationDurationRange
        sessionMaxDuration = Double.random(in: durationRange)
        sessionElapsed = 0

        // Determine access point on top edge: choose whichever corner is closer to Cookie
        let distToStart = hypot(topPath.startPoint.x - cookiePosition.x, topPath.startPoint.y - cookiePosition.y)
        let distToEnd = hypot(topPath.endPoint.x - cookiePosition.x, topPath.endPoint.y - cookiePosition.y)

        if distToStart <= distToEnd {
            destinationPoint = topPath.startPoint
            edgeProgress = 0.0
            traversalDirection = 1.0 // Walk left to right
        } else {
            destinationPoint = topPath.endPoint
            edgeProgress = 1.0
            traversalDirection = -1.0 // Walk right to left
        }

        // Begin with anticipation pause looking up at the window edge
        currentPhase = .anticipating
        phaseElapsed = 0
        phaseDuration = Double.random(in: 0.35...0.65)
        playfulReaction = .shy
        updateLookAngle(from: cookiePosition, toward: destinationPoint ?? topPath.startPoint)

        applyCooldown(for: frequency)
        log.info("Started window edge exploration on \(win.ownerName, privacy: .public) (#\(win.id, privacy: .public))")
    }

    // MARK: - Jumping Preparation & Launch

    /// Prepares and executes a calculated jump trajectory to a target surface.
    func startJump(proposal: JumpProposal) {
        guard proposal.isSafe else {
            log.notice("Cannot start jump: \(proposal.rejectionReason ?? "unsafe", privacy: .public)")
            return
        }

        self.pendingJumpProposal = proposal
        let trajectory = JumpTrajectory(
            startPoint: proposal.startPoint,
            endPoint: proposal.targetSurface.landingPoint,
            duration: proposal.jumpDuration,
            apexHeight: proposal.apexHeight,
            style: proposal.style
        )
        self.activeJumpTrajectory = trajectory
        self.destinationPoint = proposal.targetSurface.landingPoint
        self.jumpProgress = 0.0

        currentPhase = .preparingJump
        phaseElapsed = 0
        phaseDuration = Double.random(in: 0.40...0.65)
        playfulReaction = .curious
        updateLookAngle(from: proposal.startPoint, toward: proposal.targetSurface.landingPoint)
        log.info("Preparing jump to \(proposal.targetSurface.ownerName, privacy: .public) [style: \(proposal.style.rawValue, privacy: .public), dist: \(Int(proposal.totalEuclideanDistance), privacy: .public)pt]")
    }

    // MARK: - Frame Update

    /// Primary tick cycle called each frame by the behavior engine.
    func tick(
        dt: TimeInterval,
        cookiePosition: NSPoint,
        characterSize: CGSize,
        frequency: WindowExplorationFrequency,
        verticalClimbingEnabled: Bool,
        jumpingEnabled: Bool = true,
        jumpFrequency: JumpFrequency = .balanced,
        jumpStyle: JumpStyle = .gentle
    ) {
        guard currentPhase != .idle, dt > 0 else { return }

        phaseElapsed += dt
        sessionElapsed += dt

        // 1. Periodic window position reconciliation (~2 Hz) unless airborne
        let date = now()
        if currentPhase != .jumping && date.timeIntervalSince(lastReconcileTime) >= 0.5 {
            lastReconcileTime = date
            reconcileActiveWindow()
        }

        // 2. Session timeout safety: never get stuck on an edge indefinitely (do not interrupt mid-jump)
        if currentPhase != .jumping && currentPhase != .preparingJump && sessionElapsed >= sessionMaxDuration {
            concludeExploration(from: cookiePosition)
            return
        }

        switch currentPhase {
        case .idle:
            break

        case .anticipating:
            if let dest = destinationPoint {
                updateLookAngle(from: cookiePosition, toward: dest)
            }
            if phaseElapsed >= phaseDuration {
                currentPhase = .approaching
                phaseElapsed = 0
                phaseDuration = 7.0 // Generous arrival timeout
            }

        case .approaching:
            guard let dest = destinationPoint else {
                concludeExploration(from: cookiePosition)
                return
            }
            updateLookAngle(from: cookiePosition, toward: dest)

            // Arrival check: reached edge access point within threshold
            let dist = hypot(dest.x - cookiePosition.x, dest.y - cookiePosition.y)
            if dist <= 14 || phaseElapsed >= phaseDuration {
                // Arrived atop the window! Begin walking along the top edge
                currentPhase = .walkingTopEdge
                phaseElapsed = 0
                phaseDuration = Double.random(in: 4.5...7.5)
                windowLookAngle = nil
                playfulReaction = .happy
            }

        case .walkingTopEdge:
            guard let path = activeEdgePath else {
                concludeExploration(from: cookiePosition)
                return
            }

            // Advance parametric progress along edge: walking speed ~115 pt/s
            let speed: CGFloat = 115.0
            let pathLen = max(10, path.length)
            let deltaProgress = (speed / pathLen) * CGFloat(dt) * traversalDirection
            edgeProgress += deltaProgress

            // Calculate destination point along top edge
            let clampedProgress = max(0, min(1, edgeProgress))
            destinationPoint = path.pointAt(progress: clampedProgress)

            // Check if Cookie reached a corner endpoint
            let reachedCorner = (traversalDirection > 0 && edgeProgress >= 1.0) ||
                                (traversalDirection < 0 && edgeProgress <= 0.0)

            if reachedCorner {
                edgeProgress = traversalDirection > 0 ? 1.0 : 0.0
                currentPhase = .cornerTransition
                phaseElapsed = 0
                phaseDuration = Double.random(in: 0.8...1.4)
                playfulReaction = .surprised
            }

        case .cornerTransition:
            // Paused at corner: evaluate jump opportunities first, then vertical climb or turn
            if phaseElapsed >= phaseDuration {
                // 1. Evaluate window jumping if enabled
                if jumpingEnabled {
                    let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(cookiePosition) }) ?? NSScreen.main
                    let surfaces = jumpPlanner.extractJumpSurfaces(from: provider.candidateWindows, screenVisibleFrame: screen?.visibleFrame)
                    if let jumpProposal = jumpPlanner.evaluateBestJump(
                        from: cookiePosition,
                        currentWindowId: activeWindow?.id,
                        surfaces: surfaces,
                        style: jumpStyle
                    ) {
                        let roll = Double.random(in: 0...1)
                        if roll < jumpFrequency.triggerProbability {
                            startJump(proposal: jumpProposal)
                            return
                        }
                    }
                }

                // 2. Evaluate vertical climbing if enabled
                if verticalClimbingEnabled, let win = activeWindow {
                    let isRightCorner = edgeProgress >= 0.9
                    let verticalType: WindowEdgeType = isRightCorner ? .rightVertical : .leftVertical
                    if let vertPath = provider.navigablePaths.first(where: { $0.windowId == win.id && $0.edgeType == verticalType }) {
                        activeEdgePath = vertPath
                        edgeProgress = 0.0 // Start at top of vertical edge
                        traversalDirection = 1.0 // Move downwards
                        currentPhase = .climbingVerticalEdge
                        phaseElapsed = 0
                        phaseDuration = Double.random(in: 3.0...5.0)
                        return
                    }
                }

                // 3. Default corner action: turn around and walk back along the top edge or conclude
                let roll = Double.random(in: 0...1)
                if roll < 0.65 {
                    traversalDirection = -traversalDirection
                    currentPhase = .walkingTopEdge
                    phaseElapsed = 0
                    phaseDuration = Double.random(in: 3.5...6.0)
                } else {
                    concludeExploration(from: cookiePosition)
                }
            }

        case .climbingVerticalEdge:
            guard let path = activeEdgePath else {
                concludeExploration(from: cookiePosition)
                return
            }

            // Simulated climb down: restrained speed ~85 pt/s
            let speed: CGFloat = 85.0
            let pathLen = max(10, path.length)
            let deltaProgress = (speed / pathLen) * CGFloat(dt) * traversalDirection
            edgeProgress += deltaProgress

            let clampedProgress = max(0, min(1, edgeProgress))
            destinationPoint = path.pointAt(progress: clampedProgress)

            // When reaching bottom or timeout: transition to pausing or departure
            if edgeProgress >= 1.0 || phaseElapsed >= phaseDuration {
                edgeProgress = 1.0
                currentPhase = .pausing
                phaseElapsed = 0
                phaseDuration = Double.random(in: 1.2...2.0)
                playfulReaction = .happy
            }

        case .pausing:
            // Brief observation pause on the edge
            if phaseElapsed >= phaseDuration {
                concludeExploration(from: cookiePosition)
            }

        case .preparingJump:
            guard let proposal = pendingJumpProposal, let trajectory = activeJumpTrajectory else {
                currentPhase = .idle
                return
            }
            updateLookAngle(from: cookiePosition, toward: proposal.targetSurface.landingPoint)

            if phaseElapsed >= phaseDuration {
                // Pre-launch validation: ensure target window is still present and valid
                provider.refreshWindows()
                if let targetWinId = proposal.targetSurface.windowId {
                    guard let updatedWin = provider.candidateWindows.first(where: { $0.id == targetWinId && !$0.isOccluded }) else {
                        log.notice("Pre-launch target window closed or occluded — cancelling jump safely")
                        pendingJumpProposal = nil
                        activeJumpTrajectory = nil
                        windowLookAngle = nil
                        if activeWindow != nil {
                            currentPhase = .walkingTopEdge
                            phaseElapsed = 0
                            phaseDuration = 3.0
                        } else {
                            concludeExploration(from: cookiePosition)
                        }
                        return
                    }

                    // Check for abrupt window movement before takeoff
                    let landingX = updatedWin.bounds.midX
                    let landingY = updatedWin.bounds.maxY + proposal.targetSurface.footOffset
                    let drift = hypot(landingX - proposal.targetSurface.landingPoint.x, landingY - proposal.targetSurface.landingPoint.y)
                    if drift > 60 {
                        log.notice("Pre-launch target window moved significantly — cancelling jump safely")
                        pendingJumpProposal = nil
                        activeJumpTrajectory = nil
                        windowLookAngle = nil
                        concludeExploration(from: cookiePosition)
                        return
                    }
                }

                // Launch into flight along trajectory
                currentPhase = .jumping
                phaseElapsed = 0
                phaseDuration = trajectory.duration
                jumpProgress = 0.0
                windowLookAngle = nil
                playfulReaction = .happy
                log.info("Launched jump toward \(proposal.targetSurface.ownerName, privacy: .public)")
            }

        case .jumping:
            guard let proposal = pendingJumpProposal, let trajectory = activeJumpTrajectory else {
                currentPhase = .idle
                return
            }

            let progress = min(1.0, CGFloat(phaseElapsed / max(0.01, phaseDuration)))
            jumpProgress = progress

            // Evaluate current point along parabolic arc
            destinationPoint = trajectory.point(at: progress)
            jumpShadowScale = trajectory.shadowScale(at: progress)
            jumpShadowAlpha = trajectory.shadowAlpha(at: progress)

            // Touchdown when flight duration completes
            if progress >= 1.0 || phaseElapsed >= phaseDuration {
                destinationPoint = trajectory.endPoint
                jumpShadowScale = 1.0
                jumpShadowAlpha = 0.09
                jumpProgress = 1.0

                currentPhase = .landing
                phaseElapsed = 0
                phaseDuration = Double.random(in: 0.28...0.45)
                playfulReaction = .dropped

                jumpPlanner.recordJumpCompleted(to: proposal.targetSurface.windowId)
                log.info("Touchdown landed on \(proposal.targetSurface.ownerName, privacy: .public)")
            }

        case .landing:
            guard let proposal = pendingJumpProposal else {
                currentPhase = .idle
                return
            }

            if phaseElapsed >= phaseDuration {
                // Post-landing surface establishment
                pendingJumpProposal = nil
                activeJumpTrajectory = nil
                jumpProgress = 0.0
                jumpShadowScale = 1.0
                jumpShadowAlpha = 0.09

                provider.refreshWindows()

                if let targetWinId = proposal.targetSurface.windowId,
                   let win = provider.candidateWindows.first(where: { $0.id == targetWinId && !$0.isOccluded }),
                   let topPath = provider.navigablePaths.first(where: { $0.windowId == win.id && $0.edgeType == .topHorizontal }) {
                    // Successfully landed on a window! Transition to top-edge walk
                    self.activeWindow = win
                    self.activeEdgePath = topPath
                    let (_, p) = topPath.closestPoint(to: cookiePosition)
                    self.edgeProgress = p
                    self.traversalDirection = (p < 0.5) ? 1.0 : -1.0
                    currentPhase = .walkingTopEdge
                    phaseElapsed = 0
                    phaseDuration = Double.random(in: 4.0...7.0)
                    playfulReaction = .happy
                    log.info("Established top-edge traversal on landed window \(win.ownerName, privacy: .public)")
                } else if proposal.targetSurface.surfaceKind == .desktopGround {
                    // Landed on desktop ground
                    concludeExploration(from: cookiePosition)
                } else {
                    // Fallback recovery if surface was lost or closed
                    log.info("Landed surface lost — recovering smoothly to ground")
                    concludeExploration(from: cookiePosition)
                }
            }

        case .departing:
            guard let dest = destinationPoint else {
                currentPhase = .idle
                return
            }
            let dist = hypot(dest.x - cookiePosition.x, dest.y - cookiePosition.y)
            if dist <= 16 || phaseElapsed >= phaseDuration {
                currentPhase = .idle
                destinationPoint = nil
                activeWindow = nil
                activeEdgePath = nil
                windowLookAngle = nil
                playfulReaction = nil
            }
        }
    }

    // MARK: - Active Window Reconciliation

    /// Reconciles the active window's position if the user moves or resizes it.
    /// If the window closed, minimized, or disappeared, smoothly dismounts to safety.
    func reconcileActiveWindow() {
        guard let currentWin = activeWindow else { return }
        provider.refreshWindows()

        // Match by window ID or owner PID
        if let updatedWin = provider.candidateWindows.first(where: { $0.id == currentWin.id }) {
            // Window moved or resized: update bounds and path
            self.activeWindow = updatedWin
            if let updatedPath = provider.navigablePaths.first(where: {
                $0.windowId == updatedWin.id && $0.edgeType == (activeEdgePath?.edgeType ?? .topHorizontal)
            }) {
                self.activeEdgePath = updatedPath
                // Re-evaluate destination point at current progress to follow the moved window!
                destinationPoint = updatedPath.pointAt(progress: edgeProgress)
            }
        } else {
            // Window was closed, minimized, or occluded: gracefully dismount to visible ground
            log.info("Active window disappeared or closed — gracefully dismounting")
            if let dest = destinationPoint {
                concludeExploration(from: dest)
            } else {
                cancelExploration()
            }
        }
    }

    // MARK: - Departure & Recovery

    /// Plans a clean, safe dismount from the window edge back onto reachable desktop space.
    private func concludeExploration(from currentPos: CGPoint) {
        currentPhase = .departing
        phaseElapsed = 0
        phaseDuration = 3.5

        // Step away from the window edge toward the center of the display
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(currentPos) }) ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 70, width: 1440, height: 800)

        let targetX = min(max(currentPos.x + CGFloat.random(in: -60...60), vis.minX + 80), vis.maxX - 80)
        let targetY = max(vis.minY + 90, currentPos.y - 75) // Step downward toward ground

        destinationPoint = CGPoint(x: targetX, y: targetY)
        windowLookAngle = nil
    }

    /// Computes subtle look angle toward target point.
    private func updateLookAngle(from cookiePos: CGPoint, toward targetPos: CGPoint) {
        let dx = targetPos.x - cookiePos.x
        let dy = targetPos.y - cookiePos.y
        let angle = atan2(dy, abs(dx))
        // Anatomically clamped to ±0.20 rad (±11.5°)
        let clamped = max(-0.20, min(0.20, angle))
        windowLookAngle = clamped
    }

    /// Clears any one-shot reaction once consumed.
    func clearPlayfulReaction() {
        playfulReaction = nil
    }
}
