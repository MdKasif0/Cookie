using System;
using System.Diagnostics;
using System.Text;
using System.Windows.Threading;
using Cookie.Windows.Core.Context;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Context;

/// <summary>
/// Native Windows application context detector.
/// Uses standard GetForegroundWindow and GetWindowThreadProcessId to observe the active application.
/// Respects user privacy: only process names and public top-level window titles are inspected;
/// no document contents, keystrokes, URLs, or browser tabs are accessed.
/// </summary>
public class WindowsApplicationContextDetector : IApplicationContextDetector, IDisposable
{
    private readonly uint _currentProcessId;
    private ApplicationContext _currentContext = ApplicationContext.Unknown;
    private ApplicationContext? _previousContext;

    private readonly DispatcherTimer? _pollTimer;
    private bool _isDisposed;

    public ApplicationContext CurrentContext => _currentContext;
    public ApplicationContext? PreviousContext => _previousContext;

    public event Action<ApplicationContext>? OnApplicationSwitched;

    public WindowsApplicationContextDetector(bool enableTimer = true)
    {
        _currentProcessId = (uint)Process.GetCurrentProcess().Id;

        if (enableTimer)
        {
            _pollTimer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(500)
            };
            _pollTimer.Tick += (s, e) => RefreshContext();
            _pollTimer.Start();
        }

        RefreshContext();
    }

    public ApplicationContext RefreshContext()
    {
        if (_isDisposed) return _currentContext;

        IntPtr foregroundHwnd = NativeMethods.GetForegroundWindow();
        var now = DateTime.UtcNow;

        if (foregroundHwnd == IntPtr.Zero)
        {
            var desktopContext = new ApplicationContext(
                DesktopContextState.DesktopVisible,
                "explorer",
                "Desktop",
                null,
                ApplicationCategory.FileManager,
                false,
                null,
                now);

            UpdateContext(desktopContext);
            return _currentContext;
        }

        NativeMethods.GetWindowThreadProcessId(foregroundHwnd, out uint pid);
        bool isCookie = (pid == _currentProcessId);

        var titleBuilder = new StringBuilder(256);
        NativeMethods.GetWindowText(foregroundHwnd, titleBuilder, 256);
        string title = titleBuilder.ToString().Trim();

        string procName = string.Empty;
        try
        {
            using var proc = Process.GetProcessById((int)pid);
            procName = proc.ProcessName;
        }
        catch { }

        CoreRect? bounds = null;
        if (NativeMethods.GetWindowRect(foregroundHwnd, out RECT rc))
        {
            bounds = new CoreRect(rc.Left, rc.Top, rc.Width, rc.Height);
        }

        var category = ApplicationCategoryExtensions.Classify(procName, title);

        DesktopContextState state;
        if (isCookie)
        {
            state = DesktopContextState.CookieActive;
        }
        else if (category == ApplicationCategory.FileManager && (title == "Program Manager" || title == "Desktop"))
        {
            state = DesktopContextState.DesktopVisible;
        }
        else
        {
            state = DesktopContextState.AnotherAppActive;
        }

        var newContext = new ApplicationContext(
            state,
            string.IsNullOrEmpty(procName) ? null : procName,
            string.IsNullOrEmpty(title) ? procName : title,
            (int)pid,
            category,
            isCookie,
            bounds,
            now);

        UpdateContext(newContext);
        return _currentContext;
    }

    private void UpdateContext(ApplicationContext newContext)
    {
        if (_currentContext.State != newContext.State ||
            _currentContext.ProcessId != newContext.ProcessId ||
            _currentContext.Category != newContext.Category)
        {
            _previousContext = _currentContext;
            _currentContext = newContext;
            OnApplicationSwitched?.Invoke(_currentContext);
        }
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            _isDisposed = true;
            _pollTimer?.Stop();
        }
    }
}
