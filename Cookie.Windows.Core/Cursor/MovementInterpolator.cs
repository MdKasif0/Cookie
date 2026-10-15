using System;
using Cookie.Windows.Core.Desktop;

namespace Cookie.Windows.Core.Cursor;

/// <summary>
/// Reusable delta-time driven movement interpolator providing smooth acceleration,
/// physical deceleration braking curves, distance-aware velocity profiles, and arrival thresholds.
/// Ported directly from macOS MovementInterpolator.swift for exact motion parity.
/// </summary>
public class MovementInterpolator
{
    /// <summary>
    /// Maximum allowed translation speed in points per second.
    /// </summary>
    public double MaxSpeed { get; set; }

    /// <summary>
    /// Acceleration rate in points per second squared.
    /// </summary>
    public double Acceleration { get; set; }

    /// <summary>
    /// Deceleration braking rate in points per second squared.
    /// </summary>
    public double Deceleration { get; set; }

    /// <summary>
    /// Arrival threshold in points — closer than this snaps to target and zeroes velocity.
    /// </summary>
    public double ArrivalThreshold { get; set; }

    // MARK: - 1D State

    public double CurrentPosition { get; private set; }
    public double CurrentVelocity { get; private set; }
    public double TargetPosition { get; private set; }
    public bool IsArrived { get; private set; } = true;
    public bool IsMoving => !IsArrived;

    // MARK: - 2D State

    public CorePoint CurrentPosition2D { get; private set; }
    public CorePoint CurrentVelocity2D { get; private set; }
    public CorePoint TargetPosition2D { get; private set; }
    public bool IsArrived2D { get; private set; } = true;
    public bool IsMoving2D => !IsArrived2D;

    public MovementInterpolator(
        double initialPosition = 0.0,
        double maxSpeed = 180.0,
        double acceleration = 360.0,
        double deceleration = 480.0,
        double arrivalThreshold = 4.0)
    {
        CurrentPosition = initialPosition;
        TargetPosition = initialPosition;
        CurrentPosition2D = new CorePoint(initialPosition, 0);
        TargetPosition2D = new CorePoint(initialPosition, 0);
        CurrentVelocity2D = new CorePoint(0, 0);
        MaxSpeed = maxSpeed;
        Acceleration = acceleration;
        Deceleration = deceleration;
        ArrivalThreshold = arrivalThreshold;
    }

    public void SetTarget(double target)
    {
        TargetPosition = target;
        TargetPosition2D = new CorePoint(target, TargetPosition2D.Y);
        if (Math.Abs(TargetPosition - CurrentPosition) > ArrivalThreshold)
        {
            IsArrived = false;
            IsArrived2D = false;
        }
    }

    public void Reset(double position)
    {
        CurrentPosition = position;
        TargetPosition = position;
        CurrentVelocity = 0.0;
        IsArrived = true;

        CurrentPosition2D = new CorePoint(position, CurrentPosition2D.Y);
        TargetPosition2D = new CorePoint(position, TargetPosition2D.Y);
        CurrentVelocity2D = new CorePoint(0, 0);
        IsArrived2D = true;
    }

    public void Snap(double position) => Reset(position);

    public void Stop()
    {
        TargetPosition = CurrentPosition;
        CurrentVelocity = 0.0;
        IsArrived = true;

        TargetPosition2D = CurrentPosition2D;
        CurrentVelocity2D = new CorePoint(0, 0);
        IsArrived2D = true;
    }

    public void SetTarget2D(CorePoint target)
    {
        TargetPosition2D = target;
        TargetPosition = target.X;
        double dist = Math.Sqrt(Math.Pow(TargetPosition2D.X - CurrentPosition2D.X, 2) + Math.Pow(TargetPosition2D.Y - CurrentPosition2D.Y, 2));
        if (dist > ArrivalThreshold)
        {
            IsArrived2D = false;
            IsArrived = false;
        }
    }

    public void Reset2D(CorePoint position)
    {
        CurrentPosition2D = position;
        TargetPosition2D = position;
        CurrentVelocity2D = new CorePoint(0, 0);
        IsArrived2D = true;

        CurrentPosition = position.X;
        TargetPosition = position.X;
        CurrentVelocity = 0.0;
        IsArrived = true;
    }

    public void Snap2D(CorePoint position) => Reset2D(position);

    public void Stop2D()
    {
        TargetPosition2D = CurrentPosition2D;
        CurrentVelocity2D = new CorePoint(0, 0);
        IsArrived2D = true;

        TargetPosition = CurrentPosition;
        CurrentVelocity = 0.0;
        IsArrived = true;
    }

    public (double Position, double Velocity) Update(double dt)
    {
        if (dt <= 0.0) return (CurrentPosition, CurrentVelocity);

        double delta = TargetPosition - CurrentPosition;
        double distance = Math.Abs(delta);

        if (distance <= ArrivalThreshold && Math.Abs(CurrentVelocity) <= (Acceleration * dt * 1.5))
        {
            CurrentPosition = TargetPosition;
            CurrentVelocity = 0.0;
            IsArrived = true;
            return (CurrentPosition, 0.0);
        }

        double direction = delta > 0.0 ? 1.0 : -1.0;
        double speed = Math.Abs(CurrentVelocity);
        double stoppingDistance = (speed * speed) / (2.0 * Math.Max(10.0, Deceleration));

        if (distance <= stoppingDistance)
        {
            double decelStep = Deceleration * dt;
            if (speed <= decelStep)
            {
                CurrentVelocity = 0.0;
            }
            else
            {
                CurrentVelocity -= (CurrentVelocity > 0 ? 1.0 : -1.0) * decelStep;
            }
        }
        else
        {
            double targetVelocity = direction * MaxSpeed;
            double accelStep = Acceleration * dt;
            if (CurrentVelocity < targetVelocity)
            {
                CurrentVelocity = Math.Min(targetVelocity, CurrentVelocity + accelStep);
            }
            else if (CurrentVelocity > targetVelocity)
            {
                CurrentVelocity = Math.Max(targetVelocity, CurrentVelocity - accelStep);
            }
        }

        CurrentPosition += CurrentVelocity * dt;
        CurrentPosition2D = new CorePoint(CurrentPosition, CurrentPosition2D.Y);
        return (CurrentPosition, CurrentVelocity);
    }

    public (CorePoint Position, CorePoint Velocity) Update2D(double dt)
    {
        if (dt <= 0.0) return (CurrentPosition2D, CurrentVelocity2D);

        double dx = TargetPosition2D.X - CurrentPosition2D.X;
        double dy = TargetPosition2D.Y - CurrentPosition2D.Y;
        double distance = Math.Sqrt(dx * dx + dy * dy);

        double currentSpeed = Math.Sqrt(CurrentVelocity2D.X * CurrentVelocity2D.X + CurrentVelocity2D.Y * CurrentVelocity2D.Y);

        if (distance <= ArrivalThreshold && currentSpeed <= (Acceleration * dt * 1.5))
        {
            CurrentPosition2D = TargetPosition2D;
            CurrentVelocity2D = new CorePoint(0, 0);
            IsArrived2D = true;
            CurrentPosition = CurrentPosition2D.X;
            CurrentVelocity = 0.0;
            IsArrived = true;
            return (CurrentPosition2D, CurrentVelocity2D);
        }

        if (distance <= 0.001)
        {
            CurrentPosition2D = TargetPosition2D;
            CurrentVelocity2D = new CorePoint(0, 0);
            IsArrived2D = true;
            CurrentPosition = CurrentPosition2D.X;
            CurrentVelocity = 0.0;
            IsArrived = true;
            return (CurrentPosition2D, CurrentVelocity2D);
        }

        double dirX = dx / distance;
        double dirY = dy / distance;

        double stoppingDistance = (currentSpeed * currentSpeed) / (2.0 * Math.Max(10.0, Deceleration));
        double newSpeed = currentSpeed;

        if (distance <= stoppingDistance)
        {
            double decelStep = Deceleration * dt;
            newSpeed = Math.Max(0.0, currentSpeed - decelStep);
        }
        else
        {
            double accelStep = Acceleration * dt;
            newSpeed = Math.Min(MaxSpeed, currentSpeed + accelStep);
        }

        CurrentVelocity2D = new CorePoint(dirX * newSpeed, dirY * newSpeed);
        CurrentPosition2D = new CorePoint(
            CurrentPosition2D.X + CurrentVelocity2D.X * dt,
            CurrentPosition2D.Y + CurrentVelocity2D.Y * dt);

        CurrentPosition = CurrentPosition2D.X;
        CurrentVelocity = CurrentVelocity2D.X;
        TargetPosition = TargetPosition2D.X;
        IsArrived = IsArrived2D;

        return (CurrentPosition2D, CurrentVelocity2D);
    }
}
