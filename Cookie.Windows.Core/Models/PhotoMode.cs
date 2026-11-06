using System;
using System.Collections.Generic;

namespace Cookie.Windows.Core.Models;

/// <summary>A pose offered in Photo Mode: one of Cookie's animations, shown as a still or a loop. Matches the macOS app.</summary>
public record PhotoPose(string Id, string Title, CookieAnimationId Animation)
{
    public static IReadOnlyList<PhotoPose> All { get; } = new[]
    {
        new PhotoPose("idle", "Sitting Pretty", CookieAnimationId.Idle),
        new PhotoPose("wave", "Hello!", CookieAnimationId.Wave),
        new PhotoPose("happy", "Happy", CookieAnimationId.HappyEmote),
        new PhotoPose("love", "In Love", CookieAnimationId.Love),
        new PhotoPose("playful", "Playful", CookieAnimationId.PlayfulEmote),
        new PhotoPose("sleepy", "Sleepy", CookieAnimationId.SleepyEmote),
        new PhotoPose("napping", "Napping", CookieAnimationId.Sleep),
        new PhotoPose("walk", "On a Stroll", CookieAnimationId.WalkRight),
        new PhotoPose("curious", "Curious", CookieAnimationId.Curious),
        new PhotoPose("stretch", "Big Stretch", CookieAnimationId.Stretch)
    };
}

public enum PhotoBackdrop
{
    Transparent,
    Cream,
    Blush,
    Sky,
    Mint,
    Night
}

public static class PhotoBackdropExtensions
{
    public static string GetTitle(this PhotoBackdrop backdrop) => backdrop.ToString();

    /// <summary>The fill color, or null to leave the background clear.</summary>
    public static (byte R, byte G, byte B)? GetColor(this PhotoBackdrop backdrop)
    {
        static (byte, byte, byte) Rgb(double r, double g, double b) =>
            ((byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

        return backdrop switch
        {
            PhotoBackdrop.Cream => Rgb(0.98, 0.95, 0.89),
            PhotoBackdrop.Blush => Rgb(0.98, 0.88, 0.86),
            PhotoBackdrop.Sky => Rgb(0.84, 0.91, 0.97),
            PhotoBackdrop.Mint => Rgb(0.86, 0.94, 0.88),
            PhotoBackdrop.Night => Rgb(0.17, 0.18, 0.26),
            _ => null
        };
    }
}

public static class PhotoClips
{
    /// <summary>The length of the shortest block that, repeated, makes up the list. Some sheets repeat frames to fill an emote's time.</summary>
    public static int CycleLength<T>(IReadOnlyList<T> items) where T : IEquatable<T>
    {
        int count = items.Count;
        if (count <= 1) return count;

        for (int length = 1; length <= count; length++)
        {
            if (count % length != 0) continue;
            bool repeats = true;
            for (int i = 0; i < count && repeats; i++) repeats = items[i].Equals(items[i % length]);
            if (repeats) return length;
        }
        return count;
    }
}
