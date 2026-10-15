namespace Cookie.Windows.Core.Models;

public readonly record struct CookieColor(byte R, byte G, byte B, byte A = 255)
{
    public static CookieColor FromRgb(byte r, byte g, byte b) => new(r, g, b, 255);
    public static CookieColor FromArgb(byte a, byte r, byte g, byte b) => new(r, g, b, a);
}
