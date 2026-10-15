using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// Physical orientation of the Windows Taskbar relative to its display monitor.
/// </summary>
public enum TaskbarOrientation
{
    Bottom,
    Top,
    Left,
    Right,
    Unknown
}

/// <summary>
/// Visibility state of the Windows Taskbar.
/// </summary>
public enum TaskbarVisibilityState
{
    Visible,
    AutoHidden
}

/// <summary>
/// Descriptive geometry and state of a Taskbar on a display monitor.
/// Coordinates are in WPF Device-Independent Pixels (DIPs).
/// </summary>
public record TaskbarInfo(
    string DisplayDeviceName,
    CoreRect TaskbarBounds,
    TaskbarOrientation Orientation,
    TaskbarVisibilityState Visibility,
    double Thickness,
    CoreRect SafeWalkingSurface)
{
    public bool IsHorizontal => Orientation is TaskbarOrientation.Bottom or TaskbarOrientation.Top;
    public bool IsVertical => Orientation is TaskbarOrientation.Left or TaskbarOrientation.Right;
}

/// <summary>
/// Inspection target representing an application icon or general area along the Taskbar.
/// </summary>
public record TaskbarInspectionTarget(
    CorePoint ScreenPoint,
    string Label,
    string? ProcessName = null);

/// <summary>
/// State machine tracking Cookie's active Taskbar exploration phases.
/// </summary>
public enum TaskbarSessionPhase
{
    /// <summary>
    /// Not currently exploring the taskbar.
    /// </summary>
    Idle,
    /// <summary>
    /// Anticipation pause: observing the taskbar or cursor nearby curiously.
    /// </summary>
    Anticipating,
    /// <summary>
    /// Walking smoothly toward a reachable target along the safe taskbar-adjacent edge.
    /// </summary>
    Approaching,
    /// <summary>
    /// Pausing near a specific application icon region, observing curiously.
    /// </summary>
    InspectingArea,
    /// <summary>
    /// Walking gently along the safe edge parallel to the taskbar.
    /// </summary>
    PacingEdge,
    /// <summary>
    /// Concluding exploration and heading back toward the central workspace.
    /// </summary>
    Departing
}

/// <summary>
/// Comprehensive, reusable representation of the desktop environment and safe reachability areas.
/// All coordinates are in WPF Device-Independent Pixels (DIPs).
/// </summary>
public record DesktopEnvironment(
    DisplayMonitorInfo PrimaryMonitor,
    IReadOnlyList<DisplayMonitorInfo> AllMonitors,
    IReadOnlyList<TaskbarInfo> Taskbars,
    IReadOnlyList<ObservableWindow> Windows,
    CorePoint? CookiePosition = null)
{
    public TaskbarInfo? PrimaryTaskbar =>
        Taskbars.FirstOrDefault(t => t.DisplayDeviceName == PrimaryMonitor.DeviceName) ??
        Taskbars.FirstOrDefault();

    /// <summary>
    /// Checks if a global screen point (in DIPs) is within proximity of any Taskbar.
    /// </summary>
    public bool IsPointNearTaskbar(CorePoint point, double threshold = 80.0)
    {
        foreach (var taskbar in Taskbars)
        {
            if (taskbar.TaskbarBounds.IsEmpty) continue;

            var testArea = taskbar.TaskbarBounds.Inflate(threshold, threshold);
            if (testArea.Contains(point))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// Clamps a proposed target coordinate strictly within the primary or nearest safe taskbar walking surface.
    /// </summary>
    public CorePoint ClampToTaskbarWalkingSurface(CorePoint point, CoreSize characterSize)
    {
        var targetTaskbar = PrimaryTaskbar;
        if (targetTaskbar == null || targetTaskbar.SafeWalkingSurface.IsEmpty)
        {
            return DesktopCoordinateSpace.ClampToWorkArea(point, characterSize, PrimaryMonitor.WorkArea);
        }

        var surface = targetTaskbar.SafeWalkingSurface;
        double minX = surface.Left;
        double maxX = Math.Max(minX, surface.Right - characterSize.Width);
        double minY = surface.Top;
        double maxY = Math.Max(minY, surface.Bottom - characterSize.Height);

        double clampedX = Math.Max(minX, Math.Min(point.X, maxX));
        double clampedY = Math.Max(minY, Math.Min(point.Y, maxY));

        return new CorePoint(clampedX, clampedY);
    }

    /// <summary>
    /// Fallback desktop environment used when no display providers are active or during testing.
    /// </summary>
    public static DesktopEnvironment Fallback
    {
        get
        {
            var monBounds = new CoreRect(0, 0, 1920, 1080);
            var workArea = new CoreRect(0, 0, 1920, 1040);
            var primaryMon = new DisplayMonitorInfo("PRIMARY", monBounds, workArea, true);

            var taskbarBounds = new CoreRect(0, 1040, 1920, 40);
            // Safe walking surface is 50 DIPs high immediately above the taskbar
            var safeSurface = new CoreRect(80, 990, 1760, 50);
            var taskbarInfo = new TaskbarInfo(
                "PRIMARY",
                taskbarBounds,
                TaskbarOrientation.Bottom,
                TaskbarVisibilityState.Visible,
                40.0,
                safeSurface);

            return new DesktopEnvironment(
                primaryMon,
                new[] { primaryMon },
                new[] { taskbarInfo },
                Array.Empty<ObservableWindow>());
        }
    }
}
