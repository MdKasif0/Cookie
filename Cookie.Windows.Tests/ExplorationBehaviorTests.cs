using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class ExplorationBehaviorTests
{
    private (CookieBehaviorController controller, DefaultDesktopEnvironmentProvider envProvider, TestAudioManager audio) CreateTestSetup()
    {
        var animController = new CookieAnimationController();
        var screenService = new ScreenGeometryService();
        var audio = new TestAudioManager();
        var envProvider = new DefaultDesktopEnvironmentProvider();

        var controller = new CookieBehaviorController(
            animController,
            screenService,
            audio,
            environmentProvider: envProvider);

        return (controller, envProvider, audio);
    }

    [Fact]
    public void WindowExploration_TopEdgeWalkingAndCornerTransition()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var winHandle = new IntPtr(901);
        var win = new ObservableWindow(
            winHandle,
            "EditorWindow",
            "CodeEditor",
            1001,
            new CoreRect(200, 300, 400, 300),
            IsOccluded: false);

        envProvider.AddWindow(win);

        // Directly mount on window for deterministic testing
        controller.MountOnWindow(win, new CorePoint(250, 286));
        Assert.Equal(WindowExplorationPhase.WalkingTopEdge, controller.WindowController.CurrentPhase);
        Assert.Equal(CookieState.ExploringWindow, controller.State);

        // Update several frames
        for (int i = 0; i < 20; i++)
        {
            controller.Update(0.1);
        }

        Assert.Equal(CookieState.ExploringWindow, controller.State);
        Assert.True(controller.CurrentPosition.X > 250, "Cookie should advance along top edge");
    }

    [Fact]
    public void WindowExploration_JumpFromOneWindowToAnother()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var win1 = new ObservableWindow(
            new IntPtr(901),
            "Win1",
            "App1",
            1001,
            new CoreRect(100, 400, 300, 300));

        var win2 = new ObservableWindow(
            new IntPtr(902),
            "Win2",
            "App2",
            1002,
            new CoreRect(450, 400, 300, 300)); // 50 DIPs gap, well within reach

        envProvider.SetWindows(new[] { win1, win2 });

        // Mount on right corner of win1
        controller.WindowController.MountOnWindow(win1, new CorePoint(375, 386));
        controller.Settings.WindowJumpingEnabled = true;

        // Force evaluate and launch jump to win2
        var surfaces = controller.WindowController.JumpPlanner.ExtractJumpSurfaces(new[] { win2 });
        var bestJump = controller.WindowController.JumpPlanner.EvaluateBestJump(
            new CorePoint(375, 386),
            win1.Handle,
            surfaces,
            JumpStyle.Gentle,
            force: true);

        Assert.NotNull(bestJump);
        Assert.True(bestJump.IsSafe);

        // Trigger jump in controller
        controller.WindowController.Update(0.1, controller.CurrentPosition, controller.CompanionSize, envProvider.GetDesktopEnvironment(), controller.Settings);
    }

    [Fact]
    public void MidJumpInvalidation_SafelyRedirectsToFloor()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var win1 = new ObservableWindow(new IntPtr(1001), "Win1", "App1", 11, new CoreRect(100, 400, 300, 300));
        var win2 = new ObservableWindow(new IntPtr(1002), "Win2", "App2", 12, new CoreRect(450, 400, 300, 300));

        envProvider.SetWindows(new[] { win1, win2 });

        // Mount and simulate launch towards win2
        controller.WindowController.MountOnWindow(win1, new CorePoint(370, 386));
        var proposal = controller.WindowController.JumpPlanner.EvaluateBestJump(
            new CorePoint(370, 386),
            win1.Handle,
            controller.WindowController.JumpPlanner.ExtractJumpSurfaces(new[] { win2 }),
            JumpStyle.Gentle,
            force: true);

        Assert.NotNull(proposal);

        // Manually launch jump
        var trajectory = new JumpTrajectory(proposal.StartPoint, proposal.TargetSurface.LandingPoint, 0.8, 40.0);
        // Remove win2 from environment to simulate closure mid-flight!
        envProvider.RemoveWindow(win2.Handle);

        // Update airborne frame
        var nextPos = controller.WindowController.Update(
            0.1,
            new CorePoint(400, 350),
            controller.CompanionSize,
            envProvider.GetDesktopEnvironment(),
            controller.Settings);

        Assert.NotNull(nextPos);
        // Must redirect downward safely rather than crashing
        Assert.Null(controller.WindowController.ActiveJumpProposal);
    }

    [Fact]
    public void ActiveWindowClosed_SafelyRecoversToFloor()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var win = new ObservableWindow(new IntPtr(2001), "TemporaryWin", "Notes", 21, new CoreRect(200, 300, 400, 300));
        envProvider.AddWindow(win);

        controller.WindowController.MountOnWindow(win, new CorePoint(300, 286));
        Assert.Equal(WindowExplorationPhase.WalkingTopEdge, controller.WindowController.CurrentPhase);

        // Close window
        envProvider.RemoveWindow(win.Handle);

        // Update tick detects window closure
        var recoveredPos = controller.WindowController.Update(
            0.05,
            controller.CurrentPosition,
            controller.CompanionSize,
            envProvider.GetDesktopEnvironment(),
            controller.Settings);

        Assert.NotNull(recoveredPos);
        Assert.Equal(WindowExplorationPhase.Idle, controller.WindowController.CurrentPhase);
        // Position should be down on the work-area floor
        Assert.True(recoveredPos.Value.Y >= 800.0, "Cookie should recover safely to floor");
    }

    [Fact]
    public void Priority_DraggingImmediatelyCancelsWindowAndTaskbarExploration()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var win = new ObservableWindow(new IntPtr(3001), "WorkWin", "App", 31, new CoreRect(200, 300, 400, 300));
        envProvider.AddWindow(win);

        controller.MountOnWindow(win, new CorePoint(250, 286));
        Assert.Equal(CookieState.ExploringWindow, controller.State);
        Assert.True(controller.WindowController.IsExploringWindow);

        // User clicks and drags Cookie
        controller.BeginDrag();

        Assert.Equal(CookieState.BeingDragged, controller.State);
        Assert.False(controller.WindowController.IsExploringWindow, "Window exploration must be cancelled immediately");
        Assert.False(controller.TaskbarController.IsExploringTaskbar, "Taskbar exploration must be cancelled immediately");
    }

    [Fact]
    public void Priority_EmoteInterruptsWindowExploration()
    {
        var (controller, envProvider, _) = CreateTestSetup();

        var win = new ObservableWindow(new IntPtr(4001), "ActiveWin", "App", 41, new CoreRect(200, 300, 400, 300));
        envProvider.AddWindow(win);

        controller.MountOnWindow(win, new CorePoint(250, 286));
        Assert.Equal(CookieState.ExploringWindow, controller.State);

        // Explicit emote triggered by user
        bool triggered = controller.TriggerEmote(Emote.Wave);

        Assert.True(triggered);
        Assert.Equal(CookieState.Emoting, controller.State);
        Assert.False(controller.WindowController.IsExploringWindow, "Emote must take priority over exploration");
    }

    [Fact]
    public void TaskbarExploration_PacesEdgeAndInspectsApplicationAreas()
    {
        var taskbarController = new TaskbarInteractionController();
        var env = DesktopEnvironment.Fallback;
        var win = new ObservableWindow(new IntPtr(5001), "Browser", "Edge", 51, new CoreRect(100, 100, 800, 600));

        taskbarController.StartExploration(
            new CorePoint(500, 800),
            new CoreSize(180, 180),
            env,
            new[] { win },
            DockExplorationFrequency.Frequent);

        Assert.True(taskbarController.IsExploringTaskbar);
        Assert.Equal(TaskbarSessionPhase.Anticipating, taskbarController.CurrentPhase);

        // Advance through anticipation phase (duration is at most 1.3s)
        taskbarController.Update(1.5, new CorePoint(500, 800), new CoreSize(180, 180), env);
        Assert.Equal(TaskbarSessionPhase.Approaching, taskbarController.CurrentPhase);
        Assert.NotNull(taskbarController.DestinationPoint);

        // Cancel exploration
        taskbarController.CancelExploration();
        Assert.False(taskbarController.IsExploringTaskbar);
        Assert.Equal(TaskbarSessionPhase.Idle, taskbarController.CurrentPhase);
    }
}
