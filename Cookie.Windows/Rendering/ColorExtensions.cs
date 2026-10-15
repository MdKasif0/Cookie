using System.Windows.Media;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Rendering;

public static class ColorExtensions
{
    public static Color ToMediaColor(this CookieColor c) => Color.FromArgb(c.A, c.R, c.G, c.B);
}
