using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

/// <summary>
/// Decodes sprite sheets, applies the fur tint, and hands out individual frames.
/// Only recently used sheets stay in memory: each one is several megabytes once decoded.
/// </summary>
public static class SpriteFrameCache
{
    private const int MaxLoadedSheets = 12;

    private static readonly Dictionary<(string Path, FurColor Fur), BitmapSource?[]> Loaded = new();
    private static readonly LinkedList<(string Path, FurColor Fur)> RecentlyUsed = new();

    public static SpriteSheetCatalog Catalog { get; } = new(
        Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sprites", "Cookie"));

    private static SpriteFrameRef? _restingFrame;
    private static bool _restingFrameResolved;

    /// <summary>A still idle frame for previews that have no animation running.</summary>
    public static SpriteFrameRef? RestingFrame
    {
        get
        {
            if (!_restingFrameResolved)
            {
                _restingFrameResolved = true;
                var sheet = Catalog.Find(CookieAnimationId.Idle.GetSpec());
                _restingFrame = sheet == null ? null : new SpriteFrameRef(sheet, 0, CookieDirection.Right, 0);
            }
            return _restingFrame;
        }
    }

    public static BitmapSource? GetFrame(SpriteSheet sheet, int cell, FurColor fur)
    {
        var key = (sheet.ImagePath, fur);
        if (!Loaded.TryGetValue(key, out var frames))
        {
            frames = LoadSheet(sheet, fur);
            Loaded[key] = frames;
            Evict();
        }

        RecentlyUsed.Remove(key);
        RecentlyUsed.AddFirst(key);

        return cell >= 0 && cell < frames.Length ? frames[cell] : null;
    }

    private static void Evict()
    {
        while (RecentlyUsed.Count >= MaxLoadedSheets)
        {
            var oldest = RecentlyUsed.Last!.Value;
            RecentlyUsed.RemoveLast();
            Loaded.Remove(oldest);
        }
    }

    private static BitmapSource?[] LoadSheet(SpriteSheet sheet, FurColor fur)
    {
        var frames = new BitmapSource?[sheet.Columns * sheet.Rows];
        try
        {
            var decoded = new BitmapImage();
            decoded.BeginInit();
            decoded.UriSource = new Uri(sheet.ImagePath, UriKind.Absolute);
            decoded.CacheOption = BitmapCacheOption.OnLoad;
            decoded.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            decoded.EndInit();
            decoded.Freeze();

            BitmapSource source = ApplyTint(decoded, fur);

            int cellWidth = source.PixelWidth / sheet.Columns;
            int cellHeight = source.PixelHeight / sheet.Rows;
            for (int index = 0; index < frames.Length; index++)
            {
                var area = new Int32Rect(index % sheet.Columns * cellWidth, index / sheet.Columns * cellHeight, cellWidth, cellHeight);
                var frame = new CroppedBitmap(source, area);
                frame.Freeze();
                frames[index] = frame;
            }
        }
        catch (Exception exception) when (exception is IOException or NotSupportedException or ArgumentException or UriFormatException)
        {
            // Missing or damaged art: callers fall back to the vector cat.
        }
        return frames;
    }

    /// <summary>Multiplies the tint over premultiplied pixels, the same blend the macOS app uses.</summary>
    private static BitmapSource ApplyTint(BitmapSource source, FurColor fur)
    {
        var converted = new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
        if (fur.GetPaintedArtTint() is not { } tint)
        {
            converted.Freeze();
            return converted;
        }

        int stride = converted.PixelWidth * 4;
        var pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);

        for (int i = 0; i < pixels.Length; i += 4)
        {
            pixels[i] = (byte)(pixels[i] * tint.B);
            pixels[i + 1] = (byte)(pixels[i + 1] * tint.G);
            pixels[i + 2] = (byte)(pixels[i + 2] * tint.R);
        }

        var tinted = BitmapSource.Create(
            converted.PixelWidth, converted.PixelHeight, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
        tinted.Freeze();
        return tinted;
    }
}
