using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum ToyKind
{
    YarnBall,
    Feather,
    ToyMouse,
    FishToy,
    Ball,
    Box
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FoodKind
{
    Fish,
    Milk,
    Chicken,
    Cookie
}

public static class WorldItemExtensions
{
    public static string GetDisplayName(this ToyKind toy) => toy switch
    {
        ToyKind.YarnBall => "Yarn Ball",
        ToyKind.Feather => "Feather",
        ToyKind.ToyMouse => "Toy Mouse",
        ToyKind.FishToy => "Fish Toy",
        ToyKind.Ball => "Ball",
        ToyKind.Box => "Cardboard Box",
        _ => toy.ToString()
    };

    public static string GetEmoji(this ToyKind toy) => toy switch
    {
        ToyKind.YarnBall => "🧶",
        ToyKind.Feather => "🪶",
        ToyKind.ToyMouse => "🐭",
        ToyKind.FishToy => "🐟",
        ToyKind.Ball => "🎾",
        ToyKind.Box => "📦",
        _ => string.Empty
    };

    public static string GetDisplayName(this FoodKind food) => food.ToString();

    public static string GetEmoji(this FoodKind food) => food switch
    {
        FoodKind.Fish => "🐟",
        FoodKind.Milk => "🥛",
        FoodKind.Chicken => "🍗",
        FoodKind.Cookie => "🍪",
        _ => string.Empty
    };

    /// <summary>File name, without extension, of the item's art in Resources/WorldItems.</summary>
    public static string GetAssetName(this ToyKind toy) => toy switch
    {
        ToyKind.YarnBall => "yarnBall",
        ToyKind.Feather => "feather",
        ToyKind.ToyMouse => "toyMouse",
        ToyKind.FishToy => "fishToy",
        ToyKind.Ball => "ball",
        ToyKind.Box => "box",
        _ => "ball"
    };

    public static string GetAssetName(this FoodKind food) => "food-" + food.ToString().ToLowerInvariant();
}

/// <summary>
/// An item placed on the desktop for Cookie. X is the item's horizontal center
/// and GroundY the line its bottom sits on, both in desktop DIPs.
/// </summary>
public record WorldItem(ToyKind? Toy, FoodKind? Food, double X, double GroundY)
{
    public bool IsBox => Toy == ToyKind.Box;
    public bool IsFood => Food.HasValue;
    public string AssetName => Food?.GetAssetName() ?? Toy?.GetAssetName() ?? "ball";
    public string DisplayName => Food?.GetDisplayName() ?? Toy?.GetDisplayName() ?? string.Empty;
}
