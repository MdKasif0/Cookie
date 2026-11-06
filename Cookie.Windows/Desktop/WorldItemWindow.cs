using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;
using Cookie.Windows.Rendering;

namespace Cookie.Windows.Desktop;

/// <summary>
/// A small transparent window showing one toy or treat on the desktop.
/// Drag to move it along the ground; right-click to put it away.
/// </summary>
public sealed class WorldItemWindow : Window
{
    private const double ItemSize = 80;

    /// <summary>The box is sized for Cookie to sit inside it.</summary>
    private const double BoxSize = 170;

    /// <summary>Share of the item's height below its art, so it rests on Cookie's ground line.</summary>
    private const double GroundInsetRatio = 0.1;

    private readonly double _size;
    private readonly Image _image;
    private readonly RotateTransform _wiggle;
    private readonly Action<double> _onMoved;
    private readonly Action _onDismiss;

    private bool _isDragging;
    private double _dragOffsetX;

    public WorldItemWindow(WorldItem item, Action<double> onMoved, Action onDismiss)
    {
        _size = item.IsBox ? BoxSize : ItemSize;
        _wiggle = new RotateTransform(0, _size / 2, _size / 2);
        _onMoved = onMoved;
        _onDismiss = onDismiss;

        Title = item.DisplayName;
        Width = _size;
        Height = _size;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        ShowActivated = false;
        Focusable = false;
        Cursor = Cursors.Hand;
        ToolTip = $"{item.DisplayName} (drag to move, right-click to put away)";
        AutomationPropertiesHelper.SetName(this, item.DisplayName);

        var image = new Image
        {
            Source = CookieIcons.Art("Items", item.AssetName),
            Width = _size,
            Height = _size,
            RenderTransform = _wiggle,
            SnapsToDevicePixels = true
        };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
        _image = image;
        Content = image;

        Reposition(item);
    }

    /// <summary>Swaps the art, for showing one wall of the box at a time.</summary>
    public void SetArt(string assetName)
    {
        _image.Source = CookieIcons.Art("Items", assetName);
    }

    public void Reposition(WorldItem item)
    {
        Left = item.X - _size / 2;
        Top = item.GroundY - _size * (1 - GroundInsetRatio);
    }

    public void SetInteracting(bool isInteracting)
    {
        if (!isInteracting)
        {
            _wiggle.BeginAnimation(RotateTransform.AngleProperty, null);
            _wiggle.Angle = 0;
            return;
        }

        var wiggle = new DoubleAnimation(-6, 6, TimeSpan.FromMilliseconds(220))
        {
            AutoReverse = true,
            RepeatBehavior = RepeatBehavior.Forever,
            EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut }
        };
        _wiggle.BeginAnimation(RotateTransform.AngleProperty, wiggle);
    }

    /// <summary>Topmost windows stack by when they became topmost, so re-assert to move to the front.</summary>
    public void BringToFront()
    {
        Topmost = false;
        Topmost = true;
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        IntPtr hWnd = new WindowInteropHelper(this).Handle;
        int exStyle = NativeMethods.GetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE).ToInt32();
        exStyle |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
        NativeMethods.SetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE, new IntPtr(exStyle));
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        _isDragging = true;
        _dragOffsetX = PointToScreen(e.GetPosition(this)).X - PointToScreen(new Point(_size / 2, 0)).X;
        CaptureMouse();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!_isDragging) return;

        // Screen pixels to DIPs for the current monitor.
        var source = PresentationSource.FromVisual(this);
        double dpiScale = source?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
        double centerX = (PointToScreen(e.GetPosition(this)).X - _dragOffsetX) / dpiScale;
        _onMoved(centerX);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        _isDragging = false;
        ReleaseMouseCapture();
    }

    protected override void OnMouseRightButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseRightButtonUp(e);
        _onDismiss();
    }

    private static class AutomationPropertiesHelper
    {
        public static void SetName(DependencyObject element, string name) =>
            System.Windows.Automation.AutomationProperties.SetName(element, name);
    }
}
