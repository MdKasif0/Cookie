using System;
using System.Collections.Generic;
using Cookie.Windows.Core.Windows;

namespace Cookie.Windows.Core.Desktop;

/// <summary>
/// Service abstraction for discovering display environment geometry, taskbar configuration,
/// and external window perimeters on the desktop.
/// </summary>
public interface IDesktopEnvironmentProvider
{
    /// <summary>
    /// Gets the current desktop environment snapshot in WPF Device-Independent Pixels (DIPs).
    /// </summary>
    DesktopEnvironment GetDesktopEnvironment(CorePoint? cookiePosition = null);

    /// <summary>
    /// Enumerates candidate external application windows suitable for surface walking/jumping.
    /// Excludes tooltips, menus, cloaked windows, minimized windows, and Cookie's own companion window.
    /// </summary>
    IReadOnlyList<ObservableWindow> EnumerateVisibleWindows();

    /// <summary>
    /// Discovers taskbar bounding boxes, orientations, and safe walking corridors across active monitors.
    /// </summary>
    IReadOnlyList<TaskbarInfo> GetTaskbarInfos();

    /// <summary>
    /// Triggered when display topology, resolution, DPI, or work area bounds change.
    /// </summary>
    event Action? OnEnvironmentChanged;
}
