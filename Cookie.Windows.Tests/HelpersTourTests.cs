using System;
using System.IO;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Persistence;
using Xunit;

namespace Cookie.Windows.Tests;

public class HelpersTourTests
{
    [Fact]
    public void TheTourCoversEachHelperAndEndsWithAWrapUp()
    {
        var steps = HelpersTour.Steps("Biscuit");
        Assert.Equal(new[] { "Reminders", "Notes and to-dos", "Drop files on me", "Chat with Biscuit", "That's the tour!" },
            steps.Select(s => s.Title));
        Assert.Equal(new[] { HelpersTour.TourAction.NewReminder, HelpersTour.TourAction.PinNote, HelpersTour.TourAction.OpenPowerTools },
            steps.Where(s => s.Action != null).Select(s => s.Action!.Value));
        // A step with something to try names the button, and one without doesn't.
        Assert.All(steps, s => Assert.Equal(s.TryTitle == null, s.Action == null));
        Assert.Null(steps[^1].Action);
    }

    [Theory]
    [InlineData(true, false, true, false, false, true)]
    [InlineData(false, false, true, false, false, false)] // not before she has been met
    [InlineData(true, true, true, false, false, false)]   // only once
    [InlineData(true, false, false, false, false, false)] // not while she's hidden
    [InlineData(true, false, true, true, false, false)]   // not over a full-screen app
    [InlineData(true, false, true, false, true, false)]   // not during a focus session
    public void ItStartsOnItsOwnOnlyOnceAndAtACalmMoment(bool onboarded, bool seen, bool visible, bool quiet, bool focusing, bool expected)
    {
        Assert.Equal(expected, HelpersTour.CanStartOnItsOwn(onboarded, seen, visible, quiet, focusing));
    }

    [Fact]
    public void TheCardSitsBesideHerAndStaysOnScreen()
    {
        var visible = new CoreRect(0, 0, 1000, 800);
        var card = new CoreSize(270, 150);
        // Room on the right: it goes there, level with her head.
        var right = HelpersTour.CardOrigin(card, new CoreRect(100, 300, 120, 120), visible);
        Assert.Equal(224, right.X);
        Assert.Equal(300, right.Y);
        // Against the right edge: it flips to her left.
        var left = HelpersTour.CardOrigin(card, new CoreRect(850, 300, 120, 120), visible);
        Assert.Equal(850 - 270 - 4, left.X);
        // Near the bottom: it's lifted to stay on screen.
        var low = HelpersTour.CardOrigin(card, new CoreRect(100, 760, 120, 40), visible);
        Assert.Equal(800 - 150 - 4, low.Y);
    }

    [Fact]
    public void ANotePinnedDuringTheTourKeepsClearOfTheCard()
    {
        var area = new CoreRect(0, 0, 1000, 800);
        var cookie = new CoreRect(820, 600, 120, 120);
        var card = new CoreRect(820 - 270 - 4, 600, 270, 150);
        var (noteLeft, _) = StickyNote.PlaceBeside(HelpersTour.Union(cookie, card), area, 0);
        Assert.True(noteLeft + StickyNote.Width <= card.Left, $"note at {noteLeft} overlaps the card at {card.Left}");
    }

    [Fact]
    public void OldProfilesHaveNotSeenTheTourAndTheFlagIsSaved()
    {
        string dir = Path.Combine(Path.GetTempPath(), "CookieTour_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "profile.json");
            File.WriteAllText(path, "{\"Version\":1,\"DisplayName\":\"Cookie\",\"Settings\":{\"HasCompletedOnboarding\":true}}");
            var profile = new SettingsManager(path).LoadProfile();
            Assert.False(profile.HasSeenHelpersTour);

            profile.HasSeenHelpersTour = true;
            new SettingsManager(path).SaveProfileImmediate(profile);
            Assert.True(new SettingsManager(path).LoadProfile().HasSeenHelpersTour);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch { }
        }
    }
}
