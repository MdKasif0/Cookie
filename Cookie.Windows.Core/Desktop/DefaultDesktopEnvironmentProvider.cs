using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// In-memory and testing implementation of IDesktopEnvironmentProvider.
/// Supports programmatic injection of monitors, taskbars, and windows for unit tests.
/// </summary>
public class DefaultDesktopEnvironmentProvider : IDesktopEnvironmentProvider
{
    private readonly List<DisplayMonitorInfo> _monitors = new();
    private readonly List<TaskbarInfo> _taskbars = new();
    private readonly List<ObservableWindow> _windows = new();

    public event Action? OnEnvironmentChanged;

    public DefaultDesktopEnvironmentProvider()
    {
        var primaryMon = new DisplayMonitorInfo(
            "PRIMARY",
            new CoreRect(0, 0, 1920, 1080),
            new CoreRect(0, 0, 1920, 1040),
            true);
        _monitors.Add(primaryMon);

        var primaryTaskbar = new TaskbarInfo(
            "PRIMARY",
            new CoreRect(0, 1040, 1920, 40),
            TaskbarOrientation.Bottom,
            TaskbarVisibilityState.Visible,
            40.0,
            new CoreRect(80, 990, 1760, 50));
        _taskbars.Add(primaryTaskbar);
    }

    public void SetMonitors(IEnumerable<DisplayMonitorInfo> monitors)
    {
        _monitors.Clear();
        _monitors.AddRange(monitors);
        OnEnvironmentChanged?.Invoke();
    }

    public void SetTaskbars(IEnumerable<TaskbarInfo> taskbars)
    {
        _taskbars.Clear();
        _taskbars.AddRange(taskbars);
        OnEnvironmentChanged?.Invoke();
    }

    public void SetWindows(IEnumerable<ObservableWindow> windows)
    {
        _windows.Clear();
        _windows.AddRange(windows);
        OnEnvironmentChanged?.Invoke();
    }

    public void AddWindow(ObservableWindow window)
    {
        _windows.Add(window);
        OnEnvironmentChanged?.Invoke();
    }

    public void RemoveWindow(IntPtr handle)
    {
        _windows.RemoveAll(w => w.Handle == handle);
        OnEnvironmentChanged?.Invoke();
    }

    public DesktopEnvironment GetDesktopEnvironment(CorePoint? cookiePosition = null)
    {
        var primary = _monitors.FirstOrDefault(m => m.IsPrimary) ??
                      _monitors.FirstOrDefault() ??
                      new DisplayMonitorInfo("PRIMARY", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);

        return new DesktopEnvironment(
            primary,
            _monitors.ToList(),
            _taskbars.ToList(),
            _windows.ToList(),
            cookiePosition);
    }

    public IReadOnlyList<ObservableWindow> EnumerateVisibleWindows()
    {
        return _windows.ToList();
    }

    public IReadOnlyList<TaskbarInfo> GetTaskbarInfos()
    {
        return _taskbars.ToList();
    }

    public void NotifyEnvironmentChanged()
    {
        OnEnvironmentChanged?.Invoke();
    }
}
