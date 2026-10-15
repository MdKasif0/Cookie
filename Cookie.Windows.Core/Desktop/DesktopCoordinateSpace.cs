using System;

namespace Cookie.Windows.Core.Desktop;

public readonly record struct CorePoint(double X, double Y);
public readonly record struct CoreSize(double Width, double Height);
public readonly record struct CoreRect(double X, double Y, double Width, double Height)
{
    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

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
        double clampedX = Math.Max(workArea.Left, Math.Min(desiredPosition.X, workArea.Right - companionSize.Width));
        double clampedY = Math.Max(workArea.Top, Math.Min(desiredPosition.Y, workArea.Bottom - companionSize.Height));
        return new CorePoint(clampedX, clampedY);
    }

    public static CorePoint CalculateDefaultSpawn(CoreRect primaryWorkArea, CoreSize companionSize)
    {
        double x = primaryWorkArea.Right - companionSize.Width - 120;
        double y = primaryWorkArea.Bottom - companionSize.Height - 10;
        return ClampToWorkArea(new CorePoint(x, y), companionSize, primaryWorkArea);
    }
}
