using System;
using Cookie.Windows.Core.Desktop;

namespace Cookie.Windows.Core.Windows;

/// <summary>
/// Observable representation of an external application window on the Windows desktop.
/// All bounds are normalized to WPF Device-Independent Pixels (DIPs).
/// </summary>
public record ObservableWindow(
    IntPtr Handle,
    string Title,
    string ProcessName,
    int ProcessId,
    CoreRect Bounds,
    bool IsOccluded = false,
    bool IsActive = false)
{
    public DateTime LastObserved { get; init; } = DateTime.UtcNow;

    /// <summary>
    /// Top horizontal edge segment Y coordinate (in DIPs).
    /// Suitable for walking surface.
    /// </summary>
    public double TopEdgeY => Bounds.Top;

    /// <summary>
    /// Left vertical edge X coordinate (in DIPs).
    /// </summary>
    public double LeftEdgeX => Bounds.Left;

    /// <summary>
    /// Right vertical edge X coordinate (in DIPs).
    /// </summary>
    public double RightEdgeX => Bounds.Right;

    /// <summary>
    /// Bottom horizontal edge segment Y coordinate (in DIPs).
    /// </summary>
    public double BottomEdgeY => Bounds.Bottom;

    public double Width => Bounds.Width;
    public double Height => Bounds.Height;
}
