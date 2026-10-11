import AppKit
import Combine
import os

/// Dedicated controller governing Cookie's intelligent interactions with the macOS Dock,
/// including natural approach, safe edge pacing, application icon awareness, gaze orientation,
/// and cursor-dock coordination.
@MainActor
final class DockInteractionController: ObservableObject {
    // MARK: - Published Properties

    /// Current phase in the Dock exploration state machine.
    @Published private(set) var currentPhase: DockSessionPhase = .idle

    /// Target destination along the safe Dock walking surface.
    @Published private(set) var destinationPoint: CGPoint?

    /// Active application icon region being inspected, if any.
    @Published private(set) var activeInspectionTarget: DockInspectionTarget?

    /// Anatomically plausible look angle in radians toward the Dock or inspected icon.
    @Published private(set) var dockLookAngle: CGFloat?

    /// Playful one-shot reaction produced during Dock play (e.g. curious glance, sniff, chirp).
    @Published private(set) var playfulReaction: CookieReaction?

    /// Whether Cookie is currently engaged in any Dock exploration activity.
    var isExploringDock: Bool {
        currentPhase != .idle
    }

    // MARK: - Dependencies & Seams

    let detector: DockEnvironmentDetector
    var now: () -> Date = { Date() }

    private let log = Logger(subsystem: "com.cookie.mac", category: "DockInteraction")

    // MARK: - Internal Timers & Memory

    private(set) var cooldownUntil: Date = .distantPast
    private var phaseElapsed: TimeInterval = 0
    private var phaseDuration: TimeInterval = 0
    private var sessionElapsed: TimeInterval = 0
    private var sessionMaxDuration: TimeInterval = 12
    private var inspectionTargets: [DockInspectionTarget] = []

    // MARK: - Initialization

    init(detector: DockEnvironmentDetector? = nil) {
        self.detector = detector ?? DockEnvironmentDetector()
    }

    // MARK: - Lifecycle & Interruption

    /// Immediately aborts any ongoing Dock exploration session (e.g. user dragged Cookie or triggered an emote).
    func cancelExploration() {
        if currentPhase != .idle {
            log.info("Dock exploration cancelled")
        }
        currentPhase = .idle
        destinationPoint = nil
        activeInspectionTarget = nil
        dockLookAngle = nil
        playfulReaction = nil
        phaseElapsed = 0
    }

    /// Sets the cooldown timer based on user frequency preference.
    func applyCooldown(for frequency: DockExplorationFrequency) {
        let range = frequency.cooldownRange
        let interval = Double.random(in: range)
        cooldownUntil = now().addingTimeInterval(interval)
    }

    // MARK: - Application Icon Discovery (Supported Public APIs)

    /// Builds estimated inspection targets along the Dock span using running applications.
    /// Uses official `NSWorkspace.shared.runningApplications` without private Dock memory scraping.
    func refreshInspectionTargets(environment: DesktopEnvironment) {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, bundleId: String)? in
                guard let name = app.localizedName, !name.isEmpty else { return nil }
                return (name: name, bundleId: app.bundleIdentifier ?? "")
            }

        let appCount = max(3, min(runningApps.count, 12))
        var targets: [DockInspectionTarget] = []

        let dFrame = environment.dockFrame
        let orientation = environment.dockOrientation

        switch orientation {
        case .bottom:
            // Distribute along center span of the bottom screen
            let centerSpan = dFrame.width * 0.7
            let startX = dFrame.midX - (centerSpan / 2)
            let step = centerSpan / CGFloat(appCount + 1)
            let y = dFrame.midY

            for i in 0..<appCount {
                let x = startX + (CGFloat(i + 1) * step)
                let app = i < runningApps.count ? runningApps[i] : (name: "Application \(i + 1)", bundleId: "")
                targets.append(DockInspectionTarget(screenPoint: CGPoint(x: x, y: y), label: app.name, bundleIdentifier: app.bundleId))
            }

        case .left:
            // Distribute vertically along the left dock
            let centerSpan = dFrame.height * 0.7
            let startY = dFrame.midY - (centerSpan / 2)
            let step = centerSpan / CGFloat(appCount + 1)
            let x = dFrame.midX

            for i in 0..<appCount {
                let y = startY + (CGFloat(i + 1) * step)
                let app = i < runningApps.count ? runningApps[i] : (name: "Application \(i + 1)", bundleId: "")
                targets.append(DockInspectionTarget(screenPoint: CGPoint(x: x, y: y), label: app.name, bundleIdentifier: app.bundleId))
            }

        case .right:
            // Distribute vertically along the right dock
            let centerSpan = dFrame.height * 0.7
            let startY = dFrame.midY - (centerSpan / 2)
            let step = centerSpan / CGFloat(appCount + 1)
            let x = dFrame.midX

            for i in 0..<appCount {
                let y = startY + (CGFloat(i + 1) * step)
                let app = i < runningApps.count ? runningApps[i] : (name: "Application \(i + 1)", bundleId: "")
                targets.append(DockInspectionTarget(screenPoint: CGPoint(x: x, y: y), label: app.name, bundleIdentifier: app.bundleId))
            }

        case .unknown:
            break
        }

        self.inspectionTargets = targets
    }

    // MARK: - Exploration Triggering

    /// Evaluates whether Cookie should autonomously begin approaching the Dock.
    func shouldTriggerAutonomousExploration(
        cookiePosition: NSPoint,
        frequency: DockExplorationFrequency,
        settingsEnabled: Bool,
        isInterrupted: Bool
    ) -> Bool {
        guard settingsEnabled, !isInterrupted, currentPhase == .idle else { return false }
        let date = now()
        guard date >= cooldownUntil else { return false }

        // Frequency-tuned probability check
        let roll = Double.random(in: 0...1)
        guard roll < frequency.triggerProbability else {
            // Short backoff before next check
            cooldownUntil = date.addingTimeInterval(Double.random(in: 15...30))
            return false
        }

        return true
    }

    /// Begins a structured Dock exploration session.
    func startExploration(
        fromPosition cookiePosition: NSPoint,
        frequency: DockExplorationFrequency,
        targetIconIndex: Int? = nil
    ) {
        let env = detector.refreshEnvironment(forPoint: cookiePosition)
        refreshInspectionTargets(environment: env)

        let durationRange = frequency.explorationDurationRange
        sessionMaxDuration = Double.random(in: durationRange)
        sessionElapsed = 0

        // Select an inspection target along the Dock
        let target: DockInspectionTarget?
        if !inspectionTargets.isEmpty {
            if let index = targetIconIndex, index >= 0, index < inspectionTargets.count {
                target = inspectionTargets[index]
            } else {
                target = inspectionTargets.randomElement()
            }
        } else {
            target = nil
        }
        activeInspectionTarget = target

        // Determine destination along the safe walking surface
        let targetPoint: CGPoint
        if let target {
            targetPoint = pointOnSafeSurface(closestTo: target.screenPoint, environment: env)
        } else {
            targetPoint = defaultPointOnSafeSurface(environment: env)
        }
        destinationPoint = targetPoint

        // Begin with a brief curious anticipation glance
        currentPhase = .anticipating
        phaseElapsed = 0
        phaseDuration = Double.random(in: 0.35...0.55)
        playfulReaction = .shy
        updateLookAngle(from: cookiePosition, toward: target?.screenPoint ?? targetPoint, environment: env)

        applyCooldown(for: frequency)
        log.info("Started Dock exploration towards \(target?.label ?? "Dock Edge", privacy: .public)")
    }

    // MARK: - Frame Update

    /// Primary tick cycle called each frame by the behavior engine.
    func tick(
        dt: TimeInterval,
        cookiePosition: NSPoint,
        characterSize: CGSize,
        frequency: DockExplorationFrequency
    ) {
        guard currentPhase != .idle, dt > 0 else { return }

        phaseElapsed += dt
        sessionElapsed += dt

        let env = detector.currentEnvironment

        // Session timeout safety: never spend too long exploring the Dock
        if sessionElapsed >= sessionMaxDuration {
            concludeExploration(from: cookiePosition, environment: env)
            return
        }

        switch currentPhase {
        case .idle:
            break

        case .anticipating:
            // Curious anticipation pause: glance toward the target before moving
            if let targetPt = activeInspectionTarget?.screenPoint ?? destinationPoint {
                updateLookAngle(from: cookiePosition, toward: targetPt, environment: env)
            }
            if phaseElapsed >= phaseDuration {
                currentPhase = .approaching
                phaseElapsed = 0
                phaseDuration = 8.0 // Generous arrival timeout
            }

        case .approaching:
            guard let dest = destinationPoint else {
                concludeExploration(from: cookiePosition, environment: env)
                return
            }
            // Update look angle toward destination
            updateLookAngle(from: cookiePosition, toward: dest, environment: env)

            // Arrival check: reached within threshold of the Dock-adjacent target
            let dist = hypot(dest.x - cookiePosition.x, dest.y - cookiePosition.y)
            if dist <= 12 || phaseElapsed >= phaseDuration {
                // Arrived at the Dock edge! Transition to icon inspection or edge pacing
                if activeInspectionTarget != nil {
                    currentPhase = .inspectingIcon
                    phaseElapsed = 0
                    phaseDuration = Double.random(in: 1.8...3.2)
                    playfulReaction = .happy
                } else {
                    currentPhase = .pacingEdge
                    phaseElapsed = 0
                    phaseDuration = Double.random(in: 2.5...4.5)
                    selectAdjacentEdgeDestination(from: cookiePosition, environment: env)
                }
            }

        case .inspectingIcon:
            // Paused near the icon: look directly toward it
            if let iconPt = activeInspectionTarget?.screenPoint {
                updateLookAngle(from: cookiePosition, toward: iconPt, environment: env)
            }
            if phaseElapsed >= phaseDuration {
                // Transition to pacing along the edge or departing
                let roll = Double.random(in: 0...1)
                if roll < 0.6 {
                    currentPhase = .pacingEdge
                    phaseElapsed = 0
                    phaseDuration = Double.random(in: 2.0...4.0)
                    selectAdjacentEdgeDestination(from: cookiePosition, environment: env)
                } else {
                    concludeExploration(from: cookiePosition, environment: env)
                }
            }

        case .pacingEdge:
            guard let dest = destinationPoint else {
                concludeExploration(from: cookiePosition, environment: env)
                return
            }
            let dist = hypot(dest.x - cookiePosition.x, dest.y - cookiePosition.y)
            if dist <= 14 || phaseElapsed >= phaseDuration {
                concludeExploration(from: cookiePosition, environment: env)
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
                activeInspectionTarget = nil
                dockLookAngle = nil
                playfulReaction = nil
            }
        }
    }

    // MARK: - Cursor & Dock Coordination

    /// Handles cursor interaction when user moves pointer near or over the Dock.
    func handleCursorNearDock(
        cursorLocation: NSPoint,
        cookieCenter: NSPoint,
        environment: DesktopEnvironment,
        settingsEnabled: Bool
    ) {
        guard settingsEnabled else { return }

        // Check if cursor is hovering in the Dock area
        let isCursorInDock = environment.isPointNearDock(cursorLocation, threshold: 40)
        guard isCursorInDock else { return }

        // If Cookie is within awareness range (~260 pt), she notices the cursor hovering over the Dock
        let dist = hypot(cursorLocation.x - cookieCenter.x, cursorLocation.y - cookieCenter.y)
        if dist <= 260 {
            updateLookAngle(from: cookieCenter, toward: cursorLocation, environment: env)

            // If Cookie was idle and cooldown passed, cursor may draw her toward the Dock!
            if currentPhase == .idle && now() >= cooldownUntil {
                let roll = Double.random(in: 0...1)
                if roll < 0.4 {
                    startExploration(fromPosition: cookieCenter, frequency: .occasional)
                }
            }
        }
    }

    private var env: DesktopEnvironment {
        detector.currentEnvironment
    }

    // MARK: - Geometry & Safe Navigation Helpers

    /// Computes the point on the safe walking surface closest to a given target point.
    func pointOnSafeSurface(closestTo point: CGPoint, environment: DesktopEnvironment) -> CGPoint {
        let surface = environment.safeWalkingSurface
        switch environment.dockOrientation {
        case .bottom:
            let clampedX = min(max(point.x, surface.minX), surface.maxX)
            return CGPoint(x: clampedX, y: surface.midY)
        case .left:
            let clampedY = min(max(point.y, surface.minY), surface.maxY)
            return CGPoint(x: surface.midX, y: clampedY)
        case .right:
            let clampedY = min(max(point.y, surface.minY), surface.maxY)
            return CGPoint(x: surface.midX, y: clampedY)
        case .unknown:
            return CGPoint(x: surface.midX, y: surface.midY)
        }
    }

    /// Selects a reasonable default point on the safe walking surface.
    func defaultPointOnSafeSurface(environment: DesktopEnvironment) -> CGPoint {
        let surface = environment.safeWalkingSurface
        return CGPoint(x: surface.midX, y: surface.midY)
    }

    /// Selects a new destination along the edge for the pacing phase.
    private func selectAdjacentEdgeDestination(from currentPos: CGPoint, environment: DesktopEnvironment) {
        let surface = environment.safeWalkingSurface
        switch environment.dockOrientation {
        case .bottom:
            let stride = CGFloat.random(in: 70...150) * (Bool.random() ? 1.0 : -1.0)
            let newX = min(max(currentPos.x + stride, surface.minX), surface.maxX)
            destinationPoint = CGPoint(x: newX, y: surface.midY)
        case .left, .right:
            let stride = CGFloat.random(in: 60...130) * (Bool.random() ? 1.0 : -1.0)
            let newY = min(max(currentPos.y + stride, surface.minY), surface.maxY)
            destinationPoint = CGPoint(x: surface.midX, y: newY)
        case .unknown:
            destinationPoint = CGPoint(x: surface.midX, y: surface.midY)
        }
    }

    /// Concludes the exploration and plans a smooth departure back toward the main desktop area.
    private func concludeExploration(from currentPos: CGPoint, environment: DesktopEnvironment) {
        currentPhase = .departing
        phaseElapsed = 0
        phaseDuration = 3.5

        // Depart inward away from the Dock edge
        let departureTarget: CGPoint
        let inwardStep: CGFloat = 85

        switch environment.dockOrientation {
        case .bottom:
            departureTarget = CGPoint(x: currentPos.x, y: min(environment.visibleFrame.maxY - 100, currentPos.y + inwardStep))
        case .left:
            departureTarget = CGPoint(x: min(environment.visibleFrame.maxX - 100, currentPos.x + inwardStep), y: currentPos.y)
        case .right:
            departureTarget = CGPoint(x: max(environment.visibleFrame.minX + 100, currentPos.x - inwardStep), y: currentPos.y)
        case .unknown:
            departureTarget = CGPoint(x: currentPos.x, y: currentPos.y + inwardStep)
        }

        destinationPoint = departureTarget
        dockLookAngle = nil
        activeInspectionTarget = nil
    }

    /// Computes subtle look angle toward target point.
    private func updateLookAngle(from cookiePos: CGPoint, toward targetPos: CGPoint, environment: DesktopEnvironment) {
        let dx = targetPos.x - cookiePos.x
        let dy = targetPos.y - cookiePos.y
        let angle = atan2(dy, abs(dx))
        // Anatomically clamped to ±0.20 rad (±11.5°)
        let clamped = max(-0.20, min(0.20, angle))
        dockLookAngle = clamped
    }

    /// Clears any transient playful reaction once consumed by the behavior engine.
    func clearPlayfulReaction() {
        playfulReaction = nil
    }
}
