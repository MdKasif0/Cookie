using System;
using System.Text.Json;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class CustomizationParityTests
{
    [Fact]
    public void FurColors_ExactTenOptions_WithValidPalettes()
    {
        var colors = Enum.GetValues<FurColor>();
        Assert.Equal(10, colors.Length);

        foreach (var color in colors)
        {
            var palette = CharacterPalette.FromFurColor(color);
            Assert.NotNull(palette.Fur);
            Assert.NotNull(palette.FurShade);
            Assert.NotNull(palette.Outline);
            Assert.NotNull(palette.InnerEar);
            Assert.NotNull(palette.Blush);
            Assert.NotNull(palette.Stripe);
            Assert.NotNull(palette.Eye);
        }
    }

    [Fact]
    public void FurPatterns_FourOptions()
    {
        var patterns = Enum.GetValues<FurPattern>();
        Assert.Equal(4, patterns.Length);
        Assert.Contains(FurPattern.None, patterns);
        Assert.Contains(FurPattern.Tuxedo, patterns);
        Assert.Contains(FurPattern.Points, patterns);
        Assert.Contains(FurPattern.Tabby, patterns);
    }

    [Fact]
    public void EyeAppearance_FiveColorsAndThreeStyles()
    {
        var colors = Enum.GetValues<EyeColor>();
        Assert.Equal(5, colors.Length);
        foreach (var color in colors)
        {
            var render = color.GetRenderColor();
            Assert.True(render.R > 0 || render.G > 0 || render.B > 0);
        }

        var styles = Enum.GetValues<EyeStyle>();
        Assert.Equal(3, styles.Length);
        Assert.Contains(EyeStyle.Round, styles);
        Assert.Contains(EyeStyle.Sleepy, styles);
        Assert.Contains(EyeStyle.Sparkle, styles);
    }

    [Fact]
    public void AnatomyVariations_EarsTailBody_ThreeEach()
    {
        Assert.Equal(3, Enum.GetValues<EarVariation>().Length);
        Assert.Equal(3, Enum.GetValues<TailVariation>().Length);
        Assert.Equal(3, Enum.GetValues<BodyVariation>().Length);
    }

    [Fact]
    public void Accessories_NineThemedKinds()
    {
        var accessories = Enum.GetValues<AccessoryKind>();
        Assert.Equal(9, accessories.Length);

        Assert.Contains(AccessoryKind.Collar, accessories);
        Assert.Contains(AccessoryKind.Bow, accessories);
        Assert.Contains(AccessoryKind.Hat, accessories);
        Assert.Contains(AccessoryKind.Glasses, accessories);
        Assert.Contains(AccessoryKind.Scarf, accessories);
        Assert.Contains(AccessoryKind.Crown, accessories);
        Assert.Contains(AccessoryKind.Bandana, accessories);
        Assert.Contains(AccessoryKind.Pumpkin, accessories);
        Assert.Contains(AccessoryKind.SantaHat, accessories);

        var config = new CookieAppearanceConfig();
        Assert.Equal(9, config.Accessories.Count);

        var glasses = config.Accessory(AccessoryKind.Glasses);
        glasses.IsEnabled = true;
        Assert.True(config.Accessory(AccessoryKind.Glasses).IsEnabled);
    }

    [Fact]
    public void Personality_SixPresets_WithMetrics()
    {
        var presets = Enum.GetValues<CookiePersonality>();
        Assert.Equal(6, presets.Length);

        foreach (var p in presets)
        {
            Assert.False(string.IsNullOrWhiteSpace(p.GetDisplayName()));
            Assert.False(string.IsNullOrWhiteSpace(p.GetSummary()));
            Assert.True(p.GetWalkSpeed() > 0);
            Assert.True(p.GetPetTolerance() > 0);
        }

        Assert.Equal(18.0, CookiePersonality.Sleepy.GetWalkSpeed());
        Assert.Equal(40.0, CookiePersonality.Energetic.GetWalkSpeed());
        Assert.Equal(2, CookiePersonality.Grumpy.GetPetTolerance());
        Assert.Equal(9, CookiePersonality.Affectionate.GetPetTolerance());
    }

    [Fact]
    public void Customization_JsonRoundTripSerialization()
    {
        var profile = new CookieProfile
        {
            DisplayName = "Mochi",
            Personality = CookiePersonality.Curious,
            Appearance = new CookieAppearanceConfig
            {
                FurColor = FurColor.WarmPeach,
                Pattern = FurPattern.Tuxedo,
                EyeColor = EyeColor.Honey,
                EyeStyle = EyeStyle.Sparkle,
                EarVariation = EarVariation.Tufted,
                TailVariation = TailVariation.Fluffy,
                BodyVariation = BodyVariation.Chubby
            }
        };

        profile.Appearance.Accessory(AccessoryKind.Crown).IsEnabled = true;

        string json = JsonSerializer.Serialize(profile);
        var restored = JsonSerializer.Deserialize<CookieProfile>(json);

        Assert.NotNull(restored);
        Assert.Equal("Mochi", restored.DisplayName);
        Assert.Equal(CookiePersonality.Curious, restored.Personality);
        Assert.Equal(FurColor.WarmPeach, restored.Appearance.FurColor);
        Assert.Equal(FurPattern.Tuxedo, restored.Appearance.Pattern);
        Assert.Equal(EyeColor.Honey, restored.Appearance.EyeColor);
        Assert.Equal(EyeStyle.Sparkle, restored.Appearance.EyeStyle);
        Assert.Equal(EarVariation.Tufted, restored.Appearance.EarVariation);
        Assert.Equal(TailVariation.Fluffy, restored.Appearance.TailVariation);
        Assert.Equal(BodyVariation.Chubby, restored.Appearance.BodyVariation);
        Assert.True(restored.Appearance.Accessory(AccessoryKind.Crown).IsEnabled);
    }
}
