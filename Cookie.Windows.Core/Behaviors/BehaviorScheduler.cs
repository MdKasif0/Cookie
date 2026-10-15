using System;
using System.Collections.Generic;
using System.Linq;
using Cookie.Windows.Core.Context;
using Cookie.Windows.Core.Cursor;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Centralized behavior scheduler that coordinates ambient autonomous activity selection,
/// priority rules, and context adaptation.
/// Evaluates candidate behaviors at meaningful decision points rather than every rendered frame.
/// </summary>
public class BehaviorScheduler
{
    private readonly Random _random = new();

    public BehaviorMemory Memory { get; }

    public Func<DateTime> Now
    {
        get => Memory.Now;
        set => Memory.Now = value;
    }

    public BehaviorScheduler(BehaviorMemory? memory = null)
    {
        Memory = memory ?? new BehaviorMemory();
    }

    /// <summary>
    /// Evaluates candidate ambient behaviors and selects the most appropriate action
    /// based on desktop context, memory history, and user settings.
    /// </summary>
    public AmbientBehaviorKind? SelectNextAmbientBehavior(
        CookieState currentState,
        CorePoint cookiePosition,
        CorePoint? cursorPosition,
        double cursorVelocity,
        CursorProximityZone cursorZone,
        ApplicationContext context,
        DesktopEnvironment environment,
        CookieSettings settings,
        bool isBeingDragged,
        bool isEmoting)
    {
        // 1. Hard gating: autonomous behavior disabled or paused
        if (!settings.RandomInteractions || settings.PauseAutonomousBehavior || !settings.AutonomousBehaviorEnabled)
        {
            return null;
        }

        // 2. High-priority states prevent autonomous scheduling
        if (isBeingDragged || isEmoting || currentState is CookieState.BeingDragged or CookieState.Emoting or CookieState.Jumping)
        {
            return null;
        }

        // 3. Active cursor interaction: prioritize responsiveness over wandering off
        if (cursorZone == CursorProximityZone.Interaction || (cursorZone == CursorProximityZone.Awareness && cursorVelocity > 100.0))
        {
            if (cursorZone == CursorProximityZone.Interaction && !Memory.IsActionRepetitive("PlayfulInteraction"))
            {
                return AmbientBehaviorKind.PlayfulInteraction;
            }
            return null;
        }

        // 4. Recent direct interaction grace period: remain attentive near user
        if (Memory.TimeSinceLastInteraction() < 6.0)
        {
            if (!Memory.IsActionRepetitive("PlayfulInteraction"))
            {
                return AmbientBehaviorKind.PlayfulInteraction;
            }
            return AmbientBehaviorKind.ReturnToRest;
        }

        // 5. Activity level cadence: calm needs longer quiet time between wanderings
        double minActionInterval = settings.Activity switch
        {
            ActivityLevel.Calm => 28.0,
            ActivityLevel.Balanced => 14.0,
            ActivityLevel.Playful => 7.0,
            _ => 14.0
        };

        if (Memory.TimeSinceLastAutonomousAction() < minActionInterval)
        {
            // Still in rest cadence
            return null;
        }

        // 6. Build weighted candidate options based on desktop context & anti-repetition rules
        var candidates = new List<(AmbientBehaviorKind Behavior, double Weight)>();

        // A. Return to Rest / Sitting
        if (currentState != CookieState.Sitting && currentState != CookieState.Sleeping)
        {
            candidates.Add((AmbientBehaviorKind.ReturnToRest, 30.0));
        }

        // B. Short Desktop Patrol
        if (!Memory.IsActionRepetitive("ShortDesktopPatrol"))
        {
            double patrolWeight = (settings.Activity == ActivityLevel.Playful) ? 40.0 : 25.0;
            // Reduce patrol weight if reduced motion is requested
            if (settings.ReducedMotion != ReducedMotionMode.Never)
            {
                patrolWeight *= 0.7;
            }
            candidates.Add((AmbientBehaviorKind.ShortDesktopPatrol, patrolWeight));
        }

        // C. Curious Observation (especially if frontmost window or candidate windows exist)
        if (context.FrontmostWindowBounds.HasValue || environment.Windows.Count > 0)
        {
            if (!Memory.IsActionRepetitive("CuriousObservation"))
            {
                candidates.Add((AmbientBehaviorKind.CuriousObservation, 35.0));
            }
        }

        // D. Window Inspection
        if (settings.WindowInteraction && environment.Windows.Count > 0)
        {
            if (!Memory.IsActionRepetitive("WindowInspection"))
            {
                double windowWeight = (settings.Activity == ActivityLevel.Playful) ? 35.0 : 20.0;
                candidates.Add((AmbientBehaviorKind.WindowInspection, windowWeight));
            }
        }

        // E. Gentle Taskbar Visit
        if (settings.DockInteraction && settings.AutonomousDockExploration && environment.PrimaryTaskbar != null)
        {
            if (!Memory.IsActionRepetitive("TaskbarVisit"))
            {
                double dockWeight = (settings.Activity == ActivityLevel.Playful) ? 30.0 : 18.0;
                candidates.Add((AmbientBehaviorKind.TaskbarVisit, dockWeight));
            }
        }

        // F. Playful Interaction (if cursor is present and still, inviting user)
        if (cursorPosition.HasValue && cursorVelocity < 30.0 && !Memory.IsActionRepetitive("PlayfulInteraction"))
        {
            candidates.Add((AmbientBehaviorKind.PlayfulInteraction, 25.0));
        }

        // 7. Pick using weighted random selection
        double totalWeight = candidates.Sum(c => c.Weight);
        if (totalWeight <= 0.0) return null;

        double roll = _random.NextDouble() * totalWeight;
        foreach (var (behavior, weight) in candidates)
        {
            roll -= weight;
            if (roll <= 0.0)
            {
                Memory.RecordAutonomousAction(behavior.ToString());
                return behavior;
            }
        }

        return candidates.Last().Behavior;
    }
}
