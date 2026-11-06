using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Feeding and toy play: Cookie notices an item placed nearby, walks over, enjoys it,
/// and winds down. Timings match the macOS engine.
/// </summary>
public partial class CookieBehaviorController
{
    private const double ItemSpawnDistance = 150.0;
    private const double ItemStandOffDistance = 62.0;

    private sealed record CareStep(
        CookieState State,
        CookieAnimationId Animation,
        double Duration,
        bool IsWalkToItem = false,
        Action? OnEnter = null);

    private readonly Queue<CareStep> _careQueue = new();
    private CareStep? _careStep;
    private double _careStepTimer;

    public CookieStatistics Statistics { get; set; } = new();
    public WorldItem? CurrentWorldItem { get; private set; }
    public bool IsCareSequenceActive => _careStep != null;

    public event Action<WorldItem?>? OnWorldItemChanged;
    public event Action? OnStatisticsChanged;

    public void OfferFood(FoodKind food)
    {
        if (!PrepareForItem()) return;

        PlaceItem(new WorldItem(null, food, ItemSpawnX(), CompanionGroundY));

        bool isMilk = food == FoodKind.Milk;
        StartCareSequence(new[]
        {
            new CareStep(CookieState.Curious, CookieAnimationId.Curious, 1.2, OnEnter: () => _audioManager.Play(SoundEffect.Chirp)),
            new CareStep(CookieState.Walking, CookieAnimationId.WalkRight, 0, IsWalkToItem: true),
            new CareStep(CookieState.Investigating, CookieAnimationId.Investigate, 1.8),
            new CareStep(
                isMilk ? CookieState.Drinking : CookieState.Eating,
                isMilk ? CookieAnimationId.Drink : CookieAnimationId.Eat,
                3.8,
                OnEnter: () =>
                {
                    _audioManager.Play(SoundEffect.Eat);
                    Statistics.TreatsGiven++;
                    Statistics.Affection++;
                    OnStatisticsChanged?.Invoke();
                }),
            new CareStep(CookieState.Reacting, CookieAnimationId.Pet, 1.8, OnEnter: () =>
            {
                SetWorldItem(null);
                _audioManager.Play(SoundEffect.Purr);
            }),
            new CareStep(CookieState.Grooming, CookieAnimationId.Groom, 2.2),
            new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 4.0)
        });
    }

    public void OfferToy(ToyKind toy)
    {
        if (!PrepareForItem()) return;

        PlaceItem(new WorldItem(toy, null, ItemSpawnX(), CompanionGroundY));

        var windDown = toy == ToyKind.Box
            ? new[]
            {
                new CareStep(CookieState.InBox, CookieAnimationId.InBox, RandomBetween(18, 30), OnEnter: () =>
                {
                    Statistics.BoxVisits++;
                    OnStatisticsChanged?.Invoke();
                }),
                new CareStep(CookieState.Stretching, CookieAnimationId.Stretch, 2.2, OnEnter: () => SetWorldItem(null)),
                new CareStep(CookieState.Sitting, CookieAnimationId.Sit, 4.0)
            }
            : new[]
            {
                new CareStep(CookieState.Playing, CookieAnimationId.Playful, RandomBetween(4.2, 6.8), OnEnter: () =>
                {
                    _audioManager.Play(SoundEffect.Toy);
                    Statistics.RecordToyPlayed(toy);
                    Statistics.Affection++;
                    OnStatisticsChanged?.Invoke();
                }),
                new CareStep(CookieState.Tired, CookieAnimationId.Tired, RandomBetween(2.6, 4.0), OnEnter: () => SetWorldItem(null)),
                new CareStep(CookieState.Sitting, CookieAnimationId.Sit, RandomBetween(4, 8))
            };

        var steps = new List<CareStep>
        {
            new(CookieState.Curious, CookieAnimationId.Curious, 1.4, OnEnter: () => _audioManager.Play(SoundEffect.Chirp)),
            new(CookieState.Walking, CookieAnimationId.WalkRight, 0, IsWalkToItem: true),
            new(CookieState.Investigating, CookieAnimationId.Investigate, 2.0)
        };
        steps.AddRange(windDown);
        StartCareSequence(steps);
    }

    /// <summary>Moves the item when the user drags it. Cookie re-targets if she is still walking over.</summary>
    public void MoveWorldItem(double centerX)
    {
        if (CurrentWorldItem == null) return;
        SetWorldItem(CurrentWorldItem with { X = ClampItemX(centerX) });
    }

    /// <summary>Puts the current item away and ends any sequence built around it.</summary>
    public void ClearWorldItem()
    {
        bool wasActive = IsCareSequenceActive;
        CancelCareSequence();
        if (wasActive) TransitionToState(CookieState.Idle);
    }

    private double CompanionGroundY => _currentPosition.Y + _companionSize.Height;
    private double CompanionCenterX => _currentPosition.X + _companionSize.Width / 2.0;

    private bool PrepareForItem()
    {
        if (_state == CookieState.BeingDragged || _isSessionLocked) return false;

        CancelCareSequence();
        CancelActiveEmote();
        _walkTarget = null;
        _dodgeTarget = null;
        MovementInterpolator.Stop2D();
        WindowController.CancelExploration();
        TaskbarController.CancelExploration();
        Memory.RecordDirectInteraction();
        return true;
    }

    private double ItemSpawnX()
    {
        double direction = _facing == CookieDirection.Right ? 1 : -1;
        double preferred = CompanionCenterX + direction * ItemSpawnDistance;
        double clamped = ClampItemX(preferred);

        // Near a screen edge there is no room on her facing side, so use the other one.
        if (Math.Abs(clamped - CompanionCenterX) < ItemStandOffDistance + 1)
        {
            clamped = ClampItemX(CompanionCenterX - direction * ItemSpawnDistance);
        }
        return clamped;
    }

    private double ClampItemX(double x)
    {
        var area = _screenService.GetPrimaryWorkArea();
        if (!(CompanionCenterX >= area.Left && CompanionCenterX <= area.Right))
        {
            // On a secondary display: keep the item level with her, not on the primary screen.
            return x;
        }
        return Math.Max(area.Left + 50, Math.Min(x, area.Right - 50));
    }

    private void PlaceItem(WorldItem item)
    {
        SetFacing(item.X >= CompanionCenterX ? CookieDirection.Right : CookieDirection.Left);
        SetWorldItem(item);
    }

    private void SetWorldItem(WorldItem? item)
    {
        CurrentWorldItem = item;
        OnWorldItemChanged?.Invoke(item);
    }

    private void StartCareSequence(IEnumerable<CareStep> steps)
    {
        _careQueue.Clear();
        foreach (var step in steps) _careQueue.Enqueue(step);
        AdvanceCareStep();
    }

    private void CancelCareSequence()
    {
        bool wasActive = _careStep != null;
        _careQueue.Clear();
        _careStep = null;
        _careStepTimer = 0;
        if (CurrentWorldItem != null) SetWorldItem(null);

        // Looping care animations outrank idle, so release them before callers
        // make their own lower-priority animation requests.
        if (wasActive) _animationController.ForceAnimation(CookieAnimationId.Idle);
    }

    private void AdvanceCareStep()
    {
        _careStepTimer = 0;

        if (_careQueue.Count == 0)
        {
            _careStep = null;
            if (CurrentWorldItem != null) SetWorldItem(null);
            TransitionToState(CookieState.Idle);
            _animationController.ForceAnimation(CookieAnimationId.Idle);
            _stateTimer = 0;
            return;
        }

        _careStep = _careQueue.Dequeue();
        TransitionToState(_careStep.State);
        _careStep.OnEnter?.Invoke();

        if (_careStep.IsWalkToItem && CurrentWorldItem != null)
        {
            FaceItemAndWalk(CurrentWorldItem);
        }
        else
        {
            _animationController.ForceAnimation(_careStep.Animation);
        }
    }

    private void FaceItemAndWalk(WorldItem item)
    {
        var direction = item.X >= CompanionCenterX ? CookieDirection.Right : CookieDirection.Left;
        SetFacing(direction);
        _animationController.ForceAnimation(direction == CookieDirection.Right ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
    }

    private void UpdateCareSequence(double deltaTimeSeconds)
    {
        var step = _careStep!;

        if (step.IsWalkToItem)
        {
            UpdateWalkToItem(deltaTimeSeconds);
            return;
        }

        // One-shot animations restart to fill the step, so she never falls back to idle mid-meal.
        if (_animationController.CurrentAnimationId != step.Animation)
        {
            _animationController.ForceAnimation(step.Animation);
        }

        _careStepTimer += deltaTimeSeconds;
        if (_careStepTimer >= step.Duration)
        {
            AdvanceCareStep();
        }
    }

    private void UpdateWalkToItem(double deltaTimeSeconds)
    {
        if (CurrentWorldItem is not { } item)
        {
            AdvanceCareStep();
            return;
        }

        // She stands beside food and toys, and walks right into a box.
        double standOff = item.IsBox ? 0 : ItemStandOffDistance;
        double toItem = item.X - CompanionCenterX;
        double remaining = Math.Abs(toItem) - standOff;

        if (remaining <= 0)
        {
            AdvanceCareStep();
            return;
        }

        var direction = toItem >= 0 ? CookieDirection.Right : CookieDirection.Left;
        if (direction != _facing) FaceItemAndWalk(item);

        double speed = Settings.ReducedMotion == ReducedMotionMode.Always ? BaseWalkSpeed * 0.65 : BaseWalkSpeed;
        double step = Math.Min(speed * deltaTimeSeconds, remaining);
        _currentPosition = new CorePoint(_currentPosition.X + Math.Sign(toItem) * step, _currentPosition.Y);
        OnPositionChanged?.Invoke(_currentPosition);
    }

    private double RandomBetween(double low, double high) => low + _random.NextDouble() * (high - low);
}
