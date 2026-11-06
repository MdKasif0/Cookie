using System.IO;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Xunit;

namespace Cookie.Windows.Tests;

public class WorldItemAndStatisticsTests
{
    private const double Tick = 0.05;

    private readonly CookieAnimationController _animation = new();
    private readonly TestAudioManager _audio = new();
    private readonly CookieBehaviorController _cookie;

    public WorldItemAndStatisticsTests()
    {
        _cookie = new CookieBehaviorController(_animation, new ScreenGeometryService(), _audio);
        _cookie.SetPosition(new CorePoint(600, 400));
    }

    private void RunUntil(System.Func<bool> condition, double maxSeconds = 90)
    {
        for (double t = 0; t < maxSeconds && !condition(); t += Tick)
        {
            _cookie.Update(Tick, new CorePoint(5000, 5000));
        }
        Assert.True(condition(), $"Timed out in state {_cookie.State}");
    }

    [Fact]
    public void OfferFood_PlacesItemBesideCookieAndCountsTreat()
    {
        _cookie.OfferFood(FoodKind.Fish);

        var item = Assert.IsType<WorldItem>(_cookie.CurrentWorldItem);
        Assert.Equal(FoodKind.Fish, item.Food);
        Assert.Equal(_cookie.CurrentPosition.Y + _cookie.CompanionSize.Height, item.GroundY);
        Assert.Equal(CookieState.Curious, _cookie.State);

        RunUntil(() => _cookie.State == CookieState.Eating);
        Assert.Equal(CookieAnimationId.Eat, _animation.CurrentAnimationId);
        Assert.Equal(1, _cookie.Statistics.TreatsGiven);
        Assert.Equal("cookie-eat.wav", _audio.LastPlayedSoundFile);
    }

    [Fact]
    public void OfferFood_MilkIsDrunk()
    {
        _cookie.OfferFood(FoodKind.Milk);

        RunUntil(() => _cookie.State == CookieState.Drinking);
        Assert.Equal(CookieAnimationId.Drink, _animation.CurrentAnimationId);
    }

    [Fact]
    public void EatingAnimation_HoldsForTheWholeMeal()
    {
        _cookie.OfferFood(FoodKind.Chicken);
        RunUntil(() => _cookie.State == CookieState.Eating);

        for (double t = 0; t < 3.0; t += Tick)
        {
            _cookie.Update(Tick, new CorePoint(5000, 5000));
            Assert.Equal(CookieAnimationId.Eat, _animation.CurrentAnimationId);
        }
    }

    [Fact]
    public void FoodSequence_FinishesIdleWithItemConsumed()
    {
        _cookie.OfferFood(FoodKind.Cookie);

        RunUntil(() => !_cookie.IsCareSequenceActive);

        Assert.Null(_cookie.CurrentWorldItem);
        Assert.Equal(CookieState.Idle, _cookie.State);
        Assert.Equal(CookieAnimationId.Idle, _animation.CurrentAnimationId);
    }

    [Fact]
    public void WalkToItem_StopsBesideItAndFacesIt()
    {
        _cookie.SetFacing(CookieDirection.Left);
        _cookie.OfferToy(ToyKind.YarnBall);
        var item = _cookie.CurrentWorldItem!;
        Assert.True(item.X < _cookie.CurrentPosition.X);

        RunUntil(() => _cookie.State == CookieState.Investigating);

        double center = _cookie.CurrentPosition.X + _cookie.CompanionSize.Width / 2;
        Assert.InRange(System.Math.Abs(item.X - center), 55, 70);
        Assert.Equal(CookieDirection.Left, _cookie.Facing);
    }

    [Fact]
    public void OfferToy_RecordsPlayAndFavorite()
    {
        _cookie.OfferToy(ToyKind.Feather);

        RunUntil(() => _cookie.State == CookieState.Playing);
        Assert.Equal(CookieAnimationId.Playful, _animation.CurrentAnimationId);
        Assert.Equal(1, _cookie.Statistics.ToysPlayedWith);
        Assert.Equal(ToyKind.Feather, _cookie.Statistics.FavoriteToy);
        Assert.Equal("cookie-toy.wav", _audio.LastPlayedSoundFile);
    }

    [Fact]
    public void OfferBox_CookieGetsInsideAndVisitIsCounted()
    {
        _cookie.OfferToy(ToyKind.Box);

        RunUntil(() => _cookie.State == CookieState.InBox);

        double center = _cookie.CurrentPosition.X + _cookie.CompanionSize.Width / 2;
        Assert.InRange(System.Math.Abs(_cookie.CurrentWorldItem!.X - center), 0, 1);
        Assert.Equal(CookieAnimationId.InBox, _animation.CurrentAnimationId);
        Assert.Equal(1, _cookie.Statistics.BoxVisits);
        Assert.Equal(0, _cookie.Statistics.ToysPlayedWith);
    }

    [Fact]
    public void MoveWorldItem_RetargetsTheWalk()
    {
        _cookie.SetFacing(CookieDirection.Right);
        _cookie.OfferToy(ToyKind.Ball);
        RunUntil(() => _cookie.State == CookieState.Walking);

        _cookie.MoveWorldItem(_cookie.CurrentPosition.X - 200);
        _cookie.Update(Tick, new CorePoint(5000, 5000));

        Assert.Equal(CookieDirection.Left, _cookie.Facing);
    }

    [Fact]
    public void ClearWorldItem_EndsSequenceAndReturnsToIdle()
    {
        _cookie.OfferToy(ToyKind.Box);
        RunUntil(() => _cookie.State == CookieState.InBox);

        _cookie.ClearWorldItem();

        Assert.Null(_cookie.CurrentWorldItem);
        Assert.False(_cookie.IsCareSequenceActive);
        Assert.Equal(CookieState.Idle, _cookie.State);
        Assert.Equal(CookieAnimationId.Idle, _animation.CurrentAnimationId);
    }

    [Fact]
    public void Dragging_InterruptsCareAndRemovesItem()
    {
        _cookie.OfferFood(FoodKind.Fish);

        _cookie.BeginDrag();

        Assert.Null(_cookie.CurrentWorldItem);
        Assert.False(_cookie.IsCareSequenceActive);
        Assert.Equal(CookieState.BeingDragged, _cookie.State);
    }

    [Fact]
    public void OfferFood_IsIgnoredWhileBeingDragged()
    {
        _cookie.BeginDrag();

        _cookie.OfferFood(FoodKind.Fish);

        Assert.Null(_cookie.CurrentWorldItem);
    }

    [Fact]
    public void Pet_DuringMeal_PlaysPetAndCountsAffection()
    {
        _cookie.OfferFood(FoodKind.Fish);
        RunUntil(() => _cookie.State == CookieState.Eating);

        _cookie.Pet();

        Assert.Equal(CookieAnimationId.Pet, _animation.CurrentAnimationId);
        Assert.Equal(1, _cookie.Statistics.PetsReceived);
        Assert.False(_cookie.IsCareSequenceActive);
    }

    [Fact]
    public void Statistics_RaiseChangeNotificationForSaving()
    {
        int changes = 0;
        _cookie.OnStatisticsChanged += () => changes++;

        _cookie.Pet();

        Assert.Equal(1, changes);
    }

    [Fact]
    public void Statistics_DaysTogetherCountsFirstDayAsOne()
    {
        var stats = new CookieStatistics();
        var start = new System.DateTime(2026, 1, 1, 23, 0, 0, System.DateTimeKind.Utc);
        stats.RecordLaunch(start);
        stats.RecordLaunch(start.AddDays(2));

        Assert.Equal(2, stats.LaunchCount);
        Assert.Equal(start, stats.FirstLaunchedAt);
        Assert.Equal(1, stats.DaysTogether(start));
        Assert.Equal(3, stats.DaysTogether(start.AddDays(2)));
    }

    [Fact]
    public void Statistics_SurviveSaveAndLoad()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cookie-stats-{System.Guid.NewGuid():N}.json");
        try
        {
            var manager = new SettingsManager(path);
            var profile = new CookieProfile();
            profile.Statistics.RecordPet();
            profile.Statistics.RecordToyPlayed(ToyKind.Ball);
            profile.Statistics.RecordToyPlayed(ToyKind.Ball);
            profile.Statistics.RecordToyPlayed(ToyKind.Feather);
            manager.SaveProfileImmediate(profile);

            var loaded = manager.LoadProfile();

            Assert.Equal(1, loaded.Statistics.PetsReceived);
            Assert.Equal(3, loaded.Statistics.ToysPlayedWith);
            Assert.Equal(ToyKind.Ball, loaded.Statistics.FavoriteToy);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void Statistics_OldProfileWithoutThemLoadsWithDefaults()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cookie-stats-{System.Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, "{\"Version\":1,\"DisplayName\":\"Biscuit\"}");

            var loaded = new SettingsManager(path).LoadProfile();

            Assert.Equal("Biscuit", loaded.DisplayName);
            Assert.NotNull(loaded.Statistics);
            Assert.Equal(0, loaded.Statistics.PetsReceived);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Theory]
    [InlineData(ToyKind.YarnBall, "yarnBall")]
    [InlineData(ToyKind.Box, "box")]
    [InlineData(FoodKind.Milk, "food-milk")]
    public void AssetNames_MatchRenderedArtFiles(object kind, string expected)
    {
        string actual = kind is ToyKind toy ? toy.GetAssetName() : ((FoodKind)kind).GetAssetName();
        Assert.Equal(expected, actual);
    }
}
