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

    /// <summary>Reminders and timers still to come.</summary>
    public List<Cookie.Windows.Core.Helpers.CookieReminder> Reminders { get; set; } = new();
    /// <summary>When she last suggested going to bed (local time), so she says it once a night.</summary>
    public DateTime? LastBedtimeWindDown { get; set; }
    public List<Cookie.Windows.Core.Helpers.StickyNote> StickyNotes { get; set; } = new();
    public List<Cookie.Windows.Core.Helpers.TodoItem> Todos { get; set; } = new();
    /// <summary>When she last offered to tidy screenshots, so she asks at most once a day.</summary>
    public DateTime? LastScreenshotOffer { get; set; }
    public DateTime LastModified { get; set; } = DateTime.UtcNow;
}
