import Foundation
import CoreGraphics
import os

/// Lightweight, in-memory short-term behavior memory.
/// Tracks recent desktop visits, actions, emotes, and failed targets to prevent
/// repetitive loops without persisting private activity histories.
final class BehaviorMemory {

    // MARK: - Cooldown Constants

    /// Cooldown for returning to the same window surface (seconds).
    var windowVisitCooldown: TimeInterval = 45.0

    /// Cooldown for approaching the same Dock region (seconds).
    var dockRegionCooldown: TimeInterval = 40.0

    /// Minimum duration between active-application switch glance reactions (seconds).
    var appSwitchReactionCooldown: TimeInterval = 25.0

    /// Cooldown for replaying the exact same emote (seconds).
    var sameEmoteCooldown: TimeInterval = 30.0

    /// Maximum number of recent autonomous actions stored in the ring buffer.
    var maxActionHistoryCount: Int = 6

    // MARK: - In-Memory State

    private(set) var recentlyVisitedWindows: [CGWindowID: Date] = [:]
    private(set) var recentlyVisitedDockRegions: [CGFloat: Date] = [:]
    private(set) var recentAutonomousActions: [String] = []
    private(set) var recentlyCompletedJumps: [Date] = []
    private(set) var failedNavigationTargets: [String: Date] = [:]
    private(set) var lastDirectInteractionDate: Date = .distantPast
    private(set) var lastAutonomousActionDate: Date = .distantPast
    private(set) var lastAppSwitchReactionDate: Date = .distantPast
    private(set) var lastEmoteId: String?
    private(set) var lastEmoteDate: Date = .distantPast

    /// Seam for time.
    var now: () -> Date = { Date() }

    private let log = Logger(subsystem: "com.cookie.mac", category: "BehaviorMemory")

    init() {}

    // MARK: - Memory Mutations

    /// Records a completed visit to an application window.
    func recordWindowVisit(windowId: CGWindowID) {
        let currentTime = now()
        recentlyVisitedWindows[windowId] = currentTime
        pruneExpiredWindows(currentTime: currentTime)
    }

    /// Records an approach to a specific horizontal Dock region.
    func recordDockVisit(regionX: CGFloat) {
        let currentTime = now()
        // Quantize dock X coordinate into 80pt buckets
        let bucket = (regionX / 80.0).rounded() * 80.0
        recentlyVisitedDockRegions[bucket] = currentTime
        pruneExpiredDockRegions(currentTime: currentTime)
    }

    /// Records an autonomous action identifier in the short-term history buffer.
    func recordAutonomousAction(_ action: String) {
        recentAutonomousActions.append(action)
        if recentAutonomousActions.count > maxActionHistoryCount {
            recentAutonomousActions.removeFirst()
        }
        lastAutonomousActionDate = now()
    }

    /// Records a completed jump.
    func recordJump() {
        recentlyCompletedJumps.append(now())
        // Keep only jumps within the last 2 minutes
        let cutoff = now().addingTimeInterval(-120)
        recentlyCompletedJumps.removeAll(where: { $0 < cutoff })
    }

    /// Records a failed navigation route target to avoid retrying immediately.
    func recordFailedTarget(_ targetId: String) {
        failedNavigationTargets[targetId] = now()
        log.notice("Recorded failed navigation target: \(targetId, privacy: .public)")
    }

    /// Records a direct user interaction (pet, tap, feed, toy, drag).
    func recordDirectInteraction() {
        lastDirectInteractionDate = now()
    }

    /// Records that Cookie glanced or reacted to an active application switch.
    func recordAppSwitchReaction() {
        lastAppSwitchReactionDate = now()
    }

    /// Records an emote playback.
    func recordEmote(id: String) {
        lastEmoteId = id
        lastEmoteDate = now()
    }

    // MARK: - Memory Query & Anti-Repetition Rules

    /// Checks whether a window is on cooldown.
    func isWindowOnCooldown(_ windowId: CGWindowID) -> Bool {
        guard let visitTime = recentlyVisitedWindows[windowId] else { return false }
        return now().timeIntervalSince(visitTime) < windowVisitCooldown
    }

    /// Checks whether a Dock region is on cooldown.
    func isDockRegionOnCooldown(_ regionX: CGFloat) -> Bool {
        let bucket = (regionX / 80.0).rounded() * 80.0
        guard let visitTime = recentlyVisitedDockRegions[bucket] else { return false }
        return now().timeIntervalSince(visitTime) < dockRegionCooldown
    }

    /// Checks whether an action has been repeated recently.
    func isActionRepetitive(_ action: String) -> Bool {
        // If the same action was performed as the last action, or twice in the last 4 actions
        if recentAutonomousActions.last == action { return true }
        let recentCount = recentAutonomousActions.suffix(4).filter({ $0 == action }).count
        return recentCount >= 2
    }

    /// Checks whether a navigation target recently failed.
    func isTargetFailed(_ targetId: String, failureCooldown: TimeInterval = 60.0) -> Bool {
        guard let failTime = failedNavigationTargets[targetId] else { return false }
        return now().timeIntervalSince(failTime) < failureCooldown
    }

    /// Validates whether Cookie is allowed to react to an application switch.
    func canReactToAppSwitch() -> Bool {
        return now().timeIntervalSince(lastAppSwitchReactionDate) >= appSwitchReactionCooldown
    }

    /// Validates whether an emote can be repeated or if it was just performed.
    func canPlayEmote(id: String) -> Bool {
        if lastEmoteId == id {
            return now().timeIntervalSince(lastEmoteDate) >= sameEmoteCooldown
        }
        return true
    }

    /// Time in seconds since the last direct user interaction.
    func timeSinceLastInteraction() -> TimeInterval {
        return now().timeIntervalSince(lastDirectInteractionDate)
    }

    /// Time in seconds since the last autonomous movement.
    func timeSinceLastAutonomousAction() -> TimeInterval {
        return now().timeIntervalSince(lastAutonomousActionDate)
    }

    // MARK: - Cache Pruning

    private func pruneExpiredWindows(currentTime: Date) {
        recentlyVisitedWindows = recentlyVisitedWindows.filter {
            currentTime.timeIntervalSince($0.value) < windowVisitCooldown * 2
        }
    }

    private func pruneExpiredDockRegions(currentTime: Date) {
        recentlyVisitedDockRegions = recentlyVisitedDockRegions.filter {
            currentTime.timeIntervalSince($0.value) < dockRegionCooldown * 2
        }
    }
}
