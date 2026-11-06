using System;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Runs focus sessions: Cookie naps beside you while the clock counts down, then stretches and tells you it is
/// time for a break. Time advances by real elapsed time, so a PC that sleeps through the end of a session still
/// finishes it on waking.
/// </summary>
public class FocusSession
{
    private readonly CookieProfile _profile;
    private readonly CookieBehaviorController _controller;
    private readonly Action<string> _say;
    private readonly Action<SoundEffect> _play;
    private DateTime _lastTick;

    public FocusTimer Timer { get; } = new();
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    /// <summary>Raised whenever the timer or its phase changes, for updating menus and tooltips.</summary>
    public event Action? Changed;

    public FocusSession(CookieProfile profile, CookieBehaviorController controller, Action<string> say, Action<SoundEffect> play)
    {
        _profile = profile;
        _controller = controller;
        _say = say;
        _play = play;
    }

    public bool IsFocusing => Timer.Phase == FocusPhase.Focusing;
    public bool IsOnBreak => Timer.Phase == FocusPhase.OnBreak;

    /// <summary>Text for the tray tooltip while a session runs, such as "24:10" or "Break 4:30".</summary>
    public string? StatusTitle => Timer.Phase switch
    {
        FocusPhase.Focusing => Timer.RemainingLabel,
        FocusPhase.OnBreak => $"Break {Timer.RemainingLabel}",
        _ => null
    };

    public void Start(int? minutes = null)
    {
        int length = minutes ?? _profile.Settings.FocusMinutes;
        if (Timer.IsActive) Stop();

        Timer.StartFocus(length);
        _controller.BeginFocus();
        _say("Okay, I'll keep you company.");
        _lastTick = Now();
        Changed?.Invoke();
    }

    /// <summary>Ends a focus session early or skips the break.</summary>
    public void Stop()
    {
        if (Timer.Phase == FocusPhase.Focusing) _controller.EndFocus(completed: false);
        Timer.Cancel();
        Changed?.Invoke();
    }

    /// <summary>Advances the clock to now. Called about once a second while a session runs.</summary>
    public void Tick()
    {
        var now = Now();
        double delta = Math.Max(0, (now - _lastTick).TotalSeconds);
        _lastTick = now;

        var finished = Timer.Advance(delta);
        if (finished is { } result)
        {
            switch (result.Kind)
            {
                case FocusEventKind.FocusCompleted:
                    _profile.Statistics.RecordFocusSession(result.Minutes);
                    _controller.EndFocus(completed: true);
                    _say($"Time for a break! You focused for {result.Minutes} minutes.");
                    Timer.StartBreak(_profile.Settings.BreakMinutes);
                    break;
                case FocusEventKind.BreakCompleted:
                    _say("Break's over. Ready for another round?");
                    _play(SoundEffect.Chirp);
                    break;
            }
        }
        Changed?.Invoke();
    }
}
