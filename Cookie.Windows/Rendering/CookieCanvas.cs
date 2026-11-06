using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

public class CookieCanvas : FrameworkElement
{
    private CookiePose _currentPose = new();
    private CharacterPalette _palette = CharacterPalette.FromFurColor(FurColor.Cream);
    private CookieAppearanceConfig _appearance = new();
    private CookieDirection _direction = CookieDirection.Right;
    private double _scale = 1.0;
    private Emote? _activeEmote;
    private BitmapImage? _emoteImage;
    private SpriteFrameRef? _spriteFrame;

    public CookieCanvas()
    {
        Width = CookieSpriteRenderer.CanvasSize.Width;
        Height = CookieSpriteRenderer.CanvasSize.Height;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
    }

    public void UpdateSpriteFrame(SpriteFrameRef frame)
    {
        _spriteFrame = frame;
        if (!_appearance.RequiresVectorRenderer)
        {
            InvalidateVisual();
        }
    }

    public void UpdatePose(CookiePose pose, CookieDirection direction)
    {
        _currentPose = pose;
        _direction = direction;
        if (_appearance.RequiresVectorRenderer || (_spriteFrame == null && SpriteFrameCache.RestingFrame == null))
        {
            InvalidateVisual();
        }
    }

    public void UpdatePalette(CharacterPalette palette)
    {
        _palette = palette;
        InvalidateVisual();
    }

    public void UpdateAppearance(CookieAppearanceConfig appearance)
    {
        _appearance = appearance;
        _palette = CharacterPalette.FromFurColor(appearance.FurColor);
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

        // Draw in the 180pt canvas space, whatever size this control is laid out at.
        double canvasWidth = CookieSpriteRenderer.CanvasSize.Width;
        double renderScale = ActualWidth > 0 ? ActualWidth / canvasWidth : _scale;
        bool isScaled = Math.Abs(renderScale - 1.0) > 0.001;
        if (isScaled)
        {
            dc.PushTransform(new ScaleTransform(renderScale, renderScale));
        }

        if (!_appearance.RequiresVectorRenderer && TryDrawPaintedFrame(dc))
        {
            // The painted cat was drawn.
        }
        else
        {
            var characterDrawing = CookieSpriteRenderer.Render(_currentPose, _palette, _appearance, _direction);
            dc.DrawDrawing(characterDrawing);
        }

        if (_activeEmote != null)
        {
            DrawEmoteOverlay(dc);
        }

        if (isScaled)
        {
            dc.Pop();
        }
    }

    private bool TryDrawPaintedFrame(DrawingContext dc)
    {
        var frameRef = _spriteFrame ?? SpriteFrameCache.RestingFrame;
        if (frameRef == null) return false;

        var bitmap = SpriteFrameCache.GetFrame(frameRef.Sheet, frameRef.Cell, _appearance.FurColor);
        if (bitmap == null) return false;

        double size = CookieSpriteRenderer.CanvasSize.Width;
        var transform = new TransformGroup();

        var (bodyX, bodyY) = _appearance.BodyVariation switch
        {
            BodyVariation.Chubby => (1.05, 1.02),
            BodyVariation.Petite => (0.94, 0.96),
            _ => (1.0, 1.0)
        };
        transform.Children.Add(new ScaleTransform(bodyX, bodyY, size / 2, size));

        if (Math.Abs(frameRef.HeadTilt) > 0.001)
        {
            transform.Children.Add(new RotateTransform(-frameRef.HeadTilt, size / 2, size * 0.94));
        }
        if (frameRef.Direction == CookieDirection.Left)
        {
            transform.Children.Add(new ScaleTransform(-1, 1, size / 2, size / 2));
        }

        dc.PushTransform(transform);
        dc.DrawImage(bitmap, new Rect(0, 0, size, size));
        if (SpriteSheetCatalog.IsDrawnFromBasePose(frameRef.Sheet.Name))
        {
            CookieSpriteRenderer.RenderAccessoriesOnPaintedArt(dc, _appearance);
        }
        dc.Pop();
        return true;
    }

    private void DrawEmoteOverlay(DrawingContext dc)
    {
        double bubbleX = _direction == CookieDirection.Right ? 130 : 16;
        double bubbleY = 22;

        // Special heart effect for Love emote (warm peach / muted-coral heart)
        if (_activeEmote?.Id == EmoteId.Love)
        {
            DrawLoveHeartEffect(dc, bubbleX, bubbleY);
        }

        if (_emoteImage != null)
        {
            dc.DrawImage(_emoteImage, new Rect(bubbleX, bubbleY, 36, 36));
        }
        else if (_activeEmote != null)
        {
            var bgBrush = new SolidColorBrush(Color.FromArgb(240, 253, 251, 247));
            var borderPen = new Pen(new SolidColorBrush(Color.FromRgb(224, 135, 68)), 1.5);
            borderPen.Freeze();
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

    private void DrawLoveHeartEffect(DrawingContext dc, double bx, double by)
    {
        // Gentle floating warm peach / muted-coral heart above Cookie
        double hx = _direction == CookieDirection.Right ? 110 : 70;
        double hy = 18;

        var heartGeo = new StreamGeometry();
        using (var ctx = heartGeo.Open())
        {
            ctx.BeginFigure(new Point(hx, hy + 10), true, true);
            ctx.BezierTo(new Point(hx - 12, hy + 2), new Point(hx - 12, hy - 8), new Point(hx, hy - 4), true, true);
            ctx.BezierTo(new Point(hx + 12, hy - 8), new Point(hx + 12, hy + 2), new Point(hx, hy + 10), true, true);
        }
        heartGeo.Freeze();

        var heartBrush = new SolidColorBrush(Color.FromArgb(230, 224, 135, 68)); // Warm muted coral
        var heartPen = new Pen(new SolidColorBrush(Color.FromArgb(180, 198, 122, 56)), 1.5);
        heartPen.Freeze();
        dc.DrawGeometry(heartBrush, heartPen, heartGeo);

        // Small secondary baby heart
        var babyHeartGeo = new StreamGeometry();
        using (var ctx = babyHeartGeo.Open())
        {
            double bx2 = hx + 14;
            double by2 = hy - 8;
            ctx.BeginFigure(new Point(bx2, by2 + 5), true, true);
            ctx.BezierTo(new Point(bx2 - 6, by2 + 1), new Point(bx2 - 6, by2 - 4), new Point(bx2, by2 - 2), true, true);
            ctx.BezierTo(new Point(bx2 + 6, by2 - 4), new Point(bx2 + 6, by2 + 1), new Point(bx2, by2 + 5), true, true);
        }
        babyHeartGeo.Freeze();
        var babyBrush = new SolidColorBrush(Color.FromArgb(200, 242, 186, 140)); // Warm peach
        dc.DrawGeometry(babyBrush, null, babyHeartGeo);
    }

    protected override HitTestResult HitTestCore(PointHitTestParameters hitTestParameters)
    {
        Point pt = hitTestParameters.HitPoint;
        double cx = ActualWidth / 2.0;
        double cy = ActualHeight / 2.0;

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
