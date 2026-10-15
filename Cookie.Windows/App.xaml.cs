using System;
using System.IO;
using System.Threading;
using System.Windows;
using Cookie.Windows.Animation;
using Cookie.Windows.Audio;
using Cookie.Windows.Behaviors;
using Cookie.Windows.Desktop;
using Cookie.Windows.Models;
using Cookie.Windows.Persistence;

namespace Cookie.Windows;

public partial class App : Application
{
    private const string SingleInstanceMutexName = "CookieDesktopCompanion_SingleInstance_Mutex_2026";
    private Mutex? _singleInstanceMutex;

    private SettingsManager? _settingsManager;
    private CookieProfile? _profile;
    private CompanionWindow? _companionWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 1. Single-instance enforcement
        _singleInstanceMutex = new Mutex(true, SingleInstanceMutexName, out bool isOnlyInstance);
        if (!isOnlyInstance)
        {
            // Another instance of Cookie is already running on this desktop
            Shutdown();
            return;
        }

        // Global exception logging
        DispatcherUnhandledException += (s, args) =>
        {
            try
            {
                string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Cookie", "Logs");
                Directory.CreateDirectory(logDir);
                string logFile = Path.Combine(logDir, "error.log");
                File.AppendAllText(logFile, $"[{DateTime.UtcNow:O}] Unhandled Exception: {args.Exception}\n");
            }
            catch { }
            args.Handled = true;
        };

        // 2. Initialize Core Services
        _settingsManager = new SettingsManager();
        _profile = _settingsManager.LoadProfile();

        var audioManager = new WindowsAudioManager();
        var screenService = new ScreenGeometryService();
        var animationController = new CookieAnimationController();
        var behaviorController = new CookieBehaviorController(animationController, screenService, audioManager);

        // 3. Create and show Companion Window
        _companionWindow = new CompanionWindow(
            animationController,
            behaviorController,
            screenService,
            _settingsManager,
            audioManager,
            _profile);

        if (_profile.Settings.ShowOnStartup)
        {
            _companionWindow.Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_settingsManager != null && _profile != null)
        {
            try
            {
                if (_companionWindow != null)
                {
                    _profile.Settings.SavedPositionX = _companionWindow.Left;
                    _profile.Settings.SavedPositionY = _companionWindow.Top;
                }
                _settingsManager.SaveProfileImmediate(_profile);
            }
            catch { }
        }

        if (_singleInstanceMutex != null)
        {
            try
            {
                _singleInstanceMutex.ReleaseMutex();
                _singleInstanceMutex.Dispose();
            }
            catch { }
        }

        base.OnExit(e);
    }
}
