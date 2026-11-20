using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Desktop;

namespace Cookie.Windows.Views;

/// <summary>A small window with one text field, used for reminders, tasks and sticky notes.</summary>
public sealed class TextPromptWindow : Window
{
    private readonly TextBox _text;
    private readonly ComboBox? _minutes;
    private readonly Button _ok;

    /// <param name="withMinutes">Shows a "Remind me in" picker, for reminders.</param>
    public TextPromptWindow(string title, string prompt, string placeholder, string actionTitle, Action<string, int> onDone,
        string initialText = "", bool multiline = false, int maximumLength = 120, bool withMinutes = false, bool allowEmpty = false)
    {
        Title = title;
        Width = 380;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ShowInTaskbar = true;
        Topmost = true;
        CookieTheme.Attach(this);

        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = prompt, FontWeight = FontWeights.SemiBold, FontSize = 14, Margin = new Thickness(0, 0, 0, 10), TextWrapping = TextWrapping.Wrap });

        _text = new TextBox
        {
            Text = initialText,
            MaxLength = maximumLength,
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            MinHeight = multiline ? 90 : 0,
            VerticalScrollBarVisibility = multiline ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled,
            ToolTip = placeholder
        };
        System.Windows.Automation.AutomationProperties.SetName(_text, prompt);
        panel.Children.Add(_text);
        panel.Children.Add(new TextBlock { Text = placeholder, FontSize = 11, Opacity = 0.65, Margin = new Thickness(2, 4, 0, 0), TextWrapping = TextWrapping.Wrap });

        if (withMinutes)
        {
            var row = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
            row.Children.Add(new TextBlock { Text = "Remind me in", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
            _minutes = new ComboBox { MinWidth = 140 };
            foreach (int minutes in CookieReminder.PresetMinutes) _minutes.Items.Add(new ComboBoxItem { Content = CookieReminder.Label(minutes), Tag = minutes });
            _minutes.SelectedIndex = Array.IndexOf(CookieReminder.PresetMinutes, 20);
            row.Children.Add(_minutes);
            panel.Children.Add(row);
        }

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 80, Margin = new Thickness(0, 0, 8, 0) };
        cancel.Click += (s, e) => Close();
        _ok = new Button { Content = actionTitle, IsDefault = !multiline, MinWidth = 90 };
        _ok.Click += (s, e) =>
        {
            string value = _text.Text.Trim();
            if (value.Length == 0 && !allowEmpty) return;
            int minutes = _minutes?.SelectedItem is ComboBoxItem { Tag: int m } ? m : 0;
            onDone(value, minutes);
            Close();
        };
        buttons.Children.Add(cancel);
        buttons.Children.Add(_ok);
        panel.Children.Add(buttons);

        if (!allowEmpty)
        {
            _ok.IsEnabled = _text.Text.Trim().Length > 0;
            _text.TextChanged += (s, e) => _ok.IsEnabled = _text.Text.Trim().Length > 0;
        }

        Content = panel;
        Loaded += (s, e) =>
        {
            _text.Focus();
            _text.SelectAll();
            Activate();
        };
    }
}

/// <summary>A sticky note on the desktop. Drag it anywhere; hover for color, edit and done.</summary>
public sealed class StickyNoteWindow : Window
{
    private readonly TextBlock _text;
    private readonly Border _paper;
    private readonly StackPanel _tools;

    public Guid NoteId { get; }
    public event Action<Guid>? Recolor;
    public event Action<Guid>? Edit;
    public event Action<Guid>? Done;
    public event Action<Guid, double, double>? Moved;

    public StickyNoteWindow(StickyNote note)
    {
        NoteId = note.Id;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        Width = StickyNote.Width;
        Height = StickyNote.Height;
        Title = "Sticky note";

        _text = new TextBlock
        {
            FontSize = 13,
            FontWeight = FontWeights.Medium,
            Foreground = new SolidColorBrush(Color.FromArgb(0xC8, 0, 0, 0)),
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Margin = new Thickness(12, 18, 12, 10)
        };
        _tools = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 4, 4, 0), Visibility = Visibility.Collapsed };
        _tools.Children.Add(ToolButton("🎨", "Change color", () => Recolor?.Invoke(NoteId)));
        _tools.Children.Add(ToolButton("✏", "Edit note", () => Edit?.Invoke(NoteId)));
        _tools.Children.Add(ToolButton("✓", "Done with this note", () => Done?.Invoke(NoteId)));

        var tape = new Border
        {
            Width = 46,
            Height = 12,
            Background = new SolidColorBrush(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF)),
            CornerRadius = new CornerRadius(2),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, -4, 0, 0),
            RenderTransform = new RotateTransform(-4)
        };

        var grid = new Grid();
        grid.Children.Add(_text);
        grid.Children.Add(tape);
        grid.Children.Add(_tools);
        _paper = new Border
        {
            CornerRadius = new CornerRadius(6),
            Margin = new Thickness(6),
            Child = grid,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Opacity = 0.25 }
        };
        Content = _paper;

        MouseLeftButtonDown += (s, e) =>
        {
            if (e.ClickCount == 2)
            {
                Edit?.Invoke(NoteId);
                return;
            }
            try { DragMove(); } catch (InvalidOperationException) { }
            Moved?.Invoke(NoteId, Left, Top);
        };
        MouseEnter += (s, e) => _tools.Visibility = Visibility.Visible;
        MouseLeave += (s, e) => _tools.Visibility = Visibility.Collapsed;

        Update(note);
    }

    public void Update(StickyNote note)
    {
        _text.Text = note.Text;
        _paper.Background = (SolidColorBrush)new BrushConverter().ConvertFromString(note.Color.Hex())!;
        System.Windows.Automation.AutomationProperties.SetName(this, $"Sticky note: {note.Text}");
    }

    private static Button ToolButton(string glyph, string label, Action action)
    {
        var button = new Button
        {
            Content = glyph,
            Width = 22,
            Height = 22,
            Padding = new Thickness(0),
            Margin = new Thickness(2, 0, 0, 0),
            FontSize = 11,
            ToolTip = label,
            Background = new SolidColorBrush(Color.FromArgb(0xB3, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(0),
            Cursor = Cursors.Hand
        };
        System.Windows.Automation.AutomationProperties.SetName(button, label);
        button.Click += (s, e) => action();
        return button;
    }
}

/// <summary>The "Ask Cookie" chat window.</summary>
public sealed class AskCookieWindow : Window
{
    private readonly ChatSession _chat;
    private readonly string _name;
    private readonly StackPanel _lines = new() { Margin = new Thickness(14) };
    private readonly ScrollViewer _scroll;
    private readonly TextBox _input;
    private readonly Button _send;
    private readonly TextBlock _status;
    private readonly Func<bool> _isReady;

    public AskCookieWindow(ChatSession chat, string name, Func<bool> isReady, Action openSettings)
    {
        _chat = chat;
        _name = name;
        _isReady = isReady;
        Title = $"Ask {name}";
        Width = 420;
        Height = 500;
        MinWidth = 340;
        MinHeight = 360;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        CookieTheme.Attach(this);

        _scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _lines };
        _input = new TextBox { AcceptsReturn = false, TextWrapping = TextWrapping.Wrap, MaxLength = AskCookie.MaximumQuestion, VerticalContentAlignment = VerticalAlignment.Center, MinHeight = 32 };
        System.Windows.Automation.AutomationProperties.SetName(_input, $"Question for {name}");
        _send = new Button { Content = "Send", MinWidth = 70, Margin = new Thickness(8, 0, 0, 0), IsDefault = true };
        _send.Click += async (s, e) => await SendAsync();
        _status = new TextBlock { Opacity = 0.7, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };

        var openSettingsButton = new Button { Content = "Open Settings", Margin = new Thickness(8, 0, 0, 0) };
        openSettingsButton.Click += (s, e) => openSettings();
        var newChat = new Button { Content = "New Chat", Margin = new Thickness(0, 0, 8, 0) };
        newChat.Click += (s, e) => _chat.Reset();

        var inputRow = new DockPanel { Margin = new Thickness(12) };
        DockPanel.SetDock(_send, Dock.Right);
        DockPanel.SetDock(newChat, Dock.Left);
        inputRow.Children.Add(_send);
        inputRow.Children.Add(newChat);
        inputRow.Children.Add(_input);

        var setupRow = new DockPanel { Margin = new Thickness(12) };
        DockPanel.SetDock(openSettingsButton, Dock.Right);
        setupRow.Children.Add(openSettingsButton);
        setupRow.Children.Add(new TextBlock { Text = "Turn on Ask Cookie and add your Claude API key to start.", Opacity = 0.7, TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center });

        var root = new DockPanel();
        var bottom = new StackPanel();
        bottom.Children.Add(new Separator());
        bottom.Children.Add(inputRow);
        bottom.Children.Add(setupRow);
        DockPanel.SetDock(bottom, Dock.Bottom);
        root.Children.Add(bottom);
        root.Children.Add(_scroll);
        Content = root;

        void RefreshReady()
        {
            bool ready = _isReady();
            inputRow.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
            setupRow.Visibility = ready ? Visibility.Collapsed : Visibility.Visible;
        }
        Activated += (s, e) => RefreshReady();
        RefreshReady();

        _chat.Changed += OnChanged;
        Closed += (s, e) =>
        {
            _chat.Changed -= OnChanged;
            // The conversation lives only as long as the window.
            _chat.Reset();
        };
        Loaded += (s, e) => _input.Focus();
        Render();
    }

    private void OnChanged() => Dispatcher.InvokeAsync(Render);

    private async System.Threading.Tasks.Task SendAsync()
    {
        string text = _input.Text;
        if (string.IsNullOrWhiteSpace(text) || _chat.IsThinking) return;
        _input.Text = "";
        await _chat.AskAsync(text);
    }

    private void Render()
    {
        _lines.Children.Clear();
        if (_chat.Lines.Count == 0)
        {
            _lines.Children.Add(new TextBlock
            {
                Text = $"Ask {_name} anything. Your questions go to Claude, Anthropic's AI, using your own API key. Nothing is saved after you close this window.",
                Opacity = 0.7,
                TextWrapping = TextWrapping.Wrap
            });
        }
        foreach (var line in _chat.Lines) _lines.Children.Add(Bubble(line));
        if (_chat.IsThinking) _lines.Children.Add(new TextBlock { Text = $"{_name} is thinking…", Opacity = 0.7, Margin = new Thickness(0, 6, 0, 0) });
        _send.IsEnabled = !_chat.IsThinking;
        _scroll.ScrollToEnd();
    }

    private UIElement Bubble(ChatLine line)
    {
        if (line.Speaker == ChatSpeaker.Notice)
        {
            return new TextBlock { Text = line.Text, FontSize = 11, Opacity = 0.7, TextWrapping = TextWrapping.Wrap, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 6), TextAlignment = TextAlignment.Center };
        }
        bool mine = line.Speaker == ChatSpeaker.You;
        var text = new TextBox
        {
            Text = line.Text,
            IsReadOnly = true,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            TextWrapping = TextWrapping.Wrap
        };
        System.Windows.Automation.AutomationProperties.SetName(text, mine ? $"You said: {line.Text}" : $"{_name} says: {line.Text}");
        return new Border
        {
            Child = text,
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(8, 4, 8, 4),
            Margin = new Thickness(mine ? 48 : 0, 4, mine ? 0 : 48, 4),
            HorizontalAlignment = mine ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Background = mine
                ? new SolidColorBrush(Color.FromArgb(0x38, 0xE0, 0x8A, 0x3C))
                : new SolidColorBrush(Color.FromArgb(0x24, 0x80, 0x80, 0x80))
        };
    }
}
