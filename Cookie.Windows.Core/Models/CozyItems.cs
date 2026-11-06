using System;
using System.Linq;
using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

/// <summary>The comfortable spots Cookie can be given: places she returns to on her own.</summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CozyKind
{
    Bed,
    Sunbeam,
    ScratchingPost
}

public static class CozyKindExtensions
{
    public static string GetDisplayName(this CozyKind kind) => kind switch
    {
        CozyKind.Bed => "Cat Bed",
        CozyKind.Sunbeam => "Sunbeam Spot",
        CozyKind.ScratchingPost => "Scratching Post",
        _ => kind.ToString()
    };

    /// <summary>Lowercase-first name, matching the macOS app's raw values and file names.</summary>
    public static string GetKey(this CozyKind kind) =>
        char.ToLowerInvariant(kind.ToString()[0]) + kind.ToString()[1..];

    /// <summary>File name, without extension, of the art under Sprites/Cookie/Items.</summary>
    public static string GetAssetName(this CozyKind kind) => "cozy-" + kind.GetKey();

    public static string GetIconName(this CozyKind kind) => "item-" + kind.GetAssetName();

    /// <summary>Side of the square window that shows it, in DIPs at Cookie's default size.</summary>
    public static double GetPanelSide(this CozyKind kind) => kind switch
    {
        CozyKind.Bed => 130,
        CozyKind.Sunbeam => 170,
        CozyKind.ScratchingPost => 120,
        _ => 130
    };

    /// <summary>How close she stands to it, from its center, before settling in.</summary>
    public const double ArrivalDistance = 14;
}

/// <summary>
/// A placed cozy item. Position is a fraction of the main screen's work-area width, so it
/// survives resolution changes and display swaps.
/// </summary>
public class CozyPlacement
{
    private double _position = 0.5;

    public CozyKind Kind { get; set; }

    public double Position
    {
        get => _position;
        set => _position = Math.Clamp(value, 0.04, 0.96);
    }

    public CozyPlacement() { }

    public CozyPlacement(CozyKind kind, double position)
    {
        Kind = kind;
        Position = position;
    }
}

/// <summary>Where new cozy items go. Matches the macOS app's placement rule.</summary>
public static class CozyLayout
{
    private const double MinimumGap = 0.11;

    /// <summary>A position near <paramref name="preferredX"/>, clear of the items already placed.</summary>
    public static double NewPosition(double preferredX, double areaLeft, double areaWidth, System.Collections.Generic.IEnumerable<double> existing)
    {
        var taken = existing.ToList();
        double preferred = (preferredX - areaLeft) / areaWidth;

        for (int step = 0; step <= 12; step++)
        {
            var offsets = step == 0 ? new[] { 0.0 } : new[] { step * 0.06, -step * 0.06 };
            foreach (double offset in offsets)
            {
                double candidate = preferred + offset;
                if (candidate < 0.05 || candidate > 0.95) continue;
                if (taken.All(position => Math.Abs(position - candidate) >= MinimumGap)) return candidate;
            }
        }
        return Math.Clamp(preferred, 0.05, 0.95);
    }
}
