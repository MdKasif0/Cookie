using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Windows;

/// <summary>
/// Dedicated controller governing Cookie's window discovery, top-edge walking,
/// simulated vertical climbing, corner transitions, and window-to-window jumping.
/// </summary>
public class WindowInteractionController
{
    private readonly Random _random = new();

    public WindowExplorationPhase CurrentPhase { get; private set; } = WindowExplorationPhase.Idle;
    public ObservableWindow? ActiveWindow { get; private set; }
    public WindowEdgePath? CurrentEdgePath { get; private set; }
    public double PathProgress { get; private set; } = 0.0;
    public double PathDirection { get; private set; } = 1.0; // +1.0 walking towards EndPoint, -1.0 towards StartPoint

    public JumpProposal? ActiveJumpProposal { get; private set; }
    public JumpTrajectory? ActiveJumpTrajectory { get; private set; }
    public double JumpProgress { get; private set; } = 0.0;

    public bool IsExploringWindow => CurrentPhase != WindowExplorationPhase.Idle;
    public bool IsAirborne => CurrentPhase == WindowExplorationPhase.Jumping;

    public DateTime CooldownUntil { get; private set; } = DateTime.MinValue;
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public JumpPlanner JumpPlanner { get; }

    private double _phaseElapsed = 0.0;
    private double _phaseDuration = 0.0;
    private double _sessionElapsed = 0.0;
    private double _sessionMaxDuration = 18.0;

    // Movement speed along window edge
    private const double EdgeWalkSpeed = 50.0;
    private const double ClimbSpeed = 35.0;

    public WindowInteractionController(JumpPlanner? jumpPlanner = null)
    {
        JumpPlanner = jumpPlanner ?? new JumpPlanner();
    }

    /// <summary>
    /// Immediately aborts any ongoing Window exploration session (e.g. user dragged Cookie or triggered an emote).
    /// </summary>
    public void CancelExploration()
    {
        CurrentPhase = WindowExplorationPhase.Idle;
        ActiveWindow = null;
        CurrentEdgePath = null;
        ActiveJumpProposal = null;
        ActiveJumpTrajectory = null;
        JumpProgress = 0.0;
        PathProgress = 0.0;
        _phaseElapsed = 0.0;
    }

    /// <summary>
    /// Sets cooldown timer based on user frequency preference.
    /// </summary>
    public void ApplyCooldown(WindowExplorationFrequency frequency)
    {
        var (minSec, maxSec) = frequency switch
        {
            WindowExplorationFrequency.Rare => (180.0, 300.0),
            WindowExplorationFrequency.Occasional => (90.0, 180.0),
            WindowExplorationFrequency.Frequent => (45.0, 90.0),
            _ => (90.0, 180.0)
        };

        double interval = minSec + _random.NextDouble() * (maxSec - minSec);
        CooldownUntil = Now().AddSeconds(interval);
    }

    /// <summary>
    /// Evaluates whether Cookie should autonomously begin approaching a candidate window.
    /// </summary>
    public bool ShouldTriggerAutonomousExploration(
        CorePoint cookiePosition,
        WindowExplorationFrequency frequency,
        bool settingsEnabled,
        bool isInterrupted)
    {
        if (!settingsEnabled || isInterrupted || CurrentPhase != WindowExplorationPhase.Idle)
        {
            return false;
        }

        if (Now() < CooldownUntil)
        {
            return false;
        }

        double probability = frequency switch
        {
            WindowExplorationFrequency.Rare => 0.015,
            WindowExplorationFrequency.Occasional => 0.035,
            WindowExplorationFrequency.Frequent => 0.075,
            _ => 0.035
        };

        return _random.NextDouble() < probability;
    }

    /// <summary>
    /// Selects an eligible visible window and starts the exploration lifecycle.
    /// </summary>
    public bool StartExploration(
        CorePoint currentCookiePos,
        IReadOnlyList<ObservableWindow> visibleWindows,
        WindowExplorationFrequency frequency,
        bool enableVerticalClimbing)
    {
        var eligible = visibleWindows
            .Where(w => !w.IsOccluded && w.Bounds.Width >= 120.0 && w.Bounds.Height >= 100.0)
            .Where(w => !JumpPlanner.IsWindowOnCooldown(w.Handle))
            .OrderBy(w => currentCookiePos.DistanceTo(new CorePoint(w.Bounds.MidX, w.Bounds.Top)))
            .ToList();

        if (eligible.Count == 0) return false;

        var targetWin = eligible.First();
        ActiveWindow = targetWin;

        _sessionElapsed = 0.0;
        _sessionMaxDuration = frequency switch
        {
            WindowExplorationFrequency.Rare => 12.0,
            WindowExplorationFrequency.Occasional => 18.0,
            WindowExplorationFrequency.Frequent => 24.0,
            _ => 18.0
        };

        double footOffset = 14.0;
        double cornerInset = 25.0;
        var startPt = new CorePoint(targetWin.Bounds.Left + cornerInset, targetWin.Bounds.Top - footOffset);
        var endPt = new CorePoint(targetWin.Bounds.Right - cornerInset, targetWin.Bounds.Top - footOffset);

        CurrentEdgePath = new WindowEdgePath(
            $"win-{targetWin.Handle}-top",
            targetWin.Handle,
            targetWin.Title,
            WindowEdgeType.TopHorizontal,
            startPt,
            endPt,
            targetWin.Bounds,
            footOffset);

        // Anticipate briefly
        CurrentPhase = WindowExplorationPhase.Anticipating;
        _phaseElapsed = 0.0;
        _phaseDuration = 0.8 + _random.NextDouble() * 0.4;

        return true;
    }

    /// <summary>
    /// Directly mounts Cookie onto a specified window surface (e.g. after a jump or spawn).
    /// </summary>
    public void MountOnWindow(ObservableWindow window, CorePoint landingPoint)
    {
        ActiveWindow = window;
        double footOffset = 14.0;
        double cornerInset = 25.0;

        var startPt = new CorePoint(window.Bounds.Left + cornerInset, window.Bounds.Top - footOffset);
        var endPt = new CorePoint(window.Bounds.Right - cornerInset, window.Bounds.Top - footOffset);

        CurrentEdgePath = new WindowEdgePath(
            $"win-{window.Handle}-top",
            window.Handle,
            window.Title,
            WindowEdgeType.TopHorizontal,
            startPt,
            endPt,
            window.Bounds,
            footOffset);

        var (closest, progress) = CurrentEdgePath.ClosestPoint(landingPoint);
        PathProgress = progress;
        PathDirection = (progress < 0.5) ? 1.0 : -1.0;

        CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
        _phaseElapsed = 0.0;
        _sessionElapsed = 0.0;
        _sessionMaxDuration = 18.0;
    }

    /// <summary>
    /// Main update loop for window exploration and jump execution.
    /// Returns the updated 2D position for Cookie.
    /// </summary>
    public CorePoint? Update(
        double deltaTimeSeconds,
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment,
        CookieSettings settings)
    {
        if (CurrentPhase == WindowExplorationPhase.Idle)
        {
            return null;
        }

        _sessionElapsed += deltaTimeSeconds;
        _phaseElapsed += deltaTimeSeconds;

        // 1. Verify Active Window validity if attached to one
        if (ActiveWindow != null && CurrentPhase is not (WindowExplorationPhase.Jumping or WindowExplorationPhase.Departing))
        {
            var currentLive = environment.Windows.FirstOrDefault(w => w.Handle == ActiveWindow.Handle);
            if (currentLive == null)
            {
                // Active window was closed or destroyed! Handle gracefully with safety recovery.
                return HandleWindowInvalidated(currentCookiePos, companionSize, environment);
            }

            // Check if window moved significantly
            double moveDist = currentLive.Bounds.Left - ActiveWindow.Bounds.Left;
            double moveDistY = currentLive.Bounds.Top - ActiveWindow.Bounds.Top;
            if (Math.Abs(moveDist) > 30.0 || Math.Abs(moveDistY) > 30.0)
            {
                // Window moved beneath Cookie: update bounds or safely dismount
                ActiveWindow = currentLive;
                return HandleWindowInvalidated(currentCookiePos, companionSize, environment);
            }
            ActiveWindow = currentLive;
        }

        // 2. Handle airborne jump
        if (CurrentPhase == WindowExplorationPhase.Jumping)
        {
            return UpdateJump(deltaTimeSeconds, currentCookiePos, companionSize, environment);
        }

        // 3. Handle session duration expiration
        if (_sessionElapsed >= _sessionMaxDuration && CurrentPhase != WindowExplorationPhase.Departing)
        {
            CurrentPhase = WindowExplorationPhase.Departing;
            _phaseElapsed = 0.0;
            _phaseDuration = 2.0;
        }

        switch (CurrentPhase)
        {
            case WindowExplorationPhase.Anticipating:
                if (_phaseElapsed >= _phaseDuration)
                {
                    CurrentPhase = WindowExplorationPhase.Approaching;
                    _phaseElapsed = 0.0;
                }
                return null;

            case WindowExplorationPhase.Approaching:
                if (CurrentEdgePath != null)
                {
                    // Approach nearest endpoint of top edge
                    var targetPt = PathDirection > 0 ? CurrentEdgePath.StartPoint : CurrentEdgePath.EndPoint;
                    double dist = currentCookiePos.DistanceTo(targetPt);

                    if (dist < 10.0)
                    {
                        CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
                        PathProgress = (PathDirection > 0) ? 0.0 : 1.0;
                        _phaseElapsed = 0.0;
                    }
                    else
                    {
                        // Step towards entry point
                        double step = EdgeWalkSpeed * deltaTimeSeconds;
                        double dx = targetPt.X - currentCookiePos.X;
                        double dy = targetPt.Y - currentCookiePos.Y;
                        double len = Math.Sqrt(dx * dx + dy * dy);
                        return new CorePoint(currentCookiePos.X + (dx / len) * step, currentCookiePos.Y + (dy / len) * step);
                    }
                }
                return null;

            case WindowExplorationPhase.WalkingTopEdge:
                return UpdateWalkingTopEdge(deltaTimeSeconds, currentCookiePos, environment, settings);

            case WindowExplorationPhase.CornerTransition:
                if (_phaseElapsed >= _phaseDuration)
                {
                    // After brief pause at corner, check for jump opportunity or turn around
                    if (settings.WindowJumpingEnabled && ConsiderJumpAtCorner(currentCookiePos, environment, settings))
                    {
                        return null; // Preparing jump
                    }

                    if (settings.WindowVerticalClimbing && _random.Next(0, 3) == 0 && ActiveWindow != null)
                    {
                        // Transition to simulated vertical climb
                        StartVerticalClimb(currentCookiePos);
                        return null;
                    }

                    // Turn around and walk top edge in reverse
                    PathDirection = -PathDirection;
                    CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
                    _phaseElapsed = 0.0;
                }
                return null;

            case WindowExplorationPhase.ClimbingVerticalEdge:
                return UpdateVerticalClimb(deltaTimeSeconds, currentCookiePos);

            case WindowExplorationPhase.PreparingJump:
                if (_phaseElapsed >= _phaseDuration)
                {
                    // Launch jump
                    LaunchPreparedJump(environment);
                }
                return null;

            case WindowExplorationPhase.Landing:
                if (_phaseElapsed >= _phaseDuration)
                {
                    CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
                    _phaseElapsed = 0.0;
                }
                return null;

            case WindowExplorationPhase.Departing:
                if (ActiveWindow != null)
                {
                    // Return safely to desktop floor
                    ApplyCooldown(settings.WindowExplorationFrequency);
                    var floorPos = DesktopCoordinateSpace.ClampToWorkArea(
                        new CorePoint(currentCookiePos.X, environment.PrimaryMonitor.WorkArea.Bottom - companionSize.Height - 10),
                        companionSize,
                        environment.PrimaryMonitor.WorkArea);

                    CancelExploration();
                    return floorPos;
                }
                CancelExploration();
                return null;

            default:
                return null;
        }
    }

    private CorePoint? UpdateWalkingTopEdge(
        double deltaTimeSeconds,
        CorePoint currentCookiePos,
        DesktopEnvironment environment,
        CookieSettings settings)
    {
        if (CurrentEdgePath == null) return null;

        double pathLen = Math.Max(1.0, CurrentEdgePath.Length);
        double deltaProgress = (EdgeWalkSpeed * deltaTimeSeconds / pathLen) * PathDirection;
        PathProgress += deltaProgress;

        if (PathProgress >= 1.0 || PathProgress <= 0.0)
        {
            // Reached a corner!
            PathProgress = Math.Clamp(PathProgress, 0.0, 1.0);
            var cornerPoint = CurrentEdgePath.PointAt(PathProgress);

            CurrentPhase = WindowExplorationPhase.CornerTransition;
            _phaseElapsed = 0.0;
            _phaseDuration = 0.7 + _random.NextDouble() * 0.5;

            return cornerPoint;
        }

        return CurrentEdgePath.PointAt(PathProgress);
    }

    private void StartVerticalClimb(CorePoint currentPos)
    {
        if (ActiveWindow == null) return;

        bool isLeft = PathProgress <= 0.5;
        double footOffset = 14.0;
        var b = ActiveWindow.Bounds;

        var startPt = isLeft
            ? new CorePoint(b.Left - footOffset, b.Top)
            : new CorePoint(b.Right, b.Top);

        var endPt = isLeft
            ? new CorePoint(b.Left - footOffset, Math.Min(b.Bottom - 40, b.Top + 140))
            : new CorePoint(b.Right, Math.Min(b.Bottom - 40, b.Top + 140));

        CurrentEdgePath = new WindowEdgePath(
            $"win-{ActiveWindow.Handle}-climb",
            ActiveWindow.Handle,
            ActiveWindow.Title,
            isLeft ? WindowEdgeType.LeftVertical : WindowEdgeType.RightVertical,
            startPt,
            endPt,
            ActiveWindow.Bounds,
            footOffset);

        CurrentPhase = WindowExplorationPhase.ClimbingVerticalEdge;
        PathProgress = 0.0;
        PathDirection = 1.0;
        _phaseElapsed = 0.0;
    }

    private CorePoint? UpdateVerticalClimb(double deltaTimeSeconds, CorePoint currentCookiePos)
    {
        if (CurrentEdgePath == null) return null;

        double pathLen = Math.Max(1.0, CurrentEdgePath.Length);
        double deltaProgress = (ClimbSpeed * deltaTimeSeconds / pathLen) * PathDirection;
        PathProgress += deltaProgress;

        if (PathProgress >= 1.0)
        {
            // Reached bottom of climb corridor, climb back up
            PathProgress = 1.0;
            PathDirection = -1.0;
        }
        else if (PathProgress <= 0.0)
        {
            // Climbed back to top corner
            PathProgress = 0.0;
            CurrentPhase = WindowExplorationPhase.CornerTransition;
            _phaseElapsed = 0.0;
            _phaseDuration = 0.6;
        }

        return CurrentEdgePath.PointAt(PathProgress);
    }

    private bool ConsiderJumpAtCorner(
        CorePoint currentCookiePos,
        DesktopEnvironment environment,
        CookieSettings settings)
    {
        double triggerProb = settings.JumpFrequency switch
        {
            JumpFrequency.Calm => 0.20,
            JumpFrequency.Balanced => 0.45,
            JumpFrequency.Playful => 0.70,
            _ => 0.45
        };

        if (_random.NextDouble() > triggerProb)
        {
            return false;
        }

        var candidateSurfaces = JumpPlanner.ExtractJumpSurfaces(
            environment.Windows,
            environment.PrimaryMonitor.WorkArea,
            environment.PrimaryTaskbar?.SafeWalkingSurface);

        var proposal = JumpPlanner.EvaluateBestJump(
            currentCookiePos,
            ActiveWindow?.Handle,
            candidateSurfaces,
            settings.JumpStyle);

        if (proposal != null && proposal.IsSafe)
        {
            ActiveJumpProposal = proposal;
            CurrentPhase = WindowExplorationPhase.PreparingJump;
            _phaseElapsed = 0.0;
            _phaseDuration = 0.45; // Crouch anticipation
            return true;
        }

        return false;
    }

    private void LaunchPreparedJump(DesktopEnvironment environment)
    {
        if (ActiveJumpProposal == null)
        {
            CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
            return;
        }

        // Validate destination window hasn't moved or closed before takeoff
        if (ActiveJumpProposal.TargetSurface.WindowHandle.HasValue)
        {
            var liveTarget = environment.Windows.FirstOrDefault(w => w.Handle == ActiveJumpProposal.TargetSurface.WindowHandle.Value);
            if (liveTarget == null)
            {
                // Target window closed! Abort jump safely before takeoff.
                ActiveJumpProposal = null;
                CurrentPhase = WindowExplorationPhase.WalkingTopEdge;
                return;
            }
        }

        ActiveJumpTrajectory = new JumpTrajectory(
            ActiveJumpProposal.StartPoint,
            ActiveJumpProposal.TargetSurface.LandingPoint,
            ActiveJumpProposal.JumpDuration,
            ActiveJumpProposal.ApexHeight,
            ActiveJumpProposal.Style);

        JumpProgress = 0.0;
        CurrentPhase = WindowExplorationPhase.Jumping;
        _phaseElapsed = 0.0;
    }

    private CorePoint UpdateJump(
        double deltaTimeSeconds,
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment)
    {
        if (ActiveJumpTrajectory == null)
        {
            CurrentPhase = WindowExplorationPhase.Idle;
            return currentCookiePos;
        }

        double deltaP = deltaTimeSeconds / ActiveJumpTrajectory.Duration;
        JumpProgress = Math.Clamp(JumpProgress + deltaP, 0.0, 1.0);

        // Check if destination window was invalidated mid-flight
        if (ActiveJumpProposal?.TargetSurface.WindowHandle != null)
        {
            var live = environment.Windows.FirstOrDefault(w => w.Handle == ActiveJumpProposal.TargetSurface.WindowHandle.Value);
            if (live == null)
            {
                // Mid-jump invalidation: redirect smoothly down to ground floor rather than snapping!
                return HandleMidJumpInvalidation(currentCookiePos, companionSize, environment);
            }
        }

        var nextPoint = ActiveJumpTrajectory.PointAt(JumpProgress);

        if (JumpProgress >= 1.0)
        {
            // Touchdown!
            JumpPlanner.RecordJumpCompleted(ActiveJumpProposal?.TargetSurface.WindowHandle);

            if (ActiveJumpProposal?.TargetSurface.WindowHandle != null)
            {
                var targetWin = environment.Windows.FirstOrDefault(w => w.Handle == ActiveJumpProposal.TargetSurface.WindowHandle.Value);
                if (targetWin != null)
                {
                    MountOnWindow(targetWin, nextPoint);
                    CurrentPhase = WindowExplorationPhase.Landing;
                    _phaseElapsed = 0.0;
                    _phaseDuration = 0.35;
                    ActiveJumpProposal = null;
                    ActiveJumpTrajectory = null;
                    return nextPoint;
                }
            }

            // Landed on ground or dock
            CurrentPhase = WindowExplorationPhase.Landing;
            _phaseElapsed = 0.0;
            _phaseDuration = 0.35;
            ActiveWindow = null;
            CurrentEdgePath = null;
            ActiveJumpProposal = null;
            ActiveJumpTrajectory = null;
        }

        return nextPoint;
    }

    private CorePoint HandleMidJumpInvalidation(
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment)
    {
        // Smooth downward safety arc to floor
        var floorPos = DesktopCoordinateSpace.ClampToWorkArea(
            new CorePoint(currentCookiePos.X, environment.PrimaryMonitor.WorkArea.Bottom - companionSize.Height - 10),
            companionSize,
            environment.PrimaryMonitor.WorkArea);

        ActiveJumpTrajectory = new JumpTrajectory(
            currentCookiePos,
            floorPos,
            0.4,
            15.0,
            JumpStyle.Gentle);

        JumpProgress = 0.0;
        ActiveJumpProposal = null;
        ActiveWindow = null;
        CurrentEdgePath = null;

        return currentCookiePos;
    }

    private CorePoint HandleWindowInvalidated(
        CorePoint currentCookiePos,
        CoreSize companionSize,
        DesktopEnvironment environment)
    {
        CancelExploration();
        ApplyCooldown(WindowExplorationFrequency.Occasional);

        // Safe recovery drop to floor
        return DesktopCoordinateSpace.ClampToWorkArea(
            new CorePoint(currentCookiePos.X, environment.PrimaryMonitor.WorkArea.Bottom - companionSize.Height - 10),
            companionSize,
            environment.PrimaryMonitor.WorkArea);
    }
}
