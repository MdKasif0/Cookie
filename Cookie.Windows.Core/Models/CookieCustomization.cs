using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FurColor
{
    WarmWhite,
    Cream,
    Ivory,
    SoftBeige,
    MutedSage,
    SoftGreen,
    WarmPeach,
    SoftOrange,
    MutedBrown,
    Charcoal
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum EyeColor
{
    Charcoal,
    WarmBrown,
    Honey,
    Moss,
    Rust
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum FurPattern
{
    None,
    Tuxedo,
    Points,
    Tabby
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum EyeStyle
{
    Round,
    Sleepy,
    Sparkle
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum BodyVariation
{
    Classic,
    Chubby,
    Petite
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum EarVariation
{
    Normal,
    Rounded,
    Tufted
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum TailVariation
{
    Normal,
    Fluffy,
    Curly
}

public class CharacterPalette
{
    public CookieColor Fur { get; set; }
    public CookieColor FurShade { get; set; }
    public CookieColor Outline { get; set; }
    public CookieColor InnerEar { get; set; }
    public CookieColor Blush { get; set; }
    public CookieColor Stripe { get; set; }
    public CookieColor Eye { get; set; }

    public CharacterPalette(CookieColor fur, CookieColor furShade, CookieColor outline, CookieColor innerEar, CookieColor blush, CookieColor stripe, CookieColor eye)
    {
        Fur = fur;
        FurShade = furShade;
        Outline = outline;
        InnerEar = innerEar;
        Blush = blush;
        Stripe = stripe;
        Eye = eye;
    }

    public static CharacterPalette FromFurColor(FurColor furColor)
    {
        return furColor switch
        {
            FurColor.WarmWhite => new CharacterPalette(
                CookieColor.FromRgb(247, 240, 224),
                CookieColor.FromRgb(235, 222, 199),
                CookieColor.FromRgb(122, 107, 89),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(184, 148, 107),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.Cream or FurColor.Ivory => new CharacterPalette(
                CookieColor.FromRgb(245, 230, 196),
                CookieColor.FromRgb(230, 209, 168),
                CookieColor.FromRgb(115, 99, 82),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(184, 148, 107),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.SoftBeige => new CharacterPalette(
                CookieColor.FromRgb(230, 209, 173),
                CookieColor.FromRgb(209, 186, 145),
                CookieColor.FromRgb(107, 92, 74),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(184, 148, 107),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.MutedSage or FurColor.SoftGreen => new CharacterPalette(
                CookieColor.FromRgb(194, 204, 171),
                CookieColor.FromRgb(168, 181, 145),
                CookieColor.FromRgb(97, 107, 84),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(140, 153, 120),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.WarmPeach or FurColor.SoftOrange => new CharacterPalette(
                CookieColor.FromRgb(242, 199, 158),
                CookieColor.FromRgb(227, 173, 128),
                CookieColor.FromRgb(120, 87, 61),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(184, 148, 107),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.MutedBrown => new CharacterPalette(
                CookieColor.FromRgb(158, 130, 97),
                CookieColor.FromRgb(133, 107, 77),
                CookieColor.FromRgb(66, 54, 41),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(115, 94, 71),
                CookieColor.FromRgb(59, 51, 46)),

            FurColor.Charcoal => new CharacterPalette(
                CookieColor.FromRgb(107, 102, 97),
                CookieColor.FromRgb(87, 82, 77),
                CookieColor.FromRgb(41, 38, 36),
                CookieColor.FromRgb(240, 179, 153),
                CookieColor.FromRgb(242, 184, 161),
                CookieColor.FromRgb(82, 77, 71),
                CookieColor.FromRgb(26, 23, 20)),

            _ => FromFurColor(FurColor.WarmWhite)
        };
    }
}

public class CookieAppearanceConfig
{
    public FurColor FurColor { get; set; } = FurColor.Cream;
    public FurPattern Pattern { get; set; } = FurPattern.None;
    public EyeColor EyeColor { get; set; } = EyeColor.Charcoal;
    public EyeStyle EyeStyle { get; set; } = EyeStyle.Round;
    public BodyVariation BodyVariation { get; set; } = BodyVariation.Classic;
    public EarVariation EarVariation { get; set; } = EarVariation.Normal;
    public TailVariation TailVariation { get; set; } = TailVariation.Normal;
    public string? SelectedAccessoryId { get; set; } = null;
}
