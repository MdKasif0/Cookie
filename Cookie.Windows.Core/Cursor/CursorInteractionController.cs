using System;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Cursor;

/// <summary>
/// Dedicated controller governing Cookie's awareness of and playful interactions with the Windows mouse cursor.
/// Converts global virtual desktop screen coordinates into Cookie's coordinate space, handles multi-monitor
/// display layouts (negative/offset coordinates), tracks radial proximity zones with hysteresis, calculates
/// cursor velocity dynamics, and coordinates organic cat responses (subtle head tilting, slow-following with
/// anticipation, and playful dodging).
/// Ported directly from macOS CursorInteractionController.swift.
/// </summary>
public class CursorInteractionController
{
    // MARK: - Public State

    public CursorProximityZone CurrentZone { get; private set; } = CursorProximityZone.Departure;
    public double? LookAngle { get; private set; }
    public CorePoint? FollowTarget { get; private set; }
    public CursorMotionState CursorMotionState { get; private set; } = CursorMotionState.Stationary;
    public CursorPlayfulReaction? ActiveReaction { get; private set; }
    public bool IsCursorNear => CurrentZone != CursorProximityZone.Departure;

    public CorePoint LastGlobalCursorPoint { get; private set; }
    public double CursorVelocity { get; private set; }
    public double SmoothedCursorVelocity { get; private set; }
    public bool IsApproachingCookie { get; private set; }

    // MARK: - Constants & Configuration

    public const double BaseAwarenessRadius = 250.0;
    public const double BaseInteractionRadius = 120.0;
    public const double BaseCloseContactRadius = 55.0;
    public const double BaseDepartureRadius = 350.0;
    public const double HysteresisMargin = 12.0;

    public double AwarenessRadius(double scale = 1.0) => BaseAwarenessRadius * scale;
    public double InteractionRadius(double scale = 1.0) => BaseInteractionRadius * scale;
    public double CloseContactRadius(double scale = 1.0) => BaseCloseContactRadius * scale;
    public double DepartureRadius(double scale = 1.0) => BaseDepartureRadius * scale;

    // MARK: - Internal State

    private CorePoint _previousCursorPoint;
    private bool _hasInitializedPosition = false;
    private DateTime _zoneTransitionCooldownUntil = DateTime.MinValue;
    private double _interactionDwellTime = 0.0;
    private double _anticipationRemaining = 0.0;
    private bool _isAnticipatingFollow = false;
    private DateTime _dodgeCooldownUntil = DateTime.MinValue;
    private DateTime _reactionCooldownUntil = DateTime.MinValue;
    private readonly Random _random = new();

    // Clock seam for deterministic testing
    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public CursorInteractionController()
    {
        LastGlobalCursorPoint = new CorePoint(0, 0);
        _previousCursorPoint = LastGlobalCursorPoint;
    }

    public static double CalculateLookAngle(CorePoint cookiePos, CorePoint cursorPos, bool facingRight)
    {
        double dx = cursorPos.X - cookiePos.X;
        double dy = cursorPos.Y - cookiePos.Y;
        double angle = Math.Atan2(dy, Math.Abs(dx));
        return Math.Clamp(angle, -0.20, 0.20);
    }

    public static CursorMotionState ClassifyMotion(double speed)
    {
        if (speed < 30.0) return CursorMotionState.Stationary;
        if (speed > 580.0) return CursorMotionState.Rapid;
        return CursorMotionState.Slow;
    }

    /// <summary>
    /// Primary update cycle called each tick.
    /// </summary>
    public void Update(
        double dt,
        CorePoint cookieCenterScreen,
        CorePoint? cursorPoint,
        double cookieSize,
        CookieSettings settings,
        bool isInterrupted)
    {
        if (dt <= 0.0) return;

        if (!settings.CursorInteraction || isInterrupted)
        {
            ResetInteractionState();
            return;
        }

        var rawCursor = cursorPoint ?? LastGlobalCursorPoint;
        if (!_hasInitializedPosition)
        {
            _hasInitializedPosition = true;
            _previousCursorPoint = rawCursor;
            LastGlobalCursorPoint = rawCursor;
        }
        LastGlobalCursorPoint = rawCursor;

        // 1. Calculate Cursor Velocity & Dynamics
        double cursorDeltaX = rawCursor.X - _previousCursorPoint.X;
        double cursorDeltaY = rawCursor.Y - _previousCursorPoint.Y;
        double instantVelocity = Math.Sqrt(cursorDeltaX * cursorDeltaX + cursorDeltaY * cursorDeltaY) / dt;
        CursorVelocity = instantVelocity;

        // Exponential smoothing on velocity (prevents single-frame jitters)
        SmoothedCursorVelocity += (instantVelocity - SmoothedCursorVelocity) * Math.Min(1.0, dt * 12.0);
        CursorMotionState = ClassifyMotion(SmoothedCursorVelocity);

        // 2. Compute 2D Vector & Proximity Zone with Hysteresis
        double dx = rawCursor.X - cookieCenterScreen.X;
        double dy = rawCursor.Y - cookieCenterScreen.Y;
        double distance = Math.Sqrt(dx * dx + dy * dy);

        double prevDx = _previousCursorPoint.X - cookieCenterScreen.X;
        double prevDy = _previousCursorPoint.Y - cookieCenterScreen.Y;
        double prevDistance = Math.Sqrt(prevDx * prevDx + prevDy * prevDy);
        IsApproachingCookie = (distance < prevDistance - 2.0);

        _previousCursorPoint = rawCursor;

        double scale = Math.Max(0.7, cookieSize);
        UpdateProximityZone(distance, scale);

        // 3. Look Toward Cursor (Anatomically plausible head tilt & orientation)
        UpdateLookAngle(dx, dy, dt);

        // 4. Playful Dodge Behavior (gentle step back from rushing pointer)
        if (settings.CursorDodgingEnabled && CheckPlayfulDodge(dx, distance))
        {
            return;
        }

        // 5. Approaching & Playful Following Behavior
        UpdateFollowing(dt, dx, distance, cookieCenterScreen, settings);
    }

    private void UpdateProximityZone(double distance, double scale)
    {
        var date = Now();
        if (date < _zoneTransitionCooldownUntil) return;

        double margin = HysteresisMargin;
        double closeLimit = BaseCloseContactRadius * scale;
        double interactLimit = BaseInteractionRadius * scale;
        double awareLimit = BaseAwarenessRadius * scale;
        double departLimit = BaseDepartureRadius * scale;

        var newZone = CurrentZone switch
        {
            CursorProximityZone.Departure => distance <= awareLimit - margin
                ? (distance <= interactLimit ? (distance <= closeLimit ? CursorProximityZone.CloseContact : CursorProximityZone.Interaction) : CursorProximityZone.Awareness)
                : CursorProximityZone.Departure,

            CursorProximityZone.Awareness => distance <= interactLimit - margin
                ? (distance <= closeLimit ? CursorProximityZone.CloseContact : CursorProximityZone.Interaction)
                : (distance >= departLimit ? CursorProximityZone.Departure : CursorProximityZone.Awareness),

            CursorProximityZone.Interaction => distance <= closeLimit - margin
                ? CursorProximityZone.CloseContact
                : (distance >= awareLimit + margin ? CursorProximityZone.Awareness : CursorProximityZone.Interaction),

            CursorProximityZone.CloseContact => distance >= closeLimit + margin
                ? (distance >= interactLimit + margin ? CursorProximityZone.Awareness : CursorProximityZone.Interaction)
                : CursorProximityZone.CloseContact,

            _ => CursorProximityZone.Departure
        };

        if (newZone != CurrentZone)
        {
            CurrentZone = newZone;
            _zoneTransitionCooldownUntil = date.AddSeconds(0.25);
        }
    }

    private void UpdateLookAngle(double dx, double dy, double dt)
    {
        switch (CurrentZone)
        {
            case CursorProximityZone.Awareness:
            case CursorProximityZone.Interaction:
            case CursorProximityZone.CloseContact:
                double angle = Math.Atan2(dy, Math.Abs(dx));
                double clampedAngle = Math.Clamp(angle, -0.20, 0.20);
                double current = LookAngle ?? 0.0;
                LookAngle = current + (clampedAngle - current) * Math.Min(1.0, dt * 10.0);
                break;

            case CursorProximityZone.Departure:
                if (LookAngle.HasValue)
                {
                    double next = LookAngle.Value + (0.0 - LookAngle.Value) * Math.Min(1.0, dt * 8.0);
                    LookAngle = Math.Abs(next) < 0.01 ? null : next;
                }
                break;
        }
    }

    private bool CheckPlayfulDodge(double dx, double distance)
    {
        var date = Now();
        if (date < _dodgeCooldownUntil) return false;

        // Trigger condition: cursor is moving rapidly straight toward Cookie into close-contact / interaction zone
        if ((CurrentZone == CursorProximityZone.Interaction || CurrentZone == CursorProximityZone.CloseContact) &&
            CursorMotionState == CursorMotionState.Rapid &&
            IsApproachingCookie &&
            SmoothedCursorVelocity > 620.0)
        {
            double cooldownSec = 25.0 + _random.NextDouble() * 20.0;
            _dodgeCooldownUntil = date.AddSeconds(cooldownSec);
            ActiveReaction = CursorPlayfulReaction.Dodge;
            return true;
        }

        return false;
    }

    private void UpdateFollowing(
        double dt,
        double dx,
        double distance,
        CorePoint cookieCenterScreen,
        CookieSettings settings)
    {
        var intensity = settings.FollowingIntensity;

        switch (CurrentZone)
        {
            case CursorProximityZone.Interaction:
                _interactionDwellTime += dt;

                if (CursorMotionState == CursorMotionState.Rapid)
                {
                    _isAnticipatingFollow = false;
                    FollowTarget = null;
                    ActiveReaction = CursorPlayfulReaction.Glance;
                    return;
                }

                if (!_isAnticipatingFollow && _interactionDwellTime >= intensity.GetAnticipationDelay())
                {
                    _isAnticipatingFollow = true;
                    _anticipationRemaining = 0.25;
                    ActiveReaction = CursorPlayfulReaction.HeadTilt;
                }

                if (_isAnticipatingFollow)
                {
                    if (_anticipationRemaining > 0.0)
                    {
                        _anticipationRemaining -= dt;
                        FollowTarget = null;
                    }
                    else if (settings.CursorFollowingEnabled)
                    {
                        double fromCursorX = cookieCenterScreen.X - LastGlobalCursorPoint.X;
                        double fromCursorY = cookieCenterScreen.Y - LastGlobalCursorPoint.Y;
                        double d = Math.Sqrt(fromCursorX * fromCursorX + fromCursorY * fromCursorY);

                        double trailingDistance = intensity.GetTrailingDistance();
                        CorePoint target;
                        if (d > 0.001)
                        {
                            double unitX = fromCursorX / d;
                            double unitY = fromCursorY / d;
                            target = new CorePoint(
                                LastGlobalCursorPoint.X + unitX * trailingDistance,
                                LastGlobalCursorPoint.Y + unitY * trailingDistance);
                        }
                        else
                        {
                            target = new CorePoint(
                                LastGlobalCursorPoint.X - trailingDistance,
                                LastGlobalCursorPoint.Y);
                        }
                        FollowTarget = target;
                    }
                }
                break;

            case CursorProximityZone.CloseContact:
                FollowTarget = null;
                _isAnticipatingFollow = false;
                _interactionDwellTime = 0.0;

                var date = Now();
                if (date >= _reactionCooldownUntil &&
                    (CursorMotionState == CursorMotionState.Slow || CursorMotionState == CursorMotionState.Stationary))
                {
                    double cooldownSec = 8.0 + _random.NextDouble() * 8.0;
                    _reactionCooldownUntil = date.AddSeconds(cooldownSec);

                    double roll = _random.NextDouble();
                    if (roll < 0.45)
                    {
                        ActiveReaction = CursorPlayfulReaction.PawReach;
                    }
                    else if (roll < 0.80)
                    {
                        ActiveReaction = CursorPlayfulReaction.HappyChirp;
                    }
                    else
                    {
                        ActiveReaction = CursorPlayfulReaction.HeadTilt;
                    }
                }
                break;

            case CursorProximityZone.Awareness:
                _interactionDwellTime = 0.0;
                _isAnticipatingFollow = false;
                FollowTarget = null;
                break;

            case CursorProximityZone.Departure:
                ResetInteractionState();
                break;
        }
    }

    public void ResetInteractionState()
    {
        _interactionDwellTime = 0.0;
        _anticipationRemaining = 0.0;
        _isAnticipatingFollow = false;
        FollowTarget = null;
        LookAngle = null;
        ActiveReaction = null;
    }

    public void ClearActiveReaction()
    {
        ActiveReaction = null;
    }
}
