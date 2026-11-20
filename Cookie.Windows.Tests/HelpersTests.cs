using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Xunit;

namespace Cookie.Windows.Tests;

public class ReminderModelTests
{
    [Fact]
    public void DueRemindersAreSplitOffSoonestFirst()
    {
        var now = new DateTime(2026, 11, 20, 12, 0, 0, DateTimeKind.Utc);
        var reminders = new[]
        {
            new CookieReminder { Text = "later", DueAt = now.AddMinutes(1) },
            new CookieReminder { Text = "second", DueAt = now.AddSeconds(-10) },
            new CookieReminder { Text = "first", DueAt = now.AddMinutes(-2) }
        };
        var (due, waiting) = ReminderQueue.Split(reminders, now);
        Assert.Equal(new[] { "first", "second" }, due.Select(r => r.Text));
        Assert.Equal(new[] { "later" }, waiting.Select(r => r.Text));
    }

    [Fact]
    public void LabelsAndTimers()
    {
        Assert.Equal("Time's up!", new CookieReminder { Text = "  " }.Message);
        Assert.Equal("Call Mom", new CookieReminder { Text = " Call Mom " }.Message);
        Assert.Equal("1 minute", CookieReminder.Label(1));
        Assert.Equal("20 minutes", CookieReminder.Label(20));
        Assert.Equal("1 hour", CookieReminder.Label(60));
        Assert.Equal("2 hours", CookieReminder.Label(120));
        var now = DateTime.UtcNow;
        Assert.Equal("in 12 min", new CookieReminder { DueAt = now.AddMinutes(11).AddSeconds(5) }.RemainingLabel(now));
        Assert.Equal("in 1 h 05 min", new CookieReminder { DueAt = now.AddMinutes(65) }.RemainingLabel(now));
        Assert.Equal("now", new CookieReminder { DueAt = now.AddSeconds(-5) }.RemainingLabel(now));
    }
}

public class BreakNudgeScheduleTests
{
    private static readonly DateTime Start = new(2026, 11, 20, 9, 0, 0, DateTimeKind.Utc);
    private static readonly BreakNudge[] All = Enum.GetValues<BreakNudge>();

    [Fact]
    public void NothingIsDueBeforeItsInterval()
    {
        var schedule = new BreakNudgeSchedule(Start);
        Assert.Null(schedule.Due(Start.AddMinutes(19), new[] { BreakNudge.Eyes, BreakNudge.Water }));
        Assert.Equal(BreakNudge.Eyes, schedule.Due(Start.AddMinutes(20), new[] { BreakNudge.Eyes, BreakNudge.Water }));
        Assert.Null(schedule.Due(Start.AddHours(3), Array.Empty<BreakNudge>()));
    }

    [Fact]
    public void TheMostOverdueWinsAndNudgesKeepTheirDistance()
    {
        var schedule = new BreakNudgeSchedule(Start);
        var t = Start.AddMinutes(61);
        Assert.Equal(BreakNudge.Eyes, schedule.Due(t, All));
        schedule.MarkShown(BreakNudge.Eyes, t);
        Assert.Null(schedule.Due(t.AddMinutes(4), All));
        Assert.Equal(BreakNudge.Posture, schedule.Due(t.AddMinutes(5), All));
    }

    [Fact]
    public void MeetingAppsAreRecognised()
    {
        Assert.True(MeetingApps.IsMeeting("Zoom"));
        Assert.True(MeetingApps.IsMeeting("ms-teams"));
        Assert.True(MeetingApps.IsMeeting("CiscoCollabHost"));
        Assert.False(MeetingApps.IsMeeting("chrome"));
        Assert.False(MeetingApps.IsMeeting(null));
    }
}

public class BedtimeTests
{
    private static DateTime Local(int day, int hour, int minute = 0) => new(2026, 11, day, hour, minute, 0, DateTimeKind.Local);

    [Fact]
    public void OnlyInsideTheWindowAfterBedtime()
    {
        int bedtime = 23 * 60;
        Assert.False(Bedtime.ShouldWindDown(Local(20, 22, 59), bedtime, null));
        Assert.True(Bedtime.ShouldWindDown(Local(20, 23), bedtime, null));
        Assert.True(Bedtime.ShouldWindDown(Local(21, 1, 30), bedtime, null));
        Assert.False(Bedtime.ShouldWindDown(Local(21, 2), bedtime, null));
    }

    [Fact]
    public void OncePerNightAndAfterMidnightBedtimes()
    {
        int bedtime = 23 * 60;
        var shown = Local(20, 23, 5);
        Assert.False(Bedtime.ShouldWindDown(Local(21, 0, 30), bedtime, shown));
        Assert.True(Bedtime.ShouldWindDown(Local(21, 23, 1), bedtime, shown));
        Assert.False(Bedtime.ShouldWindDown(Local(20, 23, 50), 30, null));
        Assert.True(Bedtime.ShouldWindDown(Local(21, 0, 45), 30, null));
    }
}

public class SystemWatchTests
{
    private static readonly DateTime Now = new(2026, 11, 20, 10, 0, 0, DateTimeKind.Utc);
    private static readonly SystemAlertKind[] All = Enum.GetValues<SystemAlertKind>();

    [Fact]
    public void BatteryWarnsOnceAtLowThenCriticalAndReArmsAfterCharging()
    {
        var watch = new SystemWatch();
        Assert.Empty(watch.Update(new SystemSnapshot(BatteryPercent: 25), Now, All));
        Assert.Equal(new SystemAlert(SystemAlertType.LowBattery, 20), Assert.Single(watch.Update(new SystemSnapshot(BatteryPercent: 20), Now, All)));
        Assert.Empty(watch.Update(new SystemSnapshot(BatteryPercent: 15), Now, All));
        Assert.Equal(new SystemAlert(SystemAlertType.CriticalBattery, 9), Assert.Single(watch.Update(new SystemSnapshot(BatteryPercent: 9), Now, All)));
        Assert.Empty(watch.Update(new SystemSnapshot(BatteryPercent: 8), Now, All));
        watch.Update(new SystemSnapshot(BatteryPercent: 9, IsCharging: true), Now, All);
        Assert.Single(watch.Update(new SystemSnapshot(BatteryPercent: 18), Now, All));
    }

    [Fact]
    public void TheCpuHasToStayBusyAndThenCoolsDown()
    {
        var watch = new SystemWatch();
        for (int i = 0; i < SystemWatch.BusySamples - 1; i++)
            Assert.Empty(watch.Update(new SystemSnapshot(CpuLoad: 0.99), Now.AddSeconds(i * 20), All));
        Assert.Equal(SystemAlertType.CpuBusy, Assert.Single(watch.Update(new SystemSnapshot(CpuLoad: 0.99), Now.AddSeconds(200), All)).Type);
        for (int i = 0; i < 20; i++)
            Assert.Empty(watch.Update(new SystemSnapshot(CpuLoad: 0.99), Now.AddSeconds(220 + i * 20), All));
    }

    [Fact]
    public void DiskAndNetwork()
    {
        var watch = new SystemWatch();
        var low = new SystemSnapshot(DiskFreeBytes: 6_000_000_000, DiskTotalBytes: 500_000_000_000);
        Assert.Equal(6, Assert.Single(watch.Update(low, Now, All)).Value);
        Assert.Empty(watch.Update(low, Now.AddHours(1), All));
        Assert.Single(watch.Update(low, Now.AddHours(25), All));

        var net = new SystemWatch();
        Assert.Empty(net.Update(new SystemSnapshot(IsOnline: true), Now, All));
        Assert.Equal(SystemAlertType.Offline, Assert.Single(net.Update(new SystemSnapshot(IsOnline: false), Now, All)).Type);
        Assert.Equal(SystemAlertType.BackOnline, Assert.Single(net.Update(new SystemSnapshot(IsOnline: true), Now, All)).Type);

        var quiet = new SystemWatch();
        quiet.Update(new SystemSnapshot(IsOnline: true), Now, Array.Empty<SystemAlertKind>());
        Assert.Empty(quiet.Update(new SystemSnapshot(IsOnline: false), Now, Array.Empty<SystemAlertKind>()));
        Assert.Empty(quiet.Update(new SystemSnapshot(IsOnline: true), Now, Array.Empty<SystemAlertKind>()));
    }

    [Fact]
    public void CpuLoadFromSystemTimes()
    {
        // 100 ticks passed, 25 of them idle: 75% busy. Kernel time includes idle.
        Assert.Equal(0.75, CpuLoad.Between((1000, 2000, 3000), (1025, 2060, 3040))!.Value, 3);
        Assert.Null(CpuLoad.Between((1, 1, 1), (1, 1, 1)));
    }
}

public class DownloadAndScreenshotTests
{
    [Fact]
    public void DownloadsAreAnnouncedOnceTheyStopGrowing()
    {
        var watch = new DownloadWatch();
        Assert.Empty(watch.Update(new Dictionary<string, long> { ["old.zip"] = 10 }));
        Assert.Empty(watch.Update(new Dictionary<string, long> { ["old.zip"] = 10, ["movie.mp4.crdownload"] = 500 }));
        Assert.Empty(watch.Update(new Dictionary<string, long> { ["old.zip"] = 10, ["movie.mp4"] = 900 }));
        Assert.Empty(watch.Update(new Dictionary<string, long> { ["old.zip"] = 10, ["movie.mp4"] = 1000 }));
        Assert.Equal(new[] { "movie.mp4" }, watch.Update(new Dictionary<string, long> { ["old.zip"] = 10, ["movie.mp4"] = 1000 }));
        Assert.Empty(watch.Update(new Dictionary<string, long> { ["old.zip"] = 10, ["movie.mp4"] = 1000 }));
        Assert.True(DownloadWatch.IsPartial("setup.exe.part"));
        Assert.True(DownloadWatch.IsPartial("desktop.ini"));
        Assert.False(DownloadWatch.IsPartial("report.pdf"));
    }

    [Fact]
    public void OnlyOldScreenshotsAreOffered()
    {
        var now = new DateTime(2026, 11, 20, 12, 0, 0, DateTimeKind.Utc);
        var old = now.AddDays(-2);
        var files = new[]
        {
            ("Screenshot 2026-11-01 101010.png", old),
            ("Screenshot 2026-11-19 230000.png", now.AddHours(-1)),
            ("Holiday photo.png", old),
            ("Screenshot notes.txt", old),
            ("Snip 3.jpg", old)
        };
        Assert.Equal(new[] { "Screenshot 2026-11-01 101010.png", "Snip 3.jpg" }, ScreenshotTidy.Candidates(files, now));
    }

    [Fact]
    public void TidyingMovesWithoutOverwriting()
    {
        using var temp = new TempFolder();
        string desktop = temp.Sub("Desktop");
        string shots = temp.Sub("Screenshots");
        File.WriteAllText(Path.Combine(shots, "Screenshot 1.png"), "old");
        File.WriteAllText(Path.Combine(desktop, "Screenshot 1.png"), "new");
        File.WriteAllText(Path.Combine(desktop, "Screenshot 2.png"), "two");

        Assert.Equal(2, ScreenshotTidy.Move(new[] { "Screenshot 1.png", "Screenshot 2.png" }, desktop, shots));
        Assert.Equal("old", File.ReadAllText(Path.Combine(shots, "Screenshot 1.png")));
        Assert.Equal("new", File.ReadAllText(Path.Combine(shots, "Screenshot 1 2.png")));
        Assert.True(File.Exists(Path.Combine(shots, "Screenshot 2.png")));
        Assert.Empty(Directory.GetFiles(desktop));
    }
}

public class CookieCommandTests
{
    private static CookieCommand? Parse(string link) => CookieCommand.Parse(link, out _);

    [Fact]
    public void EveryRoute()
    {
        Assert.Equal(new CookieCommand(CookieCommandKind.Say, "Hello there"), Parse("cookie://say?text=Hello%20there"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Remind, "Call Mom", 20), Parse("cookie://remind?minutes=20&text=Call+Mom"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Remind, "", 5), Parse("cookie://timer?minutes=5"));
        Assert.Equal(new CookieCommand(CookieCommandKind.StartFocus, Minutes: 50), Parse("cookie://focus/start?minutes=50"));
        Assert.Equal(new CookieCommand(CookieCommandKind.StopFocus), Parse("cookie://focus/stop"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Quiet, Minutes: 60), Parse("cookie://quiet/on?minutes=60"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Quiet, On: false), Parse("cookie://quiet/off"));
        Assert.Equal(new CookieCommand(CookieCommandKind.ToggleQuiet), Parse("cookie://quiet/toggle"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Summon), Parse("COOKIE://Summon"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Emote, Emote: EmoteId.Love), Parse("cookie://emote?name=Love"));
        Assert.Equal(new CookieCommand(CookieCommandKind.AddTodo, "Taxes"), Parse("cookie://todo/add?text=Taxes"));
        Assert.Equal(new CookieCommand(CookieCommandKind.AddNote, "Milk"), Parse("cookie://note?text=Milk"));
        Assert.Equal(new CookieCommand(CookieCommandKind.Ask), Parse("cookie://ask"));
    }

    [Fact]
    public void BadLinksAreRejectedAndValuesClamped()
    {
        Assert.Null(CookieCommand.Parse("https://example.com/say?text=hi", out string? error));
        Assert.NotNull(error);
        Assert.Null(Parse("cookie://say"));
        Assert.Null(Parse("cookie://remind?text=x"));
        Assert.Null(Parse("cookie://emote?name=dance"));
        Assert.Null(Parse("cookie://emote?name=3"));
        Assert.Null(Parse("cookie://delete-everything"));
        Assert.Equal(5, Parse("cookie://focus/start?minutes=1")!.Minutes);
        Assert.Equal(1440, Parse("cookie://timer?minutes=99999")!.Minutes);
        Assert.Equal(CookieCommand.MaximumText, Parse("cookie://say?text=" + new string('a', 1000))!.Text.Length);
    }

    [Fact]
    public void LinksRoundTrip()
    {
        var commands = new[]
        {
            new CookieCommand(CookieCommandKind.Say, "Hi & bye"),
            new CookieCommand(CookieCommandKind.Remind, "Tea?", 3),
            new CookieCommand(CookieCommandKind.Remind, "", 7),
            new CookieCommand(CookieCommandKind.StartFocus, Minutes: 25),
            new CookieCommand(CookieCommandKind.StartFocus),
            new CookieCommand(CookieCommandKind.Quiet, Minutes: 30),
            new CookieCommand(CookieCommandKind.Quiet),
            new CookieCommand(CookieCommandKind.Quiet, On: false),
            new CookieCommand(CookieCommandKind.Emote, Emote: EmoteId.Sleepy),
            new CookieCommand(CookieCommandKind.AddTodo, "A/B test"),
            new CookieCommand(CookieCommandKind.AddNote, "50% off")
        };
        foreach (var command in commands) Assert.Equal(command, Parse(command.ToLink()));
    }

    [Fact]
    public async Task TheChannelPassesLinksToTheRunningCopy()
    {
        string pipe = "ckt" + Guid.NewGuid().ToString("N")[..8];
        using var channel = new CommandChannel(pipe);
        var received = new TaskCompletionSource<string>();
        channel.Received += link => received.TrySetResult(link);
        channel.StartListening();

        bool sent = false;
        for (int attempt = 0; attempt < 20 && !sent; attempt++)
        {
            sent = CommandChannel.Send(pipe, "cookie://say?text=hi", 500);
            if (!sent) await Task.Delay(50);
        }
        Assert.True(sent);
        Assert.Equal("cookie://say?text=hi", await received.Task.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.False(CommandChannel.Send("ckn" + Guid.NewGuid().ToString("N")[..8], "x", 200));
    }
}

public class ClipboardAndDropTests
{
    [Fact]
    public void HistoryIsNewestFirstWithoutDuplicates()
    {
        var history = new ClipboardHistory();
        Assert.False(history.Add("  "));
        history.Add("a");
        history.Add("b");
        history.Add("a");
        Assert.Equal(new[] { "a", "b" }, history.Items);
        for (int i = 0; i < 20; i++) history.Add($"item {i}");
        Assert.Equal(ClipboardHistory.Capacity, history.Items.Count);
        Assert.False(history.Add(new string('x', ClipboardHistory.MaximumLength + 1)));
        Assert.Equal("hello world", ClipboardHistory.Preview("  hello\n\n  world "));
        Assert.Equal("aaaaaaaaa…", ClipboardHistory.Preview(new string('a', 100), 10));
    }

    [Fact]
    public void MovingNeverOverwritesAndCopyingKeepsTheOriginal()
    {
        using var temp = new TempFolder();
        string input = temp.Sub("in");
        string output = temp.Sub("out");
        File.WriteAllText(Path.Combine(output, "a.txt"), "old");
        string a = Path.Combine(input, "a.txt");
        string b = Path.Combine(input, "b.txt");
        File.WriteAllText(a, "new");
        File.WriteAllText(b, "b");

        Assert.Equal(2, FileDrop.MoveOrCopy(new[] { a, b }, output, copy: false));
        Assert.False(File.Exists(a));
        Assert.Equal("old", File.ReadAllText(Path.Combine(output, "a.txt")));
        Assert.Equal("new", File.ReadAllText(Path.Combine(output, "a 2.txt")));

        string c = Path.Combine(input, "c.txt");
        File.WriteAllText(c, "c");
        Assert.Equal(1, FileDrop.MoveOrCopy(new[] { c }, output, copy: true));
        Assert.True(File.Exists(c));
    }

    [Fact]
    public void ZippingOneOrSeveralLeavesTheOriginals()
    {
        using var temp = new TempFolder();
        string input = temp.Sub("in");
        string report = Path.Combine(input, "report.pdf");
        string notes = Path.Combine(input, "notes.txt");
        File.WriteAllText(report, "pdf");
        File.WriteAllText(notes, "txt");
        string folder = temp.Sub("in/photos");
        File.WriteAllText(Path.Combine(folder, "cat.png"), "png");

        Assert.Equal(Path.Combine(input, "report.zip"), FileDrop.Zip(new[] { report }));
        string? archive = FileDrop.Zip(new[] { report, notes, folder });
        Assert.Equal(Path.Combine(input, "Archive.zip"), archive);
        using (var zip = ZipFile.OpenRead(archive!))
        {
            Assert.Equal(new[] { "notes.txt", "photos/cat.png", "report.pdf" }, zip.Entries.Select(e => e.FullName).OrderBy(n => n));
        }
        Assert.True(File.Exists(report));
        Assert.Equal(Path.Combine(input, "report 2.zip"), FileDrop.Zip(new[] { report }));
        Assert.Equal("Zipped all 3 together!", FileDrop.Summary(3, FileDropActionKind.Zip, null));
        Assert.Equal("Filed it in Work!", FileDrop.Summary(1, FileDropActionKind.Move, Path.Combine(temp.Path, "Work")));
    }
}

public class AskCookieTests
{
    [Fact]
    public void RequestShape()
    {
        var body = AskCookie.RequestBody("sys", new JsonArray { new JsonObject { ["role"] = "user", ["content"] = "hi" } });
        Assert.Equal("claude-opus-5-5", body["model"]!.GetValue<string>());
        Assert.Equal("low", body["output_config"]!["effort"]!.GetValue<string>());
        Assert.Equal("default", body["fallbacks"]!.GetValue<string>());
        Assert.Null(body["temperature"]);
        Assert.Null(body["thinking"]);
        using var request = AskCookie.Request("k", body);
        Assert.Equal("2026-10-21", request.Headers.GetValues("anthropic-version").Single());
        Assert.Equal("server-side-fallback-2026-07-01", request.Headers.GetValues("anthropic-beta").Single());
        Assert.Equal("k", request.Headers.GetValues("x-api-key").Single());
    }

    [Fact]
    public void ParsesTextAndKeepsEveryBlock()
    {
        string json = """{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"Mrrp! "},{"type":"text","text":"Hello."}],"stop_reason":"end_turn"}""";
        var reply = Assert.IsType<AskReply.Text>(AskCookie.Parse(json, 200));
        Assert.Equal("Mrrp! Hello.", reply.Reply);
        Assert.Equal(3, reply.Content.Count);
        Assert.IsType<AskReply.Declined>(AskCookie.Parse("""{"content":[],"stop_reason":"refusal"}""", 200));
        Assert.Contains("API key", Assert.IsType<AskReply.Failed>(AskCookie.Parse("""{"type":"error","error":{"type":"authentication_error","message":"bad"}}""", 401)).Message);
        Assert.IsType<AskReply.Failed>(AskCookie.Parse("nope", 502));
    }

    [Fact]
    public async Task OffByDefaultThenAsksWithHistory()
    {
        var profile = new CookieProfile();
        var sent = new List<JsonObject>();
        var chat = new ChatSession(() => profile)
        {
            ApiKey = () => "test-key",
            Send = async (request, token) =>
            {
                sent.Add((JsonObject)JsonNode.Parse(await request.Content!.ReadAsStringAsync(token))!);
                Assert.Equal("test-key", request.Headers.GetValues("x-api-key").Single());
                return ("""{"content":[{"type":"text","text":"Purr."}],"stop_reason":"end_turn"}""", 200);
            }
        };

        await chat.AskAsync("Hello");
        Assert.Empty(sent);
        Assert.Equal(ChatSpeaker.Notice, chat.Lines.Last().Speaker);

        profile.Settings.AskCookieEnabled = true;
        await chat.AskAsync("Hello");
        await chat.AskAsync("How are you?");
        Assert.Equal(2, sent.Count);
        var roles = ((JsonArray)sent[1]["messages"]!).Select(m => m!["role"]!.GetValue<string>());
        Assert.Equal(new[] { "user", "assistant", "user" }, roles);
        Assert.Equal(new[] { "Purr.", "Purr." }, chat.Lines.Where(l => l.Speaker == ChatSpeaker.Cookie).Select(l => l.Text));
        Assert.Contains(profile.DisplayName, sent[0]["system"]!.GetValue<string>());

        chat.Reset();
        Assert.Empty(chat.Lines);
    }

    [Fact]
    public async Task NoKeyNoRequest()
    {
        var profile = new CookieProfile();
        profile.Settings.AskCookieEnabled = true;
        int calls = 0;
        var chat = new ChatSession(() => profile)
        {
            ApiKey = () => null,
            Send = (request, token) => { calls++; return Task.FromResult(("", 200)); }
        };
        await chat.AskAsync("Hi");
        Assert.Equal(0, calls);
        Assert.False(chat.IsReady);
    }
}

public class HelpersCoordinatorTests
{
    private readonly CookieProfile _profile = new();
    private readonly CookieBehaviorController _cookie = new(new CookieAnimationController(), new ScreenGeometryService(), new TestAudioManager());
    private readonly List<string> _said = new();
    private readonly List<SoundEffect> _played = new();
    private int _broughtOver;
    private DateTime _utc = new(2026, 11, 20, 9, 0, 0, DateTimeKind.Utc);
    private DateTime _local = new(2026, 11, 20, 14, 0, 0, DateTimeKind.Local);
    private TimeSpan _idle = TimeSpan.Zero;
    private bool _quiet;
    private bool _focusing;
    private string? _front = "chrome";
    private SystemSnapshot _snapshot = new();
    private Dictionary<string, long> _downloads = new();
    private List<string> _screenshots = new();
    private List<string> _moved = new();

    private HelpersCoordinator Make()
    {
        var helpers = new HelpersCoordinator(_profile, _cookie)
        {
            Say = (text, _) => _said.Add(text),
            Play = _played.Add,
            BringToCursor = () => _broughtOver++,
            UtcNow = () => _utc,
            LocalNow = () => _local,
            IdleTime = () => _idle,
            IsQuiet = () => _quiet,
            IsFocusing = () => _focusing,
            FrontmostProcess = () => _front,
            SystemSnapshot = () => _snapshot,
            DownloadsListing = () => _downloads,
            ScreenshotCandidates = () => ("C:\\Desktop", _screenshots),
            MoveScreenshots = (names, _) => { _moved = names.ToList(); return names.Count; }
        };
        helpers.Start();
        return helpers;
    }

    [Fact]
    public void AReminderComesToTheCursorAndIsSaidOnce()
    {
        var helpers = Make();
        helpers.AddReminder("Call Mom", 20);
        _said.Clear();
        _utc = _utc.AddMinutes(19);
        helpers.DeliverDueReminders();
        Assert.Empty(_said);
        _utc = _utc.AddMinutes(1);
        _quiet = true;
        _focusing = true;
        helpers.DeliverDueReminders();
        Assert.Equal(new[] { "Call Mom" }, _said);
        Assert.Equal(1, _broughtOver);
        Assert.Empty(_profile.Reminders);
        helpers.DeliverDueReminders();
        Assert.Single(_said);
    }

    [Fact]
    public void RemindersSurviveARestartAndCanBeCancelled()
    {
        using var temp = new TempFolder();
        var manager = new SettingsManager(Path.Combine(temp.Path, "profile.json"));
        var helpers = Make();
        var tea = helpers.AddReminder("Tea", 5);
        helpers.AddReminder("Stretch", 10);
        helpers.CancelReminder(tea.Id);
        manager.SaveProfileImmediate(_profile);
        var loaded = manager.LoadProfile();
        Assert.Equal(new[] { "Stretch" }, loaded.Reminders.Select(r => r.Text));
    }

    [Fact]
    public void NudgesWaitForABetterMoment()
    {
        _profile.Settings.BreakNudges.Add(BreakNudge.Eyes);
        var helpers = Make();
        _utc = _utc.AddMinutes(20);
        _quiet = true;
        helpers.CheckBreakNudges();
        _quiet = false;
        _front = "Zoom";
        helpers.CheckBreakNudges();
        _front = "chrome";
        _focusing = true;
        helpers.CheckBreakNudges();
        Assert.Empty(_said);
        _focusing = false;
        helpers.CheckBreakNudges();
        Assert.Single(_said);
        helpers.CheckBreakNudges();
        Assert.Single(_said);
    }

    [Fact]
    public void SteppingAwayResetsTheNudgeClock()
    {
        _profile.Settings.BreakNudges.Add(BreakNudge.Eyes);
        var helpers = Make();
        _utc = _utc.AddMinutes(15);
        _idle = TimeSpan.FromMinutes(6);
        helpers.CheckBreakNudges();
        _idle = TimeSpan.Zero;
        _utc = _utc.AddMinutes(10);
        helpers.CheckBreakNudges();
        Assert.Empty(_said);
        _utc = _utc.AddMinutes(10);
        helpers.CheckBreakNudges();
        Assert.Single(_said);
    }

    [Fact]
    public void TheFocusGuardOnlyWatchesChosenAppsDuringASession()
    {
        _profile.Settings.DistractingApps.Add(new DistractingApp { ProcessName = "steam", DisplayName = "Steam" });
        var helpers = Make();
        helpers.AppSwitched("steam");
        Assert.Empty(_said);
        _focusing = true;
        helpers.AppSwitched("chrome");
        Assert.Empty(_said);
        helpers.AppSwitched("Steam.exe");
        Assert.Single(_said);
        Assert.Equal(1, _broughtOver);
        helpers.AppSwitched("steam");
        Assert.Single(_said);
        _utc += HelpersCoordinator.FocusGuardCooldown;
        helpers.AppSwitched("steam");
        Assert.Equal(2, _said.Count);
    }

    [Fact]
    public void BedtimeComesOnceAndOnlyWhenTurnedOn()
    {
        _local = new DateTime(2026, 11, 20, 23, 15, 0, DateTimeKind.Local);
        var helpers = Make();
        helpers.CheckBedtime();
        Assert.Empty(_said);
        _profile.Settings.BedtimeEnabled = true;
        helpers.CheckBedtime();
        Assert.Single(_said);
        Assert.Equal(SoundEffect.Sleep, _played.Last());
        _local = _local.AddMinutes(30);
        helpers.CheckBedtime();
        Assert.Single(_said);
    }

    [Fact]
    public void LowBatteryWaitsForQuietButCriticalComesThrough()
    {
        var helpers = Make();
        _quiet = true;
        _snapshot = new SystemSnapshot(BatteryPercent: 18);
        helpers.CheckSystem();
        Assert.Empty(_said);
        _snapshot = new SystemSnapshot(BatteryPercent: 7);
        helpers.CheckSystem();
        Assert.Contains("7%", Assert.Single(_said));
        Assert.Equal(1, _broughtOver);
    }

    [Fact]
    public void DownloadsAndScreenshotsOnlyWhenTurnedOn()
    {
        var helpers = Make();
        _downloads = new Dictionary<string, long> { ["a.zip"] = 1 };
        helpers.CheckDownloads();
        _profile.Settings.DownloadAlerts = true;
        helpers.CheckDownloads();
        _downloads = new Dictionary<string, long> { ["a.zip"] = 1, ["b.pdf"] = 3 };
        helpers.CheckDownloads();
        helpers.CheckDownloads();
        Assert.Equal(new[] { "Your download finished: b.pdf" }, _said);

        _said.Clear();
        _screenshots = Enumerable.Range(1, ScreenshotTidy.OfferThreshold).Select(i => $"Screenshot {i}.png").ToList();
        helpers.CheckScreenshots();
        Assert.Empty(_said);
        Assert.Equal(0, helpers.TidyableScreenshotCount());
        _profile.Settings.ScreenshotTidyOffers = true;
        helpers.CheckScreenshots();
        Assert.Single(_said);
        _utc = _utc.AddHours(1);
        helpers.CheckScreenshots();
        Assert.Single(_said);
        Assert.Equal(ScreenshotTidy.OfferThreshold, helpers.TidyScreenshots());
        Assert.Equal(ScreenshotTidy.OfferThreshold, _moved.Count);
    }

    [Fact]
    public void TasksTickOffEarnAffectionUpToADailyCap()
    {
        var helpers = Make();
        Assert.False(helpers.AddTodo("   "));
        Assert.True(helpers.AddTodo("Water the plants"));
        var id = helpers.Todos[0].Id;
        helpers.ToggleTodo(id);
        Assert.True(helpers.Todos[0].IsDone);
        Assert.Equal(CookieStatistics.TaskAffection, _profile.Statistics.Affection);
        helpers.ToggleTodo(id);
        helpers.ClearCompletedTodos();
        Assert.Single(helpers.Todos);

        var stats = new CookieStatistics();
        for (int i = 0; i < CookieStatistics.RewardedTasksPerDay; i++) Assert.True(stats.RecordTaskCompleted(_local));
        Assert.False(stats.RecordTaskCompleted(_local));
        Assert.True(stats.RecordTaskCompleted(_local.AddDays(1)));
    }

    [Fact]
    public void OlderProfilesLoadWithHelpersOff()
    {
        using var temp = new TempFolder();
        string path = Path.Combine(temp.Path, "profile.json");
        File.WriteAllText(path, """{"Version":1,"DisplayName":"Mochi","Settings":{"FocusMinutes":30}}""");
        var profile = new SettingsManager(path).LoadProfile();
        Assert.Equal("Mochi", profile.DisplayName);
        Assert.Empty(profile.Settings.BreakNudges);
        Assert.Equal(Enum.GetValues<SystemAlertKind>(), profile.Settings.SystemAlerts.ToArray());
        Assert.False(profile.Settings.DownloadAlerts);
        Assert.False(profile.Settings.ClipboardHistory);
        Assert.False(profile.Settings.AskCookieEnabled);
        Assert.True(profile.Settings.AllowLinks);
        Assert.Empty(profile.Reminders);
        Assert.Empty(profile.StickyNotes);
    }

    [Fact]
    public void NotesAreSavedAndPlacedOnScreen()
    {
        using var temp = new TempFolder();
        var manager = new SettingsManager(Path.Combine(temp.Path, "profile.json"));
        _profile.StickyNotes.Add(new StickyNote { Text = "Milk", Color = StickyColor.Pink, Left = 10, Top = 20 });
        manager.SaveProfileImmediate(_profile);
        var note = Assert.Single(manager.LoadProfile().StickyNotes);
        Assert.Equal(("Milk", StickyColor.Pink, 10.0, 20.0), (note.Text, note.Color, note.Left!.Value, note.Top!.Value));

        var area = new CoreRect(0, 0, 1000, 800);
        var (left, top) = StickyNote.PlaceBeside(new CoreRect(900, 700, 90, 90), area, 0);
        Assert.InRange(left, area.Left, area.Right - StickyNote.Width);
        Assert.InRange(top, area.Top, area.Bottom - StickyNote.Height);
    }
}

public class ManualQuietTests
{
    [Fact]
    public void ManualQuietLastsUntilItEndsAndRemindersCanPeekThrough()
    {
        var clock = new DateTime(2026, 11, 20, 9, 0, 0, DateTimeKind.Utc);
        var state = new QuietModeState { Now = () => clock };
        const int acceptsNotifications = QuietModeRules.AcceptsNotifications;

        state.SetManualQuiet(true, 30);
        Assert.True(state.Evaluate(true, acceptsNotifications));
        Assert.True(state.IsQuiet);
        state.GrantOverride(20);
        state.Evaluate(true, acceptsNotifications);
        Assert.False(state.IsQuiet);
        clock = clock.AddSeconds(21);
        state.Evaluate(true, acceptsNotifications);
        Assert.True(state.IsQuiet);
        clock = clock.AddMinutes(30);
        state.Evaluate(true, acceptsNotifications);
        Assert.False(state.IsQuiet);
        Assert.Null(state.ManualQuietUntil);

        state.SetManualQuiet(true);
        clock = clock.AddHours(10);
        state.Evaluate(false, acceptsNotifications);
        Assert.True(state.IsQuiet);
        state.SetManualQuiet(false);
        state.Evaluate(false, acceptsNotifications);
        Assert.False(state.IsQuiet);
    }
}

internal sealed class TempFolder : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "cookie-test-" + Guid.NewGuid().ToString("N"));

    public TempFolder() => Directory.CreateDirectory(Path);

    public string Sub(string name)
    {
        string folder = System.IO.Path.Combine(Path, name);
        Directory.CreateDirectory(folder);
        return folder;
    }

    public void Dispose()
    {
        try { Directory.Delete(Path, recursive: true); } catch { }
    }
}
