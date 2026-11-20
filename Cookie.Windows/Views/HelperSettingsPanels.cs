using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Desktop;
using Microsoft.Win32;

namespace Cookie.Windows.Views;

/// <summary>What the helper tabs can ask Cookie's window to do.</summary>
public record SettingsHelperActions(Action TidyScreenshots, Action OpenAskCookie);

/// <summary>Shared pieces for the Helpers and Power Tools tabs.</summary>
internal abstract class SettingsPanelBase
{
    protected readonly CookieProfile Profile;
    private readonly SettingsManager _settings;
    private readonly Action? _changed;

    protected SettingsPanelBase(CookieProfile profile, SettingsManager settings, Action? changed)
    {
        Profile = profile;
        _settings = settings;
        _changed = changed;
    }

    protected void Saved()
    {
        _settings.DebouncedSave(Profile);
        _changed?.Invoke();
    }

    protected static GroupBox Group(string header, params UIElement[] children)
    {
        var stack = new StackPanel();
        foreach (var child in children) stack.Children.Add(child);
        return new GroupBox { Header = header, Content = stack, Margin = new Thickness(0, 0, 0, 12) };
    }

    protected CheckBox Check(string label, Func<CookieSettings, bool> get, Action<CookieSettings, bool> set, string? hint = null)
    {
        var box = new CheckBox { Content = label, IsChecked = get(Profile.Settings), Margin = new Thickness(0, 4, 0, 4) };
        if (hint != null) box.ToolTip = hint;
        box.Click += (s, e) =>
        {
            set(Profile.Settings, box.IsChecked == true);
            Saved();
        };
        return box;
    }

    protected static TextBlock Note(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        FontSize = 11,
        Opacity = 0.7,
        Margin = new Thickness(0, 4, 0, 4)
    };

    protected static ScrollViewer Page(params UIElement[] groups)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 12, 8, 0) };
        foreach (var group in groups) stack.Children.Add(group);
        return new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = stack };
    }
}

/// <summary>Break nudges, the focus guard, bedtime, the system watcher, downloads and screenshots.</summary>
internal sealed class HelpersSettingsPanel : SettingsPanelBase
{
    private readonly SettingsHelperActions? _actions;
    private readonly StackPanel _apps = new();

    public HelpersSettingsPanel(CookieProfile profile, SettingsManager settings, Action? changed, SettingsHelperActions? actions)
        : base(profile, settings, changed) => _actions = actions;

    public UIElement Build()
    {
        var nudges = Enum.GetValues<BreakNudge>().Select(nudge => (UIElement)Check(
            nudge.DisplayName(),
            s => s.BreakNudges.Contains(nudge),
            (s, on) =>
            {
                s.BreakNudges.RemoveAll(n => n == nudge);
                if (on) s.BreakNudges.Add(nudge);
            },
            nudge.SettingsHint())).ToList();
        nudges.Add(Note("Only time at the keyboard counts, and stepping away resets it. She waits during focus sessions, video calls and full-screen apps."));

        var addApp = new Button { Content = "Add App...", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 6, 0, 0) };
        addApp.Click += (s, e) => ChooseApps();
        RenderApps();

        var bedtime = new ComboBox { Width = 140, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 0) };
        for (int minutes = 20 * 60; minutes < 24 * 60 + 3 * 60; minutes += 30)
        {
            int value = minutes % (24 * 60);
            bedtime.Items.Add(new ComboBoxItem { Content = DateTime.Today.AddMinutes(value).ToString("t"), Tag = value });
        }
        bedtime.SelectedItem = bedtime.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (int)i.Tag == Profile.Settings.BedtimeMinutes)
                               ?? bedtime.Items[6];
        bedtime.SelectionChanged += (s, e) =>
        {
            if (bedtime.SelectedItem is ComboBoxItem { Tag: int value })
            {
                Profile.Settings.BedtimeMinutes = value;
                Saved();
            }
        };

        var systemChecks = Enum.GetValues<SystemAlertKind>().Select(kind => (UIElement)Check(
            kind.DisplayName(),
            s => s.SystemAlerts.Contains(kind),
            (s, on) =>
            {
                s.SystemAlerts.RemoveAll(k => k == kind);
                if (on) s.SystemAlerts.Add(kind);
            })).ToList();
        systemChecks.Add(Note("She checks every 20 seconds using information Windows makes public. Only a nearly flat battery interrupts a full-screen app."));

        var tidyNow = new Button { Content = "Tidy Up Now...", Margin = new Thickness(0, 0, 8, 0) };
        tidyNow.Click += (s, e) => _actions?.TidyScreenshots();
        var openFolder = new Button { Content = "Show Screenshots Folder" };
        openFolder.Click += (s, e) => OpenFolder(KnownFolders.Screenshots);
        var fileButtons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        fileButtons.Children.Add(tidyNow);
        fileButtons.Children.Add(openFolder);

        return Page(
            Group("Break Nudges", nudges.ToArray()),
            Group("Focus Guard",
                Check("Cookie reacts when I open a distracting app", s => s.FocusGuardEnabled, (s, on) => s.FocusGuardEnabled = on),
                _apps,
                addApp,
                Note("Only works during a focus session. Cookie can see which app is in front, but never which website or document is open, so to count a site, add the whole browser.")),
            Group("Bedtime",
                Check("Remind me when it's bedtime", s => s.BedtimeEnabled, (s, on) => s.BedtimeEnabled = on),
                bedtime,
                Note("Once a night she yawns, suggests wrapping up, and curls up to sleep. She won't bring it up more than 3 hours after bedtime.")),
            Group("System Watcher", systemChecks.ToArray()),
            Group("Downloads & Screenshots",
                Check("Tell me when a download finishes", s => s.DownloadAlerts, (s, on) => s.DownloadAlerts = on),
                Check("Offer to tidy old screenshots on my Desktop", s => s.ScreenshotTidyOffers, (s, on) => s.ScreenshotTidyOffers = on),
                fileButtons,
                Note("Tidying moves screenshots older than a day from your Desktop into Pictures\\Screenshots. Nothing is deleted or overwritten.")),
            Group("Calendar",
                Note("Calendar heads-ups are Mac-only for now. Windows only lets Store-packaged apps read your calendar, and Cookie installs as a regular desktop app.")));
    }

    private void RenderApps()
    {
        _apps.Children.Clear();
        if (Profile.Settings.DistractingApps.Count == 0)
        {
            _apps.Children.Add(Note("No apps yet."));
            return;
        }
        foreach (var app in Profile.Settings.DistractingApps.ToList())
        {
            var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
            var remove = new Button { Content = "Remove", Padding = new Thickness(8, 2, 8, 2) };
            System.Windows.Automation.AutomationProperties.SetName(remove, $"Remove {app.DisplayName}");
            remove.Click += (s, e) =>
            {
                Profile.Settings.DistractingApps.Remove(app);
                Saved();
                RenderApps();
            };
            DockPanel.SetDock(remove, Dock.Right);
            row.Children.Add(remove);
            row.Children.Add(new TextBlock { Text = $"{app.DisplayName}  ({app.ProcessName}.exe)", VerticalAlignment = VerticalAlignment.Center });
            _apps.Children.Add(row);
        }
    }

    /// <summary>Picks programs. Only the program's name is kept.</summary>
    private void ChooseApps()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Choose distracting apps",
            Filter = "Programs (*.exe)|*.exe",
            Multiselect = true,
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
        };
        if (dialog.ShowDialog() != true) return;
        foreach (string path in dialog.FileNames)
        {
            string process = DistractingApp.Normalize(Path.GetFileName(path));
            if (process == "cookie" || Profile.Settings.DistractingApps.Any(a => DistractingApp.Normalize(a.ProcessName) == process)) continue;
            string name = Path.GetFileNameWithoutExtension(path);
            try
            {
                string? description = FileVersionInfo.GetVersionInfo(path).FileDescription;
                if (!string.IsNullOrWhiteSpace(description)) name = description.Trim();
            }
            catch
            {
                // Keep the file name.
            }
            Profile.Settings.DistractingApps.Add(new DistractingApp { ProcessName = process, DisplayName = name });
        }
        Saved();
        RenderApps();
    }

    internal static void OpenFolder(string folder)
    {
        try
        {
            Directory.CreateDirectory(folder);
            Process.Start(new ProcessStartInfo { FileName = folder, UseShellExecute = true });
        }
        catch
        {
            // Nothing to open.
        }
    }
}

/// <summary>Links, the file drop zone, the clipboard buddy and Ask Cookie.</summary>
internal sealed class PowerToolsSettingsPanel : SettingsPanelBase
{
    private readonly SettingsHelperActions? _actions;
    private TextBlock _folder = null!;
    private TextBlock _keyStatus = null!;
    private PasswordBox _key = null!;

    public PowerToolsSettingsPanel(CookieProfile profile, SettingsManager settings, Action? changed, SettingsHelperActions? actions)
        : base(profile, settings, changed) => _actions = actions;

    public UIElement Build()
    {
        var examples = new TextBox
        {
            Text = "start cookie://say?text=Hello\nstart \"\" \"cookie://remind?minutes=20&text=Stretch\"\nstart cookie://focus/start?minutes=25\nstart cookie://quiet/on?minutes=60",
            IsReadOnly = true,
            FontFamily = new System.Windows.Media.FontFamily("Consolas"),
            FontSize = 11,
            TextWrapping = TextWrapping.NoWrap,
            Margin = new Thickness(0, 4, 0, 4)
        };

        _folder = new TextBlock { TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center, Opacity = 0.8 };
        UpdateFolder();
        var choose = new Button { Content = "Choose...", Margin = new Thickness(8, 0, 0, 0) };
        choose.Click += (s, e) =>
        {
            var dialog = new OpenFolderDialog { Title = "Choose where Cookie files things" };
            if (dialog.ShowDialog() != true) return;
            Profile.Settings.DropFolderPath = dialog.FolderName;
            Saved();
            UpdateFolder();
        };
        var folderRow = new DockPanel { Margin = new Thickness(0, 4, 0, 4) };
        DockPanel.SetDock(choose, Dock.Right);
        folderRow.Children.Add(choose);
        folderRow.Children.Add(_folder);

        _key = new PasswordBox { MinWidth = 260 };
        System.Windows.Automation.AutomationProperties.SetName(_key, "Claude API key");
        _keyStatus = new TextBlock { Margin = new Thickness(0, 4, 0, 0), FontSize = 11, Opacity = 0.8 };
        UpdateKeyStatus(null);
        var save = new Button { Content = "Save Key", Margin = new Thickness(8, 0, 0, 0) };
        save.Click += (s, e) =>
        {
            bool ok = ApiKeyStore.Save(_key.Password);
            _key.Clear();
            UpdateKeyStatus(ok ? "Saved in Windows Credential Manager." : "Couldn't save that key.");
            Saved();
        };
        var remove = new Button { Content = "Remove", Margin = new Thickness(8, 0, 0, 0) };
        remove.Click += (s, e) =>
        {
            ApiKeyStore.Delete();
            UpdateKeyStatus("Key removed.");
            Saved();
        };
        var keyRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        keyRow.Children.Add(_key);
        keyRow.Children.Add(save);
        keyRow.Children.Add(remove);

        var openChat = new Button { Content = "Open Chat", Margin = new Thickness(0, 0, 8, 0) };
        openChat.Click += (s, e) => _actions?.OpenAskCookie();
        var getKey = new Button { Content = "Get an API Key" };
        getKey.Click += (s, e) =>
        {
            try { Process.Start(new ProcessStartInfo { FileName = "https://console.anthropic.com/settings/keys", UseShellExecute = true }); } catch { }
        };
        var chatButtons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        chatButtons.Children.Add(openChat);
        chatButtons.Children.Add(getKey);

        return Page(
            Group("Links",
                Check("Allow cookie:// links", s => s.AllowLinks, (s, on) => s.AllowLinks = on),
                Note("Use them from Command Prompt, PowerShell, Power Automate, PowerToys Run, a desktop shortcut or a script:"),
                examples,
                Note("Also: focus/stop, quiet/off, quiet/toggle, timer, todo/add, note, summon, show, hide, pet, emote?name=wave, ask.")),
            Group("File Drop Zone",
                Check("Drop files on Cookie to file or zip them", s => s.FileDropEnabled, (s, on) => s.FileDropEnabled = on),
                folderRow,
                Note("Drag files onto Cookie and pick Move, Copy or Zip. Zips are made beside the original files. Nothing is overwritten or deleted.")),
            Group("Clipboard Buddy",
                Check($"Remember my last {ClipboardHistory.Capacity} copies", s => s.ClipboardHistory, (s, on) => s.ClipboardHistory = on),
                Note("Text only, kept in memory and never saved to disk: it's gone when Cookie quits or you turn this off. Copies that password managers mark as private are skipped. Find it under Clipboard in Cookie's menu.")),
            Group("Ask Cookie",
                Check("Chat with Cookie using Claude", s => s.AskCookieEnabled, (s, on) => s.AskCookieEnabled = on),
                keyRow,
                _keyStatus,
                chatButtons,
                Note($"This is the one feature that goes online. Your questions and Cookie's name are sent to Anthropic's Claude API (model {AskCookie.Model}) and billed to your own API key. Nothing else on your PC is sent, and the chat is forgotten when you close its window.")));
    }

    private void UpdateFolder()
    {
        string path = Profile.Settings.DropFolderPath;
        _folder.Text = path.Length > 0 ? path : "No folder chosen yet";
    }

    private void UpdateKeyStatus(string? message)
    {
        _keyStatus.Text = message ?? (ApiKeyStore.HasKey ? "A key is saved in Windows Credential Manager." : "No key saved.");
    }
}
