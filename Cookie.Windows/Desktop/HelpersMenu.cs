using System;
using System.Linq;
using System.Windows.Controls;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Desktop;

/// <summary>What the helper menus need from Cookie's window.</summary>
public interface IHelpersMenuSource
{
    CookieProfile Profile { get; }
    HelpersCoordinator Helpers { get; }
    ClipboardHistory Clipboard { get; }
    bool IsManuallyQuiet { get; }

    void NewReminder();
    void NewTodo();
    void NewStickyNote();
    void SetNotesVisible(bool visible);
    void ConfirmTidyScreenshots();
    void CopyBack(string text);
    void OpenAskCookie();
    void SetManualQuiet(bool on, int? minutes = null);
    void StartHelpersTour();
}

/// <summary>Reminders, To-Do, Sticky Notes, Clipboard, Ask Cookie and Quiet Mode, for the tray and Cookie's own menu.</summary>
public static class HelpersMenu
{
    public static void AddItems(ContextMenu menu, IHelpersMenuSource source)
    {
        menu.Items.Add(BuildReminders(source));
        menu.Items.Add(BuildTodos(source));
        menu.Items.Add(BuildNotes(source));

        int tidy = source.Helpers.TidyableScreenshotCount();
        if (tidy > 0)
        {
            var item = new MenuItem { Header = $"Tidy Up {tidy} Screenshot{(tidy == 1 ? "" : "s")}..." };
            item.Click += (s, e) => source.ConfirmTidyScreenshots();
            menu.Items.Add(item);
        }

        if (source.Profile.Settings.ClipboardHistory) menu.Items.Add(BuildClipboard(source));

        if (source.Profile.Settings.AskCookieEnabled)
        {
            var ask = new MenuItem { Header = $"Ask {source.Profile.DisplayName}..." };
            ask.Click += (s, e) => source.OpenAskCookie();
            menu.Items.Add(ask);
        }

        menu.Items.Add(BuildQuiet(source));

        var tour = new MenuItem { Header = "Take the Tour" };
        tour.Click += (s, e) => source.StartHelpersTour();
        menu.Items.Add(tour);
    }

    private static MenuItem BuildReminders(IHelpersMenuSource source)
    {
        var reminders = source.Helpers.Reminders;
        var root = new MenuItem { Header = reminders.Count == 0 ? "Reminders" : $"Reminders ({reminders.Count})" };

        var add = new MenuItem { Header = "New Reminder..." };
        add.Click += (s, e) => source.NewReminder();
        root.Items.Add(add);

        var timer = new MenuItem { Header = "Quick Timer" };
        foreach (int minutes in new[] { 1, 5, 10, 15, 30, 60 })
        {
            var entry = new MenuItem { Header = CookieReminder.Label(minutes) };
            int captured = minutes;
            entry.Click += (s, e) => source.Helpers.AddReminder("", captured);
            timer.Items.Add(entry);
        }
        root.Items.Add(timer);

        if (reminders.Count > 0)
        {
            root.Items.Add(new Separator());
            var now = DateTime.UtcNow;
            foreach (var reminder in reminders)
            {
                var entry = new MenuItem { Header = $"{reminder.Message} · {reminder.RemainingLabel(now)}" };
                var cancel = new MenuItem { Header = "Cancel Reminder" };
                var id = reminder.Id;
                cancel.Click += (s, e) => source.Helpers.CancelReminder(id);
                entry.Items.Add(cancel);
                root.Items.Add(entry);
            }
        }
        return root;
    }

    private static MenuItem BuildTodos(IHelpersMenuSource source)
    {
        var todos = source.Helpers.Todos;
        int open = todos.Count(t => !t.IsDone);
        var root = new MenuItem { Header = open == 0 ? "To-Do" : $"To-Do ({open})" };

        var add = new MenuItem { Header = "Add Task..." };
        add.Click += (s, e) => source.NewTodo();
        root.Items.Add(add);

        if (todos.Count > 0)
        {
            root.Items.Add(new Separator());
            foreach (var todo in todos)
            {
                var entry = new MenuItem
                {
                    Header = todo.Text,
                    IsCheckable = true,
                    IsChecked = todo.IsDone,
                    ToolTip = todo.IsDone ? "Click to mark as not done" : "Click to tick it off"
                };
                var id = todo.Id;
                entry.Click += (s, e) => source.Helpers.ToggleTodo(id);
                root.Items.Add(entry);
            }
            if (todos.Any(t => t.IsDone))
            {
                root.Items.Add(new Separator());
                var clear = new MenuItem { Header = "Clear Finished Tasks" };
                clear.Click += (s, e) => source.Helpers.ClearCompletedTodos();
                root.Items.Add(clear);
            }
        }
        return root;
    }

    private static MenuItem BuildNotes(IHelpersMenuSource source)
    {
        int count = source.Profile.StickyNotes.Count;
        var root = new MenuItem { Header = count == 0 ? "Sticky Notes" : $"Sticky Notes ({count})" };
        var add = new MenuItem { Header = "New Note..." };
        add.Click += (s, e) => source.NewStickyNote();
        root.Items.Add(add);
        if (count > 0)
        {
            bool showing = source.Profile.Settings.ShowStickyNotes;
            var toggle = new MenuItem { Header = showing ? "Hide Notes" : "Show Notes" };
            toggle.Click += (s, e) => source.SetNotesVisible(!showing);
            root.Items.Add(toggle);
        }
        return root;
    }

    private static MenuItem BuildClipboard(IHelpersMenuSource source)
    {
        var root = new MenuItem { Header = "Clipboard" };
        var items = source.Clipboard.Items;
        if (items.Count == 0)
        {
            root.Items.Add(new MenuItem { Header = "Nothing copied yet", IsEnabled = false });
            return root;
        }
        foreach (string text in items.ToList())
        {
            var entry = new MenuItem { Header = ClipboardHistory.Preview(text), ToolTip = "Copy this again" };
            string captured = text;
            entry.Click += (s, e) => source.CopyBack(captured);
            root.Items.Add(entry);
        }
        root.Items.Add(new Separator());
        var clear = new MenuItem { Header = "Clear History" };
        clear.Click += (s, e) => source.Clipboard.Clear();
        root.Items.Add(clear);
        return root;
    }

    private static MenuItem BuildQuiet(IHelpersMenuSource source)
    {
        bool quiet = source.IsManuallyQuiet;
        var root = new MenuItem { Header = quiet ? "Quiet Mode: On" : "Quiet Mode" };
        if (quiet)
        {
            var off = new MenuItem { Header = "Turn Off Quiet Mode" };
            off.Click += (s, e) => source.SetManualQuiet(false);
            root.Items.Add(off);
            return root;
        }
        foreach (var (title, minutes) in new (string, int?)[] { ("For 30 Minutes", 30), ("For 1 Hour", 60), ("For 2 Hours", 120), ("Until I Turn It Off", null) })
        {
            var entry = new MenuItem { Header = title };
            int? captured = minutes;
            entry.Click += (s, e) => source.SetManualQuiet(true, captured);
            root.Items.Add(entry);
        }
        return root;
    }
}
