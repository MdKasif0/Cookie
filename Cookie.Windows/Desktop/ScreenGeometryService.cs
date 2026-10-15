using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

public record DisplayMonitorInfo(
    string DeviceName,
    Rect MonitorBounds,
    Rect WorkArea,
    bool IsPrimary);

public class ScreenGeometryService
{
    public virtual Rect GetPrimaryWorkArea()
    {
        // Default fallback using SystemParameters
        return new Rect(
            SystemParameters.WorkArea.Left,
            SystemParameters.WorkArea.Top,
            SystemParameters.WorkArea.Width,
            SystemParameters.WorkArea.Height);
    }

    public virtual Rect GetVirtualScreenBounds()
    {
        return new Rect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth,
            SystemParameters.VirtualScreenHeight);
    }

    public virtual Point? GetCursorPositionDip()
    {
        if (NativeMethods.GetCursorPos(out POINT pt))
        {
            // Convert physical coordinates to DIPs
            // Under WPF standard DPI scaling:
            return new Point(pt.X, pt.Y);
        }
        return null;
    }

    public virtual List<DisplayMonitorInfo> GetActiveMonitors()
    {
        var monitors = new List<DisplayMonitorInfo>();

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));

            if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
            {
                bool isPrimary = (mi.dwFlags & 1) != 0;
                var monitorBounds = new Rect(mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Width, mi.rcMonitor.Height);
                var workArea = new Rect(mi.rcWork.Left, mi.rcWork.Top, mi.rcWork.Width, mi.rcWork.Height);

                monitors.Add(new DisplayMonitorInfo(mi.szDevice, monitorBounds, workArea, isPrimary));
            }
            return true;
        }, IntPtr.Zero);

        if (monitors.Count == 0)
        {
            // Fallback to primary work area
            var fallback = GetPrimaryWorkArea();
            monitors.Add(new DisplayMonitorInfo("PRIMARY", fallback, fallback, true));
        }

        return monitors;
    }

    public virtual Point RecoverPosition(Point currentPosition, Size companionSize)
    {
        var monitors = GetActiveMonitors();

        // Check if current position is visible on any monitor
        foreach (var monitor in monitors)
        {
            var visibleArea = monitor.WorkArea;
            var companionRect = new Rect(currentPosition, companionSize);

            // If at least 30% of Cookie is visible on this monitor, clamp and keep it
            var intersection = Rect.Intersect(visibleArea, companionRect);
            if (!intersection.IsEmpty && intersection.Width * intersection.Height >= (companionSize.Width * companionSize.Height * 0.3))
            {
                return DesktopCoordinateSpace.ClampToWorkArea(currentPosition, companionSize, visibleArea);
            }
        }

        // Off-screen or monitor disconnected: safely respawn on primary monitor
        var primaryArea = GetPrimaryWorkArea();
        return DesktopCoordinateSpace.CalculateDefaultSpawn(primaryArea, companionSize);
    }
}
