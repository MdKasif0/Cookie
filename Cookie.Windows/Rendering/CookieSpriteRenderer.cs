using System;
using System.Windows;
using System.Windows.Media;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

/// <summary>
/// Authoritative procedural vector renderer for Cookie.
/// Exactly preserves Cookie's face, eye design, ear shape, body proportions,
/// tail curve, colors, and overall silhouette from the native macOS application,
/// with full support for fur patterns, ear/tail variations, eye styles/colors, and accessories.
/// </summary>
public static class CookieSpriteRenderer
{
    public static readonly Size CanvasSize = new(180, 180);

    public static DrawingGroup Render(
        CookiePose pose,
        CharacterPalette palette,
        CookieDirection direction = CookieDirection.Right)
    {
        return Render(pose, palette, null, direction);
    }

    public static DrawingGroup Render(
        CookiePose pose,
        CharacterPalette palette,
        CookieAppearanceConfig? appearance,
        CookieDirection direction = CookieDirection.Right)
    {
        var group = new DrawingGroup();
        appearance ??= new CookieAppearanceConfig();

        using (var dc = group.Open())
        {
            double centerX = CanvasSize.Width / 2.0;
            double centerY = CanvasSize.Height / 2.0;

            if (direction == CookieDirection.Left)
            {
                dc.PushTransform(new ScaleTransform(-1, 1, centerX, centerY));
            }

            // Body variation scale adjustments
            double bodyScaleX = 1.0;
            double bodyScaleY = 1.0;
            switch (appearance.BodyVariation)
            {
                case BodyVariation.Chubby:
                    bodyScaleX = 1.05;
                    bodyScaleY = 1.02;
                    break;
                case BodyVariation.Petite:
                    bodyScaleX = 0.94;
                    bodyScaleY = 0.96;
                    break;
            }

            double wpfBodyY = -pose.BodyY;
            double scaleX = (1.0 + (1.0 - pose.Squash) * 0.7) * bodyScaleX;
            double scaleY = pose.Squash * bodyScaleY;

            var charTransform = new TransformGroup();
            charTransform.Children.Add(new TranslateTransform(0, wpfBodyY));
            charTransform.Children.Add(new ScaleTransform(scaleX, scaleY, centerX, centerY + wpfBodyY));
            dc.PushTransform(charTransform);

            // 1. Tail (rendered behind body)
            RenderTail(dc, centerX, centerY, pose.TailAngle, palette, appearance.TailVariation);

            // 2. Body & Fur Pattern
            RenderBody(dc, centerX, centerY, palette, appearance.Pattern);

            // 3. Paws
            RenderPaws(dc, centerX, centerY, pose, palette, appearance.Pattern);

            // 4. Neck Accessories (rendered between body and head)
            RenderNeckAccessories(dc, centerX, centerY, appearance);

            // 5. Head, Ears, Face, Forehead Stripes & Head Accessories
            RenderHead(dc, centerX, centerY, pose, palette, appearance);

            dc.Pop();

            if (direction == CookieDirection.Left)
            {
                dc.Pop();
            }
        }

        return group;
    }

    private static void RenderTail(
        DrawingContext dc,
        double cx,
        double cy,
        double tailAngleDeg,
        CharacterPalette palette,
        TailVariation tailVariation)
    {
        double tailRootX = cx + 26;
        double tailRootY = cy + 20;

        dc.PushTransform(new RotateTransform(-tailAngleDeg, tailRootX, tailRootY));

        double furLineWidth = tailVariation switch
        {
            TailVariation.Fluffy => 16.0,
            TailVariation.Curly => 11.0,
            _ => 10.0
        };

        double outlineLineWidth = furLineWidth + 5.0;

        var pathGeo = new StreamGeometry();
        using (var ctx = pathGeo.Open())
        {
            ctx.BeginFigure(new Point(tailRootX, tailRootY), false, false);
            if (tailVariation == TailVariation.Curly)
            {
                // Coiled upward tail
                ctx.BezierTo(
                    new Point(tailRootX + 16, tailRootY - 18),
                    new Point(tailRootX + 38, tailRootY - 14),
                    new Point(tailRootX + 42, tailRootY + 4),
                    true, true);
                ctx.BezierTo(
                    new Point(tailRootX + 44, tailRootY + 16),
                    new Point(tailRootX + 32, tailRootY + 26),
                    new Point(tailRootX + 22, tailRootY + 22),
                    true, true);
            }
            else
            {
                // Standard & Fluffy curved tail
                ctx.BezierTo(
                    new Point(tailRootX + 14, tailRootY - 12),
                    new Point(tailRootX + 30, tailRootY - 10),
                    new Point(tailRootX + 36, tailRootY + 2),
                    true, true);
                ctx.BezierTo(
                    new Point(tailRootX + 42, tailRootY + 12),
                    new Point(tailRootX + 50, tailRootY + 20),
                    new Point(tailRootX + 46, tailRootY + 30),
                    true, true);
            }
        }
        pathGeo.Freeze();

        var outlinePen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), outlineLineWidth)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        outlinePen.Freeze();
        dc.DrawGeometry(null, outlinePen, pathGeo);

        var furPen = new Pen(new SolidColorBrush(palette.Fur.ToMediaColor()), furLineWidth)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        furPen.Freeze();
        dc.DrawGeometry(null, furPen, pathGeo);

        Point tipCenter = tailVariation == TailVariation.Curly
            ? new Point(tailRootX + 22, tailRootY + 22)
            : new Point(tailRootX + 46, tailRootY + 30);

        double tipRadius = tailVariation == TailVariation.Fluffy ? 9.0 : 6.5;
        var tipPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 3);
        tipPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.FurShade.ToMediaColor()), tipPen, tipCenter, tipRadius, tipRadius);

        dc.Pop();
    }

    private static void RenderBody(
        DrawingContext dc,
        double cx,
        double cy,
        CharacterPalette palette,
        FurPattern pattern)
    {
        var bodyCenter = new Point(cx, cy + 26);
        var bodyPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 4);
        bodyPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.Fur.ToMediaColor()), bodyPen, bodyCenter, 44, 36);

        // Pattern Overlays
        if (pattern == FurPattern.Tuxedo)
        {
            // Crisp white chest bib
            var bibBrush = new SolidColorBrush(Color.FromRgb(250, 248, 244));
            dc.DrawEllipse(bibBrush, null, new Point(cx, cy + 28), 24, 22);
        }
        else if (pattern == FurPattern.Tabby)
        {
            // Gentle side body stripes
            var stripeBrush = new SolidColorBrush(palette.Stripe.ToMediaColor()) { Opacity = 0.55 };
            var stripePen = new Pen(stripeBrush, 3.5)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round
            };
            stripePen.Freeze();

            dc.DrawLine(stripePen, new Point(cx - 30, cy + 18), new Point(cx - 20, cy + 22));
            dc.DrawLine(stripePen, new Point(cx - 34, cy + 26), new Point(cx - 22, cy + 29));
            dc.DrawLine(stripePen, new Point(cx - 30, cy + 34), new Point(cx - 20, cy + 36));

            dc.DrawLine(stripePen, new Point(cx + 30, cy + 18), new Point(cx + 20, cy + 22));
            dc.DrawLine(stripePen, new Point(cx + 34, cy + 26), new Point(cx + 22, cy + 29));
            dc.DrawLine(stripePen, new Point(cx + 30, cy + 34), new Point(cx + 20, cy + 36));
        }
    }

    private static void RenderPaws(
        DrawingContext dc,
        double cx,
        double cy,
        CookiePose pose,
        CharacterPalette palette,
        FurPattern pattern)
    {
        double pawY = cy + 58 - pose.PawLift;
        var pawPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 3.5);
        pawPen.Freeze();

        // Points pattern gives darker shaded paws
        var pawBrush = (pattern == FurPattern.Points)
            ? new SolidColorBrush(palette.FurShade.ToMediaColor())
            : new SolidColorBrush(palette.Fur.ToMediaColor());

        foreach (double side in new[] { -1.0, 1.0 })
        {
            double pawX = cx + side * 16 + pose.PawOffsetX;
            dc.DrawEllipse(pawBrush, pawPen, new Point(pawX, pawY), 10, 6.5);
        }
    }

    private static void RenderNeckAccessories(
        DrawingContext dc,
        double cx,
        double cy,
        CookieAppearanceConfig appearance)
    {
        double neckX = cx;
        double neckY = cy + 10;

        // Scarf
        var scarf = appearance.Accessory(AccessoryKind.Scarf);
        if (scarf.IsEnabled)
        {
            dc.PushTransform(new TranslateTransform(0, scarf.OffsetY * 20));
            // Wrap band
            var scarfBrush = new SolidColorBrush(Color.FromRgb(160, 178, 148)); // Warm sage
            var scarfPen = new Pen(new SolidColorBrush(Color.FromRgb(112, 128, 97)), 2);
            scarfPen.Freeze();
            dc.DrawRoundedRectangle(scarfBrush, scarfPen, new Rect(neckX - 28, neckY - 5, 56, 15), 6, 6);

            // Draping tail
            var tailGeo = new StreamGeometry();
            using (var ctx = tailGeo.Open())
            {
                ctx.BeginFigure(new Point(neckX + 8, neckY + 8), true, true);
                ctx.LineTo(new Point(neckX + 22, neckY + 10), true, true);
                ctx.LineTo(new Point(neckX + 18, neckY + 36), true, true);
                ctx.LineTo(new Point(neckX + 6, neckY + 34), true, true);
            }
            tailGeo.Freeze();
            dc.DrawGeometry(scarfBrush, scarfPen, tailGeo);
            dc.Pop();
        }

        // Bandana
        var bandana = appearance.Accessory(AccessoryKind.Bandana);
        if (bandana.IsEnabled)
        {
            dc.PushTransform(new TranslateTransform(0, bandana.OffsetY * 20));
            var bandanaBrush = new SolidColorBrush(Color.FromRgb(242, 186, 140)); // Warm peach
            var bandanaPen = new Pen(new SolidColorBrush(Color.FromRgb(160, 112, 71)), 2);
            bandanaPen.Freeze();

            var triGeo = new StreamGeometry();
            using (var ctx = triGeo.Open())
            {
                ctx.BeginFigure(new Point(neckX - 22, neckY - 2), true, true);
                ctx.LineTo(new Point(neckX + 22, neckY - 2), true, true);
                ctx.LineTo(new Point(neckX, neckY + 22), true, true);
            }
            triGeo.Freeze();
            dc.DrawGeometry(bandanaBrush, bandanaPen, triGeo);

            // Knot
            dc.DrawEllipse(bandanaBrush, bandanaPen, new Point(neckX, neckY - 2), 4, 4);
            dc.Pop();
        }

        // Collar
        var collar = appearance.Accessory(AccessoryKind.Collar);
        if (collar.IsEnabled)
        {
            dc.PushTransform(new TranslateTransform(0, collar.OffsetY * 20));
            var collarBrush = new SolidColorBrush(Color.FromRgb(232, 158, 102)); // Caramel orange
            var collarPen = new Pen(new SolidColorBrush(Color.FromRgb(140, 92, 56)), 1.8);
            collarPen.Freeze();
            dc.DrawRoundedRectangle(collarBrush, collarPen, new Rect(neckX - 24, neckY - 2, 48, 10), 4, 4);

            // Bell / tag
            var bellBrush = new SolidColorBrush(Color.FromRgb(245, 204, 112));
            var bellPen = new Pen(new SolidColorBrush(Color.FromRgb(158, 122, 61)), 1.2);
            bellPen.Freeze();
            dc.DrawEllipse(bellBrush, bellPen, new Point(neckX, neckY + 11), 5, 5);
            dc.Pop();
        }

        // Bow
        var bow = appearance.Accessory(AccessoryKind.Bow);
        if (bow.IsEnabled)
        {
            dc.PushTransform(new TranslateTransform(0, bow.OffsetY * 20));
            var bowBrush = new SolidColorBrush(Color.FromRgb(168, 186, 153)); // Sage green
            var bowPen = new Pen(new SolidColorBrush(Color.FromRgb(112, 128, 97)), 1.8);
            bowPen.Freeze();

            // Left wing
            var leftWing = new StreamGeometry();
            using (var ctx = leftWing.Open())
            {
                ctx.BeginFigure(new Point(neckX, neckY + 4), true, true);
                ctx.LineTo(new Point(neckX - 16, neckY - 3), true, true);
                ctx.LineTo(new Point(neckX - 16, neckY + 11), true, true);
            }
            leftWing.Freeze();
            dc.DrawGeometry(bowBrush, bowPen, leftWing);

            // Right wing
            var rightWing = new StreamGeometry();
            using (var ctx = rightWing.Open())
            {
                ctx.BeginFigure(new Point(neckX, neckY + 4), true, true);
                ctx.LineTo(new Point(neckX + 16, neckY - 3), true, true);
                ctx.LineTo(new Point(neckX + 16, neckY + 11), true, true);
            }
            rightWing.Freeze();
            dc.DrawGeometry(bowBrush, bowPen, rightWing);

            // Center knot
            dc.DrawEllipse(bowBrush, bowPen, new Point(neckX, neckY + 4), 4.5, 4.5);
            dc.Pop();
        }
    }

    private static void RenderHead(
        DrawingContext dc,
        double cx,
        double cy,
        CookiePose pose,
        CharacterPalette palette,
        CookieAppearanceConfig appearance)
    {
        double headCenterX = cx + pose.HeadX;
        double headCenterY = cy - 30 - pose.HeadY;

        dc.PushTransform(new RotateTransform(-pose.HeadTilt, headCenterX, headCenterY));

        // 1. Ears
        foreach (double side in new[] { -1.0, 1.0 })
        {
            double earRootX = headCenterX + side * 18;
            double earRootY = headCenterY - 36;

            if (pose.EarStyle == CookieEarStyle.Back)
            {
                dc.PushTransform(new RotateTransform(-side * 31.5, earRootX, earRootY + 4));
            }

            var earGeo = new StreamGeometry();
            using (var ctx = earGeo.Open())
            {
                ctx.BeginFigure(new Point(earRootX + side * 12, earRootY + 14), true, true);

                if (appearance.EarVariation == EarVariation.Rounded)
                {
                    // Softer curved apex
                    ctx.BezierTo(
                        new Point(earRootX + side * 8, earRootY - 6),
                        new Point(earRootX + side * 4, earRootY - 14),
                        new Point(earRootX + side * 2, earRootY - 14),
                        true, true);
                    ctx.BezierTo(
                        new Point(earRootX + side * 0, earRootY - 14),
                        new Point(earRootX + side * -8, earRootY - 2),
                        new Point(earRootX + side * -12, earRootY + 6),
                        true, true);
                }
                else
                {
                    ctx.LineTo(new Point(earRootX + side * 2, earRootY - 16), true, true);
                    ctx.LineTo(new Point(earRootX + side * -12, earRootY + 6), true, true);
                }
            }
            earGeo.Freeze();

            var earPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 5)
            {
                LineJoin = PenLineJoin.Round
            };
            earPen.Freeze();

            var earBrush = (appearance.Pattern == FurPattern.Points)
                ? new SolidColorBrush(palette.FurShade.ToMediaColor())
                : new SolidColorBrush(palette.Fur.ToMediaColor());

            dc.DrawGeometry(earBrush, earPen, earGeo);

            var innerEarGeo = new StreamGeometry();
            using (var ctx = innerEarGeo.Open())
            {
                ctx.BeginFigure(new Point(earRootX + side * 6, earRootY + 8), true, true);
                ctx.LineTo(new Point(earRootX + side * 1, earRootY - 8), true, true);
                ctx.LineTo(new Point(earRootX + side * -7, earRootY + 5), true, true);
            }
            innerEarGeo.Freeze();
            var innerEarBrush = new SolidColorBrush(palette.InnerEar.ToMediaColor()) { Opacity = 0.9 };
            dc.DrawGeometry(innerEarBrush, null, innerEarGeo);

            // Tufted ear tips
            if (appearance.EarVariation == EarVariation.Tufted)
            {
                var tuftPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 2.5)
                {
                    StartLineCap = PenLineCap.Round,
                    EndLineCap = PenLineCap.Round
                };
                tuftPen.Freeze();
                dc.DrawLine(tuftPen, new Point(earRootX + side * 2, earRootY - 15), new Point(earRootX + side * 3, earRootY - 24));
                dc.DrawLine(tuftPen, new Point(earRootX + side * 1, earRootY - 15), new Point(earRootX + side * -1, earRootY - 22));
            }

            if (pose.EarStyle == CookieEarStyle.Back)
            {
                dc.Pop();
            }
        }

        // 2. Skull Ellipse: size 82 x 72 (radius 41 x 36)
        var skullPen = new Pen(new SolidColorBrush(palette.Outline.ToMediaColor()), 4);
        skullPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.Fur.ToMediaColor()), skullPen, new Point(headCenterX, headCenterY), 41, 36);

        // Tuxedo chin patch
        if (appearance.Pattern == FurPattern.Tuxedo)
        {
            var chinBrush = new SolidColorBrush(Color.FromRgb(250, 248, 244));
            dc.DrawEllipse(chinBrush, null, new Point(headCenterX, headCenterY + 18), 16, 12);
        }

        // 3. Forehead Stripes
        var stripePen = new Pen(new SolidColorBrush(palette.Stripe.ToMediaColor()) { Opacity = 0.85 }, 5)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        stripePen.Freeze();
        dc.DrawLine(stripePen, new Point(headCenterX + 12, headCenterY - 20), new Point(headCenterX + 12, headCenterY - 32));
        dc.DrawLine(stripePen, new Point(headCenterX + 19, headCenterY - 18), new Point(headCenterX + 19, headCenterY - 29));
        dc.DrawLine(stripePen, new Point(headCenterX + 26, headCenterY - 15), new Point(headCenterX + 26, headCenterY - 24));

        // 4. Eyes
        RenderEyes(dc, headCenterX, headCenterY, pose, palette, appearance);

        // 5. Blush Cheeks
        var blushBrush = new SolidColorBrush(palette.Blush.ToMediaColor()) { Opacity = 0.55 };
        double blushRadius = 8 * pose.BlushScale;
        foreach (double side in new[] { -1.0, 1.0 })
        {
            dc.DrawEllipse(blushBrush, null, new Point(headCenterX + side * 27, headCenterY + 8), blushRadius, blushRadius);
        }

        // 6. Mouth
        RenderMouth(dc, headCenterX, headCenterY, pose, palette);

        // 7. Whiskers
        var whiskerPen = new Pen(new SolidColorBrush(palette.Eye.ToMediaColor()) { Opacity = 0.45 }, 2)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        whiskerPen.Freeze();
        foreach (double side in new[] { -1.0, 1.0 })
        {
            dc.DrawLine(whiskerPen, new Point(headCenterX + side * 36, headCenterY + 2), new Point(headCenterX + side * 54, headCenterY - 2));
            dc.DrawLine(whiskerPen, new Point(headCenterX + side * 36, headCenterY + 9), new Point(headCenterX + side * 54, headCenterY + 13));
        }

        // 8. Head Accessories (Crown, Party Hat, Santa Hat, Pumpkin, Glasses)
        RenderHeadAccessories(dc, headCenterX, headCenterY, appearance);

        dc.Pop();
    }

    private static void RenderEyes(
        DrawingContext dc,
        double hcx,
        double hcy,
        CookiePose pose,
        CharacterPalette palette,
        CookieAppearanceConfig appearance)
    {
        // Custom eye tint color
        var eyeColor = appearance.EyeColor.GetRenderColor().ToMediaColor();
        var eyeBrush = new SolidColorBrush(eyeColor);
        var eyePen = new Pen(eyeBrush, 3)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        eyePen.Freeze();

        foreach (double side in new[] { -1.0, 1.0 })
        {
            double eyeX = hcx + side * 15 + pose.GazeX;
            double eyeY = hcy - 2;

            var effectiveEyeStyle = (appearance.EyeStyle == EyeStyle.Sleepy && pose.EyeStyle == CookieEyeStyle.Open)
                ? CookieEyeStyle.Half
                : pose.EyeStyle;

            switch (effectiveEyeStyle)
            {
                case CookieEyeStyle.Open:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY), 4.5, 6);
                    if (appearance.EyeStyle == EyeStyle.Sparkle)
                    {
                        // 4-point sparkle star glint
                        DrawSparkleStar(dc, eyeX - 1.5, eyeY - 2.0, 2.8);
                    }
                    else
                    {
                        dc.DrawEllipse(Brushes.White, null, new Point(eyeX - 1.5, eyeY - 2.0), 1.2, 1.2);
                    }
                    break;

                case CookieEyeStyle.Wide:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY), 5.5, 7);
                    if (appearance.EyeStyle == EyeStyle.Sparkle)
                    {
                        DrawSparkleStar(dc, eyeX - 2, eyeY - 2.5, 3.2);
                    }
                    else
                    {
                        dc.DrawEllipse(Brushes.White, null, new Point(eyeX - 2, eyeY - 2.5), 1.5, 1.5);
                    }
                    break;

                case CookieEyeStyle.Half:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY + 1), 4.5, 3);
                    var lidPen = new Pen(eyeBrush, 2.5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                    dc.DrawLine(lidPen, new Point(eyeX - 5, eyeY - 3), new Point(eyeX + 5, eyeY - 3));
                    break;

                case CookieEyeStyle.Happy:
                    var happyGeo = new StreamGeometry();
                    using (var ctx = happyGeo.Open())
                    {
                        ctx.BeginFigure(new Point(eyeX - 7, eyeY + 2), false, false);
                        ctx.ArcTo(new Point(eyeX + 7, eyeY + 2), new Size(7, 7), 0, false, SweepDirection.Clockwise, true, true);
                    }
                    happyGeo.Freeze();
                    dc.DrawGeometry(null, eyePen, happyGeo);
                    break;

                case CookieEyeStyle.Closed:
                    var closedGeo = new StreamGeometry();
                    using (var ctx = closedGeo.Open())
                    {
                        ctx.BeginFigure(new Point(eyeX - 6, eyeY - 2), false, false);
                        ctx.ArcTo(new Point(eyeX + 6, eyeY - 2), new Size(6, 6), 0, false, SweepDirection.Counterclockwise, true, true);
                    }
                    closedGeo.Freeze();
                    dc.DrawGeometry(null, eyePen, closedGeo);
                    break;
            }
        }
    }

    private static void DrawSparkleStar(DrawingContext dc, double x, double y, double size)
    {
        var starGeo = new StreamGeometry();
        using (var ctx = starGeo.Open())
        {
            ctx.BeginFigure(new Point(x, y - size), true, true);
            ctx.BezierTo(new Point(x, y), new Point(x, y), new Point(x + size, y), true, true);
            ctx.BezierTo(new Point(x, y), new Point(x, y), new Point(x, y + size), true, true);
            ctx.BezierTo(new Point(x, y), new Point(x, y), new Point(x - size, y), true, true);
            ctx.BezierTo(new Point(x, y), new Point(x, y), new Point(x, y - size), true, true);
        }
        starGeo.Freeze();
        dc.DrawGeometry(Brushes.White, null, starGeo);
    }

    private static void RenderHeadAccessories(
        DrawingContext dc,
        double hcx,
        double hcy,
        CookieAppearanceConfig appearance)
    {
        // 1. Glasses
        var glasses = appearance.Accessory(AccessoryKind.Glasses);
        if (glasses.IsEnabled)
        {
            dc.PushTransform(new TranslateTransform(0, glasses.OffsetY * 20));
            var framePen = new Pen(new SolidColorBrush(Color.FromRgb(36, 32, 28)), 2.5);
            framePen.Freeze();
            var lensBrush = new SolidColorBrush(Color.FromArgb(50, 240, 240, 240));

            foreach (double side in new[] { -1.0, 1.0 })
            {
                double gx = hcx + side * 15;
                double gy = hcy - 2;
                dc.DrawEllipse(lensBrush, framePen, new Point(gx, gy), 9, 8);
                // Glass glare shine
                var glarePen = new Pen(new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)), 1.5)
                {
                    StartLineCap = PenLineCap.Round,
                    EndLineCap = PenLineCap.Round
                };
                dc.DrawLine(glarePen, new Point(gx - 4, gy - 4), new Point(gx - 1, gy - 6));
            }

            // Bridge
            dc.DrawLine(framePen, new Point(hcx - 6, hcy - 3), new Point(hcx + 6, hcy - 3));
            dc.Pop();
        }

        // 2. Crown
        var crown = appearance.Accessory(AccessoryKind.Crown);
        if (crown.IsEnabled)
        {
            double crownY = hcy - 36 + crown.OffsetY * 20;
            var crownBrush = new SolidColorBrush(Color.FromRgb(242, 196, 78));
            var crownPen = new Pen(new SolidColorBrush(Color.FromRgb(163, 125, 46)), 2);
            crownPen.Freeze();

            var crownGeo = new StreamGeometry();
            using (var ctx = crownGeo.Open())
            {
                ctx.BeginFigure(new Point(hcx - 14, crownY), true, true);
                ctx.LineTo(new Point(hcx - 16, crownY - 14), true, true);
                ctx.LineTo(new Point(hcx - 8, crownY - 7), true, true);
                ctx.LineTo(new Point(hcx, crownY - 18), true, true);
                ctx.LineTo(new Point(hcx + 8, crownY - 7), true, true);
                ctx.LineTo(new Point(hcx + 16, crownY - 14), true, true);
                ctx.LineTo(new Point(hcx + 14, crownY), true, true);
            }
            crownGeo.Freeze();
            dc.DrawGeometry(crownBrush, crownPen, crownGeo);

            // Gem
            var gemBrush = new SolidColorBrush(Color.FromRgb(224, 85, 68));
            dc.DrawEllipse(gemBrush, null, new Point(hcx, crownY - 5), 3, 3);
        }

        // 3. Party Hat
        var hat = appearance.Accessory(AccessoryKind.Hat);
        if (hat.IsEnabled)
        {
            double hatY = hcy - 36 + hat.OffsetY * 20;
            var hatBrush = new SolidColorBrush(Color.FromRgb(235, 158, 92)); // Warm caramel
            var hatPen = new Pen(new SolidColorBrush(Color.FromRgb(150, 95, 48)), 2);
            hatPen.Freeze();

            var coneGeo = new StreamGeometry();
            using (var ctx = coneGeo.Open())
            {
                ctx.BeginFigure(new Point(hcx - 12, hatY), true, true);
                ctx.LineTo(new Point(hcx + 2, hatY - 32), true, true);
                ctx.LineTo(new Point(hcx + 14, hatY), true, true);
            }
            coneGeo.Freeze();
            dc.DrawGeometry(hatBrush, hatPen, coneGeo);

            // Pompom
            var pompomBrush = new SolidColorBrush(Color.FromRgb(252, 245, 235));
            dc.DrawEllipse(pompomBrush, hatPen, new Point(hcx + 2, hatY - 32), 4.5, 4.5);
        }

        // 4. Pumpkin Hat
        var pumpkin = appearance.Accessory(AccessoryKind.Pumpkin);
        if (pumpkin.IsEnabled)
        {
            double py = hcy - 36 + pumpkin.OffsetY * 20;
            var pumpBrush = new SolidColorBrush(Color.FromRgb(235, 128, 45));
            var pumpPen = new Pen(new SolidColorBrush(Color.FromRgb(165, 82, 25)), 2);
            pumpPen.Freeze();

            dc.DrawEllipse(pumpBrush, pumpPen, new Point(hcx, py - 6), 16, 12);

            // Stem
            var stemPen = new Pen(new SolidColorBrush(Color.FromRgb(85, 115, 65)), 3.5)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round
            };
            dc.DrawLine(stemPen, new Point(hcx, py - 18), new Point(hcx + 3, py - 24));
        }

        // 5. Santa Hat
        var santa = appearance.Accessory(AccessoryKind.SantaHat);
        if (santa.IsEnabled)
        {
            double sy = hcy - 36 + santa.OffsetY * 20;
            var redBrush = new SolidColorBrush(Color.FromRgb(215, 55, 45));
            var redPen = new Pen(new SolidColorBrush(Color.FromRgb(145, 30, 25)), 2);
            redPen.Freeze();

            var coneGeo = new StreamGeometry();
            using (var ctx = coneGeo.Open())
            {
                ctx.BeginFigure(new Point(hcx - 16, sy), true, true);
                ctx.BezierTo(new Point(hcx - 5, sy - 26), new Point(hcx + 12, sy - 28), new Point(hcx + 22, sy - 14), true, true);
                ctx.LineTo(new Point(hcx + 16, sy), true, true);
            }
            coneGeo.Freeze();
            dc.DrawGeometry(redBrush, redPen, coneGeo);

            // White fur brim
            var brimBrush = new SolidColorBrush(Color.FromRgb(252, 250, 245));
            var brimPen = new Pen(new SolidColorBrush(Color.FromRgb(210, 205, 195)), 1.5);
            brimPen.Freeze();
            dc.DrawRoundedRectangle(brimBrush, brimPen, new Rect(hcx - 18, sy - 4, 36, 9), 4, 4);

            // Pompom
            dc.DrawEllipse(brimBrush, brimPen, new Point(hcx + 22, sy - 14), 5, 5);
        }
    }

    private static void RenderMouth(
        DrawingContext dc,
        double hcx,
        double hcy,
        CookiePose pose,
        CharacterPalette palette)
    {
        var mouthBrush = new SolidColorBrush(palette.Eye.ToMediaColor());
        var mouthPen = new Pen(mouthBrush, 2.5)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        mouthPen.Freeze();

        double mouthY = hcy + 9;

        switch (pose.MouthStyle)
        {
            case CookieMouthStyle.Smile:
                foreach (double side in new[] { -1.0, 1.0 })
                {
                    double startX = hcx + (side == -1.0 ? -7 : 0);
                    double endX = hcx + (side == -1.0 ? 0 : 7);
                    var smileGeo = new StreamGeometry();
                    using (var ctx = smileGeo.Open())
                    {
                        ctx.BeginFigure(new Point(startX, mouthY - 1), false, false);
                        ctx.ArcTo(new Point(endX, mouthY - 1), new Size(3.5, 3.5), 0, false, SweepDirection.Counterclockwise, true, true);
                    }
                    smileGeo.Freeze();
                    dc.DrawGeometry(null, mouthPen, smileGeo);
                }
                break;

            case CookieMouthStyle.Flat:
                dc.DrawLine(mouthPen, new Point(hcx - 6, mouthY), new Point(hcx + 6, mouthY));
                break;

            case CookieMouthStyle.Open:
                dc.DrawEllipse(mouthBrush, null, new Point(hcx, mouthY + 2), 4, 5);
                break;

            case CookieMouthStyle.OpenWide:
                dc.DrawEllipse(mouthBrush, null, new Point(hcx, mouthY + 2), 6.5, 7.5);
                var tongueBrush = new SolidColorBrush(palette.InnerEar.ToMediaColor());
                dc.DrawEllipse(tongueBrush, null, new Point(hcx, mouthY + 5), 4, 3.5);
                break;
        }
    }
}
