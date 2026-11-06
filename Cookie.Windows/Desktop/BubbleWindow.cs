using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// A small borderless window that floats above Cookie with a line of text and fades away. It follows her
/// while she walks, and never takes a click.
/// </summary>
public sealed class BubbleWindow : Window
{
    private readonly TextBlock _text;
    private readonly DispatcherTimer _hideTimer = new();
    private Window? _anchor;

    /// <summary>Set while she is hidden, for example during a full-screen app.</summary>
    public bool IsSuppressed { get; set; }

    public BubbleWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        Focusable = false;
        SizeToContent = SizeToContent.WidthAndHeight;
        IsHitTestVisible = false;

        _text = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            MaxWidth = 230
        };
        _text.SetResourceReference(TextBlock.ForegroundProperty, "TextCharcoal");

        var card = new Border
        {
            CornerRadius = new CornerRadius(14),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(14, 9, 14, 9),
            Margin = new Thickness(8),
            Child = _text,
            Effect = new DropShadowEffect { BlurRadius = 10, ShadowDepth = 2, Opacity = 0.18, Color = Colors.Black }
        };
        card.SetResourceReference(Border.BackgroundProperty, "BgWarmWhite");
        card.SetResourceReference(Border.BorderBrushProperty, "BorderSubtle");
        Content = card;

        _hideTimer.Tick += (s, e) => Dismiss();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        IntPtr handle = new WindowInteropHelper(this).Handle;
        int style = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE).ToInt32();
        style |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TRANSPARENT;
        NativeMethods.SetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
    }

    /// <summary>Shows <paramref name="text"/> above <paramref name="companion"/> for a few seconds.</summary>
    public void Say(string text, Window companion, double seconds = 4.5)
    {
        if (IsSuppressed) return;

        _text.Text = text;
        if (_anchor != null) _anchor.LocationChanged -= OnAnchorMoved;
        _anchor = companion;
        companion.LocationChanged += OnAnchorMoved;

        _hideTimer.Stop();
        if (!IsVisible)
        {
            Opacity = 0;
            Show();
            BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(200)));
        }
        else
        {
            BeginAnimation(OpacityProperty, null);
            Opacity = 1;
        }

        // The size is only known after layout has seen the new text.
        Dispatcher.BeginInvoke(Reposition, DispatcherPriority.Loaded);
        _hideTimer.Interval = TimeSpan.FromSeconds(seconds);
        _hideTimer.Start();
    }

    public void Dismiss()
    {
        _hideTimer.Stop();
        if (!IsVisible) return;

        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(250));
        fade.Completed += (s, e) =>
        {
            // A new message may have arrived while it faded.
            if (!_hideTimer.IsEnabled) Hide();
        };
        BeginAnimation(OpacityProperty, fade);
    }

    public void HideNow()
    {
        _hideTimer.Stop();
        BeginAnimation(OpacityProperty, null);
        if (IsVisible) Hide();
    }

    private void OnAnchorMoved(object? sender, EventArgs e) => Reposition();

    private void Reposition()
    {
        if (_anchor == null) return;

        var origin = BubblePlacement.Origin(
            new CoreSize(ActualWidth, ActualHeight),
            new CoreRect(_anchor.Left, _anchor.Top, _anchor.Width, _anchor.Height),
            new CoreRect(SystemParameters.VirtualScreenLeft, SystemParameters.VirtualScreenTop,
                SystemParameters.VirtualScreenWidth, SystemParameters.VirtualScreenHeight));
        Left = origin.X;
        Top = origin.Y;
    }
}
