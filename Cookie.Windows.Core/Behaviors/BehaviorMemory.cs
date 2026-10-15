using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Lightweight, in-memory short-term behavior memory.
/// Tracks recent desktop visits, actions, emotes, and failed targets to prevent
/// repetitive loops without persisting private desktop activity histories.
/// </summary>
public class BehaviorMemory
{
    // Cooldown constants (in seconds)
    public double WindowVisitCooldown { get; set; } = 45.0;
    public double TaskbarRegionCooldown { get; set; } = 40.0;
    public double AppSwitchReactionCooldown { get; set; } = 25.0;
    public double SameEmoteCooldown { get; set; } = 30.0;
    public int MaxActionHistoryCount { get; set; } = 6;

    private readonly Dictionary<IntPtr, DateTime> _recentlyVisitedWindows = new();
    private readonly Dictionary<double, DateTime> _recentlyVisitedTaskbarRegions = new();
    private readonly List<string> _recentAutonomousActions = new();
    private readonly List<DateTime> _recentlyCompletedJumps = new();
    private readonly Dictionary<string, DateTime> _failedNavigationTargets = new();

    public DateTime LastDirectInteractionDate { get; private set; } = DateTime.MinValue;
    public DateTime LastAutonomousActionDate { get; private set; } = DateTime.MinValue;
    public DateTime LastAppSwitchReactionDate { get; private set; } = DateTime.MinValue;
    public EmoteId? LastEmoteId { get; private set; }
    public DateTime LastEmoteDate { get; private set; } = DateTime.MinValue;

    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public IReadOnlyList<string> RecentAutonomousActions => _recentAutonomousActions;

    public void RecordWindowVisit(IntPtr windowHandle)
    {
        var currentTime = Now();
        _recentlyVisitedWindows[windowHandle] = currentTime;
        PruneExpiredWindows(currentTime);
    }

    public void RecordTaskbarVisit(double regionX)
    {
        var currentTime = Now();
        // Quantize taskbar X coordinate into 80 DIP buckets
        double bucket = Math.Round(regionX / 80.0) * 80.0;
        _recentlyVisitedTaskbarRegions[bucket] = currentTime;
        PruneExpiredTaskbarRegions(currentTime);
    }

    public void RecordAutonomousAction(string action)
    {
        _recentAutonomousActions.Add(action);
        if (_recentAutonomousActions.Count > MaxActionHistoryCount)
        {
            _recentAutonomousActions.RemoveAt(0);
        }
        LastAutonomousActionDate = Now();
    }

    public void RecordJump()
    {
        var currentTime = Now();
        _recentlyCompletedJumps.Add(currentTime);
        // Retain only jumps from last 2 minutes
        var cutoff = currentTime.AddSeconds(-120);
        _recentlyCompletedJumps.RemoveAll(t => t < cutoff);
    }

    public void RecordFailedTarget(string targetId)
    {
        _failedNavigationTargets[targetId] = Now();
    }

    public void RecordDirectInteraction()
    {
        LastDirectInteractionDate = Now();
    }

    public void RecordAppSwitchReaction()
    {
        LastAppSwitchReactionDate = Now();
    }

    public void RecordEmote(EmoteId id)
    {
        LastEmoteId = id;
        LastEmoteDate = Now();
    }

    public bool IsWindowOnCooldown(IntPtr windowHandle)
    {
        if (_recentlyVisitedWindows.TryGetValue(windowHandle, out var visitTime))
        {
            return (Now() - visitTime).TotalSeconds < WindowVisitCooldown;
        }
        return false;
    }

    public bool IsTaskbarRegionOnCooldown(double regionX)
    {
        double bucket = Math.Round(regionX / 80.0) * 80.0;
        if (_recentlyVisitedTaskbarRegions.TryGetValue(bucket, out var visitTime))
        {
            return (Now() - visitTime).TotalSeconds < TaskbarRegionCooldown;
        }
        return false;
    }

    public bool IsActionRepetitive(string action)
    {
        // If the same action was performed as the immediate last action, or twice in the last 4 actions
        if (_recentAutonomousActions.Count > 0 && _recentAutonomousActions[^1] == action)
        {
            return true;
        }

        int recentCount = _recentAutonomousActions.TakeLast(4).Count(a => a == action);
        return recentCount >= 2;
    }

    public bool IsTargetFailed(string targetId, double failureCooldown = 60.0)
    {
        if (_failedNavigationTargets.TryGetValue(targetId, out var failTime))
        {
            return (Now() - failTime).TotalSeconds < failureCooldown;
        }
        return false;
    }

    public bool CanReactToAppSwitch()
    {
        return (Now() - LastAppSwitchReactionDate).TotalSeconds >= AppSwitchReactionCooldown;
    }

    public bool CanPlayEmote(EmoteId id)
    {
        if (LastEmoteId == id)
        {
            return (Now() - LastEmoteDate).TotalSeconds >= SameEmoteCooldown;
        }
        return true;
    }

    public double TimeSinceLastInteraction()
    {
        if (LastDirectInteractionDate == DateTime.MinValue) return double.MaxValue;
        return (Now() - LastDirectInteractionDate).TotalSeconds;
    }

    public double TimeSinceLastAutonomousAction()
    {
        if (LastAutonomousActionDate == DateTime.MinValue) return double.MaxValue;
        return (Now() - LastAutonomousActionDate).TotalSeconds;
    }

    public void ClearMemory()
    {
        _recentlyVisitedWindows.Clear();
        _recentlyVisitedTaskbarRegions.Clear();
        _recentAutonomousActions.Clear();
        _recentlyCompletedJumps.Clear();
        _failedNavigationTargets.Clear();
        LastDirectInteractionDate = DateTime.MinValue;
        LastAutonomousActionDate = DateTime.MinValue;
        LastAppSwitchReactionDate = DateTime.MinValue;
        LastEmoteId = null;
        LastEmoteDate = DateTime.MinValue;
    }

    private void PruneExpiredWindows(DateTime currentTime)
    {
        var stale = _recentlyVisitedWindows
            .Where(kvp => (currentTime - kvp.Value).TotalSeconds >= WindowVisitCooldown * 2)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in stale)
        {
            _recentlyVisitedWindows.Remove(key);
        }
    }

    private void PruneExpiredTaskbarRegions(DateTime currentTime)
    {
        var stale = _recentlyVisitedTaskbarRegions
            .Where(kvp => (currentTime - kvp.Value).TotalSeconds >= TaskbarRegionCooldown * 2)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in stale)
        {
            _recentlyVisitedTaskbarRegions.Remove(key);
        }
    }
}
