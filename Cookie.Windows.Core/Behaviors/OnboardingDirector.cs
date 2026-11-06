using System;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Directs Cookie during first-run setup: she walks in, reacts as her name is typed,
/// and acts out each personality as it's chosen. The window only draws what this decides.
/// </summary>
public class OnboardingDirector
{
    public const double WalkInSeconds = 2.1;
    private const double ArrivalHoldSeconds = 1.3;
    private const double TypingHoldSeconds = 1.1;
    private const double PersonalityHoldSeconds = 2.0;
    private const double SoundSpacingSeconds = 1.2;

    private readonly CookieAnimationController _animation;
    private readonly AudioManagerBase? _audio;

    private string _name;
    private CookiePersonality _personality;
    private double _walkElapsed;
    private double _settleIn;
    private double _sinceSound = SoundSpacingSeconds;

    public OnboardingDirector(
        CookieAnimationController animation,
        AudioManagerBase? audio,
        string name,
        CookiePersonality personality,
        bool reduceMotion = false)
    {
        _animation = animation;
        _audio = audio;
        _name = name;
        _personality = personality;

        if (reduceMotion)
        {
            _walkElapsed = WalkInSeconds;
            HasArrived = true;
            _animation.ForceAnimation(CookieAnimationId.Idle);
        }
        else
        {
            _animation.ForceAnimation(CookieAnimationId.WalkRight);
        }
    }

    public bool HasArrived { get; private set; }

    /// <summary>How far she still has to walk: 1 is off the left of the stage, 0 is her spot.</summary>
    public double WalkRemaining
    {
        get
        {
            double t = Math.Clamp(_walkElapsed / WalkInSeconds, 0, 1);
            return (1 - t) * (1 - t); // Ease out, so she slows as she arrives.
        }
    }

    public string ResolvedName => string.IsNullOrWhiteSpace(_name) ? "Cookie" : _name.Trim();
    public string Greeting => $"Hi, I'm {ResolvedName}!";

    public string Name
    {
        get => _name;
        set
        {
            if (value == _name) return;
            _name = value;
            if (!HasArrived) return;

            if (_animation.CurrentAnimationId != CookieAnimationId.Curious)
            {
                _animation.ForceAnimation(CookieAnimationId.Curious);
            }
            _settleIn = TypingHoldSeconds;
            PlayThrottled(SoundEffect.Chirp);
        }
    }

    public CookiePersonality Personality
    {
        get => _personality;
        set
        {
            if (value == _personality) return;
            _personality = value;
            if (!HasArrived) return;

            _animation.ForceAnimation(value.GetShowcaseAnimation());
            _settleIn = PersonalityHoldSeconds;
            PlayThrottled(value.GetGreetingSound());
        }
    }

    public void Update(double deltaTimeSeconds)
    {
        _animation.Update(deltaTimeSeconds);
        _sinceSound += deltaTimeSeconds;

        if (!HasArrived)
        {
            _walkElapsed += deltaTimeSeconds;
            if (_walkElapsed >= WalkInSeconds)
            {
                HasArrived = true;
                _animation.ForceAnimation(CookieAnimationId.Happy);
                _settleIn = ArrivalHoldSeconds;
                PlayThrottled(SoundEffect.Welcome);
            }
            return;
        }

        if (_settleIn > 0)
        {
            _settleIn -= deltaTimeSeconds;
            if (_settleIn <= 0)
            {
                _animation.ForceAnimation(CookieAnimationId.Idle);
            }
        }
    }

    private void PlayThrottled(SoundEffect sound)
    {
        if (_sinceSound < SoundSpacingSeconds) return;
        _sinceSound = 0;
        _audio?.Play(sound);
    }
}
