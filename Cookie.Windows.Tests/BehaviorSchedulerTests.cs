using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Context;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class BehaviorSchedulerTests
{
    private DesktopEnvironment CreateTestEnvironment()
    {
        var monitor = new DisplayMonitorInfo("M1", new CoreRect(0, 0, 1920, 1080), new CoreRect(0, 0, 1920, 1040), true);
        var taskbar = new TaskbarInfo("M1", new CoreRect(0, 1040, 1920, 40), TaskbarOrientation.Bottom, TaskbarVisibilityState.Visible, 40, new CoreRect(40, 980, 1840, 50));
        var win = new ObservableWindow(new IntPtr(1001), "Editor", "Code", new CoreRect(200, 300, 600, 400), false, false, false, 0);

        return new DesktopEnvironment(
            new List<DisplayMonitorInfo> { monitor },
            monitor,
            new List<TaskbarInfo> { taskbar },
            taskbar,
            new List<ObservableWindow> { win },
            new List<CoreRect> { new CoreRect(200, 300, 600, 400) },
            new CorePoint(100, 900),
            DateTime.UtcNow);
    }

    [Fact]
    public void DisabledOrPaused_ReturnsNull()
    {
        var scheduler = new BehaviorScheduler();
        var env = CreateTestEnvironment();
        var settings = new CookieSettings
        {
            AutonomousBehaviorEnabled = false
        };

        var behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.Null(behavior);

        // Test PauseAutonomousBehavior = true
        settings.AutonomousBehaviorEnabled = true;
        settings.PauseAutonomousBehavior = true;

        behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.Null(behavior);
    }

    [Fact]
    public void DraggingOrEmoting_SuppressesAutonomousScheduling()
    {
        var scheduler = new BehaviorScheduler();
        var env = CreateTestEnvironment();
        var settings = new CookieSettings();

        // Being dragged
        var behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.BeingDragged,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: true,
            isEmoting: false);

        Assert.Null(behavior);

        // Emoting
        behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Emoting,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: true);

        Assert.Null(behavior);
    }

    [Fact]
    public void CursorInInteractionZone_SelectsPlayfulInteraction()
    {
        var scheduler = new BehaviorScheduler();
        var env = CreateTestEnvironment();
        var settings = new CookieSettings();

        var behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            new CorePoint(120, 910),
            10.0,
            CursorProximityZone.Interaction,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.Equal(AmbientBehaviorKind.PlayfulInteraction, behavior);
    }

    [Fact]
    public void RecentDirectInteractionGracePeriod_PrioritizesAttentionNearUser()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var scheduler = new BehaviorScheduler
        {
            Now = () => clock
        };
        var env = CreateTestEnvironment();
        var settings = new CookieSettings();

        // Record interaction 2 seconds ago
        scheduler.Memory.RecordDirectInteraction();
        clock = clock.AddSeconds(2.0);

        var behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        // Within grace period (< 6.0s), invites playful interaction or rest
        Assert.True(behavior is AmbientBehaviorKind.PlayfulInteraction or AmbientBehaviorKind.ReturnToRest);
    }

    [Fact]
    public void ActivityLevelCadence_CalmEnforcesLongerQuietRest()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var scheduler = new BehaviorScheduler
        {
            Now = () => clock
        };
        var env = CreateTestEnvironment();
        var settings = new CookieSettings
        {
            Activity = ActivityLevel.Calm
        };

        // Record action now
        scheduler.Memory.RecordAutonomousAction("ShortDesktopPatrol");

        // 10 seconds later: Calm interval is 28s -> still resting
        clock = clock.AddSeconds(10.0);
        var behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.Null(behavior);

        // 30 seconds later: exceeds 28s -> selects action
        clock = clock.AddSeconds(20.0);
        behavior = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.NotNull(behavior);
    }

    [Fact]
    public void CandidateSelection_ConsidersContextAndAvoidsRepetition()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var scheduler = new BehaviorScheduler
        {
            Now = () => clock
        };
        var env = CreateTestEnvironment();
        var settings = new CookieSettings
        {
            Activity = ActivityLevel.Playful
        };

        // First selection
        var first = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.NotNull(first);

        // Advance by playful interval (7s)
        clock = clock.AddSeconds(8.0);

        // Immediate next selection must not be identical to first (anti-repetition)
        var second = scheduler.SelectNextAmbientBehavior(
            CookieState.Idle,
            new CorePoint(100, 900),
            null,
            0,
            CursorProximityZone.Distant,
            ApplicationContext.Unknown,
            env,
            settings,
            isBeingDragged: false,
            isEmoting: false);

        Assert.NotNull(second);
        Assert.NotEqual(first, second);
    }
}
