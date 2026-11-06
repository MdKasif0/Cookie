using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Focus sessions, naps and the daily rhythm, cozy spots, summoning and celebrating. Each is a short
/// script played through the same step machinery as feeding and toys.
/// </summary>
public partial class CookieBehaviorController
{
    private const double FloorTolerance = 40.0;

    private DateTime _napCooldownUntil = DateTime.MinValue;
    private DateTime _cozyCooldownUntil = DateTime.MinValue;

    /// <summary>The personality nudges how sleepy she gets.</summary>
    public CookiePersonality Personality { get; set; } = CookiePersonality.Playful;

    /// <summary>True while a focus session runs: she naps beside you and doesn't wander.</summary>
    public bool IsFocusing { get; private set; }

    /// <summary>The cozy items placed on the main screen, kept current by the window.</summary>
    public IReadOnlyList<CozyPlacement> CozyPlacements { get; set; } = Array.Empty<CozyPlacement>();

    private DateTime LocalNow()
    {
        var now = Now();
        return now.Kind == DateTimeKind.Utc ? now.ToLocalTime() : now;
    }

    // MARK: Scripts

    private bool PrepareForScript()
    {
        if (_state == CookieState.BeingDragged || _isSessionLocked) return false;

        CancelCareSequence();
        CancelActiveEmote();
        _walkTarget = null;
        _dodgeTarget = null;
        MovementInterpolator.Stop2D();
        WindowController.CancelExploration();
        TaskbarController.CancelExploration();
        return true;
    }

    // MARK: Focus

    /// <summary>Starts a focus session: she yawns, settles and naps beside you.</summary>
    public void BeginFocus()
    {
        if (!PrepareForScript()) return;
        IsFocusing = true;
        StartFocusNap();
    }

    private void StartFocusNap()
    {
        StartCareSequence(new[]
        {
            new CareStep(CookieState.Yawning, CookieAnimationId.Yawn, 2.0),
            new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 1.8),
            new CareStep(CookieState.Sleeping, CookieAnimationId.Sleep, double.PositiveInfinity,
                OnEnter: () => _audioManager.Play(SoundEffect.Sleep))
        });
    }

    /// <summary>
    /// Ends the session. When it ran its course she stretches, meows to say it is time for a break, and
    /// sits up; when it was cancelled she just wakes quietly.
    /// </summary>
    public void EndFocus(bool completed)
    {
        if (!IsFocusing) return;
        IsFocusing = false;
        CancelCareSequence();

        var steps = new List<CareStep> { new(CookieState.Stretching, CookieAnimationId.Stretch, 2.0) };
        if (completed)
        {
            steps.Add(new CareStep(CookieState.Reacting, CookieAnimationId.Meow, 1.6,
                OnEnter: () => _audioManager.Play(SoundEffect.Meow)));
        }
        steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, completed ? 6.0 : 4.0));
        StartCareSequence(steps);
    }

    // MARK: Naps and the day

    /// <summary>Seconds of sleep for a nap, longer at night and for sleepy cats.</summary>
    public double SampleNapSeconds()
    {
        double value = 25 + _random.NextDouble() * 35;
        if (TimeOfDayExtensions.At(LocalNow()) == TimeOfDay.LateNight) value *= 1.5;
        if (Personality == CookiePersonality.Sleepy) value *= 1.15;
        if (Settings.Sleep == SleepBehavior.Longer) value *= 1.3;
        return Math.Min(value, Settings.Sleep == SleepBehavior.Longer ? 120 : 90);
    }

    /// <summary>The full ritual: yawn, settle, sleep, and stretch on waking.</summary>
    public bool StartNap(double? seconds = null)
    {
        if (!PrepareForScript()) return false;
        StartCareSequence(new[]
        {
            new CareStep(CookieState.Yawning, CookieAnimationId.Yawn, 2.0),
            new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 1.5 + _random.NextDouble() * 1.5),
            new CareStep(CookieState.Sleeping, CookieAnimationId.Sleep, seconds ?? SampleNapSeconds(),
                OnEnter: () => _audioManager.Play(SoundEffect.Sleep)),
            new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.0)
        });
        return true;
    }

    /// <summary>Mornings begin with a wake-up stretch.</summary>
    public void BeginDay()
    {
        if (TimeOfDayExtensions.At(LocalNow()) != TimeOfDay.Morning) return;
        if (!PrepareForScript()) return;
        StartCareSequence(new[]
        {
            new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.0),
            new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 3.0)
        });
    }

    private bool TryStartAutonomousNap()
    {
        if (Settings.Sleep == SleepBehavior.None) return false;
        var now = Now();
        if (now < _napCooldownUntil) return false;

        double chance = TimeOfDayExtensions.At(LocalNow()).NapChance() * (Personality == CookiePersonality.Sleepy ? 1.5 : 1.0);
        if (_random.NextDouble() >= chance) return false;

        _napCooldownUntil = now.AddSeconds(120 + _random.NextDouble() * 80);
        return StartNap();
    }

    // MARK: Cozy spots

    /// <summary>Center x of a placed item, on the main screen's work area.</summary>
    public double CozyCenterX(CozyPlacement placement)
    {
        var area = _screenService.GetPrimaryWorkArea();
        return area.Left + placement.Position * area.Width;
    }

    /// <summary>She can only visit when she is on the floor of the main screen, where the items are.</summary>
    public bool IsOnFloor
    {
        get
        {
            var area = _screenService.GetPrimaryWorkArea();
            double centerX = CompanionCenterX;
            return centerX >= area.Left && centerX <= area.Right
                && _currentPosition.Y >= area.Bottom - _companionSize.Height - 10 - FloorTolerance;
        }
    }

    /// <summary>
    /// Now and then she wanders to a cozy item she has been given. The bed is favored at night, the
    /// sunbeam only while the sun is up, the scratching post a little at any time.
    /// </summary>
    private bool TryStartAutonomousCozyVisit()
    {
        if (CozyPlacements.Count == 0 || !Settings.RandomInteractions || !Settings.AutonomousBehaviorEnabled
            || Settings.PauseAutonomousBehavior || !IsOnFloor) return false;

        var now = Now();
        if (now < _cozyCooldownUntil) return false;

        int hour = LocalNow().Hour;
        var phase = TimeOfDayExtensions.At(LocalNow());
        var options = new List<(CozyPlacement placement, double weight)>();
        foreach (var placement in CozyPlacements)
        {
            double weight = placement.Kind switch
            {
                CozyKind.Bed => phase == TimeOfDay.LateNight ? 3.0 : phase == TimeOfDay.Evening ? 1.5 : 1.0,
                CozyKind.Sunbeam => hour is >= 9 and < 17 ? 1.5 : 0,
                _ => 0.8
            };
            if (weight > 0) options.Add((placement, weight));
        }

        double total = options.Sum(option => option.weight);
        if (total <= 0 || _random.NextDouble() >= 0.12)
        {
            _cozyCooldownUntil = now.AddSeconds(20 + _random.NextDouble() * 25);
            return false;
        }

        _cozyCooldownUntil = now.AddSeconds(150 + _random.NextDouble() * 150);
        double roll = _random.NextDouble() * total;
        foreach (var (placement, weight) in options)
        {
            roll -= weight;
            if (roll <= 0)
            {
                VisitCozy(placement.Kind, CozyCenterX(placement));
                return true;
            }
        }
        return false;
    }

    /// <summary>Walks to a cozy item and enjoys it. Public so a menu command and tests can trigger it.</summary>
    public void VisitCozy(CozyKind kind, double centerX)
    {
        if (!PrepareForScript()) return;

        CurrentCozyVisit = kind;
        _cozyTargetX = centerX;
        SetFacing(centerX >= CompanionCenterX ? CookieDirection.Right : CookieDirection.Left);

        var steps = new List<CareStep>
        {
            new(CookieState.Curious, CookieAnimationId.Curious, 1.0),
            new(CookieState.Walking, CookieAnimationId.WalkRight, 0, IsWalkToItem: true)
        };

        switch (kind)
        {
            case CozyKind.Bed:
                steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 1.5));
                steps.Add(new CareStep(CookieState.Yawning, CookieAnimationId.Yawn, 2.0));
                steps.Add(new CareStep(CookieState.Sleeping, CookieAnimationId.Sleep,
                    Math.Clamp(SampleNapSeconds() / 1.5, 30, 60), OnEnter: () => _audioManager.Play(SoundEffect.Sleep)));
                steps.Add(new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.2));
                steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 4.0));
                break;
            case CozyKind.Sunbeam:
                steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 10 + _random.NextDouble() * 6));
                steps.Add(new CareStep(CookieState.Grooming, CookieAnimationId.Groom, 2.5));
                steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 4.0));
                break;
            default:
                steps.Add(new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.2));
                steps.Add(new CareStep(CookieState.Grooming, CookieAnimationId.Groom, 2.5));
                steps.Add(new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.2));
                steps.Add(new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 4.0));
                break;
        }
        StartCareSequence(steps);
    }

    // MARK: Summoning and celebrating

    /// <summary>Calls her to the cursor, on whichever monitor it is on, and has her wave hello.</summary>
    public void Summon(CorePoint cursor)
    {
        if (_state == CookieState.BeingDragged) return;

        var monitors = _screenService.GetActiveMonitors();
        var area = monitors.FirstOrDefault(m => cursor.X >= m.WorkArea.Left && cursor.X <= m.WorkArea.Right
                                                && cursor.Y >= m.WorkArea.Top && cursor.Y <= m.WorkArea.Bottom)?.WorkArea
                   ?? _screenService.GetPrimaryWorkArea();

        CancelCareSequence();
        SetPosition(SummonPlacement.Origin(cursor, _companionSize, area));
        if (!TriggerEmote(Emote.Wave))
        {
            TransitionToState(CookieState.Reacting);
            _animationController.PlayAnimation(CookieAnimationId.Happy);
        }
    }

    /// <summary>Marks a happy occasion such as a new friendship level.</summary>
    public void Celebrate()
    {
        if (_state == CookieState.BeingDragged) return;
        if (!TriggerEmote(Emote.Love))
        {
            TransitionToState(CookieState.Reacting);
            _animationController.PlayAnimation(CookieAnimationId.Happy);
        }
    }
}
