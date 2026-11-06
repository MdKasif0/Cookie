using System;
using System.Windows.Controls;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Rendering;

namespace Cookie.Windows.Desktop;

/// <summary>What the menus need from Cookie's window: friendship, focus, cozy items and photos.</summary>
public interface ICompanionMenuSource
{
    CookieProfile Profile { get; }
    CookieBehaviorController Behavior { get; }
    BondTracker Bond { get; }
    FocusSession Session { get; }

    void StartFocus(int minutes);
    void StopFocus();
    void PlaceCozy(CozyKind kind);
    void RemoveCozy(CozyKind kind);
    void OpenPhotoMode();
}

/// <summary>The friendship line, Focus Session, Cozy Corner and Photo Mode entries, shared by the tray and Cookie's own menu.</summary>
public static class CompanionMenu
{
    public static void AddItems(ContextMenu menu, ICompanionMenuSource source)
    {
        var progress = source.Bond.Progress;
        menu.Items.Add(new MenuItem
        {
            Header = progress.Next is { } next
                ? $"{progress.Level.Name} · {source.Bond.Points} of {next.Points}"
                : $"{progress.Level.Name} · fully bonded",
            Icon = CookieIcons.MenuIcon("glyph-heart"),
            IsEnabled = false
        });

        menu.Items.Add(BuildCozyMenu(source));
        menu.Items.Add(BuildFocusMenu(source));

        var photo = new MenuItem { Header = "Photo Mode...", Icon = CookieIcons.MenuIcon("emote-happy") };
        photo.Click += (s, e) => source.OpenPhotoMode();
        menu.Items.Add(photo);
    }

    private static MenuItem BuildFocusMenu(ICompanionMenuSource source)
    {
        var focus = source.Session;
        var root = new MenuItem { Header = "Focus Session", Icon = CookieIcons.MenuIcon("glyph-moon") };

        if (focus.Timer.IsActive)
        {
            root.Items.Add(new MenuItem
            {
                Header = focus.IsFocusing ? $"Focusing: {focus.Timer.RemainingLabel} left" : $"On a break: {focus.Timer.RemainingLabel} left",
                IsEnabled = false
            });
            var stop = new MenuItem { Header = focus.IsFocusing ? "Stop Session" : "Skip Break" };
            stop.Click += (s, e) => source.StopFocus();
            root.Items.Add(stop);
            return root;
        }

        var lengths = new System.Collections.Generic.List<int> { 15, 25, 50 };
        int custom = source.Profile.Settings.FocusMinutes;
        if (!lengths.Contains(custom))
        {
            lengths.Add(custom);
            lengths.Sort();
        }
        foreach (int minutes in lengths)
        {
            var entry = new MenuItem { Header = $"Start {minutes} Minutes" };
            int captured = minutes;
            entry.Click += (s, e) => source.StartFocus(captured);
            root.Items.Add(entry);
        }
        return root;
    }

    private static MenuItem BuildCozyMenu(ICompanionMenuSource source)
    {
        var root = new MenuItem { Header = "Cozy Corner", Icon = CookieIcons.MenuIcon("item-cozy-bed") };
        foreach (var kind in Enum.GetValues<CozyKind>())
        {
            bool placed = source.Profile.CozyItems.Exists(p => p.Kind == kind);
            var entry = new MenuItem
            {
                Header = placed ? $"Put Away {kind.GetDisplayName()}" : $"Place {kind.GetDisplayName()}",
                Icon = CookieIcons.MenuIcon(kind.GetIconName())
            };

            var captured = kind;
            if (placed)
            {
                entry.Click += (s, e) => source.RemoveCozy(captured);
            }
            else if (!source.Bond.IsUnlocked(BondItem.Cozy(kind)) && Bond.RequiredLevel(BondItem.Cozy(kind)) is { } level)
            {
                entry.Header = $"Place {kind.GetDisplayName()} ({level.Name})";
                entry.IsEnabled = false;
            }
            else
            {
                entry.Click += (s, e) => source.PlaceCozy(captured);
            }
            root.Items.Add(entry);
        }
        return root;
    }
}
