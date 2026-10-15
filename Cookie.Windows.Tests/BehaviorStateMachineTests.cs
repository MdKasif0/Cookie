using System.Windows;
using Cookie.Windows.Animation;
using Cookie.Windows.Audio;
using Cookie.Windows.Behaviors;
using Cookie.Windows.Desktop;
using Cookie.Windows.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class BehaviorStateMachineTests
{
    private readonly CookieAnimationController _animController;
    private readonly ScreenGeometryService _screenService;
    private readonly WindowsAudioManager _audioManager;
    private readonly CookieBehaviorController _behaviorController;

    public BehaviorStateMachineTests()
    {
        _animController = new CookieAnimationController();
        _screenService = new ScreenGeometryService();
        _audioManager = new WindowsAudioManager();
        _behaviorController = new CookieBehaviorController(_animController, _screenService, _audioManager);
    }

    [Fact]
    public void InitialState_IsIdle()
    {
        Assert.Equal(CookieState.Idle, _behaviorController.State);
        Assert.Equal(CookieAnimationId.Idle, _animController.CurrentAnimationId);
    }

    [Fact]
    public void Dragging_TransitionsThroughPickedUpAndDropped()
    {
        _behaviorController.BeginDrag();

        Assert.Equal(CookieState.BeingDragged, _behaviorController.State);
        Assert.Equal(CookieAnimationId.PickedUp, _animController.CurrentAnimationId);

        _behaviorController.UpdateDrag(new Point(200, 300));
        Assert.Equal(200, _behaviorController.CurrentPosition.X);
        Assert.Equal(300, _behaviorController.CurrentPosition.Y);

        _behaviorController.EndDrag();

        Assert.Equal(CookieState.Reacting, _behaviorController.State);
        Assert.Equal(CookieAnimationId.Dropped, _animController.CurrentAnimationId);
    }

    [Fact]
    public void Petting_TransitionsToReactingWithPetAnimation()
    {
        _behaviorController.Pet();

        Assert.Equal(CookieState.Reacting, _behaviorController.State);
        Assert.Equal(CookieAnimationId.Pet, _animController.CurrentAnimationId);
    }

    [Fact]
    public void TriggerEmote_PlaysEmoteAnimationAndRestoresIdleAfterDuration()
    {
        var waveEmote = Emote.Wave;
        bool triggered = _behaviorController.TriggerEmote(waveEmote);

        Assert.True(triggered);
        Assert.Equal(CookieState.Emoting, _behaviorController.State);
        Assert.Equal(CookieAnimationId.Wave, _animController.CurrentAnimationId);
        Assert.Equal(waveEmote, _behaviorController.CurrentEmote);

        // Advance time past emote duration
        _behaviorController.Update(waveEmote.DurationSeconds + 0.1);

        Assert.Equal(CookieState.Idle, _behaviorController.State);
        Assert.Null(_behaviorController.CurrentEmote);
    }

    [Fact]
    public void LocomotionState_IsLocomotionFlag()
    {
        Assert.False(CookieState.Idle.IsLocomotion());
        Assert.True(CookieState.Walking.IsLocomotion());
        Assert.True(CookieState.Running.IsLocomotion());
        Assert.True(CookieState.FollowingCursor.IsLocomotion());
        Assert.False(CookieState.BeingDragged.IsLocomotion());
    }
}
