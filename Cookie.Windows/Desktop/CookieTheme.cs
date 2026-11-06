using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using Cookie.Windows.Interop;
using Microsoft.Win32;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Follows the Windows light or dark setting and gives standard windows a Mica backdrop.
/// Fluent styling for controls comes from each window's ThemeMode="System"; this adds
/// Cookie's own palette and the parts Fluent leaves to the app.
/// </summary>
public static class CookieTheme
{
    private const int DwmUseImmersiveDarkMode = 20;
    private const int DwmSystemBackdropType = 38;
    private const int BackdropMainWindow = 2;

    /// <summary>First Windows 11 build with the system backdrop attribute (22H2).</summary>
    private const int FirstBackdropBuild = 22621;

    private static readonly List<Window> AttachedWindows = new();
    private static ResourceDictionary? _palette;

    public static bool IsDark { get; private set; }

    public static void Initialize()
    {
        Refresh(force: true);
    }

    /// <summary>Re-reads the system setting; call when Windows reports a settings change.</summary>
    public static void Refresh(bool force = false)
    {
        bool isDark = ReadSystemIsDark();
        if (!force && isDark == IsDark) return;
        IsDark = isDark;

        var resources = Application.Current.Resources.MergedDictionaries;
        if (_palette != null) resources.Remove(_palette);
        _palette = new ResourceDictionary
        {
            Source = new Uri($"/Themes/Palette.{(isDark ? "Dark" : "Light")}.xaml", UriKind.Relative)
        };
        resources.Add(_palette);

        foreach (var window in AttachedWindows)
        {
            ApplyDarkTitleBar(window);
        }
    }

    /// <summary>Gives a standard, opaque window the dark title bar and Mica when supported.</summary>
    public static void Attach(Window window)
    {
        AttachedWindows.Add(window);
        window.Closed += (s, e) => AttachedWindows.Remove(window);
        window.SourceInitialized += (s, e) =>
        {
            ApplyDarkTitleBar(window);
            ApplyMica(window);
        };
    }

    private static void ApplyDarkTitleBar(Window window)
    {
        IntPtr handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        int enabled = IsDark ? 1 : 0;
        NativeMethods.DwmSetWindowAttribute(handle, DwmUseImmersiveDarkMode, ref enabled, sizeof(int));
    }

    private static void ApplyMica(Window window)
    {
        if (Environment.OSVersion.Version.Build < FirstBackdropBuild) return;

        IntPtr handle = new WindowInteropHelper(window).Handle;
        int backdrop = BackdropMainWindow;
        if (NativeMethods.DwmSetWindowAttribute(handle, DwmSystemBackdropType, ref backdrop, sizeof(int)) != 0) return;

        // Only clear the background once the system has accepted the backdrop, otherwise
        // the window would show black. Without Mica it keeps its solid Fluent background.
        var margins = new DwmMargins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
        if (NativeMethods.DwmExtendFrameIntoClientArea(handle, ref margins) != 0) return;

        if (HwndSource.FromHwnd(handle)?.CompositionTarget is { } target)
        {
            target.BackgroundColor = Colors.Transparent;
            window.Background = Brushes.Transparent;
        }
    }

    private static bool ReadSystemIsDark()
    {
        const string key = @"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
        return Registry.GetValue(key, "AppsUseLightTheme", 1) is int lightTheme && lightTheme == 0;
    }
}
