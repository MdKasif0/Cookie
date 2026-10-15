using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cookie.Windows.Models;

namespace Cookie.Windows.Rendering;

public class CookieCanvas : FrameworkElement
{
    private CookiePose _currentPose = new();
    private CharacterPalette _palette = CharacterPalette.FromFurColor(FurColor.Cream);
    private CookieDirection _direction = CookieDirection.Right;
    private double _scale = 1.0;
    private Emote? _activeEmote;
    private BitmapImage? _emoteImage;

    public CookieCanvas()
    {
        Width = CookieSpriteRenderer.CanvasSize.Width;
        Height = CookieSpriteRenderer.CanvasSize.Height;
    }

    public void UpdatePose(CookiePose pose, CookieDirection direction)
    {
        _currentPose = pose;
        _direction = direction;
        InvalidateVisual();
    }

    public void UpdatePalette(CharacterPalette palette)
    {
        _palette = palette;
        InvalidateVisual();
    }

    public void UpdateScale(double scale)
    {
        _scale = Math.Clamp(scale, 0.7, 1.4);
        Width = CookieSpriteRenderer.CanvasSize.Width * _scale;
        Height = CookieSpriteRenderer.CanvasSize.Height * _scale;
        InvalidateVisual();
    }

    public void SetActiveEmote(Emote? emote)
    {
        _activeEmote = emote;
        _emoteImage = null;

        if (emote != null)
        {
            // Attempt to load corresponding emote PNG
            string emoteFolder = emote.Id switch
            {
                EmoteId.Wave => "Wave",
                EmoteId.Happy => "Happy",
                EmoteId.Love => "Love",
                EmoteId.Sleepy => "Sleepy",
                EmoteId.Playful => "Playful",
                _ => "Happy"
            };

            string pngName = emoteFolder.ToLowerInvariant() + ".png";
            string relativePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sprites", "Cookie", "Emotes", emoteFolder, pngName);

            if (File.Exists(relativePath))
            {
                try
                {
                    var bmp = new BitmapImage();
                    bmp.BeginInit();
                    bmp.UriSource = new Uri(relativePath, UriKind.Absolute);
                    bmp.CacheOption = BitmapCacheOption.OnLoad;
                    bmp.EndInit();
                    bmp.Freeze();
                    _emoteImage = bmp;
                }
                catch
                {
                    _emoteImage = null;
                }
            }
        }

        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        // Apply scale transform if needed
        if (Math.Abs(_scale - 1.0) > 0.001)
        {
            dc.PushTransform(new ScaleTransform(_scale, _scale));
        }

        // Draw character vector drawing
        var characterDrawing = CookieSpriteRenderer.Render(_currentPose, _palette, _direction);
        dc.DrawDrawing(characterDrawing);

        // Draw emote bubble or icon if active
        if (_activeEmote != null)
        {
            DrawEmoteOverlay(dc);
        }

        if (Math.Abs(_scale - 1.0) > 0.001)
        {
            dc.Pop();
        }
    }

    private void DrawEmoteOverlay(DrawingContext dc)
    {
        double bubbleX = _direction == CookieDirection.Right ? 130 : 20;
        double bubbleY = 25;

        if (_emoteImage != null)
        {
            dc.DrawImage(_emoteImage, new Rect(bubbleX, bubbleY, 36, 36));
        }
        else if (_activeEmote != null)
        {
            // Draw warm background badge with emoji
            var bgBrush = new SolidColorBrush(Color.FromArgb(235, 253, 251, 247));
            var borderPen = new Pen(new SolidColorBrush(Color.FromRgb(224, 135, 68)), 1.5);
            dc.DrawRoundedRectangle(bgBrush, borderPen, new Rect(bubbleX, bubbleY, 34, 34), 8, 8);

            var formattedText = new FormattedText(
                _activeEmote.Emoji,
                System.Globalization.CultureInfo.InvariantCulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI Emoji"),
                18,
                Brushes.Black,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);

            dc.DrawText(formattedText, new Point(bubbleX + 6, bubbleY + 5));
        }
    }

    protected override HitTestResult HitTestCore(PointHitTestParameters hitTestParameters)
    {
        Point pt = hitTestParameters.HitPoint;
        double cx = ActualWidth / 2.0;
        double cy = ActualHeight / 2.0;

        // Approximate character silhouette ellipse for accurate hit testing
        double rx = (55.0 * _scale);
        double ry = (55.0 * _scale);

        double dx = (pt.X - cx) / rx;
        double dy = (pt.Y - cy) / ry;

        if (dx * dx + dy * dy <= 1.0)
        {
            return new PointHitTestResult(this, pt);
        }

        return base.HitTestCore(hitTestParameters);
    }
}
