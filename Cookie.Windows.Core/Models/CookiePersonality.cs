using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

/// <summary>
/// Cookie's temperament. Personalities shift behavior weights and
/// reactions — they tint the same calm companion rather than creating caricatures.
/// Ported from macOS CookiePersonality.swift.
/// </summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookiePersonality
{
    Sleepy,
    Playful,
    Affectionate,
    Energetic,
    Curious,
    Grumpy
}

public static class CookiePersonalityExtensions
{
    public static string GetDisplayName(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => "Sleepy",
            CookiePersonality.Playful => "Playful",
            CookiePersonality.Affectionate => "Affectionate",
            CookiePersonality.Energetic => "Energetic",
            CookiePersonality.Curious => "Curious",
            CookiePersonality.Grumpy => "Grumpy",
            _ => "Balanced"
        };
    }

    public static string GetSummary(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => "Naps often, but always up for gentle company.",
            CookiePersonality.Playful => "Little games and occasional bursts of mischief.",
            CookiePersonality.Affectionate => "Likes being near you; sometimes follows the cursor.",
            CookiePersonality.Energetic => "Always trotting off somewhere new.",
            CookiePersonality.Curious => "Watches everything, investigates everything.",
            CookiePersonality.Grumpy => "Judgmental, but secretly fond of you.",
            _ => "Gentle companion on your desktop."
        };
    }

    /// <summary>
    /// Desktop strolling speed in points per second.
    /// </summary>
    /// <summary>The animation that shows this personality off during first-run setup.</summary>
    public static CookieAnimationId GetShowcaseAnimation(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => CookieAnimationId.Sleep,
            CookiePersonality.Playful => CookieAnimationId.Playful,
            CookiePersonality.Affectionate => CookieAnimationId.Pet,
            CookiePersonality.Energetic => CookieAnimationId.RunRight,
            CookiePersonality.Curious => CookieAnimationId.Curious,
            CookiePersonality.Grumpy => CookieAnimationId.Annoyed,
            _ => CookieAnimationId.Idle
        };
    }

    public static SoundEffect GetGreetingSound(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => SoundEffect.Sleep,
            CookiePersonality.Playful => SoundEffect.Toy,
            CookiePersonality.Affectionate => SoundEffect.Purr,
            CookiePersonality.Energetic => SoundEffect.Happy,
            CookiePersonality.Curious => SoundEffect.Chirp,
            CookiePersonality.Grumpy => SoundEffect.Meow,
            _ => SoundEffect.Chirp
        };
    }

    public static double GetWalkSpeed(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => 18.0,
            CookiePersonality.Playful => 34.0,
            CookiePersonality.Affectionate => 26.0,
            CookiePersonality.Energetic => 40.0,
            CookiePersonality.Curious => 28.0,
            CookiePersonality.Grumpy => 20.0,
            _ => 28.0
        };
    }

    /// <summary>
    /// Pet strokes inside a one-minute window after which reactions turn annoyed.
    /// </summary>
    public static int GetPetTolerance(this CookiePersonality personality)
    {
        return personality switch
        {
            CookiePersonality.Sleepy => 4,
            CookiePersonality.Playful => 7,
            CookiePersonality.Affectionate => 9,
            CookiePersonality.Energetic => 7,
            CookiePersonality.Curious => 6,
            CookiePersonality.Grumpy => 2,
            _ => 6
        };
    }
}
