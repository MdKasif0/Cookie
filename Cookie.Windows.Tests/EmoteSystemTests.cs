using System;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class EmoteSystemTests
{
    private readonly CookieAnimationController _animController;
    private readonly ScreenGeometryService _screenService;
    private readonly TestAudioManager _audioManager;
    private readonly CookieBehaviorController _behaviorController;

    public EmoteSystemTests()
    {
        _animController = new CookieAnimationController();
        _screenService = new ScreenGeometryService();
        _audioManager = new TestAudioManager();
        _behaviorController = new CookieBehaviorController(_animController, _screenService, _audioManager);
    }

    [Fact]
    public void AllFiveEmotes_AreDefinedCorrectly()
    {
        Assert.Equal(5, Emote.All.Count);

        var wave = Emote.Wave;
        Assert.Equal(EmoteId.Wave, wave.Id);
        Assert.Equal("Wave", wave.Name);
        Assert.Equal("👋", wave.Emoji);
        Assert.Equal(CookieAnimationId.Wave, wave.AnimationIdentifier);
        Assert.Equal(SoundEffect.Mew, wave.SoundIdentifier);

        var happy = Emote.Happy;
        Assert.Equal(EmoteId.Happy, happy.Id);
        Assert.Equal("Happy", happy.Name);
        Assert.Equal("✨", happy.Emoji);
        Assert.Equal(CookieAnimationId.HappyEmote, happy.AnimationIdentifier);
        Assert.Equal(SoundEffect.Happy, happy.SoundIdentifier);

        var love = Emote.Love;
        Assert.Equal(EmoteId.Love, love.Id);
        Assert.Equal("Love", love.Name);
        Assert.Equal("🧡", love.Emoji);
        Assert.Equal(CookieAnimationId.Love, love.AnimationIdentifier);
        Assert.Equal(SoundEffect.Purr, love.SoundIdentifier);

        var sleepy = Emote.Sleepy;
        Assert.Equal(EmoteId.Sleepy, sleepy.Id);
        Assert.Equal("Sleepy", sleepy.Name);
        Assert.Equal("💤", sleepy.Emoji);
        Assert.Equal(CookieAnimationId.SleepyEmote, sleepy.AnimationIdentifier);
        Assert.Equal(SoundEffect.Sleep, sleepy.SoundIdentifier);

        var playful = Emote.Playful;
        Assert.Equal(EmoteId.Playful, playful.Id);
        Assert.Equal("Playful", playful.Name);
        Assert.Equal("🧶", playful.Emoji);
        Assert.Equal(CookieAnimationId.PlayfulEmote, playful.AnimationIdentifier);
        Assert.Equal(SoundEffect.Toy, playful.SoundIdentifier);
    }

    [Fact]
    public void EmotePriority_DraggingInterruptsActiveEmote()
    {
        bool triggered = _behaviorController.TriggerEmote(Emote.Wave);
        Assert.True(triggered);
        Assert.Equal(CookieState.Emoting, _behaviorController.State);

        // User grabs and begins dragging
        _behaviorController.BeginDrag();

        Assert.Equal(CookieState.BeingDragged, _behaviorController.State);
        Assert.Null(_behaviorController.CurrentEmote);
        Assert.Equal(CookieAnimationId.PickedUp, _animController.CurrentAnimationId);
    }

    [Fact]
    public void EmotePriority_CannotTriggerSimultaneousEmotes()
    {
        bool first = _behaviorController.TriggerEmote(Emote.Happy);
        Assert.True(first);

        // Attempting to trigger second emote while first is playing is rejected
        bool second = _behaviorController.TriggerEmote(Emote.Love);
        Assert.False(second);
        Assert.Equal(EmoteId.Happy, _behaviorController.CurrentEmote?.Id);
    }

    [Fact]
    public void EmoteCooldown_PreventsSpamUntilExpiry()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        _behaviorController.Now = () => clock;

        bool triggered = _behaviorController.TriggerEmote(Emote.Playful);
        Assert.True(triggered);

        // Advance time to complete emote (2.0s duration)
        clock = clock.AddSeconds(2.05);
        _behaviorController.Update(2.05);
        Assert.Equal(CookieState.Idle, _behaviorController.State);

        // Cooldown is 2.0s from start (at 2.05s it has expired)
        Assert.True(_behaviorController.CanPerformEmote(Emote.Playful));

        // Trigger again at 2.05s
        _behaviorController.TriggerEmote(Emote.Playful);

        // Immediately check cooldown
        Assert.False(_behaviorController.CanPerformEmote(Emote.Playful));
        Assert.True(_behaviorController.CooldownRemaining(EmoteId.Playful) > 0.0);
    }

    [Fact]
    public void EmoteLifecycle_PlaysAudioAndRestoresIdle()
    {
        bool triggered = _behaviorController.TriggerEmote(Emote.Love);
        Assert.True(triggered);

        Assert.Equal(CookieState.Emoting, _behaviorController.State);
        Assert.Equal("cookie-purr.wav", _audioManager.LastPlayedSoundFile);

        _behaviorController.Update(Emote.Love.DurationSeconds + 0.1);

        Assert.Equal(CookieState.Idle, _behaviorController.State);
        Assert.Null(_behaviorController.CurrentEmote);
    }
}
