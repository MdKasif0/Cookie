using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;
using Xunit;

namespace Cookie.Windows.Tests;

public class JumpPlannerAndTrajectoryTests
{
    [Fact]
    public void JumpTrajectory_EvaluatesParabolicArcInWindowsScreenCoordinates()
    {
        var start = new CorePoint(100, 500);
        var end = new CorePoint(300, 500);
        double duration = 0.8;
        double apexHeight = 50.0;

        var trajectory = new JumpTrajectory(start, end, duration, apexHeight, JumpStyle.Gentle);

        // At progress 0.0, position is StartPoint
        var p0 = trajectory.PointAt(0.0);
        Assert.Equal(start.X, p0.X, precision: 3);
        Assert.Equal(start.Y, p0.Y, precision: 3);

        // At progress 1.0, position is EndPoint
        var p1 = trajectory.PointAt(1.0);
        Assert.Equal(end.X, p1.X, precision: 3);
        Assert.Equal(end.Y, p1.Y, precision: 3);

        // At progress 0.5 (apex), X is 200, Y is 500 - 50 = 450 (elevated in air!)
        var pMid = trajectory.PointAt(0.5);
        Assert.Equal(200.0, pMid.X, precision: 3);
        Assert.Equal(450.0, pMid.Y, precision: 3);
        Assert.True(pMid.Y < start.Y, "In Windows coordinates, higher altitude has smaller Y coordinate");

        // Shadow scale at apex is 0.75, at landing is 1.0
        Assert.Equal(0.75, trajectory.ShadowScale(0.5), precision: 2);
        Assert.Equal(1.0, trajectory.ShadowScale(0.0), precision: 2);
        Assert.Equal(1.0, trajectory.ShadowScale(1.0), precision: 2);
    }

    [Fact]
    public void JumpPlanner_AcceptsFeasibleJumpWithinLimits()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 400);

        var targetSurface = new JumpTargetSurface(
            "win-target",
            new IntPtr(200),
            "TargetWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(250, 360, 400, 300),
            new CorePoint(300, 360),
            LandingWidth: 200.0);

        var proposals = planner.EvaluateAllJumps(start, null, new[] { targetSurface }, JumpStyle.Gentle);

        Assert.Single(proposals);
        var proposal = proposals[0];
        Assert.True(proposal.IsSafe);
        Assert.Null(proposal.RejectionReason);
        Assert.True(proposal.HorizontalDistance <= planner.MaxHorizontalDistance);
    }

    [Fact]
    public void JumpPlanner_RejectsJumpExceedingMaxHorizontalDistance()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 400);

        // Target is 500 DIPs away horizontally (max limit is 340)
        var targetSurface = new JumpTargetSurface(
            "far-target",
            new IntPtr(201),
            "FarWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(600, 400, 300, 300),
            new CorePoint(600, 400),
            LandingWidth: 200.0);

        var proposals = planner.EvaluateAllJumps(start, null, new[] { targetSurface }, JumpStyle.Gentle);

        Assert.Single(proposals);
        Assert.False(proposals[0].IsSafe);
        Assert.Contains("Horizontal distance exceeds reach", proposals[0].RejectionReason);
    }

    [Fact]
    public void JumpPlanner_RejectsJumpWithExcessiveVerticalUpwardLeap()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 500);

        // Landing Y is 250 (upward leap of 250 DIPs; max upward is 175)
        var targetSurface = new JumpTargetSurface(
            "high-target",
            new IntPtr(202),
            "HighWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(200, 250, 300, 300),
            new CorePoint(250, 250),
            LandingWidth: 200.0);

        var proposals = planner.EvaluateAllJumps(start, null, new[] { targetSurface }, JumpStyle.Gentle);

        Assert.Single(proposals);
        Assert.False(proposals[0].IsSafe);
        Assert.Contains("Upward vertical leap too high", proposals[0].RejectionReason);
    }

    [Fact]
    public void JumpPlanner_RejectsJumpWithExcessiveDownwardDrop()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 200);

        // Landing Y is 550 (downward drop of 350 DIPs; max downward is 260)
        var targetSurface = new JumpTargetSurface(
            "deep-target",
            new IntPtr(203),
            "DeepWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(200, 550, 300, 300),
            new CorePoint(250, 550),
            LandingWidth: 200.0);

        var proposals = planner.EvaluateAllJumps(start, null, new[] { targetSurface }, JumpStyle.Gentle);

        Assert.Single(proposals);
        Assert.False(proposals[0].IsSafe);
        Assert.Contains("Downward drop exceeds safe limit", proposals[0].RejectionReason);
    }

    [Fact]
    public void JumpPlanner_RejectsSurfaceNarrowerThanMinLandingWidth()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 400);

        var narrowSurface = new JumpTargetSurface(
            "narrow-target",
            new IntPtr(204),
            "NarrowWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(200, 400, 60, 300),
            new CorePoint(220, 400),
            LandingWidth: 50.0); // 50 < 75

        var proposals = planner.EvaluateAllJumps(start, null, new[] { narrowSurface }, JumpStyle.Gentle);

        Assert.Single(proposals);
        Assert.False(proposals[0].IsSafe);
        Assert.Contains("Landing surface too narrow", proposals[0].RejectionReason);
    }

    [Fact]
    public void JumpPlanner_EnforcesAntiBounceCooldownOnTargetWindow()
    {
        DateTime simulatedTime = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var planner = new JumpPlanner { Now = () => simulatedTime };

        var targetHandle = new IntPtr(301);
        var targetSurface = new JumpTargetSurface(
            "cooldown-win",
            targetHandle,
            "CoolWindow",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(200, 400, 300, 300),
            new CorePoint(250, 400),
            LandingWidth: 150.0);

        var start = new CorePoint(100, 400);

        // First evaluation: Safe
        var proposals1 = planner.EvaluateAllJumps(start, null, new[] { targetSurface });
        Assert.True(proposals1[0].IsSafe);

        // Record jump to this window
        planner.RecordJumpCompleted(targetHandle);

        // Advance by 10 seconds (within 45s cooldown)
        simulatedTime = simulatedTime.AddSeconds(10.0);
        var proposals2 = planner.EvaluateAllJumps(start, null, new[] { targetSurface });
        Assert.False(proposals2[0].IsSafe);
        Assert.Contains("recently visited", proposals2[0].RejectionReason);

        // Advance past 45s cooldown (50 seconds total)
        simulatedTime = simulatedTime.AddSeconds(40.0);
        var proposals3 = planner.EvaluateAllJumps(start, null, new[] { targetSurface }, force: true);
        Assert.True(proposals3[0].IsSafe);
    }

    [Fact]
    public void JumpPlanner_EnforcesMaxConsecutiveJumpsLimit()
    {
        var planner = new JumpPlanner();
        var start = new CorePoint(100, 400);

        var surface = new JumpTargetSurface(
            "win-seq",
            new IntPtr(401),
            "SeqWin",
            JumpSurfaceKind.WindowTopEdge,
            new CoreRect(200, 400, 300, 300),
            new CorePoint(250, 400),
            LandingWidth: 150.0);

        // Jump 1
        planner.RecordJumpCompleted(new IntPtr(1001));
        // Jump 2 (hits max 2 consecutive jumps limit)
        planner.RecordJumpCompleted(new IntPtr(1002));

        var proposals = planner.EvaluateAllJumps(start, null, new[] { surface });
        Assert.Single(proposals);
        Assert.False(proposals[0].IsSafe);
        Assert.Contains("Consecutive jump limit reached", proposals[0].RejectionReason);

        // Reset consecutive count (e.g. after pet or rest)
        planner.ResetConsecutiveJumps();
        var proposalsAfterReset = planner.EvaluateAllJumps(start, null, new[] { surface }, force: true);
        Assert.True(proposalsAfterReset[0].IsSafe);
    }
}
