using System;
using System.Windows.Threading;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Watches Windows' own notification state, which reports a full-screen app, a Direct3D game, Presentation Mode
/// and full-screen Store apps, so Cookie can step aside. Summoning her overrides it for a short while.
/// </summary>
public sealed class QuietModeMonitor
{
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly QuietModeState _state = new();
    private readonly Func<bool> _isEnabled;

    public event Action<bool>? QuietChanged;

    public bool IsQuiet => _state.IsQuiet;

    public QuietModeMonitor(Func<bool> isEnabled)
    {
        _isEnabled = isEnabled;
        _timer.Tick += (s, e) => Evaluate();
    }

    public void Start()
    {
        _timer.Start();
        Evaluate();
    }

    public void Stop() => _timer.Stop();

    /// <summary>Lets her stay visible for <paramref name="seconds"/> even if a full-screen app is up.</summary>
    public void GrantOverride(double seconds)
    {
        _state.GrantOverride(seconds);
        Evaluate();
    }

    public void Evaluate()
    {
        int notificationState = QuietModeRules.AcceptsNotifications;
        try
        {
            if (NativeMethods.SHQueryUserNotificationState(out int reported) == 0) notificationState = reported;
        }
        catch (Exception exception) when (exception is DllNotFoundException or EntryPointNotFoundException)
        {
            // Without the shell call she just never hides.
        }

        if (_state.Evaluate(_isEnabled(), notificationState)) QuietChanged?.Invoke(_state.IsQuiet);
    }
}
