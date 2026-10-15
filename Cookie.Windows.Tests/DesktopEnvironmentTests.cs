using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class DesktopEnvironmentTests
{
    [Fact]
    public void BottomTaskbar_CalculatesCorrectBoundsAndSafeWalkingSurface()
    {
        var mon = new DisplayMonitorInfo("MON1", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);
        var tbBounds = new CoreRect(0, 1040, 1920, 40);
        var safeSurface = new CoreRect(40, 980, 1840, 50);

        var taskbar = new TaskbarInfo(
            "MON1",
            tbBounds,
            TaskbarOrientation.Bottom,
            TaskbarVisibilityState.Visible,
            40.0,
            safeSurface);

        Assert.True(taskbar.IsHorizontal);
        Assert.False(taskbar.IsVertical);
        Assert.Equal(40.0, taskbar.Thickness);
        Assert.Equal(1040.0, taskbar.TaskbarBounds.Top);
        Assert.Equal(980.0, taskbar.SafeWalkingSurface.Top);
    }

    [Fact]
    public void AlternateTaskbarOrientations_TopLeftRight_AreCorrectlyIdentified()
    {
        // Top Taskbar
        var topTb = new TaskbarInfo(
            "TOP_MON",
            new CoreRect(0, 0, 1920, 40),
            TaskbarOrientation.Top,
            TaskbarVisibilityState.Visible,
            40.0,
            new CoreRect(40, 50, 1840, 50));

        Assert.True(topTb.IsHorizontal);
        Assert.Equal(TaskbarOrientation.Top, topTb.Orientation);

        // Left Taskbar
        var leftTb = new TaskbarInfo(
            "LEFT_MON",
            new CoreRect(0, 0, 60, 1080),
            TaskbarOrientation.Left,
            TaskbarVisibilityState.Visible,
            60.0,
            new CoreRect(70, 40, 50, 1000));

        Assert.True(leftTb.IsVertical);
        Assert.Equal(TaskbarOrientation.Left, leftTb.Orientation);

        // Right Taskbar
        var rightTb = new TaskbarInfo(
            "RIGHT_MON",
            new CoreRect(1860, 0, 60, 1080),
            TaskbarOrientation.Right,
            TaskbarVisibilityState.Visible,
            60.0,
            new CoreRect(1800, 40, 50, 1000));

        Assert.True(rightTb.IsVertical);
        Assert.Equal(TaskbarOrientation.Right, rightTb.Orientation);
    }

    [Fact]
    public void IsPointNearTaskbar_DetectsProximityWithinThreshold()
    {
        var primaryMon = new DisplayMonitorInfo("PRIMARY", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);
        var taskbar = new TaskbarInfo("PRIMARY", new CoreRect(0, 1040, 1920, 40), TaskbarOrientation.Bottom, TaskbarVisibilityState.Visible, 40.0, new CoreRect(40, 980, 1840, 50));

        var env = new DesktopEnvironment(
            primaryMon,
            new[] { primaryMon },
            new[] { taskbar },
            Array.Empty<ObservableWindow>());

        // Point near bottom taskbar (Y = 1000 is 40 DIPs above taskbar, within 80 threshold)
        Assert.True(env.IsPointNearTaskbar(new CorePoint(500, 1000), threshold: 80.0));

        // Point high up in center of desktop (Y = 400 is far from taskbar)
        Assert.False(env.IsPointNearTaskbar(new CorePoint(500, 400), threshold: 80.0));
    }

    [Fact]
    public void ClampToTaskbarWalkingSurface_ConstrainsToSafeCorridor()
    {
        var primaryMon = new DisplayMonitorInfo("PRIMARY", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);
        var safeSurface = new CoreRect(100, 960, 1600, 60);
        var taskbar = new TaskbarInfo("PRIMARY", new CoreRect(0, 1040, 1920, 40), TaskbarOrientation.Bottom, TaskbarVisibilityState.Visible, 40.0, safeSurface);

        var env = new DesktopEnvironment(
            primaryMon,
            new[] { primaryMon },
            new[] { taskbar },
            Array.Empty<ObservableWindow>());

        var charSize = new CoreSize(80, 80);

        // Clamping a point far to the left
        var clamped1 = env.ClampToTaskbarWalkingSurface(new CorePoint(10, 970), charSize);
        Assert.Equal(100.0, clamped1.X);

        // Clamping a point far below into the taskbar
        var clamped2 = env.ClampToTaskbarWalkingSurface(new CorePoint(500, 1060), charSize);
        Assert.True(clamped2.Y <= safeSurface.Bottom - charSize.Height);
    }

    [Fact]
    public void MultiMonitorEnvironment_HandlesNegativeCoordinatesAndSecondaryDisplays()
    {
        var primaryMon = new DisplayMonitorInfo("PRIMARY", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);
        // Secondary monitor placed to the left (negative X coordinates)
        var leftMon = new DisplayMonitorInfo("LEFT_MON", new CoreRect(-1920, 0, 1920, 1080), new CoreRect(-1920, 0, 1920, 1040), false);

        var env = new DesktopEnvironment(
            primaryMon,
            new[] { primaryMon, leftMon },
            new[]
            {
                new TaskbarInfo("PRIMARY", new CoreRect(0, 1040, 1920, 40), TaskbarOrientation.Bottom, TaskbarVisibilityState.Visible, 40, new CoreRect(40, 980, 1840, 50)),
                new TaskbarInfo("LEFT_MON", new CoreRect(-1920, 1040, 1920, 40), TaskbarOrientation.Bottom, TaskbarVisibilityState.Visible, 40, new CoreRect(-1880, 980, 1840, 50))
            },
            Array.Empty<ObservableWindow>());

        Assert.Equal(2, env.AllMonitors.Count);
        Assert.Equal(2, env.Taskbars.Count);
        Assert.True(env.IsPointNearTaskbar(new CorePoint(-500, 1020)));
    }
}
