using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// Dedicated controller governing Cookie's intelligent interactions with the Windows Taskbar,
/// including natural approach, safe edge pacing, general application icon awareness, gaze orientation,
/// and cursor-taskbar coordination.
/// </summary>
public class TaskbarInteractionController
{
    private readonly Random _random = new();

    public TaskbarSessionPhase CurrentPhase { get; private set; } = TaskbarSessionPhase.Idle;
    public CorePoint? DestinationPoint { get; private set; }
    public TaskbarInspectionTarget? ActiveInspectionTarget { get; private set; }
    public double? TaskbarLookAngle { get; private set; }
    public CookieReaction? PlayfulReaction { get; private set; }

    public bool IsExploringTaskbar => CurrentPhase != TaskbarSessionPhase.Idle;
    public DateTime CooldownUntil { get; private set; } = DateTime.MinValue;

    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    private double _phaseElapsed = 0.0;
    private double _phaseDuration = 0.0;
    private double _sessionElapsed = 0.0;
    private double _sessionMaxDuration = 12.0;
    private List<TaskbarInspectionTarget> _inspectionTargets = new();

    public TaskbarInteractionController()
    {
    }

    /// <summary>
    /// Immediately aborts any ongoing Taskbar exploration session (e.g. user dragged Cookie or triggered an emote).
    /// </summary>
    public void CancelExploration()
    {
        CurrentPhase = TaskbarSessionPhase.Idle;
        DestinationPoint = null;
        ActiveInspectionTarget = null;
        TaskbarLookAngle = null;
        PlayfulReaction = null;
        _phaseElapsed = 0.0;
    }

    /// <summary>
    /// Sets cooldown timer based on user frequency preference.
    /// </summary>
    public void ApplyCooldown(DockExplorationFrequency frequency)
    {
        var (minSec, maxSec) = frequency switch
        {
            DockExplorationFrequency.Rare => (180.0, 300.0),
            DockExplorationFrequency.Occasional => (90.0, 180.0),
            DockExplorationFrequency.Frequent => (45.0, 90.0),
            _ => (90.0, 180.0)
        };

        double interval = minSec + _random.NextDouble() * (maxSec - minSec);
        CooldownUntil = Now().AddSeconds(interval);
    }

    /// <summary>
    /// Builds estimated inspection targets along the Taskbar span using running visible application windows.
    /// Avoids inspecting internal Explorer process memory.
    /// </summary>
    public void RefreshInspectionTargets(DesktopEnvironment environment, IReadOnlyList<ObservableWindow> runningWindows)
    {
        var targets = new List<TaskbarInspectionTarget>();
        var taskbar = environment.PrimaryTaskbar;

        if (taskbar == null || taskbar.TaskbarBounds.IsEmpty)
        {
            _inspectionTargets = targets;
            return;
        }

        var tbFrame = taskbar.TaskbarBounds;
        var distinctApps = runningWindows
            .Where(w => !string.IsNullOrWhiteSpace(w.ProcessName) && w.ProcessName != "Cookie.Windows")
            .GroupBy(w => w.ProcessName)
            .Select(g => g.First())
            .Take(8)
            .ToList();

        int appCount = Math.Max(3, Math.Min(distinctApps.Count, 8));

        if (taskbar.IsHorizontal)
        {
            double centerSpan = tbFrame.Width * 0.65;
            double startX = tbFrame.MidX - (centerSpan / 2.0);
            double step = centerSpan / (appCount + 1);
            double y = tbFrame.MidY;

            for (int i = 0; i < appCount; i++)
            {
                double x = startX + ((i + 1) * step);
                string label = i < distinctApps.Count ? distinctApps[i].Title : $"App {i + 1}";
                string? proc = i < distinctApps.Count ? distinctApps[i].ProcessName : null;
                targets.Add(new TaskbarInspectionTarget(new CorePoint(x, y), label, proc));
            }
        }
        else
        {
            double centerSpan = tbFrame.Height * 0.65;
            double startY = tbFrame.MidY - (centerSpan / 2.0);
            double step = centerSpan / (appCount + 1);
            double x = tbFrame.MidX;

            for (int i = 0; i < appCount; i++)
            {
                double y = startY + ((i + 1) * step);
                string label = i < distinctApps.Count ? distinctApps[i].Title : $"App {i + 1}";
                string? proc = i < distinctApps.Count ? distinctApps[i].ProcessName : null;
                targets.Add(new TaskbarInspectionTarget(new CorePoint(x, y), label, proc));
            }
        }

        _inspectionTargets = targets;
    }

    /// <summary>
    /// Evaluates whether Cookie should autonomously begin approaching the Taskbar.
    /// </summary>
    public bool ShouldTriggerAutonomousExploration(
        CorePoint cookiePosition,
        DockExplorationFrequency frequency,
        bool settingsEnabled,
        bool isInterrupted)
    {
        if (!settingsEnabled || isInterrupted || CurrentPhase != TaskbarSessionPhase.Idle)
        {
            return false;
        }

        if (Now() < CooldownUntil)
        {
            return false;
        }

        double probability = frequency switch
        {
            DockExplorationFrequency.Rare => 0.015,
            DockExplorationFrequency.Occasional => 0.035,
            DockExplorationFrequency.Frequent => 0.070,
            _ => 0.035
        };

        return _random.NextDouble() < probability;
    }

    /// <summary>
    /// Initiates an autonomous Taskbar exploration session.
    /// </summary>
    public void StartExploration(
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment,
        IReadOnlyList<ObservableWindow> runningWindows,
        DockExplorationFrequency frequency)
    {
        RefreshInspectionTargets(environment, runningWindows);

        var taskbar = environment.PrimaryTaskbar;
        if (taskbar == null) return;

        _sessionElapsed = 0.0;
        _sessionMaxDuration = frequency switch
        {
            DockExplorationFrequency.Rare => 8.0,
            DockExplorationFrequency.Occasional => 12.0,
            DockExplorationFrequency.Frequent => 16.0,
            _ => 12.0
        };

        CurrentPhase = TaskbarSessionPhase.Anticipating;
        _phaseElapsed = 0.0;
        _phaseDuration = 0.8 + _random.NextDouble() * 0.5;

        // Subtle look toward the taskbar
        TaskbarLookAngle = taskbar.Orientation == TaskbarOrientation.Bottom ? 0.15 : -0.15;
    }

    /// <summary>
    /// Updates the Taskbar session state machine and returns the next target position if walking.
    /// </summary>
    public CorePoint? Update(
        double deltaTimeSeconds,
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment,
        CorePoint? cursorPos = null)
    {
        if (CurrentPhase == TaskbarSessionPhase.Idle)
        {
            return null;
        }

        _sessionElapsed += deltaTimeSeconds;
        _phaseElapsed += deltaTimeSeconds;

        var taskbar = environment.PrimaryTaskbar;
        if (taskbar == null)
        {
            CancelExploration();
            return null;
        }

        // If session duration expired, smoothly depart
        if (_sessionElapsed >= _sessionMaxDuration && CurrentPhase != TaskbarSessionPhase.Departing)
        {
            TransitionToDeparting(currentCookiePos, companionSize, environment);
        }

        switch (CurrentPhase)
        {
            case TaskbarSessionPhase.Anticipating:
                if (_phaseElapsed >= _phaseDuration)
                {
                    // Transition to approaching safe walking surface
                    var targetPoint = environment.ClampToTaskbarWalkingSurface(currentCookiePos, companionSize);
                    DestinationPoint = targetPoint;
                    CurrentPhase = TaskbarSessionPhase.Approaching;
                    _phaseElapsed = 0.0;
                    _phaseDuration = 4.0;
                }
                return null;

            case TaskbarSessionPhase.Approaching:
                if (DestinationPoint.HasValue)
                {
                    double dist = currentCookiePos.DistanceTo(DestinationPoint.Value);
                    if (dist < 10.0 || _phaseElapsed >= _phaseDuration)
                    {
                        // Reached safe edge corridor, begin pacing or inspecting
                        SelectNextEdgeActivity(currentCookiePos, companionSize, environment);
                    }
                }
                return DestinationPoint;

            case TaskbarSessionPhase.PacingEdge:
                if (DestinationPoint.HasValue)
                {
                    double dist = currentCookiePos.DistanceTo(DestinationPoint.Value);
                    if (dist < 8.0 || _phaseElapsed >= _phaseDuration)
                    {
                        SelectNextEdgeActivity(currentCookiePos, companionSize, environment);
                    }
                }
                return DestinationPoint;

            case TaskbarSessionPhase.InspectingArea:
                if (_phaseElapsed >= _phaseDuration)
                {
                    SelectNextEdgeActivity(currentCookiePos, companionSize, environment);
                }
                return null;

            case TaskbarSessionPhase.Departing:
                if (DestinationPoint.HasValue)
                {
                    double dist = currentCookiePos.DistanceTo(DestinationPoint.Value);
                    if (dist < 10.0 || _phaseElapsed >= _phaseDuration)
                    {
                        // Concluded exploration
                        ApplyCooldown(DockExplorationFrequency.Occasional);
                        CancelExploration();
                    }
                }
                return DestinationPoint;

            default:
                return null;
        }
    }

    private void SelectNextEdgeActivity(CorePoint currentPos, CoreSize companionSize, DesktopEnvironment environment)
    {
        _phaseElapsed = 0.0;

        if (_inspectionTargets.Count > 0 && _random.Next(0, 2) == 0)
        {
            // Inspect an application region
            var target = _inspectionTargets[_random.Next(0, _inspectionTargets.Count)];
            ActiveInspectionTarget = target;
            CurrentPhase = TaskbarSessionPhase.InspectingArea;
            _phaseDuration = 1.2 + _random.NextDouble() * 1.5;
            TaskbarLookAngle = target.ScreenPoint.X > currentPos.X ? 0.12 : -0.12;
            DestinationPoint = null;
        }
        else
        {
            // Pace along safe surface
            ActiveInspectionTarget = null;
            TaskbarLookAngle = null;
            CurrentPhase = TaskbarSessionPhase.PacingEdge;
            _phaseDuration = 3.0 + _random.NextDouble() * 2.0;

            double offset = (_random.NextDouble() * 160.0 + 40.0) * (_random.Next(0, 2) == 0 ? -1.0 : 1.0);
            var proposed = new CorePoint(currentPos.X + offset, currentPos.Y);
            DestinationPoint = environment.ClampToTaskbarWalkingSurface(proposed, companionSize);
        }
    }

    private void TransitionToDeparting(CorePoint currentPos, CoreSize companionSize, DesktopEnvironment environment)
    {
        CurrentPhase = TaskbarSessionPhase.Departing;
        _phaseElapsed = 0.0;
        _phaseDuration = 3.5;
        ActiveInspectionTarget = null;
        TaskbarLookAngle = null;

        var taskbar = environment.PrimaryTaskbar;
        double departY = currentPos.Y;
        if (taskbar != null)
        {
            departY = taskbar.Orientation == TaskbarOrientation.Bottom
                ? currentPos.Y - 60.0
                : currentPos.Y + 60.0;
        }

        var proposedDepart = new CorePoint(currentPos.X, departY);
        DestinationPoint = DesktopCoordinateSpace.ClampToWorkArea(proposedDepart, companionSize, environment.PrimaryMonitor.WorkArea);
    }
}
