using System;

namespace Cookie.Windows.Core.Cursor;

/// <summary>
/// Discrete proximity zones around Cookie based on rendered size.
/// </summary>
public enum CursorProximityZone
{
    /// <summary>
    /// Outside all interaction range (> 350 pt adjusted).
    /// </summary>
    Departure,

    /// <summary>
    /// Cookie senses the pointer and glances toward it (&lt;= 250 pt adjusted).
    /// </summary>
    Awareness,

    /// <summary>
    /// Cookie is engaged and may choose to approach or follow (&lt;= 120 pt adjusted).
    /// </summary>
    Interaction,

    /// <summary>
    /// The pointer is right next to or touching Cookie (&lt;= 55 pt adjusted).
    /// </summary>
    CloseContact
}

/// <summary>
/// Categorization of cursor movement dynamics.
/// </summary>
public enum CursorMotionState
{
    /// <summary>
    /// Pointer is virtually still (&lt; 30 pt/s).
    /// </summary>
    Stationary,

    /// <summary>
    /// Pointer is moving smoothly and gently (30...580 pt/s) — ideal for following.
    /// </summary>
    Slow,

    /// <summary>
    /// Pointer is moving rapidly (> 580 pt/s) — Cookie watches or pauses, never chases.
    /// </summary>
    Rapid
}

/// <summary>
/// Playful deterministic reactions Cookie can exhibit during cursor play.
/// </summary>
public enum CursorPlayfulReaction
{
    /// <summary>
    /// Gentle curious gaze toward the pointer.
    /// </summary>
    Glance,

    /// <summary>
    /// Adorable subtle head tilt toward cursor position.
    /// </summary>
    HeadTilt,

    /// <summary>
    /// Gentle step toward the interaction zone.
    /// </summary>
    Approach,

    /// <summary>
    /// Playful paw reach or investigative tap.
    /// </summary>
    PawReach,

    /// <summary>
    /// Gentle step backward when cursor approaches swiftly.
    /// </summary>
    Dodge,

    /// <summary>
    /// Joyful purr or happy chirp after successful play.
    /// </summary>
    HappyChirp
}

public static class CursorFollowingIntensityExtensions
{
    public static double GetMaxSpeed(this Models.CursorFollowingIntensity intensity)
    {
        return intensity switch
        {
            Models.CursorFollowingIntensity.Calm => 110.0,
            Models.CursorFollowingIntensity.Balanced => 160.0,
            Models.CursorFollowingIntensity.Intense => 220.0,
            _ => 160.0
        };
    }

    public static double GetTrailingDistance(this Models.CursorFollowingIntensity intensity)
    {
        return intensity switch
        {
            Models.CursorFollowingIntensity.Calm => 95.0,
            Models.CursorFollowingIntensity.Balanced => 75.0,
            Models.CursorFollowingIntensity.Intense => 60.0,
            _ => 75.0
        };
    }

    public static double GetAnticipationDelay(this Models.CursorFollowingIntensity intensity)
    {
        return intensity switch
        {
            Models.CursorFollowingIntensity.Calm => 0.60,
            Models.CursorFollowingIntensity.Balanced => 0.40,
            Models.CursorFollowingIntensity.Intense => 0.25,
            _ => 0.40
        };
    }
}
