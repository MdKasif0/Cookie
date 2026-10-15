using System;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Windows;

/// <summary>
/// Type of surface Cookie can jump onto.
/// </summary>
public enum JumpSurfaceKind
{
    WindowTopEdge,
    WindowCorner,
    DesktopGround,
    TaskbarEdge
}

public static class JumpSurfaceKindExtensions
{
    public static bool IsWindowSurface(this JumpSurfaceKind kind) =>
        kind is JumpSurfaceKind.WindowTopEdge or JumpSurfaceKind.WindowCorner;
}

/// <summary>
/// Observable target surface representation for jump planning.
/// Coordinates are in WPF Device-Independent Pixels (DIPs).
/// </summary>
public record JumpTargetSurface(
    string Id,
    IntPtr? WindowHandle,
    string OwnerName,
    JumpSurfaceKind SurfaceKind,
    CoreRect Bounds,
    CorePoint LandingPoint,
    double LandingWidth,
    double FootOffset = 14.0,
    bool IsTraversable = true);

/// <summary>
/// Result of evaluating a candidate jump between two surfaces.
/// </summary>
public record JumpProposal(
    CorePoint StartPoint,
    JumpTargetSurface TargetSurface,
    double HorizontalDistance,
    double VerticalDifference,
    double JumpDuration,
    double ApexHeight,
    JumpStyle Style,
    bool IsSafe,
    string? RejectionReason = null)
{
    public double TotalEuclideanDistance => Math.Sqrt(
        HorizontalDistance * HorizontalDistance +
        VerticalDifference * VerticalDifference);
}

/// <summary>
/// Reusable, deterministic time-based parabolic jump trajectory model.
/// Correctly mapped to Windows / WPF screen coordinates where Y increases downwards:
/// jumping into the air corresponds to a negative vertical displacement hump (-apexHeight).
/// </summary>
public class JumpTrajectory
{
    public CorePoint StartPoint { get; }
    public CorePoint EndPoint { get; }
    public double Duration { get; }
    public double ApexHeight { get; }
    public JumpStyle Style { get; }

    public JumpTrajectory(
        CorePoint startPoint,
        CorePoint endPoint,
        double duration,
        double apexHeight,
        JumpStyle style = JumpStyle.Gentle)
    {
        StartPoint = startPoint;
        EndPoint = endPoint;
        Duration = Math.Max(0.2, duration);
        ApexHeight = Math.Max(10.0, apexHeight);
        Style = style;
    }

    /// <summary>
    /// Evaluates 2D position along the trajectory at normalized progress in [0.0, 1.0].
    /// In Windows coordinates (Y down), subtracting the parabolic hump moves Cookie upwards into the air.
    /// </summary>
    public CorePoint PointAt(double progress)
    {
        double p = Math.Clamp(progress, 0.0, 1.0);
        // Monotonic horizontal displacement
        double x = StartPoint.X + p * (EndPoint.X - StartPoint.X);

        // Linear vertical interpolation - parabolic height hump (upwards)
        double linearY = StartPoint.Y + p * (EndPoint.Y - StartPoint.Y);
        double parabolicHump = 4.0 * ApexHeight * p * (1.0 - p);
        double y = linearY - parabolicHump;

        return new CorePoint(x, y);
    }

    /// <summary>
    /// Evaluates instantaneous 2D velocity in DIPs per second at progress p in [0.0, 1.0].
    /// </summary>
    public (double Vx, double Vy) VelocityAt(double progress)
    {
        double p = Math.Clamp(progress, 0.0, 1.0);
        double t = Math.Max(0.001, Duration);

        double vx = (EndPoint.X - StartPoint.X) / t;
        double linearVy = (EndPoint.Y - StartPoint.Y) / t;
        // Derivative of -4 * Apex * (p - p^2) w.r.t p is -4 * Apex * (1 - 2p), divided by duration t
        double parabolicVy = -(4.0 * ApexHeight * (1.0 - 2.0 * p)) / t;

        return (vx, linearVy + parabolicVy);
    }

    /// <summary>
    /// Dynamic shadow scale factor based on flight altitude [0.75 ... 1.0].
    /// When Cookie is at the peak of the jump, the ground shadow shrinks slightly.
    /// </summary>
    public double ShadowScale(double progress)
    {
        double p = Math.Clamp(progress, 0.0, 1.0);
        double hump = 4.0 * p * (1.0 - p);
        return 1.0 - 0.25 * hump;
    }

    /// <summary>
    /// Dynamic shadow opacity based on flight altitude [0.055 ... 0.09].
    /// When Cookie is higher in the air, the ground shadow diffuses slightly.
    /// </summary>
    public double ShadowAlpha(double progress)
    {
        double p = Math.Clamp(progress, 0.0, 1.0);
        double hump = 4.0 * p * (1.0 - p);
        return 0.09 * (1.0 - 0.35 * hump);
    }
}
