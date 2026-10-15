using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Cookie.Windows.Animation;
using Cookie.Windows.Audio;
using Cookie.Windows.Behaviors;
using Cookie.Windows.Interop;
using Cookie.Windows.Models;
using Cookie.Windows.Persistence;
using Cookie.Windows.Views;

namespace Cookie.Windows.Desktop;

public partial class CompanionWindow : Window
{
    private readonly CookieAnimationController _animationController;
    private readonly CookieBehaviorController _behaviorController;
    private readonly ScreenGeometryService _screenService;
    private readonly SettingsManager _settingsManager;
    private readonly WindowsAudioManager _audioManager;
    private CookieProfile _profile;

    private readonly DispatcherTimer _gameLoopTimer;
    private DateTime _lastTickTime;

    private bool _isDragging = false;
    private Point _dragStartCursor;
    private Point _dragStartWindow;
    private bool _hasDraggedEnough = false;

    public CompanionWindow(
        CookieAnimationController animationController,
        CookieBehaviorController behaviorController,
        ScreenGeometryService screenService,
        SettingsManager settingsManager,
        WindowsAudioManager audioManager,
        CookieProfile profile)
    {
        InitializeComponent();

        _animationController = animationController;
        _behaviorController = behaviorController;
        _screenService = screenService;
        _settingsManager = settingsManager;
        _audioManager = audioManager;
        _profile = profile;

        // Apply appearance from profile
        ApplyProfileAppearance();

        // Bind animation and behavior updates
        _animationController.OnFrameChanged += (pose, direction) =>
        {
            Dispatcher.InvokeAsync(() => CatCanvas.UpdatePose(pose, direction));
        };

        _behaviorController.OnPositionChanged += position =>
        {
            Dispatcher.InvokeAsync(() =>
            {
                Left = position.X;
                Top = position.Y;
            });
        };

        _behaviorController.OnEmoteChanged += emote =>
        {
            Dispatcher.InvokeAsync(() => CatCanvas.SetActiveEmote(emote));
        };

        // Restore saved position or default spawn
        RestoreInitialPosition();

        // Game loop timer at 60 FPS
        _lastTickTime = DateTime.UtcNow;
        _gameLoopTimer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(16.6)
        };
        _gameLoopTimer.Tick += GameLoopTick;
        _gameLoopTimer.Start();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        var helper = new WindowInteropHelper(this);
        IntPtr hWnd = helper.Handle;

        // Apply WS_EX_TOOLWINDOW (hide from Alt-Tab) and WS_EX_NOACTIVATE (never steal keyboard focus)
        int exStyle = NativeMethods.GetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE).ToInt32();
        exStyle |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
        NativeMethods.SetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE, new IntPtr(exStyle));

        // Hook Win32 messages for display change and DPI notifications
        var source = HwndSource.FromHwnd(hWnd);
        source?.AddHook(WndProc);

        // Play welcome audio upon initialization if enabled
        _audioManager.Play(SoundEffect.Welcome);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_DISPLAYCHANGE || msg == NativeMethods.WM_DPICHANGED)
        {
            Dispatcher.InvokeAsync(RecoverPositionToVisibleScreen);
        }
        return IntPtr.Zero;
    }

    private void GameLoopTick(object? sender, EventArgs e)
    {
        var now = DateTime.UtcNow;
        double dt = (now - _lastTickTime).TotalSeconds;
        _lastTickTime = now;

        // Guard against massive dt spikes during debugger pauses or system sleep
        if (dt > 0.1) dt = 0.1;

        _behaviorController.Update(dt);
    }

    private void RestoreInitialPosition()
    {
        var companionSize = new Size(Width, Height);
        Point initialPos;

        if (_profile.Settings.RememberPosition &&
            _profile.Settings.SavedPositionX.HasValue &&
            _profile.Settings.SavedPositionY.HasValue)
        {
            var saved = new Point(_profile.Settings.SavedPositionX.Value, _profile.Settings.SavedPositionY.Value);
            initialPos = _screenService.RecoverPosition(saved, companionSize);
        }
        else
        {
            var primaryArea = _screenService.GetPrimaryWorkArea();
            initialPos = DesktopCoordinateSpace.CalculateDefaultSpawn(primaryArea, companionSize);
        }

        Left = initialPos.X;
        Top = initialPos.Y;
        _behaviorController.SetPosition(initialPos);
        _behaviorController.SetCompanionSize(companionSize);
    }

    public void ApplyProfileAppearance()
    {
        var palette = CharacterPalette.FromFurColor(_profile.Appearance.FurColor);
        CatCanvas.UpdatePalette(palette);

        double sizeScale = _profile.Settings.CookieSize;
        Width = 180 * sizeScale;
        Height = 180 * sizeScale;
        CatCanvas.UpdateScale(sizeScale);
        _behaviorController.SetCompanionSize(new Size(Width, Height));

        _animationController.AnimationIntensity = _profile.Settings.AnimationIntensity;
        _behaviorController.AutonomousBehaviorEnabled = _profile.Settings.AutonomousBehaviorEnabled;
        _behaviorController.PauseAutonomousBehavior = _profile.Settings.PauseAutonomousBehavior;
        _behaviorController.Activity = _profile.Settings.Activity;
        _behaviorController.CursorInteractionEnabled = _profile.Settings.CursorInteraction;

        _audioManager.SoundEnabled = _profile.Settings.SoundEnabled;
        _audioManager.MasterVolume = _profile.Settings.MasterVolume;
        _audioManager.MeowVolume = _profile.Settings.MeowVolume;
        _audioManager.InteractionSounds = _profile.Settings.InteractionSounds;
        _audioManager.PurringSounds = _profile.Settings.PurringSounds;
    }

    private void RecoverPositionToVisibleScreen()
    {
        var current = new Point(Left, Top);
        var size = new Size(Width, Height);
        var safe = _screenService.RecoverPosition(current, size);

        Left = safe.X;
        Top = safe.Y;
        _behaviorController.SetPosition(safe);
    }

    private void OnCanvasMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _isDragging = true;
        _hasDraggedEnough = false;
        _dragStartCursor = PointToScreen(e.GetPosition(this));
        _dragStartWindow = new Point(Left, Top);
        CatCanvas.CaptureMouse();
        _behaviorController.BeginDrag();
    }

    private void OnCanvasMouseMove(object sender, MouseEventArgs e)
    {
        if (_isDragging)
        {
            var currentCursor = PointToScreen(e.GetPosition(this));
            double deltaX = currentCursor.X - _dragStartCursor.X;
            double deltaY = currentCursor.Y - _dragStartCursor.Y;

            if (Math.Abs(deltaX) > 4 || Math.Abs(deltaY) > 4)
            {
                _hasDraggedEnough = true;
            }

            double newLeft = _dragStartWindow.X + deltaX;
            double newTop = _dragStartWindow.Y + deltaY;

            Left = newLeft;
            Top = newTop;
            _behaviorController.UpdateDrag(new Point(newLeft, newTop));
        }
    }

    private void OnCanvasMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isDragging)
        {
            _isDragging = false;
            CatCanvas.ReleaseMouseCapture();

            if (!_hasDraggedEnough)
            {
                // Clicks count as Petting Cookie!
                _behaviorController.Pet();
            }
            else
            {
                _behaviorController.EndDrag();

                // Persist new coordinates
                _profile.Settings.SavedPositionX = Left;
                _profile.Settings.SavedPositionY = Top;
                _settingsManager.DebouncedSave(_profile);
            }
        }
    }

    private void OnCanvasMouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        ShowContextMenu();
    }

    private void ShowContextMenu()
    {
        var menu = new ContextMenu();

        // Pet item
        var petItem = new MenuItem { Header = "Pet Cookie 🧡" };
        petItem.Click += (s, e) => _behaviorController.Pet();
        menu.Items.Add(petItem);

        // Emotes Submenu
        var emotesMenu = new MenuItem { Header = "Emotes" };
        foreach (var emote in Emote.All)
        {
            var item = new MenuItem { Header = $"{emote.Emoji} {emote.Name}" };
            var capturedEmote = emote;
            item.Click += (s, e) => _behaviorController.TriggerEmote(capturedEmote);
            emotesMenu.Items.Add(item);
        }
        menu.Items.Add(emotesMenu);

        menu.Items.Add(new Separator());

        // Settings item
        var settingsItem = new MenuItem { Header = "Settings..." };
        settingsItem.Click += (s, e) => OpenSettingsWindow();
        menu.Items.Add(settingsItem);

        menu.Items.Add(new Separator());

        // Exit item
        var exitItem = new MenuItem { Header = "Exit Cookie" };
        exitItem.Click += (s, e) =>
        {
            _profile.Settings.SavedPositionX = Left;
            _profile.Settings.SavedPositionY = Top;
            _settingsManager.SaveProfileImmediate(_profile);
            Application.Current.Shutdown();
        };
        menu.Items.Add(exitItem);

        menu.IsOpen = true;
    }

    public void OpenSettingsWindow()
    {
        // Check if Settings window is already open
        foreach (Window w in Application.Current.Windows)
        {
            if (w is SettingsWindow existing)
            {
                existing.Activate();
                return;
            }
        }

        var settingsWindow = new SettingsWindow(_profile, _settingsManager, _audioManager, () =>
        {
            ApplyProfileAppearance();
        });
        settingsWindow.Show();
    }

    protected override void OnClosed(EventArgs e)
    {
        _gameLoopTimer.Stop();
        base.OnClosed(e);
    }
}
