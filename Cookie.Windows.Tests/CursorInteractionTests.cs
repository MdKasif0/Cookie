using System;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class CursorInteractionTests
{
    [Fact]
    public void RadiusCalculations_ScaleCorrectly()
    {
        var controller = new CursorInteractionController();

        Assert.Equal(250.0, controller.AwarenessRadius(1.0));
        Assert.Equal(120.0, controller.InteractionRadius(1.0));
        Assert.Equal(55.0, controller.CloseContactRadius(1.0));
        Assert.Equal(350.0, controller.DepartureRadius(1.0));

        // Scaled
        Assert.Equal(300.0, controller.AwarenessRadius(1.2));
        Assert.Equal(144.0, controller.InteractionRadius(1.2));
        Assert.Equal(66.0, controller.CloseContactRadius(1.2));
        Assert.Equal(420.0, controller.DepartureRadius(1.2));
    }

    [Fact]
    public void MotionClassification_CategorizesCorrectly()
    {
        Assert.Equal(CursorMotionState.Stationary, CursorInteractionController.ClassifyMotion(0));
        Assert.Equal(CursorMotionState.Stationary, CursorInteractionController.ClassifyMotion(25));
        Assert.Equal(CursorMotionState.Slow, CursorInteractionController.ClassifyMotion(30));
        Assert.Equal(CursorMotionState.Slow, CursorInteractionController.ClassifyMotion(200));
        Assert.Equal(CursorMotionState.Slow, CursorInteractionController.ClassifyMotion(580));
        Assert.Equal(CursorMotionState.Rapid, CursorInteractionController.ClassifyMotion(581));
        Assert.Equal(CursorMotionState.Rapid, CursorInteractionController.ClassifyMotion(800));
    }

    [Fact]
    public void LookAngle_AnatomicallyClampedWithinBounds()
    {
        var catPos = new CorePoint(100, 100);

        // Directly horizontal
        double flatAngle = CursorInteractionController.CalculateLookAngle(catPos, new CorePoint(200, 100), facingRight: true);
        Assert.Equal(0.0, flatAngle);

        // Extreme upward angle (clamped to 0.20 rad)
        double steepUp = CursorInteractionController.CalculateLookAngle(catPos, new CorePoint(101, 500), facingRight: true);
        Assert.Equal(0.20, steepUp);

        // Extreme downward angle (clamped to -0.20 rad)
        double steepDown = CursorInteractionController.CalculateLookAngle(catPos, new CorePoint(101, -300), facingRight: true);
        Assert.Equal(-0.20, steepDown);
    }

    [Fact]
    public void ProximityZones_TransitionWithHysteresis()
    {
        var controller = new CursorInteractionController();
        var catCenter = new CorePoint(500, 500);
        var settings = new CookieSettings { CursorInteraction = true };

        DateTime testClock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        controller.Now = () => testClock;

        // Start far outside (distance 400 > 350)
        controller.Update(0.016, catCenter, new CorePoint(900, 500), 1.0, settings, false);
        Assert.Equal(CursorProximityZone.Departure, controller.CurrentZone);

        // Advance clock past cooldown
        testClock = testClock.AddSeconds(0.5);

        // Move into awareness zone: distance 230 <= (250 - 12 = 238)
        controller.Update(0.016, catCenter, new CorePoint(730, 500), 1.0, settings, false);
        Assert.Equal(CursorProximityZone.Awareness, controller.CurrentZone);

        // Move to distance 245 (within hysteresis buffer: > 238 but < 350)
        testClock = testClock.AddSeconds(0.5);
        controller.Update(0.016, catCenter, new CorePoint(745, 500), 1.0, settings, false);
        // Stays in awareness due to hysteresis!
        Assert.Equal(CursorProximityZone.Awareness, controller.CurrentZone);

        // Move into interaction zone: distance 100 <= (120 - 12 = 108)
        testClock = testClock.AddSeconds(0.5);
        controller.Update(0.016, catCenter, new CorePoint(600, 500), 1.0, settings, false);
        Assert.Equal(CursorProximityZone.Interaction, controller.CurrentZone);

        // Move into close contact: distance 40 <= (55 - 12 = 43)
        testClock = testClock.AddSeconds(0.5);
        controller.Update(0.016, catCenter, new CorePoint(540, 500), 1.0, settings, false);
        Assert.Equal(CursorProximityZone.CloseContact, controller.CurrentZone);
    }

    [Fact]
    public void PlayfulDodge_TriggersOnRapidApproach()
    {
        var controller = new CursorInteractionController();
        var catCenter = new CorePoint(500, 500);
        var settings = new CookieSettings
        {
            CursorInteraction = true,
            CursorDodgingEnabled = true
        };

        DateTime testClock = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc);
        controller.Now = () => testClock;

        // First step in interaction zone
        controller.Update(0.016, catCenter, new CorePoint(600, 500), 1.0, settings, false);

        testClock = testClock.AddSeconds(0.3);

        // Rush rapidly toward Cookie: distance drops from 100 to 50 in 0.016s -> speed = 50 / 0.016 = 3125 pt/s
        controller.Update(0.016, catCenter, new CorePoint(550, 500), 1.0, settings, false);

        Assert.True(controller.SmoothedCursorVelocity > 620.0);
        Assert.True(controller.IsApproachingCookie);
        Assert.Equal(CursorPlayfulReaction.Dodge, controller.ActiveReaction);

        // Clear and verify cooldown prevents immediate re-trigger
        controller.ClearActiveReaction();
        controller.Update(0.016, catCenter, new CorePoint(540, 500), 1.0, settings, false);
        Assert.Null(controller.ActiveReaction);
    }

    [Fact]
    public void MovementInterpolator_PhysicalDecelerationBraking()
    {
        var interpolator = new MovementInterpolator(
            initialPosition: 0.0,
            maxSpeed: 100.0,
            acceleration: 200.0,
            deceleration: 300.0,
            arrivalThreshold: 2.0);

        interpolator.SetTarget(200.0);
        Assert.False(interpolator.IsArrived);

        // Step through updates
        for (int i = 0; i < 200 && !interpolator.IsArrived; i++)
        {
            interpolator.Update(0.016);
            Assert.True(interpolator.CurrentPosition <= 200.0);
        }

        Assert.True(interpolator.IsArrived);
        Assert.Equal(200.0, interpolator.CurrentPosition, precision: 1);
        Assert.Equal(0.0, interpolator.CurrentVelocity);
    }

    [Fact]
    public void MovementInterpolator2D_MovesSmoothlyToTarget()
    {
        var interpolator = new MovementInterpolator(
            maxSpeed: 160.0,
            acceleration: 340.0,
            deceleration: 480.0,
            arrivalThreshold: 4.0);

        interpolator.Reset2D(new CorePoint(100, 100));
        interpolator.SetTarget2D(new CorePoint(250, 180));

        Assert.False(interpolator.IsArrived2D);

        for (int i = 0; i < 250 && !interpolator.IsArrived2D; i++)
        {
            interpolator.Update2D(0.016);
        }

        Assert.True(interpolator.IsArrived2D);
        Assert.Equal(250.0, interpolator.CurrentPosition2D.X, precision: 1);
        Assert.Equal(180.0, interpolator.CurrentPosition2D.Y, precision: 1);
    }
}
