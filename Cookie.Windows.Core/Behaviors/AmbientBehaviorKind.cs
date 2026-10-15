using System;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Behaviors;

/// <summary>
/// Ambient autonomous behaviors supported by Cookie.
/// All behaviors reuse existing animation states, movement controllers, and emotes.
/// </summary>
public enum AmbientBehaviorKind
{
    /// <summary>
    /// Cookie pauses and glances curiously toward a nearby window or the active application.
    /// </summary>
    CuriousObservation,

    /// <summary>
    /// Cookie walks gently along a safe surface and stops naturally.
    /// </summary>
    ShortDesktopPatrol,

    /// <summary>
    /// Cookie approaches an external window edge and observes it briefly.
    /// </summary>
    WindowInspection,

    /// <summary>
    /// Cookie explores an appropriate taskbar-adjacent area.
    /// </summary>
    TaskbarVisit,

    /// <summary>
    /// Cookie executes a leap or transition between connected surfaces.
    /// </summary>
    SurfaceTransition,

    /// <summary>
    /// Cookie turns toward the cursor and invites playful interaction.
    /// </summary>
    PlayfulInteraction,

    /// <summary>
    /// Cookie settles into a calm sitting or resting posture.
    /// </summary>
    ReturnToRest,

    /// <summary>
    /// Cookie performs a brief existing emote after a successful interaction.
    /// </summary>
    GentleCelebration,

    /// <summary>
    /// Cookie safely abandons an invalid route and returns to ground.
    /// </summary>
    Recovery
}

/// <summary>
/// Detailed specification for an autonomous behavior, defining priority, limits, and animations.
/// </summary>
public record BehaviorSpec(
    AmbientBehaviorKind Kind,
    int Priority,
    double MaxDuration,
    CookieAnimationId AnimationId,
    bool CanBeInterruptedByDrag = true,
    bool CanBeInterruptedByEmote = true,
    AmbientBehaviorKind? Fallback = AmbientBehaviorKind.ReturnToRest)
{
    public static BehaviorSpec GetSpec(AmbientBehaviorKind kind)
    {
        return kind switch
        {
            AmbientBehaviorKind.CuriousObservation => new(
                kind,
                Priority: 20,
                MaxDuration: 2.5,
                AnimationId: CookieAnimationId.Curious,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            AmbientBehaviorKind.ShortDesktopPatrol => new(
                kind,
                Priority: 25,
                MaxDuration: 6.0,
                AnimationId: CookieAnimationId.WalkRight,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            AmbientBehaviorKind.WindowInspection => new(
                kind,
                Priority: 30,
                MaxDuration: 18.0,
                AnimationId: CookieAnimationId.WalkRight,
                Fallback: AmbientBehaviorKind.Recovery),

            AmbientBehaviorKind.TaskbarVisit => new(
                kind,
                Priority: 28,
                MaxDuration: 12.0,
                AnimationId: CookieAnimationId.WalkRight,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            AmbientBehaviorKind.SurfaceTransition => new(
                kind,
                Priority: 35,
                MaxDuration: 2.0,
                AnimationId: CookieAnimationId.Jump,
                Fallback: AmbientBehaviorKind.Recovery),

            AmbientBehaviorKind.PlayfulInteraction => new(
                kind,
                Priority: 40,
                MaxDuration: 4.0,
                AnimationId: CookieAnimationId.Investigate,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            AmbientBehaviorKind.ReturnToRest => new(
                kind,
                Priority: 10,
                MaxDuration: 8.0,
                AnimationId: CookieAnimationId.Sit,
                Fallback: null),

            AmbientBehaviorKind.GentleCelebration => new(
                kind,
                Priority: 45,
                MaxDuration: 2.0,
                AnimationId: CookieAnimationId.Happy,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            AmbientBehaviorKind.Recovery => new(
                kind,
                Priority: 50,
                MaxDuration: 1.5,
                AnimationId: CookieAnimationId.Dropped,
                Fallback: AmbientBehaviorKind.ReturnToRest),

            _ => new(kind, 10, 5.0, CookieAnimationId.Idle)
        };
    }
}
