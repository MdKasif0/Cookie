using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cookie.Windows.Core.Imaging;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

/// <summary>A set of frames for Photo Mode: one for a still, several for a loop.</summary>
public sealed record PhotoClip(IReadOnlyList<BitmapSource> Frames, double Fps)
{
    public bool IsStill => Frames.Count <= 1;
}

/// <summary>Renders Cookie, as she looks right now, to images for sharing, using the same canvas she is drawn with on the desktop.</summary>
public static class PhotoRenderer
{
    /// <summary>Frames are the app's 180 DIP canvas at 2x.</summary>
    public const int FrameSide = 360;

    public static PhotoClip? Render(PhotoPose pose, CookieAppearanceConfig appearance, PhotoBackdrop backdrop)
    {
        var spec = pose.Animation.GetSpec();
        var canvas = new CookieCanvas { Width = FrameSide, Height = FrameSide };
        canvas.UpdateAppearance(appearance);

        var frames = new List<BitmapSource>();
        double fps;

        var sheet = SpriteFrameCache.Catalog.Find(spec);
        if (!appearance.RequiresVectorRenderer && sheet != null)
        {
            // Some sheets repeat their frames to fill an emote's time; a shared loop needs one cycle.
            int cycle = PhotoClips.CycleLength(sheet.Frames);
            for (int i = 0; i < cycle; i++)
            {
                canvas.UpdateSpriteFrame(new SpriteFrameRef(sheet, sheet.Frames[i], CookieDirection.Right, 0));
                frames.Add(Capture(canvas, backdrop));
            }
            fps = sheet.Fps;
        }
        else
        {
            // Coats, eyes, ears and tails only exist in the vector drawing, so poses come from that.
            var poses = CookiePoseCatalog.GetFrames(spec.SheetName) ?? CookiePoseCatalog.GetFrames("idle");
            if (poses == null) return null;
            foreach (var cookiePose in poses)
            {
                canvas.UpdatePose(cookiePose, CookieDirection.Right);
                frames.Add(Capture(canvas, backdrop));
            }
            fps = spec.Fps;
        }

        return frames.Count == 0 ? null : new PhotoClip(frames, fps);
    }

    private static BitmapSource Capture(CookieCanvas canvas, PhotoBackdrop backdrop)
    {
        canvas.Measure(new Size(FrameSide, FrameSide));
        canvas.Arrange(new Rect(0, 0, FrameSide, FrameSide));
        canvas.UpdateLayout();

        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            var bounds = new Rect(0, 0, FrameSide, FrameSide);
            if (backdrop.GetColor() is { } color)
            {
                context.DrawRectangle(new SolidColorBrush(Color.FromRgb(color.R, color.G, color.B)), null, bounds);
            }
            context.DrawRectangle(new VisualBrush(canvas), null, bounds);
        }

        var bitmap = new RenderTargetBitmap(FrameSide, FrameSide, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    /// <summary>Straight (not premultiplied) RGBA pixels, which is what the GIF encoder wants.</summary>
    public static RgbaFrame ToRgba(BitmapSource source)
    {
        var converted = source.Format == PixelFormats.Pbgra32 ? source : new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
        int width = converted.PixelWidth, height = converted.PixelHeight;
        var bgra = new byte[width * height * 4];
        converted.CopyPixels(bgra, width * 4, 0);

        var rgba = new byte[bgra.Length];
        for (int i = 0; i < bgra.Length; i += 4)
        {
            int alpha = bgra[i + 3];
            if (alpha == 0) continue;
            rgba[i] = (byte)Math.Min(255, bgra[i + 2] * 255 / alpha);
            rgba[i + 1] = (byte)Math.Min(255, bgra[i + 1] * 255 / alpha);
            rgba[i + 2] = (byte)Math.Min(255, bgra[i] * 255 / alpha);
            rgba[i + 3] = (byte)alpha;
        }
        return new RgbaFrame(width, height, rgba);
    }
}
