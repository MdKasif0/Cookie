using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Context;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class WindowsLifecycleAndRecoveryTests
{
    private class MockScreenGeometryProvider : IScreenGeometryProvider
    {
        public CoreRect WorkArea { get; set; } = new CoreRect(0, 0, 1920, 1040);
        public CoreRect Bounds { get; set; } = new CoreRect(0, 0, 1920, 1080);
        public CorePoint? CursorPos { get; set; } = new CorePoint(500, 500);

        public CoreRect GetPrimaryWorkArea() => WorkArea;
        public CoreRect GetVirtualScreenBounds() => Bounds;
        public CorePoint? GetCursorPositionDip() => CursorPos;
        public List<DisplayMonitorInfo> GetActiveMonitors() =>
            new() { new DisplayMonitorInfo("M1", Bounds, WorkArea, true) };
    }

    private (CookieBehaviorController Controller, DefaultApplicationContextDetector Detector, MockScreenGeometryProvider Screen) CreateController()
    {
        var screen = new MockScreenGeometryProvider();
        var screenService = new ScreenGeometryService(screen);
        var audio = new TestAudioManager();
        var anim = new CookieAnimationController();
        var detector = new DefaultApplicationContextDetector();

        var controller = new CookieBehaviorController(
            anim,
            screenService,
            audio,
            contextDetector: detector);

        return (controller, detector, screen);
    }

    [Fact]
    public void ApplicationSwitch_PausesGroundWalk_AndNoticesNewWindow()
    {
        var (controller, detector, _) = CreateController();
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        controller.Now = () => clock;

        // Simulate an autonomous walk
        controller.AutonomousWalkForTesting(new CorePoint(500, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        // Switch application with a frontmost window
        bool noticed = false;
        controller.OnNoticeTriggered += () => noticed = true;

        var newContext = new ApplicationContext(
            DesktopContextState.AnotherAppActive,
            "code",
            "Cookie.cs",
            123,
            ApplicationCategory.CodeEditor,
            false,
            new CoreRect(800, 200, 600, 500),
            clock);

        detector.SimulateSwitch(newContext);

        // Walking should pause into Idle
        Assert.Equal(CookieState.Idle, controller.State);
        Assert.True(noticed);
    }

    [Fact]
    public void SessionLockAndUnlock_PausesAndSafelyRecovers()
    {
        var (controller, _, _) = CreateController();

        // Simulate active movement
        controller.AutonomousWalkForTesting(new CorePoint(600, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        // Lock session (WM_WTSSESSION_CHANGE: WTS_SESSION_LOCK)
        controller.PauseForSessionLock();

        Assert.True(controller.IsSessionLocked);
        Assert.Equal(CookieState.Sitting, controller.State);

        // Game loop updates while locked must not trigger movement
        controller.Update(1.0);
        Assert.Equal(CookieState.Sitting, controller.State);

        // Unlock session (WM_WTSSESSION_CHANGE: WTS_SESSION_UNLOCK)
        controller.ResumeFromSessionLock();

        Assert.False(controller.IsSessionLocked);
        Assert.Equal(CookieState.Idle, controller.State);
    }

    [Fact]
    public void DisplayConfigurationChange_CancelsMovementAndRecoversPosition()
    {
        var (controller, _, screen) = CreateController();

        // Place Cookie near edge
        controller.SetPosition(new CorePoint(1800, 900));
        controller.AutonomousWalkForTesting(new CorePoint(1900, 900));

        // Screen resized to 1280x720
        screen.Bounds = new CoreRect(0, 0, 1280, 720);
        screen.WorkArea = new CoreRect(0, 0, 1280, 680);

        // Display configuration changed
        controller.HandleDisplayConfigurationChanged();

        Assert.Equal(CookieState.Idle, controller.State);
        // Cookie position must be clamped within the new work area
        Assert.True(controller.CurrentPosition.X <= 1280 - controller.CompanionSize.Width);
        Assert.True(controller.CurrentPosition.Y <= 680 - controller.CompanionSize.Height);
    }

    [Fact]
    public void DraggingDuringAutonomousAction_CancelsAutonomousMovementImmediately()
    {
        var (controller, _, _) = CreateController();

        controller.AutonomousWalkForTesting(new CorePoint(500, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        // User starts dragging Cookie
        controller.BeginDrag();

        Assert.Equal(CookieState.BeingDragged, controller.State);
        Assert.False(controller.WindowController.IsActive);
        Assert.False(controller.TaskbarController.IsActive);
    }

    [Fact]
    public void EmoteActivationDuringNavigation_PrioritizesEmote()
    {
        var (controller, _, _) = CreateController();

        controller.AutonomousWalkForTesting(new CorePoint(500, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        // User triggers emote
        bool triggered = controller.TriggerEmote(Emote.Wave);

        Assert.True(triggered);
        Assert.Equal(CookieState.Emoting, controller.State);
        Assert.Equal(EmoteId.Wave, controller.CurrentEmote?.Id);
    }

    [Fact]
    public void SettingsToggledMidMovement_CancelsAutonomousMovement()
    {
        var (controller, _, _) = CreateController();

        controller.AutonomousWalkForTesting(new CorePoint(500, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        // User disables autonomous behavior in settings
        controller.AutonomousBehaviorEnabled = false;

        Assert.Equal(CookieState.Idle, controller.State);

        // Test pausing autonomous wandering
        controller.AutonomousBehaviorEnabled = true;
        controller.AutonomousWalkForTesting(new CorePoint(500, 800));
        Assert.Equal(CookieState.Walking, controller.State);

        controller.PauseAutonomousBehavior = true;
        Assert.Equal(CookieState.Idle, controller.State);
    }

    [Fact]
    public void ReducedMotionMode_ScalesWalkSpeed()
    {
        var (controller, _, _) = CreateController();

        controller.Settings.ReducedMotion = ReducedMotionMode.Always;
        controller.AutonomousWalkForTesting(new CorePoint(controller.CurrentPosition.X + 100, controller.CurrentPosition.Y));

        double initialX = controller.CurrentPosition.X;
        controller.Update(1.0);
        double delta = controller.CurrentPosition.X - initialX;

        // BaseWalkSpeed = 55.0, with ReducedMotion (0.65x) = 35.75
        Assert.True(delta <= 40.0, $"Expected delta <= 40.0, got {delta}");
    }
}
