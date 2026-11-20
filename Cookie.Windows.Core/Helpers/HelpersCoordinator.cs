using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Helpers;

/// <summary>
/// The jobs Cookie does for you: reminders and timers, break nudges, the focus guard, bedtime, the system
/// watcher, the downloads watcher, the screenshot tidy-up and the to-do list. The window calls <see cref="Tick"/>
/// every few seconds; everything that touches Windows comes in through the delegates below.
/// </summary>
public class HelpersCoordinator
{
    private readonly CookieProfile _profile;
    private readonly CookieBehaviorController _behavior;
    private readonly BreakNudgeSchedule _nudges;
    private readonly SystemWatch _system = new();
    private DownloadWatch _downloads = new();
    private bool _downloadsWereOn;
    private DateTime _guardCooldownUntil = DateTime.MinValue;
    private int _tickCount;

    public static readonly TimeSpan FocusGuardCooldown = TimeSpan.FromSeconds(90);

    // What she does. Set by the window.
    public Action<string, double> Say { get; set; } = (_, _) => { };
    public Action<SoundEffect> Play { get; set; } = _ => { };
    /// <summary>Puts her beside the cursor, showing her if she was hidden and stepping over quiet mode briefly.</summary>
    public Action BringToCursor { get; set; } = () => { };
    /// <summary>Asks for the profile to be saved soon.</summary>
    public Action Save { get; set; } = () => { };
    public event Action? Changed;

    // What she can see. Set by the window, replaced in tests.
    public Func<DateTime> UtcNow { get; set; } = () => DateTime.UtcNow;
    public Func<DateTime> LocalNow { get; set; } = () => DateTime.Now;
    public Func<TimeSpan> IdleTime { get; set; } = () => TimeSpan.Zero;
    public Func<bool> IsQuiet { get; set; } = () => false;
    public Func<bool> IsFocusing { get; set; } = () => false;
    public Func<bool> IsVisible { get; set; } = () => true;
    public Func<string?> FrontmostProcess { get; set; } = () => null;
    public Func<SystemSnapshot> SystemSnapshot { get; set; } = () => new SystemSnapshot();
    public Func<IReadOnlyDictionary<string, long>> DownloadsListing { get; set; } = () => new Dictionary<string, long>();
    /// <summary>Old screenshots on the Desktop: the folder they're in and their names.</summary>
    public Func<(string Folder, List<string> Names)?> ScreenshotCandidates { get; set; } = () => null;
    public Func<IReadOnlyList<string>, string, int> MoveScreenshots { get; set; } = (_, _) => 0;

    public HelpersCoordinator(CookieProfile profile, CookieBehaviorController behavior)
    {
        _profile = profile;
        _behavior = behavior;
        _nudges = new BreakNudgeSchedule(DateTime.UtcNow);
    }

    private string Name => string.IsNullOrWhiteSpace(_profile.DisplayName) ? "Cookie" : _profile.DisplayName.Trim();

    /// <summary>Starts the nudge clocks from now.</summary>
    public void Start() => _nudges.Restart(UtcNow());

    /// <summary>Every 5 seconds: reminders, nudges, bedtime and downloads. Every 20: the system. Every 10 minutes: screenshots.</summary>
    public void Tick()
    {
        _tickCount++;
        DeliverDueReminders();
        CheckBreakNudges();
        CheckBedtime();
        CheckDownloads();
        if (_tickCount % 4 == 0) CheckSystem();
        if (_tickCount % 120 == 1) CheckScreenshots();
    }

    /// <summary>Nudges and bedtime hold off while she is hidden, a full-screen app or video call is in front, or a focus session runs.</summary>
    private bool CanInterrupt => IsVisible() && !IsQuiet() && !IsFocusing() && !MeetingApps.IsMeeting(FrontmostProcess());

    // MARK: Reminders

    public IReadOnlyList<CookieReminder> Reminders => _profile.Reminders.OrderBy(r => r.DueAt).ToList();

    public CookieReminder AddReminder(string text, int minutes)
    {
        var reminder = new CookieReminder { Text = text ?? "", DueAt = UtcNow().AddMinutes(Math.Max(1, minutes)) };
        _profile.Reminders.Add(reminder);
        Save();
        Changed?.Invoke();
        Say(string.IsNullOrWhiteSpace(text)
            ? $"Timer set for {CookieReminder.Label(minutes)}."
            : $"Okay! I'll remind you in {CookieReminder.Label(minutes)}.", 4);
        return reminder;
    }

    public void CancelReminder(Guid id)
    {
        _profile.Reminders.RemoveAll(r => r.Id == id);
        Save();
        Changed?.Invoke();
    }

    /// <summary>
    /// A reminder always gets through: she comes to your cursor, meows and says it, even over a full-screen app,
    /// because you asked for it. Several due at once are said together.
    /// </summary>
    public void DeliverDueReminders()
    {
        var (due, waiting) = ReminderQueue.Split(_profile.Reminders, UtcNow());
        if (due.Count == 0) return;
        _profile.Reminders = waiting;
        Save();
        Changed?.Invoke();

        // Bringing her over has her wave hello.
        BringToCursor();
        Play(SoundEffect.Meow);
        Say(due.Count == 1 ? due[0].Message : string.Join("\n", due.Select(r => "• " + r.Message)), 12);
    }

    // MARK: Break nudges

    public void CheckBreakNudges()
    {
        var now = UtcNow();
        // Stepping away counts as a break, so the clocks start again.
        if (IdleTime() >= BreakNudgeSchedule.IdleReset)
        {
            _nudges.Restart(now);
            return;
        }
        var enabled = _profile.Settings.BreakNudges.Distinct().ToList();
        if (enabled.Count == 0 || _nudges.Due(now, enabled) is not { } nudge) return;
        // Not now: she waits, and the nudge stays due until a better moment.
        if (!CanInterrupt) return;
        _nudges.MarkShown(nudge, now);
        _behavior.PerformNudge(nudge);
        Play(nudge == BreakNudge.Water ? SoundEffect.Chirp : SoundEffect.Mew);
        Say(nudge.Message(Name), 8);
    }

    // MARK: Bedtime

    public void CheckBedtime()
    {
        var settings = _profile.Settings;
        var now = LocalNow();
        if (!settings.BedtimeEnabled
            || !Bedtime.ShouldWindDown(now, settings.BedtimeMinutes, _profile.LastBedtimeWindDown)
            || IdleTime() >= BreakNudgeSchedule.IdleReset
            || !CanInterrupt) return;
        _profile.LastBedtimeWindDown = now;
        Save();
        _behavior.WindDown();
        Play(SoundEffect.Sleep);
        Say(Bedtime.Message(Name), 8);
    }

    // MARK: Focus guard

    public void AppSwitched(string? processName)
    {
        var settings = _profile.Settings;
        var now = UtcNow();
        if (!settings.FocusGuardEnabled || !IsFocusing() || IsQuiet() || now < _guardCooldownUntil) return;
        if (DistractingApp.Match(settings.DistractingApps, processName) is not { } app) return;
        _guardCooldownUntil = now + FocusGuardCooldown;
        // She sits down right in front of what you opened.
        BringToCursor();
        _behavior.NoticeDistraction();
        Play(SoundEffect.Mew);
        Say(DistractingApp.Scolding(string.IsNullOrWhiteSpace(app.DisplayName) ? app.ProcessName : app.DisplayName), 5);
    }

    // MARK: System watcher

    public void CheckSystem()
    {
        var alerts = _system.Update(SystemSnapshot(), UtcNow(), _profile.Settings.SystemAlerts);
        if (alerts.Count == 0) return;
        var alert = alerts[0];
        if (alert.IsUrgent) BringToCursor();
        else if (!CanInterrupt) return;
        bool good = alert.Type == SystemAlertType.BackOnline;
        _behavior.React(good ? CookieAnimationId.Happy : CookieAnimationId.Surprised);
        Play(good ? SoundEffect.Happy : SoundEffect.Surprise);
        Say(alert.Message, alert.IsUrgent ? 10 : 7);
    }

    // MARK: Downloads

    public void CheckDownloads()
    {
        if (!_profile.Settings.DownloadAlerts)
        {
            // Start fresh next time, so turning it on doesn't announce what is already there.
            if (_downloadsWereOn) _downloads = new DownloadWatch();
            _downloadsWereOn = false;
            return;
        }
        _downloadsWereOn = true;
        var finished = _downloads.Update(DownloadsListing());
        if (finished.Count == 0 || !CanInterrupt) return;
        _behavior.React(CookieAnimationId.Happy);
        Play(SoundEffect.Chirp);
        Say(DownloadWatch.Message(finished), 5);
    }

    // MARK: Screenshots

    /// <summary>At most once a day she mentions that screenshots have piled up.</summary>
    public void CheckScreenshots()
    {
        if (!_profile.Settings.ScreenshotTidyOffers || !CanInterrupt) return;
        var now = UtcNow();
        if (_profile.LastScreenshotOffer is { } last && now - last < TimeSpan.FromHours(24)) return;
        if (ScreenshotCandidates() is not { } found || found.Names.Count < ScreenshotTidy.OfferThreshold) return;
        _profile.LastScreenshotOffer = now;
        Save();
        _behavior.React(CookieAnimationId.Surprised);
        Say(ScreenshotTidy.Offer(found.Names.Count), 8);
    }

    /// <summary>Old screenshots waiting to be tidied, for the menu. Only looks when the feature is on.</summary>
    public int TidyableScreenshotCount()
        => _profile.Settings.ScreenshotTidyOffers ? ScreenshotCandidates()?.Names.Count ?? 0 : 0;

    public int TidyScreenshots()
    {
        if (ScreenshotCandidates() is not { } found || found.Names.Count == 0)
        {
            Say("No old screenshots to tidy. Your desktop looks great!", 5);
            return 0;
        }
        int moved = MoveScreenshots(found.Names, found.Folder);
        if (moved > 0)
        {
            _behavior.React(CookieAnimationId.Happy);
            Play(SoundEffect.Happy);
            Say($"All tidy! I put {moved} screenshot{(moved == 1 ? "" : "s")} in your Screenshots folder.", 6);
        }
        else
        {
            Say("I couldn't move those screenshots. Check that the folder isn't read-only.", 6);
        }
        return moved;
    }

    // MARK: To-do list

    public IReadOnlyList<TodoItem> Todos => _profile.Todos;

    public bool AddTodo(string text)
    {
        string trimmed = (text ?? "").Trim();
        if (trimmed.Length == 0) return false;
        if (_profile.Todos.Count(t => !t.IsDone) >= TodoItem.MaximumCount)
        {
            Say("That's a lot of tasks! Finish a few first?", 5);
            return false;
        }
        _profile.Todos.Add(new TodoItem { Text = trimmed.Length > 120 ? trimmed[..120] : trimmed, CreatedAt = UtcNow() });
        Save();
        Changed?.Invoke();
        return true;
    }

    /// <summary>Ticking a task off earns bond points (a few a day) and a little celebration.</summary>
    public void ToggleTodo(Guid id)
    {
        var todo = _profile.Todos.FirstOrDefault(t => t.Id == id);
        if (todo == null) return;
        todo.IsDone = !todo.IsDone;
        todo.DoneAt = todo.IsDone ? UtcNow() : null;
        Save();
        Changed?.Invoke();
        if (!todo.IsDone) return;
        bool rewarded = _profile.Statistics.RecordTaskCompleted(LocalNow());
        _behavior.React(CookieAnimationId.Happy);
        Play(rewarded ? SoundEffect.Happy : SoundEffect.Chirp);
        Say(TodoItem.Cheer(Name), 4);
    }

    public void ClearCompletedTodos()
    {
        _profile.Todos.RemoveAll(t => t.IsDone);
        Save();
        Changed?.Invoke();
    }

    // MARK: Folders

    /// <summary>The Downloads folder, file names mapped to sizes.</summary>
    public static IReadOnlyDictionary<string, long> ListFolder(string? folder)
    {
        var result = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        if (folder == null || !Directory.Exists(folder)) return result;
        try
        {
            foreach (var entry in new DirectoryInfo(folder).EnumerateFileSystemInfos())
            {
                if (entry.Attributes.HasFlag(FileAttributes.Hidden)) continue;
                result[entry.Name] = entry is FileInfo file ? file.Length : 1;
            }
        }
        catch
        {
            // A folder we can't read reports nothing.
        }
        return result;
    }

    /// <summary>Old screenshots in <paramref name="folder"/>.</summary>
    public static (string Folder, List<string> Names)? FindScreenshots(string? folder, DateTime nowUtc)
    {
        if (folder == null || !Directory.Exists(folder)) return null;
        try
        {
            var files = new DirectoryInfo(folder).EnumerateFiles().Select(f => (f.Name, f.LastWriteTimeUtc));
            return (folder, ScreenshotTidy.Candidates(files, nowUtc));
        }
        catch
        {
            return null;
        }
    }
}
