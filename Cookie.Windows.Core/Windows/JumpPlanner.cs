using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Windows;

/// <summary>
/// Evaluates reachability, feasibility, safety limits, and anti-bounce routing
/// for Cookie's window-to-window and desktop surface jumping maneuvers.
/// </summary>
public class JumpPlanner
{
    // MARK: - Tuned Physical Limits

    /// <summary>
    /// Maximum horizontal travel distance for a believable, grounded leap (in DIPs).
    /// </summary>
    public double MaxHorizontalDistance { get; set; } = 340.0;

    /// <summary>
    /// Minimum horizontal distance before a jump is warranted (closer is a stroll).
    /// </summary>
    public double MinHorizontalDistance { get; set; } = 35.0;

    /// <summary>
    /// Maximum vertical reach when leaping upward to a higher surface.
    /// </summary>
    public double MaxVerticalUp { get; set; } = 175.0;

    /// <summary>
    /// Maximum vertical drop when jumping down to a lower surface or desktop ground.
    /// </summary>
    public double MaxVerticalDown { get; set; } = 260.0;

    /// <summary>
    /// Minimum landing width required so Cookie does not land off an edge.
    /// </summary>
    public double MinLandingWidth { get; set; } = 75.0;

    /// <summary>
    /// Cookie's effective collision width.
    /// </summary>
    public double CookieCollisionWidth { get; set; } = 60.0;

    /// <summary>
    /// Cookie's effective collision height.
    /// </summary>
    public double CookieCollisionHeight { get; set; } = 70.0;

    /// <summary>
    /// Maximum consecutive jumps before Cookie takes a rest or strolls.
    /// </summary>
    public int MaxConsecutiveJumps { get; set; } = 2;

    /// <summary>
    /// Anti-ping-pong cooldown in seconds for recently visited windows.
    /// </summary>
    public double WindowVisitCooldown { get; set; } = 45.0;

    // MARK: - State Memory & Clocks

    private readonly Dictionary<IntPtr, DateTime> _recentlyVisitedWindows = new();
    public int ConsecutiveJumpCount { get; private set; } = 0;
    public DateTime LastJumpTime { get; private set; } = DateTime.MinValue;

    /// <summary>
    /// Seam for deterministic testing.
    /// </summary>
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    // MARK: - Surface Extraction

    /// <summary>
    /// Extracts valid jump target surfaces from candidate windows, desktop ground, and taskbars.
    /// </summary>
    public List<JumpTargetSurface> ExtractJumpSurfaces(
        IEnumerable<ObservableWindow> windows,
        CoreRect? workArea = null,
        CoreRect? taskbarSurface = null)
    {
        var surfaces = new List<JumpTargetSurface>();

        foreach (var win in windows)
        {
            if (win.IsOccluded) continue;

            var b = win.Bounds;
            double footOffset = 14.0;
            double cornerInset = 25.0;
            double availableWidth = Math.Max(0, b.Width - (cornerInset * 2));

            if (availableWidth < MinLandingWidth) continue;

            // In Windows coordinates, character stands above the top edge:
            // Feet are at win.Top, companion top is at win.Top - companionHeight + footOffset
            // Landing point represents where Cookie's top-left or reference position lands
            double landingY = b.Top - footOffset;

            // 1. Top Edge Landing Zone
            surfaces.Add(new JumpTargetSurface(
                $"win-{win.Handle}-topLanding",
                win.Handle,
                win.Title,
                JumpSurfaceKind.WindowTopEdge,
                b,
                new CorePoint(b.MidX, landingY),
                availableWidth,
                footOffset));

            // 2. Top-Left Corner
            surfaces.Add(new JumpTargetSurface(
                $"win-{win.Handle}-tlCorner",
                win.Handle,
                win.Title,
                JumpSurfaceKind.WindowCorner,
                b,
                new CorePoint(b.Left + cornerInset, landingY),
                availableWidth,
                footOffset));

            // 3. Top-Right Corner
            surfaces.Add(new JumpTargetSurface(
                $"win-{win.Handle}-trCorner",
                win.Handle,
                win.Title,
                JumpSurfaceKind.WindowCorner,
                b,
                new CorePoint(b.Right - cornerInset, landingY),
                availableWidth,
                footOffset));
        }

        // 4. Desktop Ground Surface
        if (workArea.HasValue && !workArea.Value.IsEmpty)
        {
            var vis = workArea.Value;
            double groundY = vis.Bottom - 60.0;
            surfaces.Add(new JumpTargetSurface(
                "desktop-ground",
                null,
                "Desktop",
                JumpSurfaceKind.DesktopGround,
                vis,
                new CorePoint(vis.MidX, groundY),
                vis.Width,
                0.0));
        }

        // 5. Taskbar-Adjacent Surface
        if (taskbarSurface.HasValue && !taskbarSurface.Value.IsEmpty)
        {
            var tb = taskbarSurface.Value;
            surfaces.Add(new JumpTargetSurface(
                "taskbar-surface",
                null,
                "Taskbar",
                JumpSurfaceKind.TaskbarEdge,
                tb,
                new CorePoint(tb.MidX, tb.Top),
                tb.Width,
                10.0));
        }

        return surfaces;
    }

    // MARK: - Feasibility Evaluation

    /// <summary>
    /// Evaluates candidate surfaces and produces the best safe jump proposal, if one exists.
    /// </summary>
    public JumpProposal? EvaluateBestJump(
        CorePoint startPoint,
        IntPtr? currentWindowHandle,
        IReadOnlyList<JumpTargetSurface> surfaces,
        JumpStyle style = JumpStyle.Gentle,
        bool force = false)
    {
        var proposals = EvaluateAllJumps(startPoint, currentWindowHandle, surfaces, style, force);

        return proposals
            .Where(p => p.IsSafe)
            .OrderByDescending(p => p.TargetSurface.SurfaceKind.IsWindowSurface())
            .ThenBy(p => p.TotalEuclideanDistance)
            .FirstOrDefault();
    }

    /// <summary>
    /// Evaluates all candidate surfaces and returns proposals with safety status and diagnostics.
    /// </summary>
    public List<JumpProposal> EvaluateAllJumps(
        CorePoint startPoint,
        IntPtr? currentWindowHandle,
        IReadOnlyList<JumpTargetSurface> surfaces,
        JumpStyle style = JumpStyle.Gentle,
        bool force = false)
    {
        PruneStaleCooldowns();

        var results = new List<JumpProposal>();

        foreach (var surface in surfaces)
        {
            // 1. Exclude surfaces belonging to the window Cookie is currently on
            if (currentWindowHandle.HasValue &&
                surface.WindowHandle.HasValue &&
                currentWindowHandle.Value == surface.WindowHandle.Value)
            {
                continue;
            }

            // 2. Adjust landing target within safe edge corridor
            var landingPt = surface.LandingPoint;
            if (surface.SurfaceKind == JumpSurfaceKind.WindowTopEdge && surface.Bounds.Width > 0)
            {
                double inset = 25.0;
                double minX = surface.Bounds.Left + inset;
                double maxX = surface.Bounds.Right - inset;
                if (minX <= maxX)
                {
                    landingPt = new CorePoint(Math.Clamp(surface.LandingPoint.X, minX, maxX), landingPt.Y);
                }
            }
            else if (surface.SurfaceKind == JumpSurfaceKind.DesktopGround)
            {
                landingPt = new CorePoint(startPoint.X, surface.LandingPoint.Y);
            }

            double dx = landingPt.X - startPoint.X;
            double dy = landingPt.Y - startPoint.Y;
            double horizDist = Math.Abs(dx);
            double totalDist = Math.Sqrt(dx * dx + dy * dy);

            // In Windows coordinates (Y increases downwards):
            // - If dy < 0, landingPt is ABOVE startPoint -> Upward leap of (-dy) DIPs
            // - If dy > 0, landingPt is BELOW startPoint -> Downward drop of (+dy) DIPs
            double upwardReach = -dy;
            double downwardDrop = dy;

            string? rejectionReason = null;

            if (surface.LandingWidth < MinLandingWidth)
            {
                rejectionReason = $"Landing surface too narrow ({surface.LandingWidth:F0} < {MinLandingWidth:F0})";
            }
            else if (horizDist > MaxHorizontalDistance)
            {
                rejectionReason = $"Horizontal distance exceeds reach ({horizDist:F0} > {MaxHorizontalDistance:F0})";
            }
            else if (horizDist < MinHorizontalDistance && Math.Abs(dy) < 25.0)
            {
                rejectionReason = "Distance too short for a jump — prefer walking";
            }
            else if (upwardReach > 0 && upwardReach > MaxVerticalUp)
            {
                rejectionReason = $"Upward vertical leap too high ({upwardReach:F0} > {MaxVerticalUp:F0})";
            }
            else if (downwardDrop > 0 && downwardDrop > MaxVerticalDown)
            {
                rejectionReason = $"Downward drop exceeds safe limit ({downwardDrop:F0} > {MaxVerticalDown:F0})";
            }
            else if (!force && surface.WindowHandle.HasValue && IsWindowOnCooldown(surface.WindowHandle.Value))
            {
                rejectionReason = "Target window recently visited (anti-bounce cooldown active)";
            }
            else if (!force && ConsecutiveJumpCount >= MaxConsecutiveJumps)
            {
                rejectionReason = $"Consecutive jump limit reached ({ConsecutiveJumpCount}/{MaxConsecutiveJumps})";
            }

            // Trajectory duration & apex calculations
            double duration;
            double apexHeight;

            switch (style)
            {
                case JumpStyle.Gentle:
                    duration = Math.Clamp(0.45 + totalDist * 0.0014, 0.65, 0.92);
                    apexHeight = Math.Clamp(28.0 + totalDist * 0.11, 28.0, 65.0);
                    break;
                case JumpStyle.Playful:
                default:
                    duration = Math.Clamp(0.40 + totalDist * 0.0012, 0.60, 0.85);
                    apexHeight = Math.Clamp(45.0 + totalDist * 0.17, 45.0, 95.0);
                    break;
            }

            var proposal = new JumpProposal(
                startPoint,
                surface with { LandingPoint = landingPt },
                horizDist,
                dy,
                duration,
                apexHeight,
                style,
                rejectionReason == null,
                rejectionReason);

            results.Add(proposal);
        }

        return results;
    }

    // MARK: - Jump History & Memory

    /// <summary>
    /// Records successful landing on a target surface.
    /// </summary>
    public void RecordJumpCompleted(IntPtr? windowHandle)
    {
        var date = Now();
        ConsecutiveJumpCount++;
        LastJumpTime = date;
        if (windowHandle.HasValue)
        {
            _recentlyVisitedWindows[windowHandle.Value] = date;
        }
    }

    /// <summary>
    /// Resets consecutive jump count when Cookie rests, strolls, or is petted.
    /// </summary>
    public void ResetConsecutiveJumps()
    {
        ConsecutiveJumpCount = 0;
    }

    /// <summary>
    /// Checks if a window is currently in anti-bounce cooldown.
    /// </summary>
    public bool IsWindowOnCooldown(IntPtr windowHandle)
    {
        if (_recentlyVisitedWindows.TryGetValue(windowHandle, out var visitedAt))
        {
            return (Now() - visitedAt).TotalSeconds < WindowVisitCooldown;
        }
        return false;
    }

    private void PruneStaleCooldowns()
    {
        var date = Now();
        var staleKeys = _recentlyVisitedWindows
            .Where(kvp => (date - kvp.Value).TotalSeconds >= WindowVisitCooldown)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in staleKeys)
        {
            _recentlyVisitedWindows.Remove(key);
        }
    }

    /// <summary>
    /// Clears all jump history.
    /// </summary>
    public void ClearHistory()
    {
        _recentlyVisitedWindows.Clear();
        ConsecutiveJumpCount = 0;
        LastJumpTime = DateTime.MinValue;
    }
}
