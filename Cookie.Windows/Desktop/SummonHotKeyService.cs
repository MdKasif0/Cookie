using System;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Desktop;

/// <summary>A global keyboard shortcut that calls Cookie to the cursor, registered on her window.</summary>
public sealed class SummonHotKeyService : IDisposable
{
    public const int HotKeyId = 0x4B43;

    private IntPtr _handle = IntPtr.Zero;
    private bool _isRegistered;

    /// <summary>True when the chosen shortcut could not be registered, usually because another app owns it.</summary>
    public static bool IsUnavailable { get; private set; }

    public void Attach(IntPtr windowHandle) => _handle = windowHandle;

    /// <summary>Registers <paramref name="shortcut"/>, replacing the previous one. Off just unregisters.</summary>
    public bool Register(SummonShortcut shortcut)
    {
        Unregister();
        IsUnavailable = false;
        if (_handle == IntPtr.Zero || shortcut.GetVirtualKey() is not { } key) return true;

        _isRegistered = NativeMethods.RegisterHotKey(_handle, HotKeyId, shortcut.GetModifiers() | NativeMethods.MOD_NOREPEAT, key);
        IsUnavailable = !_isRegistered;
        return _isRegistered;
    }

    public void Unregister()
    {
        if (_isRegistered && _handle != IntPtr.Zero) NativeMethods.UnregisterHotKey(_handle, HotKeyId);
        _isRegistered = false;
    }

    public static bool IsHotKeyMessage(int message, IntPtr wParam) =>
        message == NativeMethods.WM_HOTKEY && wParam.ToInt32() == HotKeyId;

    public void Dispose() => Unregister();
}
