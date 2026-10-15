using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

public class WindowsScreenGeometryProvider : IScreenGeometryProvider
{
    public CoreRect GetPrimaryWorkArea()
    {
        return new CoreRect(
            SystemParameters.WorkArea.Left,
            SystemParameters.WorkArea.Top,
            SystemParameters.WorkArea.Width,
            SystemParameters.WorkArea.Height);
    }

    public CoreRect GetVirtualScreenBounds()
    {
        return new CoreRect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth,
            SystemParameters.VirtualScreenHeight);
    }

    public CorePoint? GetCursorPositionDip()
    {
        if (NativeMethods.GetCursorPos(out POINT pt))
        {
            return new CorePoint(pt.X, pt.Y);
        }
        return null;
    }

    public List<DisplayMonitorInfo> GetActiveMonitors()
    {
        var monitors = new List<DisplayMonitorInfo>();

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));

            if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
            {
                bool isPrimary = (mi.dwFlags & 1) != 0;
                var monitorBounds = new CoreRect(mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Width, mi.rcMonitor.Height);
                var workArea = new CoreRect(mi.rcWork.Left, mi.rcWork.Top, mi.rcWork.Width, mi.rcWork.Height);

                monitors.Add(new DisplayMonitorInfo(mi.szDevice, monitorBounds, workArea, isPrimary));
            }
            return true;
        }, IntPtr.Zero);

        if (monitors.Count == 0)
        {
            var fallback = GetPrimaryWorkArea();
            monitors.Add(new DisplayMonitorInfo("PRIMARY", fallback, fallback, true));
        }

        return monitors;
    }
}
