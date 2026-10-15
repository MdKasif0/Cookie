using System.Text.Json.Serialization;
using System.Windows.Media;

namespace Cookie.Windows.Models;

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
    public Color Fur { get; set; }
    public Color FurShade { get; set; }
    public Color Outline { get; set; }
    public Color InnerEar { get; set; }
    public Color Blush { get; set; }
    public Color Stripe { get; set; }
    public Color Eye { get; set; }

    public CharacterPalette(Color fur, Color furShade, Color outline, Color innerEar, Color blush, Color stripe, Color eye)
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
                Color.FromRgb(247, 240, 224),
                Color.FromRgb(235, 222, 199),
                Color.FromRgb(122, 107, 89),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(184, 148, 107),
                Color.FromRgb(59, 51, 46)),

            FurColor.Cream or FurColor.Ivory => new CharacterPalette(
                Color.FromRgb(245, 230, 196),
                Color.FromRgb(230, 209, 168),
                Color.FromRgb(115, 99, 82),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(184, 148, 107),
                Color.FromRgb(59, 51, 46)),

            FurColor.SoftBeige => new CharacterPalette(
                Color.FromRgb(230, 209, 173),
                Color.FromRgb(209, 186, 145),
                Color.FromRgb(107, 92, 74),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(184, 148, 107),
                Color.FromRgb(59, 51, 46)),

            FurColor.MutedSage or FurColor.SoftGreen => new CharacterPalette(
                Color.FromRgb(194, 204, 171),
                Color.FromRgb(168, 181, 145),
                Color.FromRgb(97, 107, 84),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(140, 153, 120),
                Color.FromRgb(59, 51, 46)),

            FurColor.WarmPeach or FurColor.SoftOrange => new CharacterPalette(
                Color.FromRgb(242, 199, 158),
                Color.FromRgb(227, 173, 128),
                Color.FromRgb(120, 87, 61),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(184, 148, 107),
                Color.FromRgb(59, 51, 46)),

            FurColor.MutedBrown => new CharacterPalette(
                Color.FromRgb(158, 130, 97),
                Color.FromRgb(133, 107, 77),
                Color.FromRgb(66, 54, 41),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(115, 94, 71),
                Color.FromRgb(59, 51, 46)),

            FurColor.Charcoal => new CharacterPalette(
                Color.FromRgb(107, 102, 97),
                Color.FromRgb(87, 82, 77),
                Color.FromRgb(41, 38, 36),
                Color.FromRgb(240, 179, 153),
                Color.FromRgb(242, 184, 161),
                Color.FromRgb(82, 77, 71),
                Color.FromRgb(26, 23, 20)),

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
