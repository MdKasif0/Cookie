using System;

namespace Cookie.Windows.Models;

public class CookieProfile
{
    public int Version { get; set; } = 1;
    public string DisplayName { get; set; } = "Cookie";
    public bool IsCompanionVisible { get; set; } = true;
    public CookieAppearanceConfig Appearance { get; set; } = new();
    public CookieSettings Settings { get; set; } = new();
    public DateTime LastModified { get; set; } = DateTime.UtcNow;
}
