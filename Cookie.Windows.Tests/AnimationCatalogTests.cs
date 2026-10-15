using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class AnimationCatalogTests
{
    [Theory]
    [InlineData("idle")]
    [InlineData("idleBlink")]
    [InlineData("walk")]
    [InlineData("run")]
    [InlineData("sit")]
    [InlineData("sleep")]
    [InlineData("wake")]
    [InlineData("stretch")]
    [InlineData("yawn")]
    [InlineData("groom")]
    [InlineData("happy")]
    [InlineData("curious")]
    [InlineData("pet")]
    [InlineData("meow")]
    [InlineData("pickedUp")]
    [InlineData("dropped")]
    [InlineData("wave")]
    [InlineData("love")]
    [InlineData("sleepy")]
    public void PoseCatalog_ContainsFramesForAllStandardSheets(string sheetName)
    {
        var frames = CookiePoseCatalog.GetFrames(sheetName);

        Assert.NotNull(frames);
        Assert.NotEmpty(frames);
    }

    [Fact]
    public void AnimationPriority_StrictlyFollowsSpecTiers()
    {
        Assert.True(CookieAnimationPriority.Sleep < CookieAnimationPriority.Idle);
        Assert.True(CookieAnimationPriority.Idle < CookieAnimationPriority.Walk);
        Assert.True(CookieAnimationPriority.Walk < CookieAnimationPriority.Interaction);
        Assert.True(CookieAnimationPriority.Interaction < CookieAnimationPriority.Emote);
        Assert.True(CookieAnimationPriority.Emote < CookieAnimationPriority.Special);
    }

    [Fact]
    public void PlayAnimation_LowerPriorityCannotInterruptHigherPriority()
    {
        var controller = new CookieAnimationController();

        controller.PlayAnimation(CookieAnimationId.PickedUp);
        Assert.Equal(CookieAnimationId.PickedUp, controller.CurrentAnimationId);

        bool played = controller.PlayAnimation(CookieAnimationId.Idle);

        Assert.False(played);
        Assert.Equal(CookieAnimationId.PickedUp, controller.CurrentAnimationId);
    }

    [Fact]
    public void PlayAnimation_HigherPriorityInterruptsLowerPriority()
    {
        var controller = new CookieAnimationController();

        Assert.Equal(CookieAnimationId.Idle, controller.CurrentAnimationId);

        bool played = controller.PlayAnimation(CookieAnimationId.Pet);

        Assert.True(played);
        Assert.Equal(CookieAnimationId.Pet, controller.CurrentAnimationId);
    }
}
