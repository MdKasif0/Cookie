using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Core.Startup;
using Cookie.Windows.Interop;
using Cookie.Windows.Startup;
using Cookie.Windows.Views;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Native Windows notification area (System Tray) manager.
/// Manages tray icon lifecycle, DPI-aware icon rendering, and rich context menu operations.
/// </summary>
public class WindowsTrayService : IDisposable
{
    private readonly IntPtr _hWnd;
    private readonly CookieBehaviorController _behaviorController;
    private readonly SettingsManager _settingsManager;
    private readonly AudioManagerBase _audioManager;
    private readonly CookieProfile _profile;
    private readonly IStartupService _startupService;
    private readonly Action _openSettingsAction;
    private readonly Action _openEmotePickerAction;
    private readonly Action _openAboutAction;
    private readonly Action _checkForUpdatesAction;

    private NOTIFYICONDATA _nid;
    private IntPtr _hIcon = IntPtr.Zero;
    private bool _isCreated = false;
    private bool _isDisposed = false;

    public WindowsTrayService(
        IntPtr hWnd,
        CookieBehaviorController behaviorController,
        SettingsManager settingsManager,
        AudioManagerBase audioManager,
        CookieProfile profile,
        IStartupService? startupService,
        Action openSettingsAction,
        Action openEmotePickerAction,
        Action openAboutAction,
        Action checkForUpdatesAction)
    {
        _hWnd = hWnd;
        _behaviorController = behaviorController;
        _settingsManager = settingsManager;
        _audioManager = audioManager;
        _profile = profile;
        _startupService = startupService ?? new WindowsStartupService();
        _openSettingsAction = openSettingsAction;
        _openEmotePickerAction = openEmotePickerAction;
        _openAboutAction = openAboutAction;
        _checkForUpdatesAction = checkForUpdatesAction;

        InitializeTrayIcon();
    }

    private void InitializeTrayIcon()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string icoPath = Path.Combine(baseDir, "Resources", "Cookie.ico");

        if (File.Exists(icoPath))
        {
            _hIcon = NativeMethods.LoadImage(
                IntPtr.Zero,
                icoPath,
                1 /* IMAGE_ICON */,
                16,
                16,
                0x00000010 /* LR_LOADFROMFILE */);
        }

        _nid = new NOTIFYICONDATA
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NOTIFYICONDATA>(),
            hWnd = _hWnd,
            uID = 1001,
            uFlags = NativeMethods.NIF_MESSAGE | NativeMethods.NIF_ICON | NativeMethods.NIF_TIP,
            uCallbackMessage = NativeMethods.WM_TRAYICON,
            hIcon = _hIcon,
            szTip = "Cookie Desktop Companion"
        };

        _isCreated = NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_ADD, ref _nid);
    }

    public void HandleTrayMessage(IntPtr wParam, IntPtr lParam)
    {
        if (_isDisposed) return;

        int msg = lParam.ToInt32();

        if (msg == NativeMethods.WM_RBUTTONUP)
        {
            ShowTrayContextMenu();
        }
        else if (msg is NativeMethods.WM_LBUTTONDBLCLK or NativeMethods.WM_LBUTTONUP)
        {
            _openSettingsAction();
        }
    }

    private void ShowTrayContextMenu()
    {
        var menu = new ContextMenu();

        // 1. Header item
        var headerItem = new MenuItem
        {
            Header = "Cookie 🍪",
            FontWeight = FontWeights.Bold,
            IsEnabled = false
        };
        menu.Items.Add(headerItem);

        menu.Items.Add(new Separator());

        // 2. Open Settings
        var settingsItem = new MenuItem { Header = "Settings..." };
        settingsItem.Click += (s, e) => _openSettingsAction();
        menu.Items.Add(settingsItem);

        // 3. Open Emotes
        var emotesItem = new MenuItem { Header = "Emotes..." };
        emotesItem.Click += (s, e) => _openEmotePickerAction();
        menu.Items.Add(emotesItem);

        menu.Items.Add(new Separator());

        // 4. Pause Autonomous Wandering
        var pauseItem = new MenuItem
        {
            Header = "Pause Wandering",
            IsCheckable = true,
            IsChecked = _behaviorController.PauseAutonomousBehavior
        };
        pauseItem.Click += (s, e) =>
        {
            bool newVal = pauseItem.IsChecked;
            _behaviorController.PauseAutonomousBehavior = newVal;
            _profile.Settings.PauseAutonomousBehavior = newVal;
            _settingsManager.DebouncedSave(_profile);
        };
        menu.Items.Add(pauseItem);

        // 5. Autonomous Behavior Enabled
        var autoItem = new MenuItem
        {
            Header = "Autonomous Behavior",
            IsCheckable = true,
            IsChecked = _behaviorController.AutonomousBehaviorEnabled
        };
        autoItem.Click += (s, e) =>
        {
            bool newVal = autoItem.IsChecked;
            _behaviorController.AutonomousBehaviorEnabled = newVal;
            _profile.Settings.AutonomousBehaviorEnabled = newVal;
            _settingsManager.DebouncedSave(_profile);
        };
        menu.Items.Add(autoItem);

        // 6. Sound Toggle
        var soundItem = new MenuItem
        {
            Header = "Sound Enabled",
            IsCheckable = true,
            IsChecked = _audioManager.SoundEnabled
        };
        soundItem.Click += (s, e) =>
        {
            bool newVal = soundItem.IsChecked;
            _audioManager.SoundEnabled = newVal;
            _profile.Settings.SoundEnabled = newVal;
            _settingsManager.DebouncedSave(_profile);
        };
        menu.Items.Add(soundItem);

        // 7. Launch at Startup
        var startupItem = new MenuItem
        {
            Header = "Launch at Windows Startup",
            IsCheckable = true,
            IsChecked = _profile.Settings.LaunchAtLogin
        };
        startupItem.Click += (s, e) =>
        {
            bool newVal = startupItem.IsChecked;
            _startupService.SetStartupEnabled(newVal);
            _profile.Settings.LaunchAtLogin = newVal;
            _settingsManager.DebouncedSave(_profile);
        };
        menu.Items.Add(startupItem);

        menu.Items.Add(new Separator());

        // 8. Check for Updates
        var updateItem = new MenuItem { Header = "Check for Updates..." };
        updateItem.Click += (s, e) => _checkForUpdatesAction();
        menu.Items.Add(updateItem);

        // 9. About Cookie
        var aboutItem = new MenuItem { Header = "About Cookie..." };
        aboutItem.Click += (s, e) => _openAboutAction();
        menu.Items.Add(aboutItem);

        menu.Items.Add(new Separator());

        // 10. Quit Cookie
        var quitItem = new MenuItem { Header = "Quit Cookie" };
        quitItem.Click += (s, e) =>
        {
            _settingsManager.SaveProfileImmediate(_profile);
            Application.Current.Shutdown();
        };
        menu.Items.Add(quitItem);

        NativeMethods.SetForegroundWindow(_hWnd);
        menu.IsOpen = true;
    }

    public void Dispose()
    {
        if (!_isDisposed)
        {
            _isDisposed = true;
            if (_isCreated)
            {
                NativeMethods.Shell_NotifyIcon(NativeMethods.NIM_DELETE, ref _nid);
                _isCreated = false;
            }

            if (_hIcon != IntPtr.Zero)
            {
                NativeMethods.DestroyIcon(_hIcon);
                _hIcon = IntPtr.Zero;
            }
        }
    }
}
