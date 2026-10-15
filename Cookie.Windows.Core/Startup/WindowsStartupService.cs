using System;
using Microsoft.Win32;

namespace Cookie.Windows.Core.Startup;

/// <summary>
/// Native Windows launch-at-login manager using standard HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
/// Operates strictly within user-level registry boundaries without requiring elevation.
/// </summary>
public class WindowsStartupService : IStartupService
{
    public const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string ValueName = "CookieDesktopCompanion";
    private readonly string? _customExecutablePath;

    public WindowsStartupService(string? customExecutablePath = null)
    {
        _customExecutablePath = customExecutablePath;
    }

    public bool IsStartupEnabled()
    {
        try
        {
            if (!OperatingSystem.IsWindows()) return false;

            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false);
            var val = key?.GetValue(ValueName);
            return val != null;
        }
        catch
        {
            return false;
        }
    }

    public bool SetStartupEnabled(bool enable)
    {
        try
        {
            if (!OperatingSystem.IsWindows()) return false;

            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true);
            if (key == null) return false;

            if (enable)
            {
                string exePath = _customExecutablePath ?? Environment.ProcessPath ?? string.Empty;
                if (string.IsNullOrEmpty(exePath)) return false;

                key.SetValue(ValueName, $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue(ValueName, false);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public string GetApplicationPath()
    {
        return _customExecutablePath ?? Environment.ProcessPath ?? string.Empty;
    }
}
