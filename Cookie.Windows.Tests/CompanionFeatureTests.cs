using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Imaging;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Xunit;

namespace Cookie.Windows.Tests;

public class BondTests
{
    [Fact]
    public void Points_ComeFromAffectionAndVisitDays()
    {
        var stats = new CookieStatistics { Affection = 12, VisitDays = 3 };
        Assert.Equal(12 + 3 * Bond.VisitDayPoints, Bond.Points(stats));
    }

    [Fact]
    public void Levels_MatchTheMacTable()
    {
        Assert.Equal(new[] { 0, 25, 100, 250, 600 }, Bond.Levels.Select(level => level.Points));
        Assert.Equal(new[] { "Just Met", "Friends", "Good Friends", "Best Friends", "Inseparable" }, Bond.Levels.Select(level => level.Name));
        Assert.Equal(0, Bond.LevelFor(24).Index);
        Assert.Equal(1, Bond.LevelFor(25).Index);
        Assert.Equal("Best Friends", Bond.LevelFor(250).Name);
        Assert.Equal(4, Bond.LevelFor(100_000).Index);
    }

    /// <summary>The same ids and levels as the macOS app, so a profile means the same on both.</summary>
    [Fact]
    public void UnlockIds_MatchTheMacTable()
    {
        var expected = new Dictionary<int, string[]>
        {
            [1] = new[] { "toy.feather", "accessory.bow", "accessory.collar" },
            [2] = new[] { "toy.toyMouse", "accessory.bandana", "accessory.glasses", "accessory.pumpkin", "coat.tabby", "cozy.bed" },
            [3] = new[] { "toy.fishToy", "accessory.hat", "accessory.scarf", "accessory.santaHat", "coat.tuxedo", "cozy.sunbeam" },
            [4] = new[] { "accessory.crown", "coat.points", "cozy.scratchingPost" }
        };

        foreach (var (index, ids) in expected)
        {
            Assert.Equal(ids, Bond.Levels[index].Unlocks.Select(item => item.Id));
        }
        Assert.Empty(Bond.Levels[0].Unlocks);
    }

    [Fact]
    public void ProgressTowardTheNextLevel()
    {
        var progress = Bond.ProgressFor(62);
        Assert.Equal(1, progress.Level.Index);
        Assert.Equal(2, progress.Next!.Index);
        Assert.Equal(38, progress.PointsToNext);
        Assert.Equal(37.0 / 75.0, progress.Fraction, 4);

        var top = Bond.ProgressFor(9999);
        Assert.Null(top.Next);
        Assert.Equal(1, top.Fraction);
    }

    [Fact]
    public void EveryItemIsUnlockedByExactlyOneLevel_AndEverythingIsAccountedFor()
    {
        var all = Bond.Levels.SelectMany(level => level.Unlocks).ToList();
        Assert.Equal(all.Count, all.Select(item => item.Id).Distinct().Count());

        foreach (var kind in Enum.GetValues<AccessoryKind>()) Assert.Contains(BondItem.Accessory(kind), all);
        foreach (var kind in Enum.GetValues<CozyKind>()) Assert.Contains(BondItem.Cozy(kind), all);
        foreach (var pattern in Enum.GetValues<FurPattern>().Where(p => p != FurPattern.None)) Assert.Contains(BondItem.Coat(pattern), all);

        var freeToys = Enum.GetValues<ToyKind>().Where(toy => Bond.RequiredLevel(BondItem.Toy(toy)) == null);
        Assert.Equal(new[] { ToyKind.YarnBall, ToyKind.Ball, ToyKind.Box }.OrderBy(t => t), freeToys.OrderBy(t => t));
        Assert.Null(Bond.RequiredLevel(BondItem.Coat(FurPattern.None)));
    }

    [Fact]
    public void LockedItemsOpenAtTheirLevelOrWhenKept()
    {
        var crown = BondItem.Accessory(AccessoryKind.Crown);
        Assert.False(Bond.IsUnlocked(crown, 599));
        Assert.True(Bond.IsUnlocked(crown, 600));
        Assert.True(Bond.IsUnlocked(crown, 0, new HashSet<string> { crown.Id }));
        Assert.True(Bond.IsUnlocked(BondItem.Toy(ToyKind.Ball), 0));
    }

    [Fact]
    public void NewUnlocks_CoverEverySkippedLevel()
    {
        var items = Bond.NewUnlocks(0, 250);
        Assert.Contains(BondItem.Toy(ToyKind.Feather), items);
        Assert.Contains(BondItem.Cozy(CozyKind.Bed), items);
        Assert.Contains(BondItem.Cozy(CozyKind.Sunbeam), items);
        Assert.DoesNotContain(BondItem.Accessory(AccessoryKind.Crown), items);
        Assert.Empty(Bond.NewUnlocks(3, 250));
    }

    [Fact]
    public void Visits_CountOncePerCalendarDay()
    {
        var stats = new CookieStatistics();
        var morning = new DateTime(2026, 3, 4, 9, 0, 0, DateTimeKind.Utc);

        Assert.True(stats.RecordVisit(morning, TimeZoneInfo.Utc));
        Assert.False(stats.RecordVisit(morning.AddHours(12), TimeZoneInfo.Utc));
        Assert.True(stats.RecordVisit(morning.AddDays(1), TimeZoneInfo.Utc));
        Assert.Equal(2, stats.VisitDays);
    }

    [Fact]
    public void FocusSessions_AddToTheBond()
    {
        var stats = new CookieStatistics();
        stats.RecordFocusSession(25);
        Assert.Equal(1, stats.FocusSessions);
        Assert.Equal(25, stats.FocusMinutes);
        Assert.Equal(5, stats.Affection);
    }

    [Fact]
    public void LevelUp_IsClaimedOnceAndRemembersItsItems()
    {
        var profile = new CookieProfile();
        profile.Statistics.Affection = 120;
        var tracker = new BondTracker(profile);

        var first = tracker.ClaimLevelUp();

        Assert.NotNull(first);
        Assert.Equal(2, first!.Level.Index);
        Assert.Contains(BondItem.Accessory(AccessoryKind.Glasses), first.NewItems);
        Assert.Null(tracker.ClaimLevelUp());
        Assert.Contains("cozy.bed", profile.UnlockedItems);
    }

    [Fact]
    public void WhatYouAlreadyWearStaysUnlocked()
    {
        var profile = new CookieProfile();
        profile.Appearance.Accessory(AccessoryKind.Crown).IsEnabled = true;
        profile.Appearance.Pattern = FurPattern.Tabby;
        var tracker = new BondTracker(profile);

        Assert.False(tracker.IsUnlocked(BondItem.Accessory(AccessoryKind.Crown)));
        tracker.KeepInUseItemsUnlocked();

        Assert.True(tracker.IsUnlocked(BondItem.Accessory(AccessoryKind.Crown)));
        Assert.True(tracker.IsUnlocked(BondItem.Coat(FurPattern.Tabby)));
        Assert.False(tracker.IsUnlocked(BondItem.Coat(FurPattern.Points)));
    }

    [Fact]
    public void OldProfilesWithoutTheNewFieldsStillLoad()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cookie-bond-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, "{\"Version\":1,\"DisplayName\":\"Mochi\",\"Statistics\":{\"Affection\":20}}");

            var loaded = new SettingsManager(path).LoadProfile();

            Assert.Equal("Mochi", loaded.DisplayName);
            Assert.Equal(20, loaded.Statistics.Affection);
            Assert.Equal(0, loaded.Statistics.VisitDays);
            Assert.Empty(loaded.CozyItems);
            Assert.Empty(loaded.UnlockedItems);
            Assert.True(loaded.Settings.HideInFullscreen);
            Assert.Equal(SummonShortcut.ControlAltC, loaded.Settings.SummonShortcut);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void CozyPlacementsSurviveSavingAndLoading()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cookie-cozy-{Guid.NewGuid():N}.json");
        try
        {
            var manager = new SettingsManager(path);
            var profile = new CookieProfile();
            profile.CozyItems.Add(new CozyPlacement(CozyKind.Bed, 0.3));
            profile.CozyItems.Add(new CozyPlacement(CozyKind.ScratchingPost, 0.8));
            profile.UnlockedItems.Add("accessory.crown");
            manager.SaveProfileImmediate(profile);

            var loaded = manager.LoadProfile();

            Assert.Equal(new[] { CozyKind.Bed, CozyKind.ScratchingPost }, loaded.CozyItems.Select(i => i.Kind));
            Assert.Equal(0.8, loaded.CozyItems[1].Position, 4);
            Assert.Contains("accessory.crown", loaded.UnlockedItems);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void CozyPositionsAreClamped_AndAssetNamesMatchTheArt()
    {
        Assert.Equal(0.96, new CozyPlacement(CozyKind.Bed, 7).Position);
        Assert.Equal(0.04, new CozyPlacement(CozyKind.Bed, -2).Position);
        Assert.Equal("cozy-scratchingPost", CozyKind.ScratchingPost.GetAssetName());
        Assert.Equal("item-cozy-bed", CozyKind.Bed.GetIconName());
    }
}

public class FocusTimerTests
{
    [Fact]
    public void AFocusSessionRunsDownAndReportsItsLength()
    {
        var timer = new FocusTimer();
        timer.StartFocus(25);

        Assert.Equal(FocusPhase.Focusing, timer.Phase);
        Assert.Equal("25:00", timer.RemainingLabel);
        Assert.Null(timer.Advance(60));
        Assert.Equal("24:00", timer.RemainingLabel);
        Assert.Equal(1.0 / 25.0, timer.Progress, 4);

        var done = timer.Advance(24 * 60);
        Assert.Equal(new FocusEvent(FocusEventKind.FocusCompleted, 25), done);
        Assert.False(timer.IsActive);
    }

    [Fact]
    public void BreaksFinishWithTheirOwnEvent()
    {
        var timer = new FocusTimer();
        timer.StartBreak(5);

        Assert.Equal(FocusPhase.OnBreak, timer.Phase);
        Assert.Equal(FocusEventKind.BreakCompleted, timer.Advance(301)!.Value.Kind);
    }

    [Fact]
    public void CancelledSessionsReportNothing_AndSleepingThroughTheEndFinishesOnce()
    {
        var timer = new FocusTimer();
        timer.StartFocus(15);
        timer.Advance(600);
        timer.Cancel();
        Assert.Equal(FocusPhase.Idle, timer.Phase);
        Assert.Null(timer.Advance(9999));

        timer.StartFocus(10);
        Assert.Equal(new FocusEvent(FocusEventKind.FocusCompleted, 10), timer.Advance(3 * 3600));
        Assert.Null(timer.Advance(10));
    }

    [Theory]
    [InlineData(0.2, "0:01")]
    [InlineData(65, "1:05")]
    [InlineData(3725, "1:02:05")]
    public void LabelsRoundUpAndShowHours(double seconds, string expected)
    {
        Assert.Equal(expected, FocusTimer.Format(seconds));
    }
}

public class DailyRhythmTests
{
    private static DateTime Day(int month, int day, int hour = 12, int year = 2026) => new(year, month, day, hour, 0, 0);

    [Fact]
    public void SeasonsDressHer()
    {
        Assert.Equal(new[] { AccessoryKind.Pumpkin }, DailyRhythm.Outfit(Day(10, 31), null));
        Assert.Equal(new[] { AccessoryKind.SantaHat, AccessoryKind.Scarf }, DailyRhythm.Outfit(Day(12, 25), null));
        Assert.Equal(new[] { AccessoryKind.Scarf }, DailyRhythm.Outfit(Day(1, 20), null));
        Assert.Empty(DailyRhythm.Outfit(Day(6, 15), null));
        Assert.Empty(DailyRhythm.Outfit(Day(10, 23), null));
    }

    [Fact]
    public void BirthdayNeedsAFullYearAndTheRightDay()
    {
        var met = Day(3, 8, 14, 2025);
        Assert.True(DailyRhythm.IsBirthday(Day(3, 8, 8), met));
        Assert.False(DailyRhythm.IsBirthday(Day(3, 9), met));
        Assert.False(DailyRhythm.IsBirthday(Day(3, 8, 15, 2025), met));
        Assert.Equal(new[] { AccessoryKind.Hat }, DailyRhythm.Outfit(Day(3, 8), met));
    }

    [Fact]
    public void BirthdayOutranksOtherHeadwear()
    {
        var met = Day(12, 12, 12, 2024);
        Assert.Equal(new[] { AccessoryKind.Hat, AccessoryKind.Scarf }, DailyRhythm.Outfit(Day(12, 12), met));
    }

    [Fact]
    public void WhatTheUserChoseAlwaysWins_AndTheStoredConfigIsNeverChanged()
    {
        var config = new CookieAppearanceConfig();
        config.Accessory(AccessoryKind.Crown).IsEnabled = true;

        var dressed = config.WithDailyOutfit(Day(12, 25), null);

        Assert.False(dressed.Accessory(AccessoryKind.SantaHat).IsEnabled);
        Assert.True(dressed.Accessory(AccessoryKind.Crown).IsEnabled);
        Assert.True(dressed.Accessory(AccessoryKind.Scarf).IsEnabled);
        Assert.False(config.Accessory(AccessoryKind.Scarf).IsEnabled);
    }

    [Fact]
    public void Greetings_FollowTheClock_AndMatchTheMacWording()
    {
        Assert.Equal("Good morning!", DailyRhythm.Greeting(Day(5, 5, 8), null));
        Assert.Equal("Hi there!", DailyRhythm.Greeting(Day(5, 5, 13), null));
        Assert.Equal("Good evening!", DailyRhythm.Greeting(Day(5, 5, 19), null));
        Assert.Contains("late", DailyRhythm.Greeting(Day(5, 5, 23), null));
        Assert.Equal("It's our birthday! 2 years together.", DailyRhythm.Greeting(Day(5, 5, 8), Day(5, 5, 12, 2024)));
        Assert.Equal("It's our birthday! One year together.", DailyRhythm.Greeting(Day(5, 5, 8), Day(5, 5, 12, 2025)));
    }

    [Theory]
    [InlineData(4, TimeOfDay.LateNight)]
    [InlineData(5, TimeOfDay.Morning)]
    [InlineData(9, TimeOfDay.Morning)]
    [InlineData(10, TimeOfDay.Day)]
    [InlineData(16, TimeOfDay.Day)]
    [InlineData(17, TimeOfDay.Evening)]
    [InlineData(21, TimeOfDay.Evening)]
    [InlineData(22, TimeOfDay.LateNight)]
    public void TimeOfDayBuckets_MatchTheMacApp(int hour, TimeOfDay expected)
    {
        Assert.Equal(expected, TimeOfDayExtensions.At(Day(5, 5, hour)));
    }

    [Fact]
    public void NightIsTheSleepiestTime()
    {
        Assert.True(TimeOfDay.LateNight.NapChance() > TimeOfDay.Evening.NapChance());
        Assert.True(TimeOfDay.Evening.NapChance() > TimeOfDay.Day.NapChance());
        Assert.True(TimeOfDay.Day.NapChance() > TimeOfDay.Morning.NapChance());
    }
}

public class QuietModeAndShortcutTests
{
    [Theory]
    [InlineData(QuietModeRules.Busy, true)]
    [InlineData(QuietModeRules.D3DFullScreen, true)]
    [InlineData(QuietModeRules.PresentationMode, true)]
    [InlineData(QuietModeRules.App, true)]
    [InlineData(QuietModeRules.AcceptsNotifications, false)]
    [InlineData(QuietModeRules.QuietTime, false)]
    [InlineData(QuietModeRules.NotPresent, false)]
    public void FullscreenAndPresentationStatesHideHer(int state, bool expected)
    {
        Assert.Equal(expected, QuietModeRules.ShouldHide(state));
    }

    [Fact]
    public void SummoningOverridesQuietModeBriefly()
    {
        var clock = new DateTime(2026, 5, 5, 12, 0, 0, DateTimeKind.Utc);
        var quiet = new QuietModeState { Now = () => clock };

        Assert.False(quiet.Evaluate(true, QuietModeRules.AcceptsNotifications));
        Assert.True(quiet.Evaluate(true, QuietModeRules.Busy));
        Assert.True(quiet.IsQuiet);

        quiet.GrantOverride(20);
        Assert.True(quiet.Evaluate(true, QuietModeRules.Busy));
        Assert.False(quiet.IsQuiet);

        clock = clock.AddSeconds(21);
        Assert.True(quiet.Evaluate(true, QuietModeRules.Busy));
        Assert.True(quiet.IsQuiet);
    }

    [Fact]
    public void TurningTheSettingOffNeverQuietsHer()
    {
        var quiet = new QuietModeState();
        Assert.False(quiet.Evaluate(false, QuietModeRules.Busy));
        Assert.False(quiet.IsQuiet);
    }

    [Fact]
    public void SummonedCookieAppearsBesideTheCursor_MatchingTheMac()
    {
        var area = new CoreRect(0, 0, 1440, 900);
        var size = new CoreSize(160, 160);

        var normal = SummonPlacement.Origin(new CorePoint(500, 400), size, area);
        Assert.Equal(540, normal.X);
        Assert.Equal(320, normal.Y);
        Assert.Equal(1200, SummonPlacement.Origin(new CorePoint(1400, 400), size, area).X);
        Assert.Equal(8, SummonPlacement.Origin(new CorePoint(10, 5), size, area).Y);
    }

    [Fact]
    public void EveryShortcutHasAKeyExceptOff()
    {
        foreach (var shortcut in Enum.GetValues<SummonShortcut>())
        {
            Assert.Equal(shortcut != SummonShortcut.Off, shortcut.GetVirtualKey().HasValue);
        }
        Assert.Equal(0x43u, SummonShortcut.ControlAltC.GetVirtualKey());
        Assert.Equal(SummonShortcutExtensions.ModControl | SummonShortcutExtensions.ModAlt, SummonShortcut.ControlAltC.GetModifiers());
        Assert.NotEqual(SummonShortcut.ControlAltC.GetModifiers(), SummonShortcut.ControlShiftAltC.GetModifiers());
    }
}

public class CompanionControllerTests
{
    private readonly CookieAnimationController _animation = new();
    private readonly TestAudioManager _audio = new();
    private readonly CookieBehaviorController _cookie;

    public CompanionControllerTests()
    {
        _cookie = new CookieBehaviorController(_animation, new ScreenGeometryService(), _audio);
        _cookie.SetPosition(new CorePoint(600, 400));
    }

    private void Run(double seconds)
    {
        for (double t = 0; t < seconds; t += 0.05) _cookie.Update(0.05, new CorePoint(5000, 5000));
    }

    [Fact]
    public void Focus_SettlesIntoANapAndStaysThere()
    {
        _cookie.BeginFocus();
        Assert.Equal(CookieState.Yawning, _cookie.State);
        Assert.True(_cookie.IsFocusing);

        Run(6);
        Assert.Equal(CookieState.Sleeping, _cookie.State);

        Run(600);
        Assert.Equal(CookieState.Sleeping, _cookie.State);
        Assert.Equal(CookieAnimationId.Sleep, _animation.CurrentAnimationId);
    }

    [Fact]
    public void PettingDuringFocus_ReactsThenReturnsToSleep()
    {
        _cookie.BeginFocus();
        Run(6);

        _cookie.Pet();
        Assert.Equal(CookieState.Reacting, _cookie.State);

        Run(10);
        Assert.Equal(CookieState.Sleeping, _cookie.State);
        Assert.True(_cookie.IsFocusing);
    }

    [Fact]
    public void FocusStopsHerFromFollowingTheCursor()
    {
        _cookie.BeginFocus();
        Run(6);

        for (int i = 0; i < 400; i++)
        {
            _cookie.Update(0.05, new CorePoint(700 + i % 3, 480));
        }

        Assert.Equal(CookieState.Sleeping, _cookie.State);
    }

    [Fact]
    public void FinishingFocus_StretchesMeowsAndSits()
    {
        _cookie.BeginFocus();
        Run(6);

        _cookie.EndFocus(completed: true);
        Assert.Equal(CookieState.Stretching, _cookie.State);
        Assert.False(_cookie.IsFocusing);

        Run(2.2);
        Assert.Equal(CookieState.Reacting, _cookie.State);
        Assert.Equal("cookie-meow.wav", _audio.LastPlayedSoundFile);

        Run(1.7);
        Assert.Equal(CookieState.Sitting, _cookie.State);
    }

    [Fact]
    public void CancellingFocus_JustWakesHerGently()
    {
        _cookie.BeginFocus();
        Run(6);
        _audio.LastPlayedSoundFile = null;

        _cookie.EndFocus(completed: false);

        Assert.Equal(CookieState.Stretching, _cookie.State);
        Run(2.2);
        Assert.Equal(CookieState.Sitting, _cookie.State);
        Assert.NotEqual("cookie-meow.wav", _audio.LastPlayedSoundFile);
    }

    [Fact]
    public void EndingWhenNotFocusing_ChangesNothing()
    {
        var before = _cookie.State;
        _cookie.EndFocus(completed: true);
        Assert.Equal(before, _cookie.State);
    }

    [Fact]
    public void ANap_RunsTheFullRitualThenReturnsToIdle()
    {
        Assert.True(_cookie.StartNap(5));
        var seen = new List<CookieState> { _cookie.State };
        for (double t = 0; t < 20; t += 0.05)
        {
            _cookie.Update(0.05, new CorePoint(5000, 5000));
            if (seen[^1] != _cookie.State) seen.Add(_cookie.State);

            // Once she is idle again her own choices take over, which isn't part of the ritual.
            if (_cookie.State == CookieState.Idle) break;
        }

        Assert.Equal(new[] { CookieState.Yawning, CookieState.Sitting, CookieState.Sleeping, CookieState.Stretching, CookieState.Idle }, seen);
    }

    [Fact]
    public void Mornings_BeginWithAStretch_OtherTimesDoNot()
    {
        _cookie.Now = () => new DateTime(2026, 3, 4, 8, 0, 0, DateTimeKind.Local);
        _cookie.BeginDay();
        Assert.Equal(CookieState.Stretching, _cookie.State);

        var animation = new CookieAnimationController();
        var afternoon = new CookieBehaviorController(animation, new ScreenGeometryService(), new TestAudioManager());
        afternoon.Now = () => new DateTime(2026, 3, 4, 14, 0, 0, DateTimeKind.Local);
        afternoon.BeginDay();
        Assert.Equal(CookieState.Idle, afternoon.State);
    }

    [Fact]
    public void NapsRunLongerAtNightAndForSleepyCats()
    {
        _cookie.Now = () => new DateTime(2026, 3, 4, 23, 0, 0, DateTimeKind.Local);
        _cookie.Personality = CookiePersonality.Sleepy;
        _cookie.Settings.Sleep = SleepBehavior.Longer;
        for (int i = 0; i < 100; i++)
        {
            double seconds = _cookie.SampleNapSeconds();
            Assert.InRange(seconds, 25 * 1.5 * 1.15 * 1.3 - 0.01, 120);
        }

        _cookie.Now = () => new DateTime(2026, 3, 4, 13, 0, 0, DateTimeKind.Local);
        _cookie.Personality = CookiePersonality.Playful;
        _cookie.Settings.Sleep = SleepBehavior.Normal;
        for (int i = 0; i < 100; i++) Assert.InRange(_cookie.SampleNapSeconds(), 25, 60);
    }

    [Fact]
    public void IsOnFloor_OnlyNearTheBottomOfTheMainScreen()
    {
        _cookie.SetPosition(new CorePoint(600, 850));
        Assert.True(_cookie.IsOnFloor);
        _cookie.SetPosition(new CorePoint(600, 300));
        Assert.False(_cookie.IsOnFloor);
    }

    [Fact]
    public void CozyPositions_AreFractionsOfTheWorkArea()
    {
        Assert.Equal(960, _cookie.CozyCenterX(new CozyPlacement(CozyKind.Bed, 0.5)), 3);
        Assert.Equal(480, _cookie.CozyCenterX(new CozyPlacement(CozyKind.Sunbeam, 0.25)), 3);
    }

    [Fact]
    public void VisitingTheBed_WalksThereThenNaps()
    {
        _cookie.SetPosition(new CorePoint(600, 850));
        _cookie.VisitCozy(CozyKind.Bed, 1200);
        Assert.Equal(CozyKind.Bed, _cookie.CurrentCozyVisit);
        Assert.Equal(CookieState.Curious, _cookie.State);

        Run(1.1);
        Assert.Equal(CookieState.Walking, _cookie.State);

        for (double t = 0; t < 30 && _cookie.State == CookieState.Walking; t += 0.05) _cookie.Update(0.05, new CorePoint(5000, 5000));
        Assert.Equal(CookieState.Sitting, _cookie.State);
        Assert.Equal(1200, _cookie.CurrentPosition.X + _cookie.CompanionSize.Width / 2, 1);

        Run(4);
        Assert.Equal(CookieState.Sleeping, _cookie.State);
        Assert.Equal(CozyKind.Bed, _cookie.CurrentCozyVisit);
    }

    [Fact]
    public void TheCozyVisitEnds_AndHerWalkWorksWithoutAToyOnTheDesktop()
    {
        _cookie.SetPosition(new CorePoint(600, 850));
        _cookie.VisitCozy(CozyKind.ScratchingPost, 800);
        Assert.Null(_cookie.CurrentWorldItem);

        for (double t = 0; t < 60 && _cookie.CurrentCozyVisit != null; t += 0.05) _cookie.Update(0.05, new CorePoint(5000, 5000));

        // The moment the visit ends she is idle again; what she chooses next is her own business.
        Assert.Null(_cookie.CurrentCozyVisit);
        Assert.Equal(CookieState.Idle, _cookie.State);
    }

    [Fact]
    public void GrabbingHerCancelsTheVisit()
    {
        _cookie.VisitCozy(CozyKind.Sunbeam, 900);
        _cookie.BeginDrag();
        Assert.Null(_cookie.CurrentCozyVisit);
        Assert.Equal(CookieState.BeingDragged, _cookie.State);
    }

    [Fact]
    public void Summon_MovesHerBesideTheCursorAndWaves()
    {
        _cookie.Summon(new CorePoint(500, 400));

        Assert.Equal(540, _cookie.CurrentPosition.X);
        Assert.Equal(400 - _cookie.CompanionSize.Height / 2, _cookie.CurrentPosition.Y);
        Assert.Equal(EmoteId.Wave, _cookie.CurrentEmote?.Id);
    }

    [Fact]
    public void Celebrating_ShowsLove_AndFocusResumesAfterward()
    {
        _cookie.BeginFocus();
        Run(6);

        _cookie.Celebrate();
        Assert.Equal(EmoteId.Love, _cookie.CurrentEmote?.Id);

        Run(15);
        Assert.Equal(CookieState.Sleeping, _cookie.State);
    }
}

public class GifEncoderTests
{
    // --- A small independent decoder, so the encoder is checked against the format, not itself ---

    private sealed record DecodedGif(int Width, int Height, List<(byte R, byte G, byte B)> Palette, List<byte[]> Frames,
        List<int> TransparentIndexes, List<int> Delays, List<int> Disposals, bool LoopsForever);

    private static DecodedGif Decode(byte[] gif)
    {
        Assert.Equal("GIF89a", System.Text.Encoding.ASCII.GetString(gif, 0, 6));
        int width = gif[6] | gif[7] << 8, height = gif[8] | gif[9] << 8;
        int flags = gif[10];
        int position = 13;
        var palette = new List<(byte, byte, byte)>();
        if ((flags & 0x80) != 0)
        {
            int entries = 1 << ((flags & 7) + 1);
            for (int i = 0; i < entries; i++) palette.Add((gif[position + i * 3], gif[position + i * 3 + 1], gif[position + i * 3 + 2]));
            position += entries * 3;
        }

        var result = new DecodedGif(width, height, palette, new(), new(), new(), new(), false);
        bool loops = false;
        int transparent = -1, delay = 0, disposal = 0;
        while (gif[position] != 0x3B)
        {
            if (gif[position] == 0x21)
            {
                byte label = gif[position + 1];
                int size = gif[position + 2];
                if (label == 0xF9)
                {
                    disposal = (gif[position + 3] >> 2) & 7;
                    delay = gif[position + 4] | gif[position + 5] << 8;
                    transparent = (gif[position + 3] & 1) != 0 ? gif[position + 6] : -1;
                }
                else if (label == 0xFF && System.Text.Encoding.ASCII.GetString(gif, position + 3, 11) == "NETSCAPE2.0")
                {
                    loops = gif[position + 15] == 1 && gif[position + 16] == 0 && gif[position + 17] == 0;
                }
                position += 2;
                while (gif[position] != 0) position += gif[position] + 1;
                position++;
            }
            else if (gif[position] == 0x2C)
            {
                int w = gif[position + 5] | gif[position + 6] << 8, h = gif[position + 7] | gif[position + 8] << 8;
                Assert.Equal(0, gif[position + 9]);
                position += 10;
                int minCode = gif[position++];
                var data = new List<byte>();
                while (gif[position] != 0)
                {
                    int length = gif[position++];
                    data.AddRange(gif.Skip(position).Take(length));
                    position += length;
                }
                position++;
                var pixels = LzwDecode(minCode, data.ToArray());
                Assert.Equal(w * h, pixels.Length);
                result.Frames.Add(pixels);
                result.TransparentIndexes.Add(transparent);
                result.Delays.Add(delay);
                result.Disposals.Add(disposal);
            }
            else
            {
                throw new InvalidDataException($"Unexpected block 0x{gif[position]:X2} at {position}");
            }
        }
        return result with { LoopsForever = loops };
    }

    private static byte[] LzwDecode(int minCode, byte[] data)
    {
        int clear = 1 << minCode, end = clear + 1;
        var dictionary = new List<byte[]>();
        int codeSize = minCode + 1;
        void Reset()
        {
            dictionary.Clear();
            for (int i = 0; i < clear; i++) dictionary.Add(new[] { (byte)i });
            dictionary.Add(Array.Empty<byte>());
            dictionary.Add(Array.Empty<byte>());
            codeSize = minCode + 1;
        }
        Reset();

        var output = new List<byte>();
        byte[]? previous = null;
        int bitPosition = 0;
        while (true)
        {
            int code = 0;
            for (int bit = 0; bit < codeSize; bit++)
            {
                int absolute = bitPosition + bit;
                if (absolute / 8 >= data.Length) throw new InvalidDataException("Ran out of data before the end code.");
                code |= ((data[absolute / 8] >> (absolute % 8)) & 1) << bit;
            }
            bitPosition += codeSize;

            if (code == clear) { Reset(); previous = null; continue; }
            if (code == end) break;

            byte[] entry;
            if (code < dictionary.Count) entry = dictionary[code];
            else if (code == dictionary.Count && previous != null) entry = previous.Append(previous[0]).ToArray();
            else throw new InvalidDataException($"Bad code {code}");

            output.AddRange(entry);
            if (previous != null && dictionary.Count < 4096) dictionary.Add(previous.Append(entry[0]).ToArray());
            previous = entry;
            if (dictionary.Count == 1 << codeSize && codeSize < 12) codeSize++;
        }
        return output.ToArray();
    }

    private static RgbaFrame Gradient(int width, int height, int phase, bool clearCorner)
    {
        var rgba = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int o = (y * width + x) * 4;
                rgba[o] = (byte)(x * 255 / Math.Max(1, width - 1));
                rgba[o + 1] = (byte)(y * 255 / Math.Max(1, height - 1));
                rgba[o + 2] = (byte)((phase * 60 + x + y) % 256);
                rgba[o + 3] = clearCorner && x < width / 4 && y < height / 4 ? (byte)0 : (byte)255;
            }
        }
        return new RgbaFrame(width, height, rgba);
    }

    [Fact]
    public void LZW_RoundTripsData_IncludingTablesThatFillAndReset()
    {
        var random = new Random(42);
        var cases = new List<byte[]>
        {
            new byte[] { 7 },
            new byte[] { 1, 2 },
            Enumerable.Repeat((byte)3, 5000).ToArray(),
            Enumerable.Range(0, 70_000).Select(i => (byte)(i % 251)).ToArray(),
            Enumerable.Range(0, 60_000).Select(_ => (byte)random.Next(256)).ToArray(),
            Enumerable.Range(0, 50_000).Select(i => (byte)(random.Next(4) + (i / 997) % 5)).ToArray()
        };
        for (int length = 1; length < 600; length += 37) cases.Add(Enumerable.Range(0, length).Select(_ => (byte)random.Next(256)).ToArray());

        foreach (var original in cases)
        {
            var compressed = GifEncoder.LzwCompress(original);
            Assert.Equal(original, LzwDecode(8, compressed));
        }
    }

    [Fact]
    public void TheFileHasTheRightStructure_AndEveryFrame()
    {
        var frames = new[] { Gradient(48, 36, 0, false), Gradient(48, 36, 1, false), Gradient(48, 36, 2, false) };

        var gif = GifEncoder.Encode(frames, 8);
        var decoded = Decode(gif);

        Assert.Equal(48, decoded.Width);
        Assert.Equal(36, decoded.Height);
        Assert.Equal(3, decoded.Frames.Count);
        Assert.Equal(256, decoded.Palette.Count);
        Assert.True(decoded.LoopsForever);
        Assert.All(decoded.Delays, delay => Assert.Equal(8, delay));
        Assert.Equal(0x3B, gif[^1]);
    }

    [Fact]
    public void OpaquePixelsKeepTheirColorsApproximately()
    {
        var frame = Gradient(60, 40, 0, false);

        var decoded = Decode(GifEncoder.Encode(new[] { frame }, 10));

        long worst = 0;
        for (int i = 0; i < 60 * 40; i++)
        {
            var color = decoded.Palette[decoded.Frames[0][i]];
            long dr = color.R - frame.Rgba[i * 4], dg = color.G - frame.Rgba[i * 4 + 1], db = color.B - frame.Rgba[i * 4 + 2];
            worst = Math.Max(worst, dr * dr + dg * dg + db * db);
        }
        Assert.True(worst < 60 * 60 * 3, $"A pixel was off by too much (squared distance {worst}).");
    }

    [Fact]
    public void ClearPixelsUseTheTransparentIndex_AndEachFrameRestoresTheBackground()
    {
        var decoded = Decode(GifEncoder.Encode(new[] { Gradient(40, 40, 0, true), Gradient(40, 40, 1, true) }, 8));

        Assert.All(decoded.TransparentIndexes, index => Assert.Equal(255, index));
        Assert.All(decoded.Disposals, disposal => Assert.Equal(2, disposal));
        Assert.Equal(255, decoded.Frames[0][0]);
        Assert.Equal(255, decoded.Frames[1][5 * 40 + 5]);
        Assert.NotEqual(255, decoded.Frames[0][39 * 40 + 39]);
        // No opaque pixel may use the transparent slot.
        for (int i = 0; i < 40 * 40; i++)
        {
            bool clear = i % 40 < 10 && i / 40 < 10;
            Assert.Equal(clear, decoded.Frames[0][i] == 255);
        }
    }

    [Fact]
    public void SoftEdgesAreBlendedAgainstTheMatte()
    {
        // A mostly opaque red pixel at 80% keeps a red tint instead of showing fringe from raw color values.
        var rgba = new byte[2 * 1 * 4] { 255, 0, 0, 204, 255, 0, 0, 30 };
        var decoded = Decode(GifEncoder.Encode(new[] { new RgbaFrame(2, 1, rgba) }, 5, matte: ((byte)250, (byte)238, (byte)225)));

        Assert.Equal(255, decoded.Frames[0][1]);
        var color = decoded.Palette[decoded.Frames[0][0]];
        Assert.True(color.R > 240 && color.G > 30 && color.G < 80, $"Expected a soft red, got {color}");
    }

    [Fact]
    public void BadInputIsRefusedClearly()
    {
        Assert.Throws<ArgumentException>(() => GifEncoder.Encode(Array.Empty<RgbaFrame>(), 5));
        Assert.Throws<ArgumentException>(() => GifEncoder.Encode(new[] { Gradient(10, 10, 0, false), Gradient(12, 10, 0, false) }, 5));
        Assert.Throws<ArgumentException>(() => GifEncoder.Encode(new[] { new RgbaFrame(4, 4, new byte[3]) }, 5));
    }

    [Fact]
    public void ARealSizedAnimationEncodesAndDecodes()
    {
        var frames = Enumerable.Range(0, 6).Select(i => Gradient(360, 360, i, true)).ToArray();

        var gif = GifEncoder.Encode(frames, 9);
        var decoded = Decode(gif);

        Assert.Equal(6, decoded.Frames.Count);
        Assert.True(gif.Length < 6 * 360 * 360, "The GIF should be smaller than the raw pixels.");
        File.WriteAllBytes(Path.Combine(Path.GetTempPath(), $"cookie-gif-check-{Environment.ProcessId}.gif"), gif);
    }
}

public class FocusSessionTests
{
    private static (CookieProfile, CookieBehaviorController, FocusSession, List<string>) Make(Func<DateTime> clock)
    {
        var profile = new CookieProfile();
        var controller = new CookieBehaviorController(new CookieAnimationController(), new ScreenGeometryService(), new TestAudioManager())
        {
            Statistics = profile.Statistics
        };
        var said = new List<string>();
        var session = new FocusSession(profile, controller, said.Add, _ => { }) { Now = clock };
        return (profile, controller, session, said);
    }

    [Fact]
    public void ASessionCountsDownThenStartsABreak()
    {
        var clock = new DateTime(2026, 1, 1, 9, 0, 0, DateTimeKind.Utc);
        var (profile, controller, session, said) = Make(() => clock);
        profile.Settings.BreakMinutes = 5;

        session.Start(10);
        Assert.True(controller.IsFocusing);
        Assert.Equal("10:00", session.StatusTitle);

        clock = clock.AddMinutes(5);
        session.Tick();
        Assert.Equal("5:00", session.StatusTitle);

        clock = clock.AddMinutes(5).AddSeconds(1);
        session.Tick();
        Assert.False(controller.IsFocusing);
        Assert.Equal(1, profile.Statistics.FocusSessions);
        Assert.Equal(10, profile.Statistics.FocusMinutes);
        Assert.Equal(5, profile.Statistics.Affection);
        Assert.True(session.IsOnBreak);
        Assert.Equal("Break 5:00", session.StatusTitle);
        Assert.Contains("Time for a break", said[^1]);

        clock = clock.AddMinutes(5).AddSeconds(1);
        session.Tick();
        Assert.Equal(FocusPhase.Idle, session.Timer.Phase);
        Assert.Null(session.StatusTitle);
        Assert.Contains("Break's over", said[^1]);
    }

    [Fact]
    public void StoppingEarlyRecordsNothing()
    {
        var (profile, controller, session, _) = Make(() => DateTime.UtcNow);
        session.Start(25);

        session.Stop();

        Assert.False(controller.IsFocusing);
        Assert.Equal(0, profile.Statistics.FocusSessions);
        Assert.Null(session.StatusTitle);
    }

    [Fact]
    public void SleepingThroughTheEndCompletesOnce_AndStartingDuringABreakBeginsANewSession()
    {
        var clock = new DateTime(2026, 1, 1, 9, 0, 0, DateTimeKind.Utc);
        var (profile, _, session, _) = Make(() => clock);

        session.Start(25);
        clock = clock.AddHours(4);
        session.Tick();
        session.Tick();
        Assert.Equal(1, profile.Statistics.FocusSessions);
        Assert.True(session.IsOnBreak);

        session.Start(15);
        Assert.True(session.IsFocusing);
        Assert.Equal("15:00", session.StatusTitle);
    }

    [Fact]
    public void TheDefaultLengthComesFromSettings_AndChangesAreAnnounced()
    {
        var (profile, _, session, said) = Make(() => DateTime.UtcNow);
        profile.Settings.FocusMinutes = 40;
        int changes = 0;
        session.Changed += () => changes++;

        session.Start();

        Assert.Equal("40:00", session.StatusTitle);
        Assert.Equal(1, changes);
        Assert.Contains("keep you company", said[0]);
    }
}

public class PhotoModeModelTests
{
    [Fact]
    public void PosesAndBackdropsMatchTheMacApp()
    {
        Assert.Equal(new[] { "idle", "wave", "happy", "love", "playful", "sleepy", "napping", "walk", "curious", "stretch" }, PhotoPose.All.Select(p => p.Id));
        Assert.Equal(new[] { "Sitting Pretty", "Hello!", "Happy", "In Love", "Playful", "Sleepy", "Napping", "On a Stroll", "Curious", "Big Stretch" }, PhotoPose.All.Select(p => p.Title));
        Assert.Null(PhotoBackdrop.Transparent.GetColor());
        Assert.Equal(((byte)250, (byte)242, (byte)227), PhotoBackdrop.Cream.GetColor());
        Assert.All(Enum.GetValues<PhotoBackdrop>().Where(b => b != PhotoBackdrop.Transparent), b => Assert.NotNull(b.GetColor()));
    }

    [Fact]
    public void RepeatedFramesCollapseToOneCycle()
    {
        Assert.Equal(3, PhotoClips.CycleLength(new[] { 1, 2, 3, 1, 2, 3, 1, 2, 3 }));
        Assert.Equal(3, PhotoClips.CycleLength(new[] { 1, 2, 3 }));
        Assert.Equal(1, PhotoClips.CycleLength(new[] { 7, 7, 7, 7 }));
        Assert.Equal(5, PhotoClips.CycleLength(new[] { 1, 2, 1, 2, 1 }));
        Assert.Equal(0, PhotoClips.CycleLength(Array.Empty<int>()));
    }

    [Fact]
    public void EveryPoseHasASheetOnDisk()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (!File.Exists(Path.Combine(directory!.FullName, "Cookie.Windows.sln"))) directory = directory.Parent;
        var catalog = new SpriteSheetCatalog(
            Path.Combine(directory.FullName, "Cookie", "Resources", "Sprites", "Cookie"),
            Path.Combine(directory.FullName, "Cookie.Windows", "Resources", "Sprites", "Cookie"));

        foreach (var pose in PhotoPose.All)
        {
            var sheet = catalog.Find(pose.Animation.GetSpec());
            Assert.NotNull(sheet);
            Assert.True(PhotoClips.CycleLength(sheet!.Frames) > 1, pose.Id);
        }
    }

    [Fact]
    public void Muted_PlaysNothing()
    {
        var audio = new TestAudioManager { IsMuted = true };
        Assert.False(audio.Play(SoundEffect.Meow));
        audio.IsMuted = false;
        Assert.True(audio.Play(SoundEffect.Meow));
    }
}

public class CozyLayoutTests
{
    [Fact]
    public void NewItemsKeepTheirDistance_MatchingTheMac()
    {
        // Preferred 0.5 is taken, and 0.56 and 0.44 are too close, so 0.62 is the first clear spot.
        double spot = CozyLayout.NewPosition(500, 0, 1000, new[] { 0.5 });
        Assert.Equal(0.62, spot, 4);
        Assert.Equal(0.3, CozyLayout.NewPosition(300, 0, 1000, new[] { 0.5 }), 4);
    }

    [Fact]
    public void PositionsAreFractionsOfTheWorkArea()
    {
        Assert.Equal(0.25, CozyLayout.NewPosition(600, 100, 2000, Array.Empty<double>()), 4);
    }

    [Fact]
    public void ABubbleSitsOverHerHeadAndStaysOnScreen()
    {
        var visible = new CoreRect(0, 0, 1440, 900);
        var bubble = new CoreSize(200, 40);

        var centered = BubblePlacement.Origin(bubble, new CoreRect(700, 400, 160, 160), visible);
        Assert.Equal(680, centered.X);
        Assert.Equal(374, centered.Y);

        Assert.Equal(1440 - 200 - 4, BubblePlacement.Origin(bubble, new CoreRect(1380, 400, 160, 160), visible).X);

        // No room above her, so it drops beside her instead of off the screen.
        var top = BubblePlacement.Origin(bubble, new CoreRect(700, 10, 160, 160), visible);
        Assert.True(top.Y > 10);
    }
}
