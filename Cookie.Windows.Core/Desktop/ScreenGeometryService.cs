using System.Collections.Generic;

namespace Cookie.Windows.Core.Desktop;

public record DisplayMonitorInfo(
    string DeviceName,
    CoreRect MonitorBounds,
    CoreRect WorkArea,
    bool IsPrimary);

public interface IScreenGeometryProvider
{
    CoreRect GetPrimaryWorkArea();
    CoreRect GetVirtualScreenBounds();
    CorePoint? GetCursorPositionDip();
    List<DisplayMonitorInfo> GetActiveMonitors();
}

public class DefaultScreenGeometryProvider : IScreenGeometryProvider
{
    private readonly CoreRect _defaultWorkArea = new(0, 0, 1920, 1040);

    public CoreRect GetPrimaryWorkArea() => _defaultWorkArea;
    public CoreRect GetVirtualScreenBounds() => new(0, 0, 1920, 1080);
    public CorePoint? GetCursorPositionDip() => null;
    public List<DisplayMonitorInfo> GetActiveMonitors() =>
        new() { new DisplayMonitorInfo("PRIMARY", new CoreRect(0, 0, 1920, 1080), _defaultWorkArea, true) };
}

public class ScreenGeometryService
{
    private readonly IScreenGeometryProvider _provider;

    public ScreenGeometryService(IScreenGeometryProvider? provider = null)
    {
        _provider = provider ?? new DefaultScreenGeometryProvider();
    }

    public virtual CoreRect GetPrimaryWorkArea() => _provider.GetPrimaryWorkArea();
    public virtual CoreRect GetVirtualScreenBounds() => _provider.GetVirtualScreenBounds();
    public virtual CorePoint? GetCursorPositionDip() => _provider.GetCursorPositionDip();
    public virtual List<DisplayMonitorInfo> GetActiveMonitors() => _provider.GetActiveMonitors();

    public virtual CorePoint RecoverPosition(CorePoint currentPosition, CoreSize companionSize)
    {
        var monitors = GetActiveMonitors();

        foreach (var monitor in monitors)
        {
            var visibleArea = monitor.WorkArea;
            bool insideX = currentPosition.X + companionSize.Width > visibleArea.Left && currentPosition.X < visibleArea.Right;
            bool insideY = currentPosition.Y + companionSize.Height > visibleArea.Top && currentPosition.Y < visibleArea.Bottom;

            if (insideX && insideY)
            {
                return DesktopCoordinateSpace.ClampToWorkArea(currentPosition, companionSize, visibleArea);
            }
        }

        var primaryArea = GetPrimaryWorkArea();
        return DesktopCoordinateSpace.CalculateDefaultSpawn(primaryArea, companionSize);
    }
}
