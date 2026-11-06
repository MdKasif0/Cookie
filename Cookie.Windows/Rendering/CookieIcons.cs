using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

/// <summary>Loads the rendered art under Resources/Sprites/Cookie, shared with the macOS app.</summary>
public static class CookieIcons
{
    private static readonly Dictionary<string, BitmapImage?> Loaded = new();

    public static BitmapImage? Art(string folder, string name)
    {
        string key = folder + "/" + name;
        if (Loaded.TryGetValue(key, out var cached)) return cached;

        string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sprites", "Cookie", folder, name + ".png");
        BitmapImage? bitmap = null;
        if (File.Exists(path))
        {
            try
            {
                bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.UriSource = new Uri(path, UriKind.Absolute);
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.EndInit();
                bitmap.Freeze();
            }
            catch (Exception exception) when (exception is IOException or NotSupportedException)
            {
                bitmap = null;
            }
        }
        Loaded[key] = bitmap;
        return bitmap;
    }

    /// <summary>A small image for a menu item's Icon slot.</summary>
    public static Image? MenuIcon(string name)
    {
        var art = Art("Icons", name);
        if (art == null) return null;
        var image = new Image { Source = art, Width = 18, Height = 18 };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
        return image;
    }

    public static string IconName(this ToyKind toy) => "item-" + toy.GetAssetName();
    public static string IconName(this FoodKind food) => "item-" + food.GetAssetName();

    public static string IconName(this EmoteId emote) => "emote-" + emote.ToString().ToLowerInvariant();
}
