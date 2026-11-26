using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Helpers;

/// <summary>
/// The short tour Cookie gives of her helpers: after the welcome, once after the update that added them, and
/// whenever it's chosen from her menu. Each step can be tried on the spot.
/// </summary>
public static class HelpersTour
{
    public enum TourAction { NewReminder, PinNote, OpenPowerTools }

    public sealed record Step(string Title, string Text, string? TryTitle, TourAction? Action, CookieAnimationId Reaction);

    /// <summary>The note she pins when "Pin a Note" is chosen.</summary>
    public const string SampleNote = "Hi! I'm a sticky note. Drag me anywhere, or double-click to edit.";

    public static IReadOnlyList<Step> Steps(string name) => new[]
    {
        new Step("Reminders",
            "Need a nudge later? I'll come find you and meow when it's time, even over a full-screen app.",
            "Set a Reminder", TourAction.NewReminder, CookieAnimationId.Happy),
        new Step("Notes and to-dos",
            "I can pin sticky notes to your desktop and keep a to-do list. Every task you finish brings us closer.",
            "Pin a Note", TourAction.PinNote, CookieAnimationId.Surprised),
        new Step("Drop files on me",
            "Drag any file onto me and I'll move it, copy it or zip it for you.",
            null, null, CookieAnimationId.Curious),
        new Step($"Chat with {name}",
            "Add your own Claude API key under Settings → Power Tools and we can talk. It's off until you do.",
            "Open Settings", TourAction.OpenPowerTools, CookieAnimationId.Meow),
        new Step("That's the tour!",
            "Right-click me or the tray icon any time for all of this and more. Break nudges, focus guard and bedtime are in Settings → Helpers.",
            null, null, CookieAnimationId.Happy),
    };

    /// <summary>
    /// She only starts the tour on her own at a calm moment: on screen, with no full-screen app and no focus
    /// session. Otherwise she waits for another launch.
    /// </summary>
    public static bool CanStartOnItsOwn(bool hasCompletedOnboarding, bool hasSeenTour, bool isVisible, bool isQuiet, bool isFocusing) =>
        hasCompletedOnboarding && !hasSeenTour && isVisible && !isQuiet && !isFocusing;

    /// <summary>
    /// Where the card goes: beside her on whichever side has room, level with her head, kept inside the
    /// visible area. Screen y grows downwards.
    /// </summary>
    public static CorePoint CardOrigin(CoreSize card, CoreRect companion, CoreRect visible)
    {
        const double gap = 4;
        double x = companion.Right + gap;
        if (x + card.Width > visible.Right - 4) x = companion.Left - card.Width - gap;
        x = Math.Clamp(x, visible.Left + 4, Math.Max(visible.Left + 4, visible.Right - card.Width - 4));
        double y = Math.Clamp(companion.Top, visible.Top + 4, Math.Max(visible.Top + 4, visible.Bottom - card.Height - 4));
        return new CorePoint(x, y);
    }

    /// <summary>A rectangle covering both, so a note pinned during the tour keeps clear of its card.</summary>
    public static CoreRect Union(CoreRect a, CoreRect b)
    {
        double left = Math.Min(a.Left, b.Left), top = Math.Min(a.Top, b.Top);
        return new CoreRect(left, top, Math.Max(a.Right, b.Right) - left, Math.Max(a.Bottom, b.Bottom) - top);
    }
}
