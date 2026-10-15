using System;
using System.Windows;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Centralized coordinate conversion layer reconciling differences between:
/// 1. Windows physical-pixel virtual screen space (origin at top-left of primary monitor, Y increases downwards).
/// 2. WPF Device-Independent Points (DIP: 96 DPI units).
/// 3. Multi-monitor virtual bounds with negative origins.
/// 4. Taskbar margins and safe desktop working areas.
/// </summary>
public static class DesktopCoordinateSpace
{
    public static Point PhysicalToDip(Point physicalPoint, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new Point(physicalPoint.X / scale, physicalPoint.Y / scale);
    }

    public static Point DipToPhysical(Point dipPoint, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new Point(dipPoint.X * scale, dipPoint.Y * scale);
    }

    public static Rect PhysicalToDip(Rect physicalRect, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new Rect(
            physicalRect.X / scale,
            physicalRect.Y / scale,
            physicalRect.Width / scale,
            physicalRect.Height / scale);
    }

    public static Rect DipToPhysical(Rect dipRect, double dpiScale)
    {
        double scale = dpiScale > 0 ? dpiScale : 1.0;
        return new Rect(
            dipRect.X * scale,
            dipRect.Y * scale,
            dipRect.Width * scale,
            dipRect.Height * scale);
    }

    /// <summary>
    /// Clamps window position so Cookie remains completely visible within the provided work area.
    /// </summary>
    public static Point ClampToWorkArea(Point desiredPosition, Size companionSize, Rect workArea)
    {
        double clampedX = Math.Max(workArea.Left, Math.Min(desiredPosition.X, workArea.Right - companionSize.Width));
        double clampedY = Math.Max(workArea.Top, Math.Min(desiredPosition.Y, workArea.Bottom - companionSize.Height));
        return new Point(clampedX, clampedY);
    }

    /// <summary>
    /// Calculates default spawn location for Cookie sitting above the taskbar on the primary display.
    /// </summary>
    public static Point CalculateDefaultSpawn(Rect primaryWorkArea, Size companionSize)
    {
        // Place Cookie near the bottom-right, roughly 120 points from right edge, sitting on bottom boundary
        double x = primaryWorkArea.Right - companionSize.Width - 120;
        double y = primaryWorkArea.Bottom - companionSize.Height - 10;

        // Ensure within bounds
        return ClampToWorkArea(new Point(x, y), companionSize, primaryWorkArea);
    }
}
