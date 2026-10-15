using System;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class BehaviorMemoryTests
{
    [Fact]
    public void IsActionRepetitive_CatchesImmediateRepetitionAndHighFrequency()
    {
        var memory = new BehaviorMemory();

        Assert.False(memory.IsActionRepetitive("ShortDesktopPatrol"));

        memory.RecordAutonomousAction("ShortDesktopPatrol");
        // Immediate repetition is blocked
        Assert.True(memory.IsActionRepetitive("ShortDesktopPatrol"));

        // Different action
        Assert.False(memory.IsActionRepetitive("CuriousObservation"));
        memory.RecordAutonomousAction("CuriousObservation");

        // "ShortDesktopPatrol" was not immediate, but let's test frequency threshold
        Assert.False(memory.IsActionRepetitive("ShortDesktopPatrol"));

        memory.RecordAutonomousAction("ShortDesktopPatrol");
        // Now ShortDesktopPatrol is immediate again
        Assert.True(memory.IsActionRepetitive("ShortDesktopPatrol"));

        memory.RecordAutonomousAction("ReturnToRest");
        // History: ["ShortDesktopPatrol", "CuriousObservation", "ShortDesktopPatrol", "ReturnToRest"]
        // In the last 4 actions, ShortDesktopPatrol appears twice -> blocked by frequency
        Assert.True(memory.IsActionRepetitive("ShortDesktopPatrol"));
    }

    [Fact]
    public void WindowVisitCooldown_EnforcesVisitInterval()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var memory = new BehaviorMemory
        {
            Now = () => clock,
            WindowVisitCooldown = 45.0
        };

        var hwnd = new IntPtr(0x12345);
        Assert.False(memory.IsWindowOnCooldown(hwnd));

        memory.RecordWindowVisit(hwnd);
        Assert.True(memory.IsWindowOnCooldown(hwnd));

        // Advance by 30 seconds (still on cooldown)
        clock = clock.AddSeconds(30.0);
        Assert.True(memory.IsWindowOnCooldown(hwnd));

        // Advance past 45 seconds
        clock = clock.AddSeconds(16.0);
        Assert.False(memory.IsWindowOnCooldown(hwnd));
    }

    [Fact]
    public void TaskbarVisitCooldown_QuantizesAndEnforcesInterval()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var memory = new BehaviorMemory
        {
            Now = () => clock,
            TaskbarRegionCooldown = 40.0
        };

        // Visit at X = 155 (quantizes to 160)
        Assert.False(memory.IsTaskbarRegionOnCooldown(155.0));
        memory.RecordTaskbarVisit(155.0);

        // A nearby coordinate in the same bucket (e.g. 162) is on cooldown
        Assert.True(memory.IsTaskbarRegionOnCooldown(162.0));

        // A far coordinate (e.g. 600) is not on cooldown
        Assert.False(memory.IsTaskbarRegionOnCooldown(600.0));

        // Advance time past cooldown
        clock = clock.AddSeconds(41.0);
        Assert.False(memory.IsTaskbarRegionOnCooldown(162.0));
    }

    [Fact]
    public void AppSwitchReactionCooldown_EnforcesInterval()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var memory = new BehaviorMemory
        {
            Now = () => clock,
            AppSwitchReactionCooldown = 25.0
        };

        Assert.True(memory.CanReactToAppSwitch());

        memory.RecordAppSwitchReaction();
        Assert.False(memory.CanReactToAppSwitch());

        clock = clock.AddSeconds(20.0);
        Assert.False(memory.CanReactToAppSwitch());

        clock = clock.AddSeconds(6.0);
        Assert.True(memory.CanReactToAppSwitch());
    }

    [Fact]
    public void EmoteAntiRepetition_BlocksConsecutiveSameEmoteUntilCooldown()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var memory = new BehaviorMemory
        {
            Now = () => clock,
            SameEmoteCooldown = 30.0
        };

        Assert.True(memory.CanPlayEmote(EmoteId.Happy));

        memory.RecordEmote(EmoteId.Happy);
        // Same emote is blocked
        Assert.False(memory.CanPlayEmote(EmoteId.Happy));
        // Different emote is allowed
        Assert.True(memory.CanPlayEmote(EmoteId.Love));

        clock = clock.AddSeconds(31.0);
        Assert.True(memory.CanPlayEmote(EmoteId.Happy));
    }

    [Fact]
    public void FailedNavigationTargets_TrackedAndExpired()
    {
        DateTime clock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        var memory = new BehaviorMemory
        {
            Now = () => clock
        };

        string targetId = "win-999-top";
        Assert.False(memory.IsTargetFailed(targetId));

        memory.RecordFailedTarget(targetId);
        Assert.True(memory.IsTargetFailed(targetId, 60.0));

        clock = clock.AddSeconds(61.0);
        Assert.False(memory.IsTargetFailed(targetId, 60.0));
    }

    [Fact]
    public void ClearMemory_ResetsAllShortTermState()
    {
        var memory = new BehaviorMemory();
        memory.RecordAutonomousAction("ShortDesktopPatrol");
        memory.RecordWindowVisit(new IntPtr(123));
        memory.RecordEmote(EmoteId.Wave);

        Assert.NotEmpty(memory.RecentAutonomousActions);
        Assert.NotNull(memory.LastEmoteId);

        memory.ClearMemory();

        Assert.Empty(memory.RecentAutonomousActions);
        Assert.Null(memory.LastEmoteId);
        Assert.False(memory.IsWindowOnCooldown(new IntPtr(123)));
    }
}
