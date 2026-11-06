using System;
using System.Collections.Generic;

namespace Cookie.Windows.Core.Models;

public class CookieProfile
{
    public int Version { get; set; } = 1;
    public string DisplayName { get; set; } = "Cookie";
    public bool IsCompanionVisible { get; set; } = true;
    public CookiePersonality Personality { get; set; } = CookiePersonality.Playful;
    public CookieAppearanceConfig Appearance { get; set; } = new();
    public CookieSettings Settings { get; set; } = new();
    public CookieStatistics Statistics { get; set; } = new();

    /// <summary>Ids of unlocked items (see <see cref="BondItem.Id"/>) that must stay available regardless of level.</summary>
    public List<string> UnlockedItems { get; set; } = new();

    public List<CozyPlacement> CozyItems { get; set; } = new();
    public DateTime LastModified { get; set; } = DateTime.UtcNow;
}
