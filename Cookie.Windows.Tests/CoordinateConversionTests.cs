using System.Windows;
using Cookie.Windows.Desktop;
using Xunit;

namespace Cookie.Windows.Tests;

public class CoordinateConversionTests
{
    [Theory]
    [InlineData(100, 100, 1.0, 100, 100)]
    [InlineData(150, 150, 1.5, 100, 100)]
    [InlineData(200, 200, 2.0, 100, 100)]
    [InlineData(125, 250, 1.25, 100, 200)]
    public void PhysicalToDip_ConvertsCorrectly(double px, double py, double dpiScale, double expectedDipX, double expectedDipY)
    {
        var physical = new Point(px, py);
        var dip = DesktopCoordinateSpace.PhysicalToDip(physical, dpiScale);

        Assert.Equal(expectedDipX, dip.X, 3);
        Assert.Equal(expectedDipY, dip.Y, 3);
    }

    [Theory]
    [InlineData(100, 100, 1.0, 100, 100)]
    [InlineData(100, 100, 1.5, 150, 150)]
    [InlineData(100, 100, 2.0, 200, 200)]
    public void DipToPhysical_ConvertsCorrectly(double dipX, double dipY, double dpiScale, double expectedPx, double expectedPy)
    {
        var dip = new Point(dipX, dipY);
        var physical = DesktopCoordinateSpace.DipToPhysical(dip, dpiScale);

        Assert.Equal(expectedPx, physical.X, 3);
        Assert.Equal(expectedPy, physical.Y, 3);
    }

    [Fact]
    public void ClampToWorkArea_ClampsOutOfBoundsCoordinates()
    {
        var workArea = new Rect(0, 0, 1920, 1040); // 1080 minus 40px taskbar
        var size = new Size(180, 180);

        // Test bottom-right overflow
        var outOfBounds = new Point(1900, 1000);
        var clamped = DesktopCoordinateSpace.ClampToWorkArea(outOfBounds, size, workArea);

        Assert.Equal(1740, clamped.X); // 1920 - 180
        Assert.Equal(860, clamped.Y);  // 1040 - 180

        // Test top-left overflow
        var negativePos = new Point(-50, -30);
        var clampedNegative = DesktopCoordinateSpace.ClampToWorkArea(negativePos, size, workArea);

        Assert.Equal(0, clampedNegative.X);
        Assert.Equal(0, clampedNegative.Y);
    }

    [Fact]
    public void ClampToWorkArea_HandlesSecondaryMonitorWithNegativeOrigins()
    {
        // Monitor positioned to the left of the primary display
        var leftMonitorWorkArea = new Rect(-1920, 0, 1920, 1080);
        var size = new Size(180, 180);

        var target = new Point(-1000, 500);
        var clamped = DesktopCoordinateSpace.ClampToWorkArea(target, size, leftMonitorWorkArea);

        Assert.Equal(-1000, clamped.X);
        Assert.Equal(500, clamped.Y);

        // Test boundary clamp on negative monitor
        var farLeft = new Point(-2500, 500);
        var clampedFarLeft = DesktopCoordinateSpace.ClampToWorkArea(farLeft, size, leftMonitorWorkArea);

        Assert.Equal(-1920, clampedFarLeft.X);
    }

    [Fact]
    public void CalculateDefaultSpawn_PlacesCatAboveTaskbar()
    {
        var primaryWorkArea = new Rect(0, 0, 1920, 1040);
        var size = new Size(180, 180);

        var spawn = DesktopCoordinateSpace.CalculateDefaultSpawn(primaryWorkArea, size);

        Assert.True(spawn.X > 0 && spawn.X < 1920);
        Assert.True(spawn.Y > 0 && spawn.Y < 1040);
        Assert.Equal(1920 - 180 - 120, spawn.X);
        Assert.Equal(1040 - 180 - 10, spawn.Y);
    }
}
