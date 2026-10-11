import Foundation
import CoreGraphics
import AppKit
import os

/// Ambient autonomous behaviors supported by Cookie.
/// All behaviors reuse existing animation states, movement controllers, and emotes.
enum AmbientBehaviorKind: String, CaseIterable, Identifiable {
    case curiousObservation    // Pauses and looks toward a nearby window or frontmost app
    case shortDesktopPatrol     // Walks along a safe ground surface and stops
    case windowInspection       // Approaches a suitable window edge and observes
    case gentleDockVisit        // Visits a reachable Dock-adjacent area
    case surfaceTransition      // Jumps or transitions between connected surfaces
    case cursorInvitation       // Looks toward the cursor and waits for user interaction
    case returnToRest           // Returns to a safe resting or sitting posture
    case briefCelebration       // Performs a brief existing emote after positive interaction
    case recoveryBehavior       // Gracefully recovers from an invalidated route to ground

    var id: String { rawValue }
}

/// Centralized scheduler that orchestrates autonomous behavior selection,
/// priority rules, and context adaptation.
@MainActor
final class BehaviorScheduler {

    let memory: BehaviorMemory
    weak var windowProvider: WindowEnvironmentProvider?

    /// Seam for time.
    var now: () -> Date = { Date() }

    private let log = Logger(subsystem: "com.cookie.mac", category: "BehaviorScheduler")

    init(memory: BehaviorMemory, windowProvider: WindowEnvironmentProvider? = nil) {
        self.memory = memory
        self.windowProvider = windowProvider
    }

    // MARK: - Autonomous Schedule Evaluation

    /// Evaluates candidate ambient behaviors and selects the most appropriate action
    /// based on desktop context, memory history, and user preferences.
    func selectNextAmbientBehavior(
        currentState: CookieState,
        cookiePosition: CGPoint,
        cursorPosition: CGPoint?,
        cursorVelocity: CGFloat,
        cursorZone: CursorProximityZone,
        context: ApplicationContext,
        settings: CookieSettings,
        isPressed: Bool,
        isEmoting: Bool,
        worldItemActive: Bool
    ) -> AmbientBehaviorKind? {
        let currentTime = now()

        // 1. Hard gating: autonomous behavior disabled or paused
        guard settings.randomInteractions, !settings.pauseAutonomousBehavior else {
            return nil
        }

        // 2. High-priority interruptions prevent autonomous scheduling
        guard !isPressed, !isEmoting, !worldItemActive, currentState != .beingDragged else {
            return nil
        }

        // 3. User is actively interacting with the cursor: prioritize responsiveness over wandering
        if cursorZone == .interaction || (cursorZone == .awareness && cursorVelocity > 100) {
            // If the cursor is right by Cookie or moving rapidly nearby, don't wander off
            if cursorZone == .interaction && !memory.isActionRepetitive("cursorInvitation") {
                return .cursorInvitation
            }
            return nil
        }

        // 4. Recent direct interaction grace period: remain attentive near user
        if memory.timeSinceLastInteraction() < 6.0 {
            if !memory.isActionRepetitive("cursorInvitation") {
                return .cursorInvitation
            }
            return .returnToRest
        }

        // 5. Activity level cadence: calm needs longer quiet time between wanderings
        let minActionInterval: TimeInterval
        switch settings.activity {
        case .calm: minActionInterval = 28.0
        case .balanced: minActionInterval = 14.0
        case .lively: minActionInterval = 7.0
        }

        if memory.timeSinceLastAutonomousAction() < minActionInterval {
            // Still in rest period
            return nil
        }

        // 6. Build weighted candidate options based on desktop context
        var candidates: [(behavior: AmbientBehaviorKind, weight: Double)] = []

        // A. Return to Rest / Sitting
        if currentState != .sitting && currentState != .sleeping {
            candidates.append((.returnToRest, 30.0))
        }

        // B. Short Desktop Patrol
        if !memory.isActionRepetitive("shortDesktopPatrol") {
            let patrolWeight = (settings.activity == .lively) ? 40.0 : 25.0
            candidates.append((.shortDesktopPatrol, patrolWeight))
        }

        // C. Curious Observation (especially if frontmost window or candidate windows exist)
        if context.frontmostWindowBounds != nil || !(windowProvider?.candidateWindows.isEmpty ?? true) {
            if !memory.isActionRepetitive("curiousObservation") {
                candidates.append((.curiousObservation, 35.0))
            }
        }

        // D. Window Inspection
        if settings.windowInteraction, !(windowProvider?.candidateWindows.isEmpty ?? true) {
            if !memory.isActionRepetitive("windowInspection") {
                let windowWeight = (settings.activity == .lively) ? 35.0 : 20.0
                candidates.append((.windowInspection, windowWeight))
            }
        }

        // E. Gentle Dock Visit
        if settings.dockInteraction, settings.autonomousDockExploration {
            if !memory.isActionRepetitive("gentleDockVisit") {
                let dockWeight = (settings.activity == .lively) ? 30.0 : 18.0
                candidates.append((.gentleDockVisit, dockWeight))
            }
        }

        // F. Cursor Invitation (if cursor is stationary on screen)
        if cursorPosition != nil && cursorVelocity < 30 && !memory.isActionRepetitive("cursorInvitation") {
            candidates.append((.cursorInvitation, 25.0))
        }

        // 7. Pick using weighted random selection
        let totalWeight = candidates.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        var roll = Double.random(in: 0..<totalWeight)
        for candidate in candidates {
            roll -= candidate.weight
            if roll <= 0 {
                memory.recordAutonomousAction(candidate.behavior.rawValue)
                log.info("Scheduler selected ambient behavior: \(candidate.behavior.rawValue, privacy: .public)")
                return candidate.behavior
            }
        }

        return nil
    }
}
