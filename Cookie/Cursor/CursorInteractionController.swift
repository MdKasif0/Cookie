import AppKit
import SpriteKit
import Combine
import os

/// Dedicated controller governing Cookie's awareness of and playful interactions with the macOS mouse cursor.
///
/// Converts global virtual desktop screen coordinates into Cookie's local SpriteKit scene coordinates,
/// handles multi-monitor display layouts (displays positioned above or to the left of the primary screen),
/// tracks radial proximity zones with hysteresis, calculates cursor velocity dynamics, and coordinates
/// organic cat responses (subtle head tilting, slow-following with anticipation, and playful dodging).
@MainActor
final class CursorInteractionController: ObservableObject {
    // MARK: - Published Properties

    /// Active proximity zone with hysteresis protection.
    @Published private(set) var currentZone: CursorProximityZone = .departure

    /// Character orientation angle in radians for subtle head/body glance toward cursor.
    @Published private(set) var lookAngle: CGFloat?

    /// Desired 2D locomotion destination in global screen coordinates when Cookie is following the cursor.
    @Published private(set) var followTarget: CGPoint?

    /// Desired horizontal locomotion destination (for backward compatibility).
    var followTargetX: CGFloat? {
        followTarget?.x
    }

    /// Desired vertical locomotion destination.
    var followTargetY: CGFloat? {
        followTarget?.y
    }

    /// Current cursor motion classification (stationary, slow, or rapid).
    @Published private(set) var cursorMotionState: CursorMotionState = .stationary

    /// Active playful reaction to be expressed, if any.
    @Published private(set) var activeReaction: CursorPlayfulReaction?

    /// Whether the cursor is currently in any awareness or interaction zone.
    var isCursorNear: Bool {
        currentZone != .departure
    }

    // MARK: - Constants & Configuration

    private static let baseAwarenessRadius: CGFloat = 250
    private static let baseInteractionRadius: CGFloat = 120
    private static let baseCloseContactRadius: CGFloat = 55
    private static let baseDepartureRadius: CGFloat = 350

    /// Radius calculation helpers respecting character rendered scale.
    func awarenessRadius(forScale scale: CGFloat = 1.0) -> CGFloat {
        Self.baseAwarenessRadius * scale
    }

    func interactionRadius(forScale scale: CGFloat = 1.0) -> CGFloat {
        Self.baseInteractionRadius * scale
    }

    func closeContactRadius(forScale scale: CGFloat = 1.0) -> CGFloat {
        Self.baseCloseContactRadius * scale
    }

    func departureRadius(forScale scale: CGFloat = 1.0) -> CGFloat {
        Self.baseDepartureRadius * scale
    }

    /// Hysteresis buffer in points to prevent boundary state chatter.
    private static let hysteresisMargin: CGFloat = 12

    // MARK: - Internal State

    private var globalEventMonitor: Any?
    private var screenObservers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.cookie.mac", category: "CursorInteraction")

    // Position memory
    private(set) var lastGlobalCursorPoint: NSPoint = .zero
    private var previousCursorPoint: NSPoint = .zero
    private var cursorVelocity: CGFloat = 0
    private var smoothedCursorVelocity: CGFloat = 0
    private var isApproachingCookie: Bool = false

    // Dwell and cooldown timers
    private var zoneTransitionCooldownUntil = Date.distantPast
    private var interactionDwellTime: TimeInterval = 0
    private var anticipationRemaining: TimeInterval = 0
    private var isAnticipatingFollow = false
    private var dodgeCooldownUntil = Date.distantPast
    private var reactionCooldownUntil = Date.distantPast
    private var headTiltRestCooldownUntil = Date.distantPast

    // Clock seam for deterministic testing
    var now: () -> Date = { Date() }

    // MARK: - Initialization & Teardown

    init() {
        setupGlobalEventMonitor()
        setupScreenNotifications()
        lastGlobalCursorPoint = NSEvent.mouseLocation
        previousCursorPoint = lastGlobalCursorPoint
    }

    deinit {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for observer in screenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts event-driven mouse tracking if not already active.
    func startTracking() {
        if globalEventMonitor == nil {
            setupGlobalEventMonitor()
        }
    }

    /// Cleans up event monitors and notification observers cleanly.
    func teardown() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        for observer in screenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObservers.removeAll()
        resetInteractionState()
        currentZone = .departure
    }

    // MARK: - Event Monitoring

    private func setupGlobalEventMonitor() {
        // Event-driven mouse move monitor for responsive tracking
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastGlobalCursorPoint = event.locationInWindow
            }
        }
    }

    private func setupScreenNotifications() {
        let center = NotificationCenter.default
        let screenParamsObs = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange()
            }
        }
        screenObservers.append(screenParamsObs)

        let wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange()
            }
        }
        screenObservers.append(wakeObs)
    }

    private func handleDisplayChange() {
        log.info("Display geometry changed — recalculating safe coordinate spaces")
        // Refresh cursor location
        lastGlobalCursorPoint = NSEvent.mouseLocation
        previousCursorPoint = lastGlobalCursorPoint
    }

    // MARK: - Coordinate Transformations

    /// Converts a global macOS screen coordinate into Cookie's local SpriteKit scene coordinate space.
    /// Accurately handles multi-display bounds, displays placed left or above the main screen, and window scaling.
    func convertScreenPointToScene(
        screenPoint: NSPoint,
        window: NSWindow?,
        scene: SKScene?
    ) -> CGPoint? {
        guard let window, let scene, let view = window.contentView else { return nil }
        // 1. Convert global screen point to window local coordinates
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        // 2. Convert window local coordinates to view coordinates
        let viewPoint = view.convert(windowPoint, from: nil)
        // 3. Convert view coordinates into SpriteKit scene coordinates
        return scene.convertPoint(fromView: viewPoint)
    }

    /// Converts screen coordinates to scene coordinates given a window frame and scene size (useful for geometry tests).
    func convertScreenPointToScene(
        _ screenPoint: NSPoint,
        windowFrame: CGRect,
        sceneSize: CGSize
    ) -> CGPoint {
        let localX = screenPoint.x - windowFrame.midX
        let localY = screenPoint.y - windowFrame.midY
        return CGPoint(x: localX, y: localY)
    }

    /// Computes the anatomically clamped look angle in radians toward cursor.
    func calculateLookAngle(
        fromCookie cookiePos: CGPoint,
        toCursor cursorPos: CGPoint,
        facingRight: Bool
    ) -> CGFloat {
        let dx = cursorPos.x - cookiePos.x
        let dy = cursorPos.y - cookiePos.y
        let angle = atan2(dy, abs(dx))
        return max(-0.20, min(0.20, angle))
    }

    /// Classifies cursor velocity into motion states.
    func classifyMotion(velocity: CGVector) -> CursorMotionState {
        let speed = hypot(velocity.dx, velocity.dy)
        if speed < 30 {
            return .stationary
        } else if speed > 580 {
            return .rapid
        } else {
            return .slow
        }
    }

    // MARK: - Frame Update Cycle

    /// Primary update cycle called each frame by the scene or behavior engine.
    ///
    /// - Parameters:
    ///   - dt: Delta time in seconds since the previous frame.
    ///   - cookieCenterScreen: Center of Cookie's rendered sprite in macOS global screen coordinates.
    ///   - cursorPoint: Optional cursor point override (useful for deterministic tests or multi-window routing).
    ///   - cookieSize: Current scale multiplier from CookieSettings.
    ///   - settings: User preferences governing cursor interaction.
    ///   - isInterrupted: True if high-priority behaviors (dragging, emotes) are active.
    func update(
        dt: TimeInterval,
        cookieCenterScreen: NSPoint,
        cursorPoint: NSPoint? = nil,
        cookieSize: Double,
        settings: CookieSettings,
        isInterrupted: Bool
    ) {
        guard dt > 0 else { return }

        // If cursor interaction is disabled or higher-priority interaction is active, reset smoothly
        guard settings.cursorInteraction, !isInterrupted else {
            resetInteractionState()
            return
        }

        // Lightweight throttled fallback sampling or explicit cursor point
        let rawCursor = cursorPoint ?? NSEvent.mouseLocation
        lastGlobalCursorPoint = rawCursor

        // 1. Calculate Cursor Velocity & Dynamics
        let cursorDeltaX = rawCursor.x - previousCursorPoint.x
        let cursorDeltaY = rawCursor.y - previousCursorPoint.y
        let instantVelocity = hypot(cursorDeltaX, cursorDeltaY) / CGFloat(dt)
        previousCursorPoint = rawCursor

        // Exponential smoothing on velocity (prevents single-frame jitters)
        smoothedCursorVelocity += (instantVelocity - smoothedCursorVelocity) * min(1.0, CGFloat(dt) * 12.0)

        // Classify motion state
        if smoothedCursorVelocity < 30 {
            cursorMotionState = .stationary
        } else if smoothedCursorVelocity > 580 {
            cursorMotionState = .rapid
        } else {
            cursorMotionState = .slow
        }

        // 2. Compute 2D Vector & Proximity Zone with Hysteresis
        let dx = rawCursor.x - cookieCenterScreen.x
        let dy = rawCursor.y - cookieCenterScreen.y
        let distance = hypot(dx, dy)

        // Determine if cursor is moving closer to Cookie
        let prevDx = previousCursorPoint.x - cookieCenterScreen.x
        let prevDy = previousCursorPoint.y - cookieCenterScreen.y
        let prevDistance = hypot(prevDx, prevDy)
        isApproachingCookie = (distance < prevDistance - 2)

        let scale = CGFloat(max(0.7, cookieSize))
        updateProximityZone(distance: distance, scale: scale)

        // 3. Look Toward Cursor (Anatomically plausible head tilt & orientation)
        updateLookAngle(dx: dx, dy: dy, distance: distance, dt: dt)

        // 4. Playful Dodge Behavior (infrequent gentle step back from rushing pointer)
        if settings.cursorDodgingEnabled, checkPlayfulDodge(dx: dx, distance: distance) {
            return
        }

        // 5. Approaching & Playful Following Behavior
        updateFollowing(
            dt: dt,
            dx: dx,
            distance: distance,
            cookieCenterScreen: cookieCenterScreen,
            settings: settings
        )
    }

    // MARK: - Proximity Zone State Machine

    private func updateProximityZone(distance: CGFloat, scale: CGFloat) {
        let date = now()
        guard date >= zoneTransitionCooldownUntil else { return }

        let margin = Self.hysteresisMargin
        let closeLimit = Self.baseCloseContactRadius * scale
        let interactLimit = Self.baseInteractionRadius * scale
        let awareLimit = Self.baseAwarenessRadius * scale
        let departLimit = Self.baseDepartureRadius * scale

        let newZone: CursorProximityZone
        switch currentZone {
        case .departure:
            if distance <= awareLimit - margin {
                newZone = distance <= interactLimit ? (distance <= closeLimit ? .closeContact : .interaction) : .awareness
            } else {
                newZone = .departure
            }

        case .awareness:
            if distance <= interactLimit - margin {
                newZone = distance <= closeLimit ? .closeContact : .interaction
            } else if distance >= departLimit {
                newZone = .departure
            } else {
                newZone = .awareness
            }

        case .interaction:
            if distance <= closeLimit - margin {
                newZone = .closeContact
            } else if distance >= awareLimit + margin {
                newZone = .awareness
            } else {
                newZone = .interaction
            }

        case .closeContact:
            if distance >= closeLimit + margin {
                newZone = distance >= interactLimit + margin ? .awareness : .interaction
            } else {
                newZone = .closeContact
            }
        }

        if newZone != currentZone {
            currentZone = newZone
            zoneTransitionCooldownUntil = date.addingTimeInterval(0.25)
            log.debug("Cursor entered zone: \(newZone.displayName, privacy: .public) (distance: \(Int(distance)))")
        }
    }

    // MARK: - Looking & Tilting

    private func updateLookAngle(dx: CGFloat, dy: CGFloat, distance: CGFloat, dt: TimeInterval) {
        switch currentZone {
        case .awareness, .interaction, .closeContact:
            // Calculate natural glance angle based on relative vertical & horizontal offset
            let angle = atan2(dy, abs(dx))
            // Clamp strictly to subtle anatomical tilt: -11.5° to +11.5° (±0.20 rad)
            let clampedAngle = max(-0.20, min(0.20, angle))
            let current = lookAngle ?? 0
            lookAngle = current + (clampedAngle - current) * min(1.0, CGFloat(dt) * 10.0)

        case .departure:
            // Smoothly release head tilt when cursor departs
            if let current = lookAngle {
                let next = current + (0 - current) * min(1.0, CGFloat(dt) * 8.0)
                lookAngle = abs(next) < 0.01 ? nil : next
            }
        }
    }

    // MARK: - Playful Dodge

    private func checkPlayfulDodge(dx: CGFloat, distance: CGFloat) -> Bool {
        let date = now()
        guard date >= dodgeCooldownUntil else { return false }
        // Trigger condition: cursor is moving rapidly straight toward Cookie into close-contact / interaction zone
        guard (currentZone == .interaction || currentZone == .closeContact),
              cursorMotionState == .rapid,
              isApproachingCookie,
              smoothedCursorVelocity > 620 else {
            return false
        }

        dodgeCooldownUntil = date.addingTimeInterval(Double.random(in: 25...45))
        activeReaction = .dodge
        log.info("Playful dodge triggered: rapid cursor approach detected")
        return true
    }

    // MARK: - Approaching & Following

    private func updateFollowing(
        dt: TimeInterval,
        dx: CGFloat,
        distance: CGFloat,
        cookieCenterScreen: NSPoint,
        settings: CookieSettings
    ) {
        let intensity = CursorFollowingIntensity(rawValue: settings.cursorFollowingIntensity) ?? .balanced

        switch currentZone {
        case .interaction:
            // Cursor is lingering in interaction zone
            interactionDwellTime += dt

            // If cursor moves rapidly, pause following — curious cat watches rather than chasing
            if cursorMotionState == .rapid {
                isAnticipatingFollow = false
                followTarget = nil
                activeReaction = .glance
                return
            }

            // Anticipation pause before beginning follow
            if !isAnticipatingFollow, interactionDwellTime >= intensity.anticipationDelay {
                isAnticipatingFollow = true
                anticipationRemaining = 0.25
                activeReaction = .headTilt
            }

            if isAnticipatingFollow {
                if anticipationRemaining > 0 {
                    anticipationRemaining -= dt
                    followTarget = nil
                } else if settings.cursorFollowingEnabled {
                    // Calculate comfortable trailing position in 2D
                    let fromCursorX = cookieCenterScreen.x - lastGlobalCursorPoint.x
                    let fromCursorY = cookieCenterScreen.y - lastGlobalCursorPoint.y
                    let d = hypot(fromCursorX, fromCursorY)

                    let target: CGPoint
                    if d > 0.001 {
                        let unitX = fromCursorX / d
                        let unitY = fromCursorY / d
                        target = CGPoint(
                            x: lastGlobalCursorPoint.x + unitX * intensity.trailingDistance,
                            y: lastGlobalCursorPoint.y + unitY * intensity.trailingDistance
                        )
                    } else {
                        target = CGPoint(
                            x: lastGlobalCursorPoint.x - intensity.trailingDistance,
                            y: lastGlobalCursorPoint.y
                        )
                    }
                    followTarget = target
                }
            }

        case .closeContact:
            // Arrived at close contact: stop translation, trigger playful reaction
            followTarget = nil
            isAnticipatingFollow = false
            interactionDwellTime = 0

            let date = now()
            if date >= reactionCooldownUntil, cursorMotionState == .slow || cursorMotionState == .stationary {
                reactionCooldownUntil = date.addingTimeInterval(Double.random(in: 8...16))
                let roll = Double.random(in: 0...1)
                if roll < 0.45 {
                    activeReaction = .pawReach
                } else if roll < 0.8 {
                    activeReaction = .happyChirp
                } else {
                    activeReaction = .headTilt
                }
            }

        case .awareness:
            // Cursor is visible but in outer zone: hold position, watch curiously
            interactionDwellTime = 0
            isAnticipatingFollow = false
            followTarget = nil

        case .departure:
            resetInteractionState()
        }
    }

    /// Resets interaction timers and target positions cleanly.
    func resetInteractionState() {
        interactionDwellTime = 0
        anticipationRemaining = 0
        isAnticipatingFollow = false
        followTarget = nil
        lookAngle = nil
        activeReaction = nil
    }

    /// Clears any one-shot reaction after consumption by the behavior engine.
    func clearActiveReaction() {
        activeReaction = nil
    }
}
