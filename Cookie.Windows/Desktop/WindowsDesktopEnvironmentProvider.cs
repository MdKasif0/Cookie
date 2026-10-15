using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Windows;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Native Windows implementation of IDesktopEnvironmentProvider.
/// Uses standard Win32 APIs (EnumDisplayMonitors, GetMonitorInfo, EnumWindows, GetWindowRect, DwmGetWindowAttribute, SHAppBarMessage)
/// to discover taskbar bounds, monitor work areas, and candidate external window surfaces.
/// Caches geometry with a modest reconciliation rate (1.5s) to avoid UI thread overhead.
/// </summary>
public class WindowsDesktopEnvironmentProvider : IDesktopEnvironmentProvider
{
    private readonly uint _currentProcessId;
    private readonly List<IntPtr> _cookieWindowHandles = new();

    private DateTime _lastWindowScan = DateTime.MinValue;
    private List<ObservableWindow> _cachedWindows = new();
    private readonly TimeSpan _windowCacheDuration = TimeSpan.FromSeconds(1.5);

    private DateTime _lastTaskbarScan = DateTime.MinValue;
    private List<TaskbarInfo> _cachedTaskbars = new();
    private readonly TimeSpan _taskbarCacheDuration = TimeSpan.FromSeconds(2.0);

    public event Action? OnEnvironmentChanged;

    public WindowsDesktopEnvironmentProvider()
    {
        _currentProcessId = (uint)Process.GetCurrentProcess().Id;
    }

    public void RegisterCookieWindow(IntPtr hWnd)
    {
        if (hWnd != IntPtr.Zero && !_cookieWindowHandles.Contains(hWnd))
        {
            _cookieWindowHandles.Add(hWnd);
        }
    }

    public void InvalidateCache()
    {
        _lastWindowScan = DateTime.MinValue;
        _lastTaskbarScan = DateTime.MinValue;
        OnEnvironmentChanged?.Invoke();
    }

    public DesktopEnvironment GetDesktopEnvironment(CorePoint? cookiePosition = null)
    {
        var monitors = GetActiveMonitors();
        var primary = monitors.Find(m => m.IsPrimary) ?? monitors[0];
        var taskbars = GetTaskbarInfos();
        var windows = EnumerateVisibleWindows();

        return new DesktopEnvironment(
            primary,
            monitors,
            taskbars,
            windows,
            cookiePosition);
    }

    public IReadOnlyList<TaskbarInfo> GetTaskbarInfos()
    {
        var now = DateTime.UtcNow;
        if (now - _lastTaskbarScan < _taskbarCacheDuration && _cachedTaskbars.Count > 0)
        {
            return _cachedTaskbars;
        }

        var taskbars = new List<TaskbarInfo>();

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));

            if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
            {
                var monitorRect = mi.rcMonitor;
                var workRect = mi.rcWork;

                // Deduce taskbar location from difference between monitor and work area
                TaskbarOrientation orientation = TaskbarOrientation.Bottom;
                CoreRect tbBounds;
                double thickness = 0.0;

                if (workRect.Bottom < monitorRect.Bottom)
                {
                    orientation = TaskbarOrientation.Bottom;
                    thickness = monitorRect.Bottom - workRect.Bottom;
                    tbBounds = new CoreRect(monitorRect.Left, workRect.Bottom, monitorRect.Width, thickness);
                }
                else if (workRect.Top > monitorRect.Top)
                {
                    orientation = TaskbarOrientation.Top;
                    thickness = workRect.Top - monitorRect.Top;
                    tbBounds = new CoreRect(monitorRect.Left, monitorRect.Top, monitorRect.Width, thickness);
                }
                else if (workRect.Left > monitorRect.Left)
                {
                    orientation = TaskbarOrientation.Left;
                    thickness = workRect.Left - monitorRect.Left;
                    tbBounds = new CoreRect(monitorRect.Left, monitorRect.Top, thickness, monitorRect.Height);
                }
                else if (workRect.Right < monitorRect.Right)
                {
                    orientation = TaskbarOrientation.Right;
                    thickness = monitorRect.Right - workRect.Right;
                    tbBounds = new CoreRect(workRect.Right, monitorRect.Top, thickness, monitorRect.Height);
                }
                else
                {
                    // Work area equals monitor rectangle; taskbar is auto-hidden or not docked
                    orientation = TaskbarOrientation.Bottom;
                    thickness = 40.0;
                    tbBounds = new CoreRect(monitorRect.Left, monitorRect.Bottom - 40, monitorRect.Width, 40);
                }

                // Check autohide state via SHAppBarMessage
                var abd = new APPBARDATA();
                abd.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
                IntPtr state = NativeMethods.SHAppBarMessage(NativeMethods.ABM_GETSTATE, ref abd);
                bool isAutoHide = (state.ToInt64() & NativeMethods.ABS_AUTOHIDE) != 0;

                // Safe walking surface in the adjacent work area
                CoreRect safeSurface = orientation switch
                {
                    TaskbarOrientation.Bottom => new CoreRect(
                        workRect.Left + 40,
                        Math.Max(workRect.Top, workRect.Bottom - 60),
                        Math.Max(100, workRect.Width - 80),
                        50),

                    TaskbarOrientation.Top => new CoreRect(
                        workRect.Left + 40,
                        workRect.Top + 10,
                        Math.Max(100, workRect.Width - 80),
                        50),

                    TaskbarOrientation.Left => new CoreRect(
                        workRect.Left + 10,
                        workRect.Top + 40,
                        50,
                        Math.Max(100, workRect.Height - 80)),

                    TaskbarOrientation.Right => new CoreRect(
                        Math.Max(workRect.Left, workRect.Right - 60),
                        workRect.Top + 40,
                        50,
                        Math.Max(100, workRect.Height - 80)),

                    _ => new CoreRect(workRect.Left + 40, workRect.Bottom - 60, workRect.Width - 80, 50)
                };

                taskbars.Add(new TaskbarInfo(
                    mi.szDevice,
                    tbBounds,
                    orientation,
                    isAutoHide ? TaskbarVisibilityState.AutoHidden : TaskbarVisibilityState.Visible,
                    thickness,
                    safeSurface));
            }
            return true;
        }, IntPtr.Zero);

        if (taskbars.Count == 0)
        {
            var fallback = DesktopEnvironment.Fallback.PrimaryTaskbar;
            if (fallback != null) taskbars.Add(fallback);
        }

        _cachedTaskbars = taskbars;
        _lastTaskbarScan = now;
        return _cachedTaskbars;
    }

    public IReadOnlyList<ObservableWindow> EnumerateVisibleWindows()
    {
        var now = DateTime.UtcNow;
        if (now - _lastWindowScan < _windowCacheDuration && _cachedWindows.Count > 0)
        {
            return _cachedWindows;
        }

        var result = new List<ObservableWindow>();

        NativeMethods.EnumWindows((hWnd, lParam) =>
        {
            // 1. Must be visible
            if (!NativeMethods.IsWindowVisible(hWnd)) return true;

            // 2. Must not be minimized (iconic)
            if (NativeMethods.IsIconic(hWnd)) return true;

            // 3. Must not belong to Cookie companion or child windows
            NativeMethods.GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == _currentProcessId || _cookieWindowHandles.Contains(hWnd)) return true;

            // 4. Must not be cloaked by DWM (e.g. windows on other virtual desktops or suspended UWP)
            int hr = NativeMethods.DwmGetWindowAttribute(hWnd, NativeMethods.DWMWA_CLOAKED, out int cloaked, sizeof(int));
            if (hr == 0 && cloaked != 0) return true;

            // 5. Filter out tool windows, transparent click-through layers, or menus
            int exStyle = NativeMethods.GetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE).ToInt32();
            if ((exStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0 && (exStyle & NativeMethods.WS_EX_LAYERED) != 0)
            {
                return true;
            }

            // 6. Get Window bounding rectangle
            if (!NativeMethods.GetWindowRect(hWnd, out RECT rc)) return true;

            // Filter out tiny windows (< 100x100) such as notification balloons, invisible utility windows
            if (rc.Width < 100 || rc.Height < 100) return true;

            // 7. Get Window Title and Process Name
            var titleBuilder = new StringBuilder(256);
            NativeMethods.GetWindowText(hWnd, titleBuilder, 256);
            string title = titleBuilder.ToString().Trim();

            // Exclude common background shell surfaces
            if (title == "Program Manager" || title == "Windows Shell Experience Host")
            {
                return true;
            }

            string procName = "ExternalWindow";
            try
            {
                using var proc = Process.GetProcessById((int)pid);
                procName = proc.ProcessName;
            }
            catch { }

            var bounds = new CoreRect(rc.Left, rc.Top, rc.Width, rc.Height);

            result.Add(new ObservableWindow(
                hWnd,
                string.IsNullOrEmpty(title) ? procName : title,
                procName,
                (int)pid,
                bounds,
                IsOccluded: false,
                IsActive: false));

            return true;
        }, IntPtr.Zero);

        _cachedWindows = result;
        _lastWindowScan = now;
        return _cachedWindows;
    }

    private List<DisplayMonitorInfo> GetActiveMonitors()
    {
        var monitors = new List<DisplayMonitorInfo>();

        NativeMethods.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));

            if (NativeMethods.GetMonitorInfo(hMonitor, ref mi))
            {
                bool isPrimary = (mi.dwFlags & 1) != 0;
                var monBounds = new CoreRect(mi.rcMonitor.Left, mi.rcMonitor.Top, mi.rcMonitor.Width, mi.rcMonitor.Height);
                var workArea = new CoreRect(mi.rcWork.Left, mi.rcWork.Top, mi.rcWork.Width, mi.rcWork.Height);

                monitors.Add(new DisplayMonitorInfo(mi.szDevice, monBounds, workArea, isPrimary));
            }
            return true;
        }, IntPtr.Zero);

        if (monitors.Count == 0)
        {
            var fallback = new CoreRect(0, 0, 1920, 1040);
            monitors.Add(new DisplayMonitorInfo("PRIMARY", fallback, fallback, true));
        }

        return monitors;
    }
}
