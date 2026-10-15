using System;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// 2D point representation in Device-Independent Pixels (DIPs).
/// </summary>
public readonly record struct CorePoint(double X, double Y)
{
    public static CorePoint Zero => new(0, 0);

    public double DistanceTo(CorePoint other)
    {
        double dx = X - other.X;
        double dy = Y - other.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public override string ToString() => $"({X:F1}, {Y:F1})";
}

/// <summary>
/// 2D size representation in Device-Independent Pixels (DIPs).
/// </summary>
public readonly record struct CoreSize(double Width, double Height)
{
    public static CoreSize Zero => new(0, 0);

    public override string ToString() => $"{Width:F1}x{Height:F1}";
}

/// <summary>
/// 2D rectangle representation in Device-Independent Pixels (DIPs).
/// Origin (X, Y) is at top-left; X increases rightward, Y increases downward.
/// </summary>
public readonly record struct CoreRect(double X, double Y, double Width, double Height)
{
    public static CoreRect Empty => new(0, 0, 0, 0);

    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double MidX => X + Width / 2.0;
    public double MidY => Y + Height / 2.0;

    public bool IsEmpty => Width <= 0 || Height <= 0;

    public bool Contains(CorePoint point)
    {
        return point.X >= Left && point.X <= Right &&
               point.Y >= Top && point.Y <= Bottom;
    }

    public bool Contains(double x, double y)
    {
        return x >= Left && x <= Right &&
               y >= Top && y <= Bottom;
    }

    public bool IntersectsWith(CoreRect rect)
    {
        return rect.Left < Right && Left < rect.Right &&
               rect.Top < Bottom && Top < rect.Bottom;
    }

    public CoreRect Inflate(double horizontal, double vertical)
    {
        return new CoreRect(
            X - horizontal,
            Y - vertical,
            Math.Max(0, Width + horizontal * 2),
            Math.Max(0, Height + vertical * 2));
    }

    public override string ToString() => $"[{X:F1}, {Y:F1}, {Width:F1}x{Height:F1}]";
}

/// <summary>
/// Authoritative coordinate conversion and geometry helper layer for Cookie for Windows.
/// 
/// COORDINATE CONVERSION ARCHITECTURE:
/// 1. Native Windows Screen Coordinates:
///    - Expressed in physical device pixels.
///    - Origin (0,0) is at the top-left of the Primary Display monitor.
///    - In multi-monitor topologies, monitors arranged above or to the left of the primary display
///      have negative virtual-screen physical coordinates (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN).
///    - Different monitors may have distinct DPI scaling factors (e.g. 100% = 1.0, 150% = 1.5, 200% = 2.0).
/// 
/// 2. WPF Device-Independent Units (DIPs, 96 DPI):
///    - Cookie's Window coordinates (Left, Top, Width, Height) and Canvas elements operate strictly in DIPs.
///    - 1 DIP = 1/96 inch.
///    - When converting from Physical to DIP: DIP = Physical / dpiScale.
///    - When converting from DIP to Physical: Physical = DIP * dpiScale.
/// 
/// 3. Unified Internal Coordinate Space:
///    - All navigation graphs, candidate window edges, taskbar surfaces, jump trajectories, and cursor tracking
///      operate uniformly in WPF Device-Independent Pixels (DIPs).
///    - This guarantees that Cookie's collision dimensions, edge corridors, and jump physics stay identical
///      regardless of the monitor's physical pixel density or resolution.
/// </summary>
public static class DesktopCoordinateSpace
{
    public static CorePoint PhysicalToDip(CorePoint physicalPoint, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new CorePoint(physicalPoint.X / scale, physicalPoint.Y / scale);
    }

    public static CorePoint DipToPhysical(CorePoint dipPoint, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new CorePoint(dipPoint.X * scale, dipPoint.Y * scale);
    }

    public static CoreRect PhysicalToDip(CoreRect physicalRect, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new CoreRect(
            physicalRect.X / scale,
            physicalRect.Y / scale,
            physicalRect.Width / scale,
            physicalRect.Height / scale);
    }

    public static CoreRect DipToPhysical(CoreRect dipRect, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new CoreRect(
            dipRect.X * scale,
            dipRect.Y * scale,
            dipRect.Width * scale,
            dipRect.Height * scale);
    }

    public static CorePoint ClampToWorkArea(CorePoint desiredPosition, CoreSize companionSize, CoreRect workArea)
    {
        double maxX = Math.Max(workArea.Left, workArea.Right - companionSize.Width);
        double maxY = Math.Max(workArea.Top, workArea.Bottom - companionSize.Height);
        double clampedX = Math.Max(workArea.Left, Math.Min(desiredPosition.X, maxX));
        double clampedY = Math.Max(workArea.Top, Math.Min(desiredPosition.Y, maxY));
        return new CorePoint(clampedX, clampedY);
    }

    public static CorePoint CalculateDefaultSpawn(CoreRect primaryWorkArea, CoreSize companionSize)
    {
        double x = primaryWorkArea.Right - companionSize.Width - 120;
        double y = primaryWorkArea.Bottom - companionSize.Height - 10;
        return ClampToWorkArea(new CorePoint(x, y), companionSize, primaryWorkArea);
    }
}
