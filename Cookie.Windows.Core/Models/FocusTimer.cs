using System;

namespace Cookie.Windows.Core.Models;

public enum FocusPhase
{
    Idle,
    Focusing,
    OnBreak
}

public enum FocusEventKind
{
    FocusCompleted,
    BreakCompleted
}

public readonly record struct FocusEvent(FocusEventKind Kind, int Minutes);

/// <summary>
/// A focus session and the break after it. Pure state: the caller supplies elapsed time, so it can
/// be driven by a real clock or by a test.
/// </summary>
public class FocusTimer
{
    public FocusPhase Phase { get; private set; } = FocusPhase.Idle;
    public double Total { get; private set; }
    public double Elapsed { get; private set; }

    public bool IsActive => Phase != FocusPhase.Idle;
    public double Remaining => Math.Max(0, Total - Elapsed);

    /// <summary>0 to 1 through the current phase.</summary>
    public double Progress => Total > 0 ? Math.Min(1, Elapsed / Total) : 0;

    public string RemainingLabel => Format(Remaining);

    /// <summary>"24:10", or "1:05:00" past an hour.</summary>
    public static string Format(double seconds)
    {
        int whole = (int)Math.Ceiling(seconds);
        int hours = whole / 3600;
        int minutes = whole % 3600 / 60;
        int secs = whole % 60;
        return hours > 0 ? $"{hours}:{minutes:00}:{secs:00}" : $"{minutes}:{secs:00}";
    }

    public void StartFocus(int minutes) => Begin(FocusPhase.Focusing, minutes);

    public void StartBreak(int minutes) => Begin(FocusPhase.OnBreak, minutes);

    public void Cancel()
    {
        Phase = FocusPhase.Idle;
        Total = 0;
        Elapsed = 0;
    }

    /// <summary>
    /// Moves the clock forward. Returns an event when a phase finishes, after which the timer is idle
    /// and the caller decides what comes next.
    /// </summary>
    public FocusEvent? Advance(double seconds)
    {
        if (!IsActive || seconds <= 0) return null;
        Elapsed += seconds;
        if (Elapsed < Total) return null;

        var finished = Phase;
        int minutes = (int)Math.Round(Total / 60.0, MidpointRounding.AwayFromZero);
        Cancel();
        return finished == FocusPhase.Focusing
            ? new FocusEvent(FocusEventKind.FocusCompleted, minutes)
            : new FocusEvent(FocusEventKind.BreakCompleted, minutes);
    }

    private void Begin(FocusPhase phase, int minutes)
    {
        Phase = phase;
        Total = Math.Max(1, minutes) * 60.0;
        Elapsed = 0;
    }
}
