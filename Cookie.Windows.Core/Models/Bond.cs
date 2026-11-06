using System;
using System.Collections.Generic;
using System.Linq;

namespace Cookie.Windows.Core.Models;

public enum BondItemKind
{
    Accessory,
    Toy,
    Coat,
    Cozy
}

/// <summary>Something Cookie's friendship can unlock.</summary>
public record BondItem(BondItemKind Kind, string Key, string DisplayName)
{
    private static string Camel(string name) => char.ToLowerInvariant(name[0]) + name[1..];

    public static BondItem Accessory(AccessoryKind kind) => new(BondItemKind.Accessory, Camel(kind.ToString()), kind.GetDisplayName());
    public static BondItem Toy(ToyKind kind) => new(BondItemKind.Toy, Camel(kind.ToString()), kind.GetDisplayName());
    public static BondItem Coat(FurPattern pattern) => new(BondItemKind.Coat, Camel(pattern.ToString()), $"{pattern} Coat");
    public static BondItem Cozy(CozyKind kind) => new(BondItemKind.Cozy, kind.GetKey(), kind.GetDisplayName());

    /// <summary>
    /// Stable identifier, also what is stored in the profile's unlock list. Identical to the
    /// macOS app's, for example "accessory.crown" or "cozy.scratchingPost".
    /// </summary>
    public string Id => Kind switch
    {
        BondItemKind.Accessory => $"accessory.{Key}",
        BondItemKind.Toy => $"toy.{Key}",
        BondItemKind.Coat => $"coat.{Key}",
        _ => $"cozy.{Key}"
    };
}

public record BondLevel(int Index, string Name, int Points, IReadOnlyList<BondItem> Unlocks);

public record BondProgress(BondLevel Level, BondLevel? Next, double Fraction, int PointsToNext);

public record BondLevelUp(BondLevel Level, IReadOnlyList<BondItem> NewItems);

/// <summary>
/// Friendship with Cookie. It grows from affection (pets, treats, play, emotes, focus sessions) and
/// from the days you come back. All of it is local. The table matches the macOS app exactly.
/// </summary>
public static class Bond
{
    /// <summary>Each new day with Cookie is worth this many points.</summary>
    public const int VisitDayPoints = 5;

    public static IReadOnlyList<BondLevel> Levels { get; } = new List<BondLevel>
    {
        new(0, "Just Met", 0, Array.Empty<BondItem>()),
        new(1, "Friends", 25, new[]
        {
            BondItem.Toy(ToyKind.Feather), BondItem.Accessory(AccessoryKind.Bow), BondItem.Accessory(AccessoryKind.Collar)
        }),
        new(2, "Good Friends", 100, new[]
        {
            BondItem.Toy(ToyKind.ToyMouse), BondItem.Accessory(AccessoryKind.Bandana), BondItem.Accessory(AccessoryKind.Glasses),
            BondItem.Accessory(AccessoryKind.Pumpkin), BondItem.Coat(FurPattern.Tabby), BondItem.Cozy(CozyKind.Bed)
        }),
        new(3, "Best Friends", 250, new[]
        {
            BondItem.Toy(ToyKind.FishToy), BondItem.Accessory(AccessoryKind.Hat), BondItem.Accessory(AccessoryKind.Scarf),
            BondItem.Accessory(AccessoryKind.SantaHat), BondItem.Coat(FurPattern.Tuxedo), BondItem.Cozy(CozyKind.Sunbeam)
        }),
        new(4, "Inseparable", 600, new[]
        {
            BondItem.Accessory(AccessoryKind.Crown), BondItem.Coat(FurPattern.Points), BondItem.Cozy(CozyKind.ScratchingPost)
        })
    };

    public static int Points(CookieStatistics statistics) => statistics.Affection + VisitDayPoints * statistics.VisitDays;

    public static BondLevel LevelFor(int points) => Levels.Last(level => points >= level.Points);

    public static BondProgress ProgressFor(int points)
    {
        var current = LevelFor(points);
        var next = Levels.FirstOrDefault(level => level.Index == current.Index + 1);
        if (next == null) return new BondProgress(current, null, 1, 0);

        double span = next.Points - current.Points;
        double fraction = Math.Clamp((points - current.Points) / span, 0, 1);
        return new BondProgress(current, next, fraction, next.Points - points);
    }

    /// <summary>The level that unlocks an item, or null when it is there from the start.</summary>
    public static BondLevel? RequiredLevel(BondItem item) => Levels.FirstOrDefault(level => level.Unlocks.Contains(item));

    /// <summary>Items unlocked by reaching levels after <paramref name="celebrated"/>, up to the level for <paramref name="points"/>.</summary>
    public static IReadOnlyList<BondItem> NewUnlocks(int celebrated, int points)
    {
        int reached = LevelFor(points).Index;
        if (reached <= celebrated) return Array.Empty<BondItem>();
        return Levels.Where(level => level.Index > celebrated && level.Index <= reached).SelectMany(level => level.Unlocks).ToList();
    }

    /// <summary>`extra` holds items kept available for other reasons, such as ones already in use before unlocks existed.</summary>
    public static bool IsUnlocked(BondItem item, int points, ISet<string>? extra = null)
    {
        var required = RequiredLevel(item);
        if (required == null) return true;
        return points >= required.Points || (extra?.Contains(item.Id) ?? false);
    }
}

/// <summary>Applies the bond to one profile: what is unlocked now, and what just became so.</summary>
public class BondTracker
{
    private readonly CookieProfile _profile;

    public BondTracker(CookieProfile profile)
    {
        _profile = profile;
    }

    public int Points => Bond.Points(_profile.Statistics);
    public BondProgress Progress => Bond.ProgressFor(Points);

    public bool IsUnlocked(BondItem item) => Bond.IsUnlocked(item, Points, _profile.UnlockedItems.ToHashSet());

    /// <summary>
    /// Anything already in use stays available. Cookie's earlier versions had everything unlocked,
    /// so people who already wear a crown keep it.
    /// </summary>
    public void KeepInUseItemsUnlocked()
    {
        var inUse = _profile.Appearance.Accessories
            .Where(accessory => accessory.IsEnabled)
            .Select(accessory => BondItem.Accessory(accessory.Kind))
            .Append(BondItem.Coat(_profile.Appearance.Pattern));

        foreach (var item in inUse)
        {
            if (Bond.RequiredLevel(item) != null && !_profile.UnlockedItems.Contains(item.Id))
            {
                _profile.UnlockedItems.Add(item.Id);
            }
        }
    }

    /// <summary>Records a newly reached level, returning it once so it can be celebrated.</summary>
    public BondLevelUp? ClaimLevelUp()
    {
        int points = Points;
        var current = Bond.LevelFor(points);
        if (current.Index <= _profile.Statistics.CelebratedBondLevel) return null;

        var items = Bond.NewUnlocks(_profile.Statistics.CelebratedBondLevel, points);
        _profile.Statistics.CelebratedBondLevel = current.Index;
        foreach (var item in items)
        {
            if (!_profile.UnlockedItems.Contains(item.Id)) _profile.UnlockedItems.Add(item.Id);
        }
        return new BondLevelUp(current, items);
    }
}
