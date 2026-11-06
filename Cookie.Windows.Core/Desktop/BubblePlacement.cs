using System;

namespace Cookie.Windows.Core.Desktop;

/// <summary>Where Cookie's speech bubble goes: over her head, kept on screen.</summary>
public static class BubblePlacement
{
    public static CorePoint Origin(CoreSize bubble, CoreRect companion, CoreRect visible)
    {
        double x = companion.X + companion.Width / 2 - bubble.Width / 2;
        double y = companion.Y - bubble.Height + 14;
        x = Math.Min(Math.Max(x, visible.Left + 4), visible.Right - bubble.Width - 4);

        // No room above her, so it drops beside her instead of off the screen.
        if (y < visible.Top + 2) y = Math.Min(companion.Bottom - 14, visible.Bottom - bubble.Height - 2);
        return new CorePoint(x, y);
    }
}
