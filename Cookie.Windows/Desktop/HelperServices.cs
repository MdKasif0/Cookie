using System;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Interop;
using Microsoft.Win32;

namespace Cookie.Windows.Desktop;

/// <summary>Reads the PC's state for the system watcher. None of this needs any permission.</summary>
public sealed class WindowsSystemProbe
{
    private (ulong Idle, ulong Kernel, ulong User)? _lastTimes;

    public SystemSnapshot Snapshot()
    {
        int? battery = null;
        bool charging = false;
        if (HelperNativeMethods.GetSystemPowerStatus(out var power))
        {
            // 128 = no battery, 255 = unknown.
            bool hasBattery = (power.BatteryFlag & 128) == 0 && power.BatteryFlag != 255 && power.BatteryLifePercent <= 100;
            if (hasBattery) battery = power.BatteryLifePercent;
            charging = power.ACLineStatus == 1;
        }

        double? cpu = null;
        if (HelperNativeMethods.GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var now = (idle.Value, kernel.Value, user.Value);
            if (_lastTimes is { } previous) cpu = CpuLoad.Between(previous, now);
            _lastTimes = now;
        }

        long? free = null, total = null;
        try
        {
            string root = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? "C:\\";
            var drive = new DriveInfo(root);
            if (drive.IsReady)
            {
                free = drive.AvailableFreeSpace;
                total = drive.TotalSize;
            }
        }
        catch
        {
            // Leave the disk unknown.
        }

        bool? online = null;
        try
        {
            online = NetworkInterface.GetIsNetworkAvailable();
        }
        catch
        {
            // Leave the network unknown.
        }

        return new SystemSnapshot(battery, charging, cpu, free, total, online);
    }

    /// <summary>Time since the last keyboard or mouse input.</summary>
    public static TimeSpan IdleTime()
    {
        var info = new HelperNativeMethods.LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<HelperNativeMethods.LASTINPUTINFO>() };
        if (!HelperNativeMethods.GetLastInputInfo(ref info)) return TimeSpan.Zero;
        uint now = (uint)Environment.TickCount;
        return TimeSpan.FromMilliseconds(unchecked(now - info.dwTime));
    }
}

/// <summary>Where Windows keeps Downloads and the Desktop, and where screenshots belong.</summary>
public static class KnownFolders
{
    private static readonly Guid DownloadsId = new("374DE290-123F-4565-9164-39C4925E467B");
    private static readonly Guid ScreenshotsId = new("B7BEDE81-DF94-4682-A7D8-57A52620B86F");

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);

    private static string? Known(Guid id)
    {
        try
        {
            if (SHGetKnownFolderPath(id, 0, IntPtr.Zero, out IntPtr pointer) != 0) return null;
            try { return Marshal.PtrToStringUni(pointer); }
            finally { Marshal.FreeCoTaskMem(pointer); }
        }
        catch
        {
            return null;
        }
    }

    public static string? Downloads => Known(DownloadsId)
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

    public static string Desktop => Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);

    /// <summary>Pictures\Screenshots, where Windows saves Win+PrtScn screenshots.</summary>
    public static string Screenshots => Known(ScreenshotsId)
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
}

/// <summary>Keeps the Claude API key in Windows Credential Manager, never in Cookie's settings file.</summary>
public static class ApiKeyStore
{
    private const string Target = "Cookie/AnthropicApiKey";

    public static bool HasKey => Load() != null;

    public static string? Load()
    {
        try
        {
            if (!HelperNativeMethods.CredRead(Target, HelperNativeMethods.CRED_TYPE_GENERIC, 0, out IntPtr pointer)) return null;
            try
            {
                var credential = Marshal.PtrToStructure<HelperNativeMethods.CREDENTIAL>(pointer);
                if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero) return null;
                string key = Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
                return string.IsNullOrWhiteSpace(key) ? null : key;
            }
            finally
            {
                HelperNativeMethods.CredFree(pointer);
            }
        }
        catch
        {
            return null;
        }
    }

    public static bool Save(string key)
    {
        string trimmed = key.Trim();
        if (trimmed.Length == 0) return false;
        byte[] bytes = Encoding.Unicode.GetBytes(trimmed);
        IntPtr blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new HelperNativeMethods.CREDENTIAL
            {
                Type = HelperNativeMethods.CRED_TYPE_GENERIC,
                TargetName = Target,
                Comment = "Cookie – Claude API key",
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = HelperNativeMethods.CRED_PERSIST_LOCAL_MACHINE,
                UserName = "Cookie"
            };
            return HelperNativeMethods.CredWrite(ref credential, 0);
        }
        catch
        {
            return false;
        }
        finally
        {
            Marshal.FreeCoTaskMem(blob);
        }
    }

    public static void Delete()
    {
        try { HelperNativeMethods.CredDelete(Target, HelperNativeMethods.CRED_TYPE_GENERIC, 0); } catch { }
    }
}

/// <summary>
/// Registers <c>cookie://</c> for this user (no administrator rights), so links open Cookie. Windows then starts
/// Cookie with the link, and the new copy hands it to the one already running.
/// </summary>
public static class LinkProtocol
{
    public static void Register()
    {
        try
        {
            string? exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;
            using var key = Registry.CurrentUser.CreateSubKey(@"Software\Classes\cookie");
            key.SetValue("", "URL:Cookie");
            key.SetValue("URL Protocol", "");
            using (var icon = key.CreateSubKey("DefaultIcon")) icon.SetValue("", $"\"{exe}\",0");
            using var command = key.CreateSubKey(@"shell\open\command");
            string wanted = $"\"{exe}\" \"%1\"";
            if (command.GetValue("") as string != wanted) command.SetValue("", wanted);
        }
        catch
        {
            // Links just won't open Cookie; nothing else depends on it.
        }
    }

    /// <summary>The first cookie:// link among command-line arguments.</summary>
    public static string? LinkIn(string[] args)
        => args.FirstOrDefault(arg => arg.StartsWith(CookieCommand.Scheme + ":", StringComparison.OrdinalIgnoreCase));
}
