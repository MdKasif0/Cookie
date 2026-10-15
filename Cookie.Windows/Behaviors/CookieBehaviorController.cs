using System;
using System.Windows;
using Cookie.Windows.Animation;
using Cookie.Windows.Audio;
using Cookie.Windows.Desktop;
using Cookie.Windows.Models;

namespace Cookie.Windows.Behaviors;

public class CookieBehaviorController
{
    private readonly CookieAnimationController _animationController;
    private readonly ScreenGeometryService _screenService;
    private readonly WindowsAudioManager _audioManager;

    private CookieState _state = CookieState.Idle;
    private Point _currentPosition;
    private Size _companionSize = new(180, 180);
    private readonly Random _random = new();

    // Autonomous locomotion state
    private double _stateTimer = 0.0;
    private double _nextBehaviorTime = 4.0;
    private Point? _walkTarget;
    private const double WalkSpeedDipPerSecond = 55.0;

    // Emote playback state
    private Emote? _currentEmote;
    private double _emoteTimer = 0.0;

    public CookieState State => _state;
    public Point CurrentPosition => _currentPosition;
    public Size CompanionSize => _companionSize;
    public Emote? CurrentEmote => _currentEmote;

    public event Action<Point>? OnPositionChanged;
    public event Action<CookieState>? OnStateChanged;
    public event Action<Emote?>? OnEmoteChanged;

    public bool AutonomousBehaviorEnabled { get; set; } = true;
    public bool PauseAutonomousBehavior { get; set; } = false;
    public bool CursorInteractionEnabled { get; set; } = true;
    public ActivityLevel Activity { get; set; } = ActivityLevel.Balanced;

    public CookieBehaviorController(
        CookieAnimationController animationController,
        ScreenGeometryService screenService,
        WindowsAudioManager audioManager)
    {
        _animationController = animationController;
        _screenService = screenService;
        _audioManager = audioManager;

        // Default start position
        var primaryArea = _screenService.GetPrimaryWorkArea();
        _currentPosition = DesktopCoordinateSpace.CalculateDefaultSpawn(primaryArea, _companionSize);

        _animationController.OnAnimationCompleted += HandleAnimationCompleted;
    }

    public void SetPosition(Point position)
    {
        _currentPosition = position;
        OnPositionChanged?.Invoke(_currentPosition);
    }

    public void SetCompanionSize(Size size)
    {
        _companionSize = size;
    }

    public void Update(double deltaTimeSeconds)
    {
        _animationController.Update(deltaTimeSeconds);

        switch (_state)
        {
            case CookieState.Idle:
                UpdateIdle(deltaTimeSeconds);
                break;

            case CookieState.Walking:
                UpdateWalking(deltaTimeSeconds);
                break;

            case CookieState.Emoting:
                UpdateEmoting(deltaTimeSeconds);
                break;

            case CookieState.BeingDragged:
                // Handled directly via DragMove
                break;

            case CookieState.Reacting:
                // Waits for reaction animation to complete
                break;
        }

        // Check cursor observation if idle
        if (_state == CookieState.Idle && CursorInteractionEnabled)
        {
            UpdateCursorObservation();
        }
    }

    private void UpdateIdle(double deltaTimeSeconds)
    {
        if (!AutonomousBehaviorEnabled || PauseAutonomousBehavior)
        {
            return;
        }

        _stateTimer += deltaTimeSeconds;

        if (_stateTimer >= _nextBehaviorTime)
        {
            _stateTimer = 0.0;
            DecideNextAutonomousBehavior();
        }
    }

    private void DecideNextAutonomousBehavior()
    {
        // Activity-based timing
        double baseInterval = Activity switch
        {
            ActivityLevel.Calm => 8.0,
            ActivityLevel.Balanced => 4.5,
            ActivityLevel.Playful => 2.5,
            _ => 4.5
        };
        _nextBehaviorTime = baseInterval + _random.NextDouble() * 3.0;

        int choice = _random.Next(0, 10);

        if (choice < 5)
        {
            // Autonomous short walk
            StartAutonomousWalk();
        }
        else if (choice == 5)
        {
            _animationController.PlayAnimation(CookieAnimationId.Stretch);
        }
        else if (choice == 6)
        {
            _animationController.PlayAnimation(CookieAnimationId.Yawn);
        }
        else if (choice == 7)
        {
            _animationController.PlayAnimation(CookieAnimationId.Groom);
        }
        else if (choice == 8)
        {
            _animationController.PlayAnimation(CookieAnimationId.IdleBlink);
        }
        else
        {
            // Stay peacefully idle
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void StartAutonomousWalk()
    {
        var primaryArea = _screenService.GetPrimaryWorkArea();

        // Walk distance: 40 to 140 DIPs
        double distance = _random.Next(40, 140) * (_random.Next(0, 2) == 0 ? -1 : 1);
        double targetX = _currentPosition.X + distance;

        // Clamp target X to visible work area
        targetX = Math.Max(primaryArea.Left + 20, Math.Min(targetX, primaryArea.Right - _companionSize.Width - 20));

        if (Math.Abs(targetX - _currentPosition.X) > 15)
        {
            _walkTarget = new Point(targetX, _currentPosition.Y);
            var dir = targetX > _currentPosition.X ? CookieDirection.Right : CookieDirection.Left;

            TransitionToState(CookieState.Walking);
            _animationController.SetFacing(dir);
            _animationController.PlayAnimation(dir == CookieDirection.Right ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
        }
    }

    private void UpdateWalking(double deltaTimeSeconds)
    {
        if (!_walkTarget.HasValue)
        {
            StopWalking();
            return;
        }

        double dx = _walkTarget.Value.X - _currentPosition.X;
        double step = WalkSpeedDipPerSecond * deltaTimeSeconds;

        if (Math.Abs(dx) <= step)
        {
            // Arrived at target
            _currentPosition.X = _walkTarget.Value.X;
            OnPositionChanged?.Invoke(_currentPosition);
            StopWalking();
        }
        else
        {
            double moveDirection = Math.Sign(dx);
            _currentPosition.X += moveDirection * step;
            OnPositionChanged?.Invoke(_currentPosition);
        }
    }

    private void StopWalking()
    {
        _walkTarget = null;
        TransitionToState(CookieState.Idle);
        _animationController.PlayAnimation(CookieAnimationId.Idle);
    }

    private void UpdateCursorObservation()
    {
        var cursorPos = _screenService.GetCursorPositionDip();
        if (!cursorPos.HasValue)
        {
            _animationController.ResetLookAt();
            return;
        }

        double catCenterX = _currentPosition.X + _companionSize.Width / 2.0;
        double catCenterY = _currentPosition.Y + _companionSize.Height / 2.0;

        double deltaX = cursorPos.Value.X - catCenterX;
        double deltaY = cursorPos.Value.Y - catCenterY;
        double distance = Math.Sqrt(deltaX * deltaX + deltaY * deltaY);

        // Within awareness radius of 280 DIPs
        if (distance < 280)
        {
            double normalizedX = Math.Clamp(deltaX / 140.0, -1.0, 1.0);
            double gazeOffset = normalizedX * 3.5;
            double tiltOffset = Math.Clamp(-deltaY / 70.0, -4.0, 4.0);

            _animationController.SetLookAt(gazeOffset, tiltOffset);
        }
        else
        {
            _animationController.ResetLookAt();
        }
    }

    public void BeginDrag()
    {
        _walkTarget = null;
        TransitionToState(CookieState.BeingDragged);
        _animationController.PlayAnimation(CookieAnimationId.PickedUp);
    }

    public void UpdateDrag(Point newPosition)
    {
        _currentPosition = newPosition;
        OnPositionChanged?.Invoke(_currentPosition);
    }

    public void EndDrag()
    {
        // Safe position clamping
        _currentPosition = _screenService.RecoverPosition(_currentPosition, _companionSize);
        OnPositionChanged?.Invoke(_currentPosition);

        // Play drop landing animation and sound
        TransitionToState(CookieState.Reacting);
        _audioManager.Play(SoundEffect.Drop);
        _animationController.PlayAnimation(CookieAnimationId.Dropped);
    }

    public void Pet()
    {
        if (_state == CookieState.BeingDragged) return;

        TransitionToState(CookieState.Reacting);
        _audioManager.Play(SoundEffect.Purr);
        _animationController.PlayAnimation(CookieAnimationId.Pet);
    }

    public bool TriggerEmote(Emote emote)
    {
        if (_state == CookieState.BeingDragged) return false;

        _currentEmote = emote;
        _emoteTimer = 0.0;
        TransitionToState(CookieState.Emoting);
        OnEmoteChanged?.Invoke(_currentEmote);

        if (emote.SoundIdentifier.HasValue)
        {
            _audioManager.Play(emote.SoundIdentifier.Value);
        }

        _animationController.PlayAnimation(emote.AnimationIdentifier, interruptIfLowerOrEqual: true);
        return true;
    }

    private void UpdateEmoting(double deltaTimeSeconds)
    {
        if (_currentEmote == null)
        {
            TransitionToState(CookieState.Idle);
            return;
        }

        _emoteTimer += deltaTimeSeconds;
        if (_emoteTimer >= _currentEmote.DurationSeconds)
        {
            _currentEmote = null;
            OnEmoteChanged?.Invoke(null);
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void HandleAnimationCompleted(CookieAnimationId completedId)
    {
        if (_state is CookieState.Reacting)
        {
            TransitionToState(CookieState.Idle);
        }
    }

    private void TransitionToState(CookieState newState)
    {
        if (_state != newState)
        {
            _state = newState;
            OnStateChanged?.Invoke(_state);
        }
    }
}
