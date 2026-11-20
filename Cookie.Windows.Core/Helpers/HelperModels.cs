using System;
using System.Collections.Generic;
using System.Linq;

namespace Cookie.Windows.Core.Helpers;

// Pure models for the little jobs Cookie does for you: reminders, break nudges, the focus guard and
// bedtime. They hold no timers and read no clock, so the coordinator and the tests drive them.

/// <summary>"Remind me in 20 minutes to call Mom." Saved, so a reminder survives a restart.</summary>
public class CookieReminder
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    /// <summary>When it is due, in UTC.</summary>
    public DateTime DueAt { get; set; }

    /// <summary>What she says when it is time. A timer without words still gets a line.</summary>
    public string Message => string.IsNullOrWhiteSpace(Text) ? "Time's up!" : Text.Trim();

    /// <summary>The lengths offered in the menu and the new-reminder window, in minutes.</summary>
    public static readonly int[] PresetMinutes = { 1, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180 };

    public static string Label(int minutes)
    {
        if (minutes < 60) return minutes == 1 ? "1 minute" : $"{minutes} minutes";
        if (minutes % 60 == 0) return minutes == 60 ? "1 hour" : $"{minutes / 60} hours";
        return $"{minutes / 60.0:0.0} hours";
    }

    /// <summary>"in 12 min", "in 1 h 05 min", or "now".</summary>
    public string RemainingLabel(DateTime nowUtc)
    {
        int minutes = (int)Math.Ceiling((DueAt - nowUtc).TotalMinutes);
        if (minutes <= 0) return "now";
        return minutes < 60 ? $"in {minutes} min" : $"in {minutes / 60} h {minutes % 60:00} min";
    }
}

public static class ReminderQueue
{
    /// <summary>Splits reminders into those due at <paramref name="nowUtc"/>, soonest first, and those still waiting.</summary>
    public static (List<CookieReminder> Due, List<CookieReminder> Waiting) Split(IEnumerable<CookieReminder> reminders, DateTime nowUtc)
    {
        var sorted = reminders.OrderBy(r => r.DueAt).ToList();
        return (sorted.Where(r => r.DueAt <= nowUtc).ToList(), sorted.Where(r => r.DueAt > nowUtc).ToList());
    }
}

public enum BreakNudge
{
    Eyes,
    Posture,
    Water
}

public static class BreakNudgeExtensions
{
    public static string DisplayName(this BreakNudge nudge) => nudge switch
    {
        BreakNudge.Eyes => "Rest your eyes",
        BreakNudge.Posture => "Check your posture",
        _ => "Drink some water"
    };

    /// <summary>How long you use the PC between nudges of this kind.</summary>
    public static TimeSpan Interval(this BreakNudge nudge) => nudge switch
    {
        BreakNudge.Eyes => TimeSpan.FromMinutes(20),   // the 20-20-20 rule
        BreakNudge.Posture => TimeSpan.FromMinutes(45),
        _ => TimeSpan.FromMinutes(60)
    };

    public static string SettingsHint(this BreakNudge nudge) => nudge switch
    {
        BreakNudge.Eyes => "Every 20 minutes: look at something 20 feet away for 20 seconds",
        BreakNudge.Posture => "Every 45 minutes: sit up and roll your shoulders",
        _ => "Every hour: a reminder to have a drink"
    };

    public static string Message(this BreakNudge nudge, string name) => nudge switch
    {
        BreakNudge.Eyes => "Look at something far away for 20 seconds. I'll wait.",
        BreakNudge.Posture => "Stretch with me! Sit up tall and roll your shoulders.",
        _ => $"{name} is having a drink. You should too!"
    };
}

/// <summary>
/// When each nudge is next due. Time only counts while you are using the PC: after a long idle stretch
/// everything starts over, because you have already had your break.
/// </summary>
public class BreakNudgeSchedule
{
    /// <summary>Nudges never come closer together than this, so two never arrive at once.</summary>
    public static readonly TimeSpan MinimumGap = TimeSpan.FromMinutes(5);
    /// <summary>Idle for this long counts as a break.</summary>
    public static readonly TimeSpan IdleReset = TimeSpan.FromMinutes(5);

    private readonly Dictionary<BreakNudge, DateTime> _lastShown = new();
    private DateTime _lastAny = DateTime.MinValue;

    public BreakNudgeSchedule(DateTime start) => Restart(start);

    public void Restart(DateTime at)
    {
        foreach (var nudge in Enum.GetValues<BreakNudge>()) _lastShown[nudge] = at;
    }

    /// <summary>The nudge to show now, if any. The most overdue enabled one wins.</summary>
    public BreakNudge? Due(DateTime now, IReadOnlyCollection<BreakNudge> enabled)
    {
        if (now - _lastAny < MinimumGap) return null;
        BreakNudge? best = null;
        TimeSpan bestOverdue = TimeSpan.MinValue;
        foreach (var nudge in enabled.Distinct())
        {
            var overdue = now - _lastShown[nudge] - nudge.Interval();
            if (overdue >= TimeSpan.Zero && overdue > bestOverdue)
            {
                best = nudge;
                bestOverdue = overdue;
            }
        }
        return best;
    }

    public void MarkShown(BreakNudge nudge, DateTime at)
    {
        _lastShown[nudge] = at;
        _lastAny = at;
    }
}

public static class MeetingApps
{
    /// <summary>Video-call apps, by process name. A nudge or bedtime chat never interrupts while one is in front.</summary>
    private static readonly string[] Tokens =
    {
        "zoom", "ms-teams", "msteams", "teams", "webex", "ciscocollabhost", "gotomeeting", "g2mlauncher",
        "bluejeans", "around", "tuple", "skype"
    };

    public static bool IsMeeting(string? processName)
    {
        if (string.IsNullOrWhiteSpace(processName)) return false;
        string name = processName.ToLowerInvariant();
        return Tokens.Any(token => name.Contains(token));
    }
}

/// <summary>
/// An app you've told Cookie distracts you, by its process name. She can only see which app is in front,
/// never which website or document is open.
/// </summary>
public class DistractingApp
{
    public string ProcessName { get; set; } = "";
    public string DisplayName { get; set; } = "";

    public static string Normalize(string processName)
    {
        string name = processName.Trim();
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        return name.ToLowerInvariant();
    }

    public static DistractingApp? Match(IEnumerable<DistractingApp> apps, string? processName)
    {
        if (string.IsNullOrWhiteSpace(processName)) return null;
        string wanted = Normalize(processName);
        return apps.FirstOrDefault(app => Normalize(app.ProcessName) == wanted);
    }

    private static readonly string[] Lines =
    {
        "Hey… weren't we focusing?",
        "{0}? Already?",
        "I saw that. Back to work!",
        "Just a peek, then back to it, okay?"
    };

    public static string Scolding(string appName, Random? random = null)
        => string.Format(Lines[(random ?? Random.Shared).Next(Lines.Length)], appName);
}

public static class Bedtime
{
    /// <summary>How long after bedtime she still brings it up. After that the night is over.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromHours(3);

    /// <summary>
    /// The bedtime this local time belongs to, if we are inside its window. <paramref name="minutes"/> is
    /// minutes after midnight, so 23:30 is 1410.
    /// </summary>
    public static DateTime? CurrentBedtime(DateTime nowLocal, int minutes)
    {
        int clamped = Math.Clamp(minutes, 0, 24 * 60 - 1);
        var today = nowLocal.Date.AddMinutes(clamped);
        foreach (var candidate in new[] { today, today.AddDays(-1) })
        {
            if (candidate <= nowLocal && nowLocal - candidate < Window) return candidate;
        }
        return null;
    }

    /// <summary>True when it is past bedtime tonight and she hasn't said so yet. Times are local.</summary>
    public static bool ShouldWindDown(DateTime nowLocal, int minutes, DateTime? lastWindDownLocal)
    {
        if (CurrentBedtime(nowLocal, minutes) is not { } bedtime) return false;
        return lastWindDownLocal is not { } last || last < bedtime;
    }

    private static readonly string[] Lines =
    {
        "It's getting late. Time to wrap up?",
        "{0} is sleepy… are you?",
        "Bedtime soon. Save your work and rest up!"
    };

    public static string Message(string name, Random? random = null)
        => string.Format(Lines[(random ?? Random.Shared).Next(Lines.Length)], name);
}
