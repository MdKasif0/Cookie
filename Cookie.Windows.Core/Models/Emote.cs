using System;
using System.Collections.Generic;

namespace Cookie.Windows.Core.Models;

public enum EmoteId
{
    Wave,
    Happy,
    Love,
    Sleepy,
    Playful
}

public enum EmotePlaybackPhase
{
    Ready,
    Starting,
    Playing,
    Finishing,
    Returning
}

public class Emote
{
    public EmoteId Id { get; }
    public string Name { get; }
    public string Description { get; }
    public string Icon { get; }
    public CookieAnimationId AnimationIdentifier { get; }
    public double DurationSeconds { get; }
    public SoundEffect? SoundIdentifier { get; }
    public double CooldownSeconds { get; }
    public CookieAnimationPriority Priority { get; }
    public string Emoji { get; }

    public Emote(
        EmoteId id,
        string name,
        string description,
        string icon,
        CookieAnimationId animationIdentifier,
        double durationSeconds,
        SoundEffect? soundIdentifier,
        double cooldownSeconds,
        CookieAnimationPriority priority,
        string emoji)
    {
        Id = id;
        Name = name;
        Description = description;
        Icon = icon;
        AnimationIdentifier = animationIdentifier;
        DurationSeconds = durationSeconds;
        SoundIdentifier = soundIdentifier;
        CooldownSeconds = cooldownSeconds;
        Priority = priority;
        Emoji = emoji;
    }

    public static readonly Emote Wave = new(
        EmoteId.Wave,
        "Wave",
        "Cookie says hello.",
        "Wave",
        CookieAnimationId.Wave,
        2.0,
        SoundEffect.Mew,
        2.0,
        CookieAnimationPriority.Emote,
        "👋"
    );

    public static readonly Emote Happy = new(
        EmoteId.Happy,
        "Happy",
        "Cookie is feeling happy.",
        "Sparkles",
        CookieAnimationId.HappyEmote,
        1.8,
        SoundEffect.Happy,
        1.8,
        CookieAnimationPriority.Emote,
        "✨"
    );

    public static readonly Emote Love = new(
        EmoteId.Love,
        "Love",
        "Cookie sends you some love.",
        "Heart",
        CookieAnimationId.Love,
        2.0,
        SoundEffect.Purr,
        2.0,
        CookieAnimationPriority.Emote,
        "🧡"
    );

    public static readonly Emote Sleepy = new(
        EmoteId.Sleepy,
        "Sleepy",
        "Cookie is getting sleepy.",
        "Moon",
        CookieAnimationId.SleepyEmote,
        2.2,
        SoundEffect.Sleep,
        2.2,
        CookieAnimationPriority.Emote,
        "💤"
    );

    public static readonly Emote Playful = new(
        EmoteId.Playful,
        "Playful",
        "Cookie wants to play.",
        "Play",
        CookieAnimationId.PlayfulEmote,
        2.0,
        SoundEffect.Toy,
        2.0,
        CookieAnimationPriority.Emote,
        "🧶"
    );

    public static readonly IReadOnlyList<Emote> All = new[]
    {
        Wave,
        Happy,
        Love,
        Sleepy,
        Playful
    };

    public static Emote? FromId(EmoteId id)
    {
        return id switch
        {
            EmoteId.Wave => Wave,
            EmoteId.Happy => Happy,
            EmoteId.Love => Love,
            EmoteId.Sleepy => Sleepy,
            EmoteId.Playful => Playful,
            _ => null
        };
    }
}
