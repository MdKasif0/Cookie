using System;
using System.Windows;
using System.Windows.Media;
using Cookie.Windows.Models;

namespace Cookie.Windows.Rendering;

/// <summary>
/// Authoritative procedural vector renderer for Cookie.
/// Exactly preserves Cookie's face, eye design, ear shape, body proportions,
/// tail curve, colors, and overall silhouette from the native macOS application.
/// </summary>
public static class CookieSpriteRenderer
{
    public static readonly Size CanvasSize = new(180, 180);

    public static DrawingGroup Render(CookiePose pose, CharacterPalette palette, CookieDirection direction = CookieDirection.Right)
    {
        var group = new DrawingGroup();

        using (var dc = group.Open())
        {
            // Center is (90, 90)
            double centerX = CanvasSize.Width / 2.0;
            double centerY = CanvasSize.Height / 2.0;

            // Handle horizontal facing flip around center
            if (direction == CookieDirection.Left)
            {
                dc.PushTransform(new ScaleTransform(-1, 1, centerX, centerY));
            }

            // Character volume squash & position transform
            // Note: In SpriteKit, Y increases UP. In WPF, Y increases DOWN.
            // bodyY in SK is inverted for WPF.
            double wpfBodyY = -pose.BodyY;
            double scaleX = 1.0 + (1.0 - pose.Squash) * 0.7;
            double scaleY = pose.Squash;

            // Push character transform group centered at (centerX, centerY)
            var charTransform = new TransformGroup();
            charTransform.Children.Add(new TranslateTransform(0, wpfBodyY));
            charTransform.Children.Add(new ScaleTransform(scaleX, scaleY, centerX, centerY + wpfBodyY));
            dc.PushTransform(charTransform);

            // 1. Tail (rendered behind body)
            RenderTail(dc, centerX, centerY, pose.TailAngle, palette);

            // 2. Body
            RenderBody(dc, centerX, centerY, palette);

            // 3. Paws
            RenderPaws(dc, centerX, centerY, pose, palette);

            // 4. Head
            RenderHead(dc, centerX, centerY, pose, palette);

            // Pop character transform
            dc.Pop();

            // Pop facing flip if applied
            if (direction == CookieDirection.Left)
            {
                dc.Pop();
            }
        }

        return group;
    }

    private static void RenderTail(DrawingContext dc, double cx, double cy, double tailAngleDeg, CharacterPalette palette)
    {
        // Tail root at (cx + 26, cy + 20) in WPF coordinates
        double tailRootX = cx + 26;
        double tailRootY = cy + 20;

        // In SK: tail zRotation = angle * pi / 180.
        // Rotation around tail root
        dc.PushTransform(new RotateTransform(-tailAngleDeg, tailRootX, tailRootY));

        // Tail path relative to tailRoot:
        // SK: move (0,0), curveTo (36, -2) cp1:(14, 12), cp2:(30, 10), curveTo (46, -30) cp1:(42, -12), cp2:(50, -20)
        // Convert to WPF (invert y):
        // p0 = (0, 0)
        // p1 = (36, 2), cp1 = (14, -12), cp2 = (30, -10)
        // p2 = (46, 30), cp1 = (42, 12), cp2 = (50, 20)
        var pathGeo = new StreamGeometry();
        using (var ctx = pathGeo.Open())
        {
            ctx.BeginFigure(new Point(tailRootX, tailRootY), false, false);
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
        pathGeo.Freeze();

        // Outline stroke
        var outlinePen = new Pen(new SolidColorBrush(palette.Outline), 15)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        outlinePen.Freeze();
        dc.DrawGeometry(null, outlinePen, pathGeo);

        // Fur stroke
        var furPen = new Pen(new SolidColorBrush(palette.Fur), 10)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        furPen.Freeze();
        dc.DrawGeometry(null, furPen, pathGeo);

        // Tail tip
        var tipCenter = new Point(tailRootX + 46, tailRootY + 30);
        var tipPen = new Pen(new SolidColorBrush(palette.Outline), 3);
        tipPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.FurShade), tipPen, tipCenter, 6.5, 6.5);

        dc.Pop();
    }

    private static void RenderBody(DrawingContext dc, double cx, double cy, CharacterPalette palette)
    {
        // SK: body size (88, 72) at y = -26 -> in WPF cy + 26
        var bodyCenter = new Point(cx, cy + 26);
        var bodyPen = new Pen(new SolidColorBrush(palette.Outline), 4);
        bodyPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.Fur), bodyPen, bodyCenter, 44, 36);
    }

    private static void RenderPaws(DrawingContext dc, double cx, double cy, CookiePose pose, CharacterPalette palette)
    {
        // SK: paws at side * 16 + pawOffsetX, y = -58 + pawLift -> WPF: cy + 58 - pawLift
        double pawY = cy + 58 - pose.PawLift;
        var pawPen = new Pen(new SolidColorBrush(palette.Outline), 3.5);
        pawPen.Freeze();
        var pawBrush = new SolidColorBrush(palette.Fur);

        foreach (double side in new[] { -1.0, 1.0 })
        {
            double pawX = cx + side * 16 + pose.PawOffsetX;
            dc.DrawEllipse(pawBrush, pawPen, new Point(pawX, pawY), 10, 6.5);
        }
    }

    private static void RenderHead(DrawingContext dc, double cx, double cy, CookiePose pose, CharacterPalette palette)
    {
        // SK: head at (cx + headX, cy - 30 - headY)
        double headCenterX = cx + pose.HeadX;
        double headCenterY = cy - 30 - pose.HeadY;

        // Head tilt transform
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

            // Outer Ear Triangle: [(side * 12, 14), (side * 2, -16), (side * -12, 6)]
            var earGeo = new StreamGeometry();
            using (var ctx = earGeo.Open())
            {
                ctx.BeginFigure(new Point(earRootX + side * 12, earRootY + 14), true, true);
                ctx.LineTo(new Point(earRootX + side * 2, earRootY - 16), true, true);
                ctx.LineTo(new Point(earRootX + side * -12, earRootY + 6), true, true);
            }
            earGeo.Freeze();

            var earPen = new Pen(new SolidColorBrush(palette.Outline), 5)
            {
                LineJoin = PenLineJoin.Round
            };
            earPen.Freeze();
            dc.DrawGeometry(new SolidColorBrush(palette.Fur), earPen, earGeo);

            // Inner Ear Triangle: [(side * 6, 8), (side * 1, -8), (side * -7, 5)]
            var innerEarGeo = new StreamGeometry();
            using (var ctx = innerEarGeo.Open())
            {
                ctx.BeginFigure(new Point(earRootX + side * 6, earRootY + 8), true, true);
                ctx.LineTo(new Point(earRootX + side * 1, earRootY - 8), true, true);
                ctx.LineTo(new Point(earRootX + side * -7, earRootY + 5), true, true);
            }
            innerEarGeo.Freeze();
            var innerEarBrush = new SolidColorBrush(palette.InnerEar) { Opacity = 0.9 };
            dc.DrawGeometry(innerEarBrush, null, innerEarGeo);

            if (pose.EarStyle == CookieEarStyle.Back)
            {
                dc.Pop();
            }
        }

        // 2. Skull Ellipse: size 82 x 72 (radius 41 x 36)
        var skullPen = new Pen(new SolidColorBrush(palette.Outline), 4);
        skullPen.Freeze();
        dc.DrawEllipse(new SolidColorBrush(palette.Fur), skullPen, new Point(headCenterX, headCenterY), 41, 36);

        // 3. Forehead Stripes
        var stripePen = new Pen(new SolidColorBrush(palette.Stripe) { Opacity = 0.85 }, 5)
        {
            StartLineCap = PenLineCap.Round,
            EndLineCap = PenLineCap.Round
        };
        stripePen.Freeze();
        dc.DrawLine(stripePen, new Point(headCenterX + 12, headCenterY - 20), new Point(headCenterX + 12, headCenterY - 32));
        dc.DrawLine(stripePen, new Point(headCenterX + 19, headCenterY - 18), new Point(headCenterX + 19, headCenterY - 29));
        dc.DrawLine(stripePen, new Point(headCenterX + 26, headCenterY - 15), new Point(headCenterX + 26, headCenterY - 24));

        // 4. Eyes
        RenderEyes(dc, headCenterX, headCenterY, pose, palette);

        // 5. Blush Cheeks
        var blushBrush = new SolidColorBrush(palette.Blush) { Opacity = 0.55 };
        double blushRadius = 8 * pose.BlushScale;
        foreach (double side in new[] { -1.0, 1.0 })
        {
            dc.DrawEllipse(blushBrush, null, new Point(headCenterX + side * 27, headCenterY + 8), blushRadius, blushRadius);
        }

        // 6. Mouth
        RenderMouth(dc, headCenterX, headCenterY, pose, palette);

        // 7. Whiskers
        var whiskerPen = new Pen(new SolidColorBrush(palette.Eye) { Opacity = 0.45 }, 2)
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

        dc.Pop();
    }

    private static void RenderEyes(DrawingContext dc, double hcx, double hcy, CookiePose pose, CharacterPalette palette)
    {
        var eyeBrush = new SolidColorBrush(palette.Eye);
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

            switch (pose.EyeStyle)
            {
                case CookieEyeStyle.Open:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY), 4.5, 6);
                    break;

                case CookieEyeStyle.Wide:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY), 5.5, 7);
                    // Glint
                    dc.DrawEllipse(Brushes.White, null, new Point(eyeX - 2, eyeY - 2.5), 1.25, 1.25);
                    break;

                case CookieEyeStyle.Half:
                    dc.DrawEllipse(eyeBrush, null, new Point(eyeX, eyeY + 1), 4.5, 3);
                    var lidPen = new Pen(eyeBrush, 2.5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                    dc.DrawLine(lidPen, new Point(eyeX - 5, eyeY - 3), new Point(eyeX + 5, eyeY - 3));
                    break;

                case CookieEyeStyle.Happy:
                    // Upward curved arc for smiling eye: arc from angle 180 to 0 (top half)
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
                    // Downward curved arc for sleeping eye
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

    private static void RenderMouth(DrawingContext dc, double hcx, double hcy, CookiePose pose, CharacterPalette palette)
    {
        var mouthBrush = new SolidColorBrush(palette.Eye);
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
                // Double arc cat smile :3
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
                var tongueBrush = new SolidColorBrush(palette.InnerEar);
                dc.DrawEllipse(tongueBrush, null, new Point(hcx, mouthY + 5), 4, 3.5);
                break;
        }
    }
}
