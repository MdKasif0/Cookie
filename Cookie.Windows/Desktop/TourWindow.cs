using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Shows the helpers tour one step at a time in a small card beside Cookie that follows her as she moves.
/// It takes clicks without taking focus from the app you're using.
/// </summary>
public sealed class TourWindow : Window
{
    /// <summary>Called with each step as it appears, so Cookie can react to it.</summary>
    public Action<HelpersTour.Step>? StepShown;
    public Action<HelpersTour.TourAction>? ActionChosen;
    /// <summary>Called once when the tour ends: true if it was finished, false if skipped.</summary>
    public Action<bool>? Ended;
    /// <summary>The area the card must stay inside (the work area, so it never covers the taskbar).</summary>
    public Func<CoreRect>? VisibleArea;

    private readonly StackPanel _dots = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _title = new() { FontSize = 14, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 8, 0, 4) };
    private readonly TextBlock _text = new() { FontSize = 12.5, TextWrapping = TextWrapping.Wrap };
    private readonly Button _skip = new() { Content = "Skip Tour", Padding = new Thickness(4, 0, 4, 0), FontSize = 11, Cursor = Cursors.Hand };
    private readonly Button _try = new() { MinWidth = 90, Padding = new Thickness(10, 3, 10, 3) };
    private readonly Button _next = new() { MinWidth = 64, Padding = new Thickness(10, 3, 10, 3) };
    private IReadOnlyList<HelpersTour.Step> _steps = Array.Empty<HelpersTour.Step>();
    private int _index;
    private Window? _anchor;
    private bool _ending;

    public bool IsRunning => _steps.Count > 0;

    public TourWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        SizeToContent = SizeToContent.WidthAndHeight;

        _title.SetResourceReference(TextBlock.ForegroundProperty, "TextCharcoal");
        _text.SetResourceReference(TextBlock.ForegroundProperty, "TextMuted");
        _skip.SetResourceReference(Control.ForegroundProperty, "TextMuted");
        _skip.Background = Brushes.Transparent;
        _skip.BorderThickness = new Thickness(0);
        _skip.Click += (s, e) => End(finished: false);
        _try.Click += (s, e) => { if (_steps.Count > 0 && _steps[_index].Action is { } action) ActionChosen?.Invoke(action); };
        _next.Click += (s, e) => Advance();
        if (Application.Current.TryFindResource("AccentButtonStyle") is Style accent) _next.Style = accent;

        var header = new DockPanel();
        DockPanel.SetDock(_skip, Dock.Right);
        header.Children.Add(_skip);
        header.Children.Add(_dots);

        var buttons = new DockPanel { Margin = new Thickness(0, 12, 0, 0), LastChildFill = false };
        DockPanel.SetDock(_next, Dock.Right);
        buttons.Children.Add(_next);
        buttons.Children.Add(_try);

        var body = new StackPanel { Width = 250 };
        body.Children.Add(header);
        body.Children.Add(_title);
        body.Children.Add(_text);
        body.Children.Add(buttons);

        var card = new Border
        {
            CornerRadius = new CornerRadius(14),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(14),
            Margin = new Thickness(8),
            Child = body,
            Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 2, Opacity = 0.22, Color = Colors.Black }
        };
        card.SetResourceReference(Border.BackgroundProperty, "BgWarmWhite");
        card.SetResourceReference(Border.BorderBrushProperty, "BorderSubtle");
        Content = card;

        // Keyboard users: Escape skips, Enter goes on (when the card has been clicked into).
        PreviewKeyDown += (s, e) =>
        {
            if (e.Key == Key.Escape) { End(finished: false); e.Handled = true; }
            else if (e.Key == Key.Enter) { Advance(); e.Handled = true; }
        };
        SizeChanged += (s, e) => Reposition();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        IntPtr handle = new WindowInteropHelper(this).Handle;
        int style = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE).ToInt32();
        // A tool window that never activates: clicking its buttons leaves your app in front.
        style |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
        NativeMethods.SetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
    }

    public void Start(IReadOnlyList<HelpersTour.Step> steps, Window companion)
    {
        if (steps.Count == 0) return;
        _steps = steps;
        _index = 0;
        _ending = false;
        if (_anchor != null) _anchor.LocationChanged -= OnAnchorMoved;
        _anchor = companion;
        companion.LocationChanged += OnAnchorMoved;

        ShowStep();
        Opacity = 0;
        Show();
        BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(250)));
        Dispatcher.BeginInvoke(Reposition, DispatcherPriority.Loaded);
    }

    /// <summary>Hides the card without ending the tour, for example while a full-screen app is up.</summary>
    public void SetSuppressed(bool suppressed)
    {
        if (!IsRunning) return;
        if (suppressed) Hide();
        else { Show(); Reposition(); }
    }

    public void End(bool finished)
    {
        if (!IsRunning || _ending) return;
        _ending = true;
        _steps = Array.Empty<HelpersTour.Step>();
        if (_anchor != null) _anchor.LocationChanged -= OnAnchorMoved;
        _anchor = null;
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(200));
        fade.Completed += (s, e) => { if (!IsRunning) Hide(); };
        BeginAnimation(OpacityProperty, fade);
        Ended?.Invoke(finished);
    }

    private void ShowStep()
    {
        var step = _steps[_index];
        bool last = _index == _steps.Count - 1;

        _dots.Children.Clear();
        for (int i = 0; i < _steps.Count; i++)
        {
            var dot = new Rectangle { Height = 6, Width = i == _index ? 14 : 6, RadiusX = 3, RadiusY = 3, Margin = new Thickness(0, 0, 5, 0) };
            dot.SetResourceReference(Shape.FillProperty, i == _index ? "AccentCaramel" : "BorderBeige");
            _dots.Children.Add(dot);
        }
        AutomationProperties_SetName(_dots, $"Step {_index + 1} of {_steps.Count}");

        _title.Text = step.Title;
        _text.Text = step.Text;
        _skip.Visibility = last ? Visibility.Collapsed : Visibility.Visible;
        _try.Visibility = step.TryTitle == null ? Visibility.Collapsed : Visibility.Visible;
        _try.Content = step.TryTitle;
        _next.Content = last ? "Done" : "Next";
        StepShown?.Invoke(step);
    }

    private static void AutomationProperties_SetName(DependencyObject element, string name) =>
        System.Windows.Automation.AutomationProperties.SetName(element, name);

    private void Advance()
    {
        if (!IsRunning) return;
        if (_index + 1 < _steps.Count)
        {
            _index++;
            ShowStep();
        }
        else
        {
            End(finished: true);
        }
    }

    private void OnAnchorMoved(object? sender, EventArgs e) => Reposition();

    private void Reposition()
    {
        if (_anchor == null) return;
        var origin = HelpersTour.CardOrigin(
            new CoreSize(ActualWidth, ActualHeight),
            new CoreRect(_anchor.Left, _anchor.Top, _anchor.Width, _anchor.Height),
            VisibleArea?.Invoke() ?? new CoreRect(SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Top,
                SystemParameters.WorkArea.Width, SystemParameters.WorkArea.Height));
        Left = origin.X;
        Top = origin.Y;
    }

    /// <summary>The card's area on screen, so a note pinned during the tour can keep clear of it.</summary>
    public CoreRect Bounds => new(Left, Top, ActualWidth, ActualHeight);
}
