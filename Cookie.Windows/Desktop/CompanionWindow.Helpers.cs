using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;
using Cookie.Windows.Views;
using Microsoft.Win32;

namespace Cookie.Windows.Desktop;

/// <summary>
/// The jobs Cookie does for you: reminders, break nudges, the focus guard, bedtime, the system watcher, sticky
/// notes, the to-do list, downloads and screenshots, cookie:// links, the file drop zone, the clipboard buddy and
/// Ask Cookie.
/// </summary>
public partial class CompanionWindow : IHelpersMenuSource
{
    private HelpersCoordinator _helpers = null!;
    private readonly WindowsSystemProbe _probe = new();
    private DispatcherTimer? _helperTimer;
    private readonly Dictionary<Guid, StickyNoteWindow> _noteWindows = new();
    private readonly ClipboardHistory _clipboard = new();
    private bool _clipboardListening;
    private ChatSession _chat = null!;
    private AskCookieWindow? _chatWindow;
    private CommandChannel? _commands;
    private IntPtr _helperHandle;

    public HelpersCoordinator Helpers => _helpers;
    public ClipboardHistory Clipboard => _clipboard;
    public bool IsManuallyQuiet => _quiet?.IsManuallyQuiet == true;

    private void InitializeHelpers()
    {
        _helpers = new HelpersCoordinator(_profile, _behaviorController)
        {
            Say = (text, seconds) => Say(text, seconds),
            Play = effect => _audioManager.Play(effect),
            BringToCursor = BringToCursor,
            Save = () => _settingsManager.DebouncedSave(_profile),
            IdleTime = WindowsSystemProbe.IdleTime,
            IsQuiet = () => _quiet?.IsQuiet == true,
            IsFocusing = () => _focus.IsFocusing,
            IsVisible = () => IsVisible,
            FrontmostProcess = () => _behaviorController.ContextDetector.CurrentContext.ProcessName,
            SystemSnapshot = _probe.Snapshot,
            DownloadsListing = () => HelpersCoordinator.ListFolder(KnownFolders.Downloads),
            ScreenshotCandidates = () => HelpersCoordinator.FindScreenshots(KnownFolders.Desktop, DateTime.UtcNow),
            MoveScreenshots = (names, folder) => ScreenshotTidy.Move(names, folder, KnownFolders.Screenshots)
        };
        _helpers.Changed += () => _settingsManager.DebouncedSave(_profile);

        _chat = new ChatSession(() => _profile) { ApiKey = ApiKeyStore.Load };
        _chat.Answered += () => Dispatcher.InvokeAsync(() => _behaviorController.React(CookieAnimationId.Happy));

        _behaviorController.ContextDetector.OnApplicationSwitched += context =>
            Dispatcher.InvokeAsync(() => _helpers.AppSwitched(context.ProcessName));

        AllowDrop = true;
        DragOver += OnDragOver;
        Drop += OnDrop;
    }

    private void StartHelpers(IntPtr windowHandle)
    {
        _helperHandle = windowHandle;
        _helpers.Start();
        _helperTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _helperTimer.Tick += (s, e) => _helpers.Tick();
        _helperTimer.Start();

        RefreshNotes();
        ApplyHelperSettings();

        LinkProtocol.Register();
        _commands = new CommandChannel(CommandChannel.PipeNameForCurrentUser());
        _commands.Received += link => Dispatcher.InvokeAsync(() => HandleLink(link));
        _commands.StartListening();
    }

    private void StopHelpers()
    {
        _helperTimer?.Stop();
        _commands?.Dispose();
        _commands = null;
        SetClipboardListening(false);
        foreach (var window in _noteWindows.Values.ToList()) window.Close();
        _noteWindows.Clear();
        _chatWindow?.Close();
    }

    /// <summary>Settings that turn things on and off: the clipboard listener and the notes.</summary>
    private void ApplyHelperSettings()
    {
        if (_helpers == null) return;
        SetClipboardListening(_profile.Settings.ClipboardHistory);
        RefreshNotes();
    }

    /// <summary>Puts her beside the cursor, showing her if she was hidden. Reminders use this.</summary>
    private void BringToCursor()
    {
        _quiet?.GrantOverride(20);
        SummonCookie();
    }

    // MARK: Manual quiet

    public void SetManualQuiet(bool on, int? minutes = null)
    {
        _quiet?.SetManualQuiet(on, minutes);
    }

    // MARK: Prompts

    public void NewReminder()
    {
        new TextPromptWindow("New Reminder", $"What should {_profile.DisplayName} remind you about?",
            "Call Mom, stretch, take the pizza out… Leave it empty for a simple timer.", "Remind Me",
            (text, minutes) => _helpers.AddReminder(text, minutes == 0 ? 20 : minutes),
            withMinutes: true, allowEmpty: true).Show();
    }

    public void NewTodo()
    {
        new TextPromptWindow("New Task", "What do you need to do?", "Reply to Sam, water the plants…", "Add",
            (text, _) =>
            {
                if (_helpers.AddTodo(text)) Say("Added to your list!", 3);
            }).Show();
    }

    public void NewStickyNote()
    {
        new TextPromptWindow("New Sticky Note", "What should the note say?", "Buy milk, call the bank…", "Pin It",
            (text, _) => AddStickyNote(text), multiline: true, maximumLength: StickyNote.MaximumLength).Show();
    }

    // MARK: Sticky notes

    /// <summary>Pins a new note beside her bed if she has one, otherwise beside her.</summary>
    public void AddStickyNote(string text)
    {
        var area = _screenService.GetPrimaryWorkArea();
        var anchor = new CoreRect(Left, Top, Width, Height);
        if (_profile.CozyItems.FirstOrDefault(p => p.Kind == CozyKind.Bed) is { } bed)
        {
            double x = _behaviorController.CozyCenterX(bed);
            anchor = new CoreRect(x - 60, area.Bottom - 120, 120, 120);
        }
        var note = new StickyNote
        {
            Text = text.Length > StickyNote.MaximumLength ? text[..StickyNote.MaximumLength] : text,
            Color = Enum.GetValues<StickyColor>()[_profile.StickyNotes.Count % 4]
        };
        (note.Left, note.Top) = StickyNote.PlaceBeside(anchor, area, _profile.StickyNotes.Count);
        _profile.StickyNotes.Add(note);
        _profile.Settings.ShowStickyNotes = true;
        _settingsManager.DebouncedSave(_profile);
        RefreshNotes();
        _behaviorController.React(CookieAnimationId.Happy);
        Say("Pinned it for you!", 3);
    }

    public void SetNotesVisible(bool visible)
    {
        _profile.Settings.ShowStickyNotes = visible;
        _settingsManager.DebouncedSave(_profile);
        RefreshNotes();
    }

    private void RefreshNotes()
    {
        bool show = _profile.Settings.ShowStickyNotes && _quiet?.IsQuiet != true;
        var wanted = _profile.StickyNotes.ToDictionary(n => n.Id);
        foreach (var (id, window) in _noteWindows.ToList())
        {
            if (!show || !wanted.ContainsKey(id))
            {
                window.Close();
                _noteWindows.Remove(id);
            }
        }
        if (!show) return;

        foreach (var note in _profile.StickyNotes)
        {
            if (_noteWindows.TryGetValue(note.Id, out var existing))
            {
                existing.Update(note);
                continue;
            }
            var window = new StickyNoteWindow(note) { Left = note.Left ?? 200, Top = note.Top ?? 200 };
            window.Recolor += id => UpdateNote(id, n => n.Color = n.Color.Next());
            window.Edit += EditNote;
            window.Done += id =>
            {
                _profile.StickyNotes.RemoveAll(n => n.Id == id);
                _settingsManager.DebouncedSave(_profile);
                RefreshNotes();
            };
            window.Moved += (id, left, top) => UpdateNote(id, n => (n.Left, n.Top) = (left, top), refresh: false);
            window.SourceInitialized += (s, e) => ScreenSharingGuard.Apply(window, _profile.Settings.HideFromScreenSharing);
            _noteWindows[note.Id] = window;
            window.Show();
        }
    }

    private void UpdateNote(Guid id, Action<StickyNote> change, bool refresh = true)
    {
        if (_profile.StickyNotes.FirstOrDefault(n => n.Id == id) is not { } note) return;
        change(note);
        _settingsManager.DebouncedSave(_profile);
        if (refresh) RefreshNotes();
    }

    private void EditNote(Guid id)
    {
        if (_profile.StickyNotes.FirstOrDefault(n => n.Id == id) is not { } note) return;
        new TextPromptWindow("Edit Note", "Edit the note", "Up to 280 characters.", "Save",
            (text, _) => UpdateNote(id, n => n.Text = text), initialText: note.Text, multiline: true, maximumLength: StickyNote.MaximumLength).Show();
    }

    // MARK: Screenshots

    public void ConfirmTidyScreenshots()
    {
        int count = _helpers.TidyableScreenshotCount();
        if (count == 0)
        {
            MessageBox.Show("No screenshots older than a day on your Desktop.", "Tidy Up Screenshots", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var answer = MessageBox.Show(
            $"Move {count} screenshot{(count == 1 ? "" : "s")} older than a day from your Desktop into your Screenshots folder ({KnownFolders.Screenshots})? Nothing is deleted.",
            "Tidy Up Screenshots", MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (answer == MessageBoxResult.OK) _helpers.TidyScreenshots();
    }

    // MARK: Clipboard buddy

    private void SetClipboardListening(bool on)
    {
        if (_helperHandle == IntPtr.Zero || on == _clipboardListening)
        {
            if (!on) _clipboard.Clear();
            return;
        }
        if (on)
        {
            _clipboardListening = HelperNativeMethods.AddClipboardFormatListener(_helperHandle);
        }
        else
        {
            HelperNativeMethods.RemoveClipboardFormatListener(_helperHandle);
            _clipboardListening = false;
            // Turning it off forgets everything.
            _clipboard.Clear();
        }
    }

    /// <summary>Called for WM_CLIPBOARDUPDATE. Text only; anything a password manager marks as private is skipped.</summary>
    private void OnClipboardUpdate()
    {
        if (!_profile.Settings.ClipboardHistory) return;
        try
        {
            var data = System.Windows.Clipboard.GetDataObject();
            if (data == null || ClipboardHistory.PrivateFormats.Any(data.GetDataPresent)) return;
            if (!data.GetDataPresent(DataFormats.UnicodeText)) return;
            if (data.GetData(DataFormats.UnicodeText) is not string text) return;
            _clipboard.Add(text);
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            // Another app has the clipboard open; skip this copy.
        }
    }

    public void CopyBack(string text)
    {
        try
        {
            System.Windows.Clipboard.SetText(text);
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            Say("The clipboard is busy. Try again in a moment.", 3);
        }
    }

    // MARK: File drop zone

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = _profile.Settings.FileDropEnabled && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (!_profile.Settings.FileDropEnabled || e.Data.GetData(DataFormats.FileDrop) is not string[] paths || paths.Length == 0) return;
        e.Handled = true;
        _behaviorController.React(CookieAnimationId.Surprised);
        _audioManager.Play(SoundEffect.Chirp);

        var menu = new ContextMenu();
        menu.Items.Add(new MenuItem { Header = paths.Length == 1 ? Path.GetFileName(paths[0]) : $"{paths.Length} items", IsEnabled = false });
        menu.Items.Add(new Separator());
        string folder = _profile.Settings.DropFolderPath;
        bool hasFolder = folder.Length > 0 && Directory.Exists(folder);
        if (hasFolder)
        {
            string folderName = Path.GetFileName(folder.TrimEnd('\\', '/'));
            AddDropItem(menu, $"Move to {folderName}", () => RunDrop(paths, FileDropActionKind.Move, folder));
            AddDropItem(menu, $"Copy to {folderName}", () => RunDrop(paths, FileDropActionKind.Copy, folder));
        }
        AddDropItem(menu, paths.Length == 1 ? "Zip It" : "Zip Them Together", () => RunDrop(paths, FileDropActionKind.Zip, null));
        menu.Items.Add(new Separator());
        AddDropItem(menu, hasFolder ? "Move to Another Folder…" : "Choose a Folder for Files…", () =>
        {
            var dialog = new OpenFolderDialog { Title = "Choose where Cookie files things" };
            if (dialog.ShowDialog() != true) return;
            _profile.Settings.DropFolderPath = dialog.FolderName;
            _settingsManager.DebouncedSave(_profile);
            RunDrop(paths, FileDropActionKind.Move, dialog.FolderName);
        });
        menu.PlacementTarget = this;
        menu.IsOpen = true;
    }

    private static void AddDropItem(ContextMenu menu, string header, Action action)
    {
        var item = new MenuItem { Header = header };
        item.Click += (s, e) => action();
        menu.Items.Add(item);
    }

    private async void RunDrop(string[] paths, FileDropActionKind action, string? folder)
    {
        int done = await System.Threading.Tasks.Task.Run(() => action switch
        {
            FileDropActionKind.Zip => FileDrop.Zip(paths) != null ? paths.Length : 0,
            _ => FileDrop.MoveOrCopy(paths, folder!, copy: action == FileDropActionKind.Copy)
        });
        if (done == paths.Length)
        {
            _behaviorController.React(CookieAnimationId.Happy);
            _audioManager.Play(SoundEffect.Happy);
            Say(FileDrop.Summary(paths.Length, action, folder), 4);
        }
        else if (done > 0)
        {
            Say($"I managed {done} of {paths.Length}. The rest wouldn't budge.", 5);
        }
        else
        {
            _behaviorController.React(CookieAnimationId.Annoyed);
            Say("I couldn't do that. Check that the folder isn't read-only.", 5);
        }
    }

    // MARK: Ask Cookie

    public void OpenAskCookie()
    {
        if (_chatWindow != null)
        {
            _chatWindow.Activate();
            return;
        }
        _chatWindow = new AskCookieWindow(_chat, _profile.DisplayName, () => _chat.IsReady, OpenSettingsWindow);
        _chatWindow.Closed += (s, e) => _chatWindow = null;
        _chatWindow.Show();
    }

    // MARK: cookie:// links

    public void HandleLink(string link)
    {
        if (CookieCommand.Parse(link, out _) is { } command) Perform(command);
    }

    /// <summary>Runs a command from a cookie:// link.</summary>
    public void Perform(CookieCommand command)
    {
        if (!_profile.Settings.AllowLinks) return;
        switch (command.Kind)
        {
            case CookieCommandKind.Say:
                Say(command.Text, Math.Clamp(command.Text.Length / 12.0, 4, 12));
                break;
            case CookieCommandKind.Remind:
                _helpers.AddReminder(command.Text, command.Minutes ?? 20);
                break;
            case CookieCommandKind.StartFocus:
                StartFocus(command.Minutes ?? _profile.Settings.FocusMinutes);
                break;
            case CookieCommandKind.StopFocus:
                StopFocus();
                break;
            case CookieCommandKind.Quiet:
                SetManualQuiet(command.On, command.On ? command.Minutes : null);
                break;
            case CookieCommandKind.ToggleQuiet:
                SetManualQuiet(!IsManuallyQuiet);
                break;
            case CookieCommandKind.Show:
                if (!IsVisible) BringToCursor();
                break;
            case CookieCommandKind.Hide:
                if (IsVisible)
                {
                    _gameLoopTimer.Stop();
                    Hide();
                    _bubble?.HideNow();
                }
                break;
            case CookieCommandKind.Summon:
                if (IsManuallyQuiet) SetManualQuiet(false);
                SummonCookie();
                break;
            case CookieCommandKind.Pet:
                _behaviorController.Pet();
                break;
            case CookieCommandKind.Emote:
                if (Emote.FromId(command.Emote) is { } emote) _behaviorController.TriggerEmote(emote);
                break;
            case CookieCommandKind.AddTodo:
                if (_helpers.AddTodo(command.Text)) Say("Added to your list!", 3);
                break;
            case CookieCommandKind.AddNote:
                AddStickyNote(command.Text);
                break;
            case CookieCommandKind.Ask:
                OpenAskCookie();
                break;
        }
    }
}
