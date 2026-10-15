using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Cookie's centralized behavior state machine and controller.
/// Enforces priority hierarchy:
/// 1. Active dragging (BeingDragged)
/// 2. Explicit user-triggered emote (Emoting)
/// 3. Active direct interaction (Reacting from drop/pet/dodge)
/// 4. Safety drop / Invalidation recovery
/// 5. Active jump (Jumping)
/// 6. Window exploration (ExploringWindow, Climbing)
/// 7. Taskbar exploration (ExploringTaskbar)
/// 8. Cursor following (FollowingCursor)
/// 9. Autonomous activity (Walking, stretching, grooming, etc.)
/// 10. Idle
/// </summary>
public class CookieBehaviorController
{
    private readonly CookieAnimationController _animationController;
    private readonly ScreenGeometryService _screenService;
    private readonly AudioManagerBase _audioManager;
    private readonly Random _random = new();

    public CursorInteractionController CursorController { get; }
    public MovementInterpolator MovementInterpolator { get; }
    public IDesktopEnvironmentProvider EnvironmentProvider { get; }
    public TaskbarInteractionController TaskbarController { get; }
    public WindowInteractionController WindowController { get; }

    private CookieState _state = CookieState.Idle;
    private CookieDirection _facing = CookieDirection.Right;
    private CorePoint _currentPosition;
    private CoreSize _companionSize = new(180, 180);

    private double _stateTimer = 0.0;
    private double _nextBehaviorTime = 4.0;
    private CorePoint? _walkTarget;
    private const double BaseWalkSpeed = 55.0;

    private Emote? _currentEmote;
    private double _emoteTimer = 0.0;
    private readonly Dictionary<EmoteId, DateTime> _emoteCooldowns = new();

    // Dodging retreat state
    private CorePoint? _dodgeTarget;
    private double _dodgeTimer = 0.0;

    public CookieState State => _state;
    public CookieDirection Facing => _facing;
    public CorePoint CurrentPosition => _currentPosition;
    public CoreSize CompanionSize => _companionSize;
    public Emote? CurrentEmote => _currentEmote;

    public event Action<CorePoint>? OnPositionChanged;
    public event Action<CookieState>? OnStateChanged;
    public event Action<CookieDirection>? OnFacingChanged;
    public event Action<Emote?>? OnEmoteChanged;
    public event Action? OnNoticeTriggered;

    public CookieSettings Settings { get; set; } = new();

    public bool AutonomousBehaviorEnabled
    {
        get => Settings.AutonomousBehaviorEnabled;
        set => Settings.AutonomousBehaviorEnabled = value;
    }

    public bool PauseAutonomousBehavior
    {
        get => Settings.PauseAutonomousBehavior;
        set => Settings.PauseAutonomousBehavior = value;
    }

    public bool CursorInteractionEnabled
    {
        get => Settings.CursorInteraction;
        set => Settings.CursorInteraction = value;
    }

    public ActivityLevel Activity
    {
        get => Settings.Activity;
        set => Settings.Activity = value;
    }

    public Func<DateTime> Now
    {
        get => CursorController.Now;
        set
        {
            CursorController.Now = value;
            TaskbarController.Now = value;
            WindowController.Now = value;
            WindowController.JumpPlanner.Now = value;
        }
    }

    public CookieBehaviorController(
        CookieAnimationController animationController,
        ScreenGeometryService screenService,
        AudioManagerBase audioManager,
        CursorInteractionController? cursorController = null,
        MovementInterpolator? movementInterpolator = null,
        IDesktopEnvironmentProvider? environmentProvider = null,
        TaskbarInteractionController? taskbarController = null,
        WindowInteractionController? windowController = null)
    {
        _animationController = animationController;
        _screenService = screenService;
        _audioManager = audioManager;

        CursorController = cursorController ?? new CursorInteractionController();
        MovementInterpolator = movementInterpolator ?? new MovementInterpolator(
            maxSpeed: Settings.FollowingIntensity.GetMaxSpeed(),
            acceleration: 340.0,
            deceleration: 480.0,
            arrivalThreshold: 5.0);

        EnvironmentProvider = environmentProvider ?? new DefaultDesktopEnvironmentProvider();
        TaskbarController = taskbarController ?? new TaskbarInteractionController();
        WindowController = windowController ?? new WindowInteractionController();

        var primaryArea = _screenService.GetPrimaryWorkArea();
        _currentPosition = DesktopCoordinateSpace.CalculateDefaultSpawn(primaryArea, _companionSize);

        _animationController.OnAnimationCompleted += HandleAnimationCompleted;
    }

    public void SetPosition(CorePoint position)
    {
        _currentPosition = position;
        OnPositionChanged?.Invoke(_currentPosition);
    }

    public void SetCompanionSize(CoreSize size)
    {
        _companionSize = size;
    }

    public void SetFacing(CookieDirection direction)
    {
        if (_facing != direction)
        {
            _facing = direction;
            _animationController.SetFacing(direction);
            OnFacingChanged?.Invoke(_facing);
        }
    }

    public double CooldownRemaining(EmoteId id)
    {
        if (_emoteCooldowns.TryGetValue(id, out var until))
        {
            double remaining = (until - Now()).TotalSeconds;
            return Math.Max(0.0, remaining);
        }
        return 0.0;
    }

    public bool CanPerformEmote(Emote emote)
    {
        if (_state == CookieState.BeingDragged) return false;
        if (_currentEmote != null) return false;
        if (CooldownRemaining(emote.Id) > 0.05) return false;
        return true;
    }

    public void Update(double deltaTimeSeconds, CorePoint? explicitCursorPos = null)
    {
        if (deltaTimeSeconds <= 0.0) return;

        _animationController.Update(deltaTimeSeconds);

        // Calculate cat center in DIPs
        var catCenter = new CorePoint(
            _currentPosition.X + _companionSize.Width / 2.0,
            _currentPosition.Y + _companionSize.Height / 2.0);

        var cursorPos = explicitCursorPos ?? _screenService.GetCursorPositionDip();

        bool isInterrupted = _state is CookieState.BeingDragged or CookieState.Emoting;
        CursorController.Update(
            deltaTimeSeconds,
            catCenter,
            cursorPos,
            Settings.CookieSize,
            Settings,
            isInterrupted);

        var env = EnvironmentProvider.GetDesktopEnvironment(_currentPosition);

        switch (_state)
        {
            case CookieState.BeingDragged:
                // Dragging has ultimate priority; autonomous movement is completely halted
                break;

            case CookieState.Emoting:
                UpdateEmoting(deltaTimeSeconds);
                break;

            case CookieState.Reacting:
                UpdateReacting(deltaTimeSeconds);
                break;

            case CookieState.Jumping:
                UpdateJumping(deltaTimeSeconds, env);
                break;

            case CookieState.Climbing:
            case CookieState.ExploringWindow:
                UpdateWindowExploration(deltaTimeSeconds, env);
                break;

            case CookieState.ExploringTaskbar:
                UpdateTaskbarExploration(deltaTimeSeconds, env, cursorPos);
                break;

            case CookieState.FollowingCursor:
                UpdateFollowingCursor(deltaTimeSeconds, catCenter);
                break;

            case CookieState.Walking:
                UpdateWalking(deltaTimeSeconds);
                break;

            case CookieState.Idle:
            default:
                UpdateIdle(deltaTimeSeconds, catCenter, cursorPos, env);
                break;
        }

        // Apply anatomical look-at to animation controller
        if (_state is CookieState.Idle or CookieState.FollowingCursor)
        {
            if (CursorController.LookAngle.HasValue)
            {
                double angle = CursorController.LookAngle.Value;
                double gazeOffset = Math.Clamp(angle * 12.0, -3.5, 3.5);
                double tiltOffset = Math.Clamp(-angle * 18.0, -4.0, 4.0);
                _animationController.SetLookAt(gazeOffset, tiltOffset);
            }
            else
            {
                _animationController.ResetLookAt();
            }
        }
    }

    private void UpdateJumping(double deltaTimeSeconds, DesktopEnvironment env)
    {
        var newPos = WindowController.Update(deltaTimeSeconds, _currentPosition, _companionSize, env, Settings);
        if (newPos.HasValue)
        {
            _currentPosition = newPos.Value;
            OnPositionChanged?.Invoke(_currentPosition);

            if (WindowController.ActiveJumpTrajectory != null)
            {
                var vel = WindowController.ActiveJumpTrajectory.VelocityAt(WindowController.JumpProgress);
                var dir = vel.Vx >= 0 ? CookieDirection.Right : CookieDirection.Left;
                SetFacing(dir);

                // If ascending in the air (Vy < 0 in Windows screen coords), show jump pose; if descending (Vy > 0), show fall pose
                if (vel.Vy < -20.0)
                {
                    _animationController.PlayAnimation(CookieAnimationId.Jump);
                }
                else if (vel.Vy > 20.0)
                {
                    _animationController.PlayAnimation(CookieAnimationId.Fall);
                }
            }
        }

        if (WindowController.CurrentPhase == WindowExplorationPhase.Landing)
        {
            if (WindowController.ActiveWindow != null)
            {
                TransitionToState(CookieState.ExploringWindow);
                _animationController.PlayAnimation(CookieAnimationId.Idle);
            }
            else
            {
                TransitionToState(CookieState.Reacting);
                _audioManager.Play(SoundEffect.Drop);
                _animationController.PlayAnimation(CookieAnimationId.Dropped);
            }
        }
        else if (WindowController.CurrentPhase == WindowExplorationPhase.Idle)
        {
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void UpdateWindowExploration(double deltaTimeSeconds, DesktopEnvironment env)
    {
        var newPos = WindowController.Update(deltaTimeSeconds, _currentPosition, _companionSize, env, Settings);
        if (newPos.HasValue)
        {
            _currentPosition = newPos.Value;
            OnPositionChanged?.Invoke(_currentPosition);
        }

        if (WindowController.CurrentPhase == WindowExplorationPhase.Jumping)
        {
            TransitionToState(CookieState.Jumping);
            _audioManager.Play(SoundEffect.Surprise);
            _animationController.PlayAnimation(CookieAnimationId.Jump);
        }
        else if (WindowController.CurrentPhase == WindowExplorationPhase.ClimbingVerticalEdge)
        {
            TransitionToState(CookieState.Climbing);
            _animationController.PlayAnimation(CookieAnimationId.Climb);
        }
        else if (WindowController.CurrentPhase == WindowExplorationPhase.WalkingTopEdge)
        {
            TransitionToState(CookieState.ExploringWindow);
            var dir = WindowController.PathDirection >= 0 ? CookieDirection.Right : CookieDirection.Left;
            SetFacing(dir);
            _animationController.PlayAnimation(dir == CookieDirection.Right ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
        }
        else if (WindowController.CurrentPhase == WindowExplorationPhase.PreparingJump)
        {
            _animationController.PlayAnimation(CookieAnimationId.Sit);
        }
        else if (WindowController.CurrentPhase == WindowExplorationPhase.Idle)
        {
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void UpdateTaskbarExploration(double deltaTimeSeconds, DesktopEnvironment env, CorePoint? cursorPos)
    {
        var targetPos = TaskbarController.Update(deltaTimeSeconds, _currentPosition, _companionSize, env, cursorPos);
        if (targetPos.HasValue)
        {
            double dx = targetPos.Value.X - _currentPosition.X;
            double step = BaseWalkSpeed * deltaTimeSeconds;

            if (Math.Abs(dx) <= step)
            {
                _currentPosition = targetPos.Value;
                _animationController.PlayAnimation(CookieAnimationId.Idle);
            }
            else
            {
                double dir = Math.Sign(dx);
                _currentPosition = new CorePoint(_currentPosition.X + dir * step, _currentPosition.Y);
                SetFacing(dir > 0 ? CookieDirection.Right : CookieDirection.Left);
                _animationController.PlayAnimation(dir > 0 ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
            }
            OnPositionChanged?.Invoke(_currentPosition);
        }

        if (TaskbarController.TaskbarLookAngle.HasValue)
        {
            double angle = TaskbarController.TaskbarLookAngle.Value;
            _animationController.SetLookAt(angle * 12.0, -angle * 18.0);
        }

        if (TaskbarController.CurrentPhase == TaskbarSessionPhase.Idle)
        {
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void UpdateIdle(double deltaTimeSeconds, CorePoint catCenter, CorePoint? cursorPos, DesktopEnvironment env)
    {
        // 1. Process active cursor reactions
        if (CursorInteractionEnabled && CursorController.IsCursorNear)
        {
            if (cursorPos.HasValue)
            {
                SetFacing(cursorPos.Value.X >= catCenter.X ? CookieDirection.Right : CookieDirection.Left);
            }

            // Playful dodge triggered
            if (CursorController.ActiveReaction == CursorPlayfulReaction.Dodge)
            {
                CursorController.ClearActiveReaction();
                ExecutePlayfulDodge(catCenter, cursorPos);
                return;
            }

            // Other playful reactions
            if (CursorController.ActiveReaction.HasValue)
            {
                var reaction = CursorController.ActiveReaction.Value;
                CursorController.ClearActiveReaction();

                switch (reaction)
                {
                    case CursorPlayfulReaction.HappyChirp:
                        _audioManager.Play(SoundEffect.Happy);
                        _animationController.PlayAnimation(CookieAnimationId.HappyEmote);
                        OnNoticeTriggered?.Invoke();
                        break;

                    case CursorPlayfulReaction.PawReach:
                        _animationController.PlayAnimation(CookieAnimationId.Investigate);
                        _audioManager.Play(SoundEffect.Mew);
                        break;

                    case CursorPlayfulReaction.HeadTilt:
                        _animationController.PlayAnimation(CookieAnimationId.Curious);
                        break;

                    case CursorPlayfulReaction.Glance:
                        _animationController.PlayAnimation(CookieAnimationId.IdleBlink);
                        break;
                }
            }

            // Start cursor following if conditions met
            if (Settings.CursorFollowingEnabled &&
                CursorController.CurrentZone == CursorProximityZone.Interaction &&
                CursorController.FollowTarget.HasValue &&
                CursorController.CursorMotionState == CursorMotionState.Slow)
            {
                StartFollowingCursor(CursorController.FollowTarget.Value);
                return;
            }
        }

        // 2. Autonomous behavior when idle and unengaged
        if (!AutonomousBehaviorEnabled || PauseAutonomousBehavior)
        {
            return;
        }

        // 3. Autonomous Window Exploration Check
        if (Settings.WindowInteraction &&
            WindowController.ShouldTriggerAutonomousExploration(
                _currentPosition,
                Settings.WindowExplorationFrequency,
                Settings.WindowInteraction,
                isInterrupted: false))
        {
            if (WindowController.StartExploration(
                _currentPosition,
                env.Windows,
                Settings.WindowExplorationFrequency,
                Settings.WindowVerticalClimbing))
            {
                TransitionToState(CookieState.ExploringWindow);
                var dir = WindowController.PathDirection >= 0 ? CookieDirection.Right : CookieDirection.Left;
                SetFacing(dir);
                _animationController.PlayAnimation(dir == CookieDirection.Right ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
                return;
            }
        }

        // 4. Autonomous Taskbar Exploration Check
        if (Settings.DockInteraction &&
            Settings.AutonomousDockExploration &&
            TaskbarController.ShouldTriggerAutonomousExploration(
                _currentPosition,
                Settings.DockExplorationFrequency,
                Settings.DockInteraction,
                isInterrupted: false))
        {
            TaskbarController.StartExploration(
                _currentPosition,
                _companionSize,
                env,
                env.Windows,
                Settings.DockExplorationFrequency);

            TransitionToState(CookieState.ExploringTaskbar);
            _animationController.PlayAnimation(CookieAnimationId.Curious);
            return;
        }

        // 5. Autonomous Ground Behaviors
        _stateTimer += deltaTimeSeconds;
        if (_stateTimer >= _nextBehaviorTime)
        {
            _stateTimer = 0.0;
            DecideNextAutonomousBehavior();
        }
    }

    private void StartFollowingCursor(CorePoint target)
    {
        MovementInterpolator.MaxSpeed = Settings.FollowingIntensity.GetMaxSpeed();
        MovementInterpolator.Reset2D(_currentPosition);
        MovementInterpolator.SetTarget2D(ClampToScreen(target));

        TransitionToState(CookieState.FollowingCursor);
        var dir = target.X >= _currentPosition.X ? CookieDirection.Right : CookieDirection.Left;
        SetFacing(dir);
        _animationController.PlayAnimation(dir == CookieDirection.Right ? CookieAnimationId.WalkRight : CookieAnimationId.WalkLeft);
    }

    private void UpdateFollowingCursor(double deltaTimeSeconds, CorePoint catCenter)
    {
        if (CursorController.CursorMotionState == CursorMotionState.Rapid)
        {
            MovementInterpolator.Stop2D();
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Curious);
            return;
        }

        if (CursorController.CurrentZone is CursorProximityZone.Departure or CursorProximityZone.CloseContact ||
            !CursorController.FollowTarget.HasValue)
        {
            MovementInterpolator.Stop2D();
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
            return;
        }

        var safeTarget = ClampToScreen(CursorController.FollowTarget.Value);
        MovementInterpolator.SetTarget2D(safeTarget);

        var (newPos, velocity) = MovementInterpolator.Update2D(deltaTimeSeconds);
        _currentPosition = newPos;
        OnPositionChanged?.Invoke(_currentPosition);

        var dir = velocity.X >= 0 ? CookieDirection.Right : CookieDirection.Left;
        SetFacing(dir);

        if (MovementInterpolator.IsArrived2D)
        {
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void ExecutePlayfulDodge(CorePoint catCenter, CorePoint? cursorPos)
    {
        double awayDir = (cursorPos.HasValue && cursorPos.Value.X >= catCenter.X) ? -1.0 : 1.0;
        double stepDistance = 45.0 + _random.NextDouble() * 20.0;
        double targetX = _currentPosition.X + (awayDir * stepDistance);

        _dodgeTarget = ClampToScreen(new CorePoint(targetX, _currentPosition.Y));
        _dodgeTimer = 0.0;

        SetFacing(awayDir > 0 ? CookieDirection.Right : CookieDirection.Left);
        TransitionToState(CookieState.Reacting);
        _audioManager.Play(SoundEffect.Surprise);
        _animationController.PlayAnimation(CookieAnimationId.Surprised);
    }

    private void UpdateReacting(double deltaTimeSeconds)
    {
        if (_dodgeTarget.HasValue)
        {
            _dodgeTimer += deltaTimeSeconds;
            double step = BaseWalkSpeed * 1.5 * deltaTimeSeconds;
            double dx = _dodgeTarget.Value.X - _currentPosition.X;

            if (Math.Abs(dx) <= step || _dodgeTimer > 0.8)
            {
                _currentPosition = _dodgeTarget.Value;
                OnPositionChanged?.Invoke(_currentPosition);
                _dodgeTarget = null;
                TransitionToState(CookieState.Idle);
                _animationController.PlayAnimation(CookieAnimationId.Curious);
            }
            else
            {
                _currentPosition = new CorePoint(_currentPosition.X + Math.Sign(dx) * step, _currentPosition.Y);
                OnPositionChanged?.Invoke(_currentPosition);
            }
        }
    }

    private void DecideNextAutonomousBehavior()
    {
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
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
    }

    private void StartAutonomousWalk()
    {
        var primaryArea = _screenService.GetPrimaryWorkArea();

        double distance = _random.Next(40, 140) * (_random.Next(0, 2) == 0 ? -1 : 1);
        double targetX = _currentPosition.X + distance;

        targetX = Math.Max(primaryArea.Left + 20, Math.Min(targetX, primaryArea.Right - _companionSize.Width - 20));

        if (Math.Abs(targetX - _currentPosition.X) > 15)
        {
            _walkTarget = new CorePoint(targetX, _currentPosition.Y);
            var dir = targetX > _currentPosition.X ? CookieDirection.Right : CookieDirection.Left;

            TransitionToState(CookieState.Walking);
            SetFacing(dir);
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
        double step = BaseWalkSpeed * deltaTimeSeconds;

        if (Math.Abs(dx) <= step)
        {
            _currentPosition = new CorePoint(_walkTarget.Value.X, _currentPosition.Y);
            OnPositionChanged?.Invoke(_currentPosition);
            StopWalking();
        }
        else
        {
            double moveDirection = Math.Sign(dx);
            _currentPosition = new CorePoint(_currentPosition.X + moveDirection * step, _currentPosition.Y);
            OnPositionChanged?.Invoke(_currentPosition);
        }
    }

    private void StopWalking()
    {
        _walkTarget = null;
        TransitionToState(CookieState.Idle);
        _animationController.PlayAnimation(CookieAnimationId.Idle);
    }

    public void BeginDrag()
    {
        CancelActiveEmote();
        _walkTarget = null;
        _dodgeTarget = null;
        MovementInterpolator.Stop2D();

        // Dragging immediately cancels active window exploration, jumping, or taskbar visits
        WindowController.CancelExploration();
        TaskbarController.CancelExploration();

        TransitionToState(CookieState.BeingDragged);
        _animationController.PlayAnimation(CookieAnimationId.PickedUp);
    }

    public void UpdateDrag(CorePoint newPosition)
    {
        _currentPosition = newPosition;
        OnPositionChanged?.Invoke(_currentPosition);
    }

    public void EndDrag()
    {
        _currentPosition = _screenService.RecoverPosition(_currentPosition, _companionSize);
        OnPositionChanged?.Invoke(_currentPosition);

        TransitionToState(CookieState.Reacting);
        _audioManager.Play(SoundEffect.Drop);
        _animationController.PlayAnimation(CookieAnimationId.Dropped);
    }

    public void Pet()
    {
        if (_state == CookieState.BeingDragged) return;

        CancelActiveEmote();
        _walkTarget = null;
        _dodgeTarget = null;
        MovementInterpolator.Stop2D();

        WindowController.CancelExploration();
        TaskbarController.CancelExploration();

        TransitionToState(CookieState.Reacting);
        _audioManager.Play(SoundEffect.Purr);
        _animationController.PlayAnimation(CookieAnimationId.Pet);
    }

    public bool TriggerEmote(Emote emote)
    {
        if (!CanPerformEmote(emote)) return false;

        _walkTarget = null;
        _dodgeTarget = null;
        MovementInterpolator.Stop2D();

        WindowController.CancelExploration();
        TaskbarController.CancelExploration();

        var date = Now();
        _emoteCooldowns[emote.Id] = date.AddSeconds(emote.CooldownSeconds);

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

    public void CancelActiveEmote()
    {
        if (_currentEmote != null)
        {
            _currentEmote = null;
            OnEmoteChanged?.Invoke(null);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
        }
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
        if (_state is CookieState.Reacting && _dodgeTarget == null)
        {
            TransitionToState(CookieState.Idle);
            _animationController.PlayAnimation(CookieAnimationId.Idle);
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

    private CorePoint ClampToScreen(CorePoint point)
    {
        var primaryArea = _screenService.GetPrimaryWorkArea();
        double x = Math.Max(primaryArea.Left + 10, Math.Min(point.X, primaryArea.Right - _companionSize.Width - 10));
        double y = Math.Max(primaryArea.Top + 10, Math.Min(point.Y, primaryArea.Bottom - _companionSize.Height - 10));
        return new CorePoint(x, y);
    }
}
