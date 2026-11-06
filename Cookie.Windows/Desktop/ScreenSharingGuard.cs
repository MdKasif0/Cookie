using System;
using System.Windows;
using System.Windows.Interop;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Asks Windows to leave a window out of screen sharing, recordings and screenshots, while it stays visible to you.
/// Needs Windows 10 version 2004 or later; on older versions the call fails and the window is simply captured.
/// </summary>
public static class ScreenSharingGuard
{
    public static void Apply(Window window, bool excludeFromCapture)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle != IntPtr.Zero)
        {
            Set(handle, excludeFromCapture);
            return;
        }

        // Not created yet: apply as soon as it has a handle.
        void OnInitialized(object? sender, EventArgs e)
        {
            window.SourceInitialized -= OnInitialized;
            Set(new WindowInteropHelper(window).Handle, excludeFromCapture);
        }
        window.SourceInitialized += OnInitialized;
    }

    private static void Set(IntPtr handle, bool exclude)
    {
        NativeMethods.SetWindowDisplayAffinity(handle, exclude ? NativeMethods.WDA_EXCLUDEFROMCAPTURE : NativeMethods.WDA_NONE);
    }
}
