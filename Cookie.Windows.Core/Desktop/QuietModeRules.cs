using System;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// Decides when Cookie steps aside, from Windows' own notification state: it reports a full-screen app,
/// a Direct3D full-screen game, Presentation Mode and full-screen Store apps.
/// </summary>
public static class QuietModeRules
{
    // QUERY_USER_NOTIFICATION_STATE values from shellapi.h.
    public const int NotPresent = 1;
    public const int Busy = 2;
    public const int D3DFullScreen = 3;
    public const int PresentationMode = 4;
    public const int AcceptsNotifications = 5;
    public const int QuietTime = 6;
    public const int App = 7;

    public static bool ShouldHide(int notificationState) =>
        notificationState is Busy or D3DFullScreen or PresentationMode or App;
}

/// <summary>Where she appears when called: beside the cursor, kept on the monitor it is on.</summary>
public static class SummonPlacement
{
    public static CorePoint Origin(CorePoint cursor, CoreSize size, CoreRect workArea)
    {
        double x = cursor.X + 40;
        if (x + size.Width > workArea.Right - 8) x = cursor.X - 40 - size.Width;
        x = Math.Min(Math.Max(x, workArea.Left + 8), workArea.Right - size.Width - 8);
        double y = Math.Min(Math.Max(cursor.Y - size.Height / 2, workArea.Top + 8), workArea.Bottom - size.Height - 8);
        return new CorePoint(x, y);
    }
}

/// <summary>Quiet-mode state: a full-screen app hides her unless she was just summoned.</summary>
public class QuietModeState
{
    private DateTime _overrideUntil = DateTime.MinValue;

    public bool IsQuiet { get; private set; }

    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public void GrantOverride(double seconds) => _overrideUntil = Now().AddSeconds(seconds);

    /// <summary>
    /// Quiet mode you turned on yourself (from the menu or a link), and when it ends.
    /// <see cref="DateTime.MaxValue"/> means until you turn it off.
    /// </summary>
    public DateTime? ManualQuietUntil { get; private set; }

    public bool IsManuallyQuiet => ManualQuietUntil is { } until && Now() < until;

    public void SetManualQuiet(bool on, int? minutes = null)
    {
        if (on)
        {
            ManualQuietUntil = minutes is { } m ? Now().AddMinutes(m) : DateTime.MaxValue;
            _overrideUntil = DateTime.MinValue;
        }
        else
        {
            ManualQuietUntil = null;
        }
    }

    /// <summary>Returns true when the quiet state changed.</summary>
    public bool Evaluate(bool hideInFullscreen, int notificationState)
    {
        if (ManualQuietUntil is { } until && Now() >= until) ManualQuietUntil = null;
        // A reminder or summon briefly overrides both kinds of quiet.
        bool overridden = Now() < _overrideUntil;
        bool quiet = !overridden && (IsManuallyQuiet || (hideInFullscreen && QuietModeRules.ShouldHide(notificationState)));
        if (quiet == IsQuiet) return false;
        IsQuiet = quiet;
        return true;
    }
}
