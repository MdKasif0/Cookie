using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;
using Cookie.Windows.Rendering;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Shows Cookie's cozy items as small windows resting on the floor behind her. Positions are stored as fractions of
/// the main screen's work area. Drag one sideways to move it; right-click to put it away.
/// </summary>
public sealed class CozyWindowManager
{
    private const double GroundInsetRatio = 0.1;
    private const double FloorMargin = 10;

    private readonly Dictionary<CozyKind, CozyWindow> _windows = new();
    private bool _excludeFromCapture;

    public Action<CozyKind, double>? OnMoved { get; set; }
    public Action<CozyKind>? OnRemoved { get; set; }

    public IEnumerable<Window> Windows => _windows.Values;

    public void SetExcludedFromCapture(bool exclude)
    {
        _excludeFromCapture = exclude;
        foreach (var window in _windows.Values) ScreenSharingGuard.Apply(window, exclude);
    }

    public void HideAll()
    {
        foreach (var window in _windows.Values) window.Hide();
    }

    /// <summary>Brings the windows in line with <paramref name="placements"/>. Call again after showing Cookie so she stays in front.</summary>
    public void Update(IReadOnlyList<CozyPlacement> placements, double scale)
    {
        var wanted = placements.Select(p => p.Kind).ToHashSet();
        foreach (var kind in _windows.Keys.Where(kind => !wanted.Contains(kind)).ToList())
        {
            _windows[kind].Close();
            _windows.Remove(kind);
        }

        var area = SystemParameters.WorkArea;
        double ground = area.Bottom - FloorMargin;
        foreach (var placement in placements)
        {
            if (!_windows.TryGetValue(placement.Kind, out var window))
            {
                window = new CozyWindow(placement.Kind, (kind, fraction) => OnMoved?.Invoke(kind, fraction), kind => OnRemoved?.Invoke(kind));
                ScreenSharingGuard.Apply(window, _excludeFromCapture);
                _windows[placement.Kind] = window;
            }

            double side = placement.Kind.GetPanelSide() * scale;
            double centerX = area.Left + placement.Position * area.Width;
            window.Width = side;
            window.Height = side;
            window.Left = centerX - side / 2;
            window.Top = ground - side * (1 - GroundInsetRatio);
            if (!window.IsVisible) window.Show();
        }
    }

    public void CloseAll()
    {
        foreach (var window in _windows.Values) window.Close();
        _windows.Clear();
    }

    private sealed class CozyWindow : Window
    {
        private readonly CozyKind _kind;
        private readonly Action<CozyKind, double> _onMoved;
        private readonly Action<CozyKind> _onRemoved;
        private bool _isDragging;
        private double _grabOffset;

        public CozyWindow(CozyKind kind, Action<CozyKind, double> onMoved, Action<CozyKind> onRemoved)
        {
            _kind = kind;
            _onMoved = onMoved;
            _onRemoved = onRemoved;

            Title = kind.GetDisplayName();
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            ShowInTaskbar = false;
            Topmost = true;
            ResizeMode = ResizeMode.NoResize;
            ShowActivated = false;
            Focusable = false;
            Cursor = Cursors.Hand;
            ToolTip = $"{kind.GetDisplayName()} (drag to move, right-click to put away)";
            System.Windows.Automation.AutomationProperties.SetName(this, kind.GetDisplayName());

            var image = new Image { Source = CookieIcons.Art("Items", kind.GetAssetName()), Stretch = Stretch.Uniform };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
            Content = image;
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            IntPtr handle = new WindowInteropHelper(this).Handle;
            int style = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE).ToInt32();
            style |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
            NativeMethods.SetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE, new IntPtr(style));
        }

        protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            base.OnMouseLeftButtonDown(e);
            _isDragging = true;
            _grabOffset = e.GetPosition(this).X - ActualWidth / 2;
            CaptureMouse();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!_isDragging) return;

            var source = PresentationSource.FromVisual(this);
            double dpi = source?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
            double screenX = PointToScreen(e.GetPosition(this)).X / dpi;
            var area = SystemParameters.WorkArea;
            _onMoved(_kind, (screenX - _grabOffset - area.Left) / area.Width);
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
            _onRemoved(_kind);
        }
    }
}
