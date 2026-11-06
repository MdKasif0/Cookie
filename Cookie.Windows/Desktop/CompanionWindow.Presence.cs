using System;
using System.Linq;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Views;

namespace Cookie.Windows.Desktop;

/// <summary>
/// Everything about when Cookie shows up and what she does around your day: friendship, focus sessions,
/// the daily rhythm, quiet mode, the summon shortcut, cozy items, speech bubbles and photos.
/// </summary>
public partial class CompanionWindow : ICompanionMenuSource
{
    private readonly CozyWindowManager _cozy = new();
    private readonly SummonHotKeyService _hotKey = new();
    private BubbleWindow? _bubble;
    private QuietModeMonitor? _quiet;
    private BondTracker _bond = null!;
    private FocusSession _focus = null!;
    private DispatcherTimer? _focusTicker;
    private DispatcherTimer? _dayTimer;
    private DispatcherTimer? _bondTimer;
    private DateTime _lastDay;
    private FocusPhase _lastFocusPhase = FocusPhase.Idle;
    private bool _wasVisibleBeforeQuiet;
    private PhotoModeWindow? _photoWindow;

    public CookieProfile Profile => _profile;
    public CookieBehaviorController Behavior => _behaviorController;
    public BondTracker Bond => _bond;
    public FocusSession Session => _focus;

    private void InitializePresence()
    {
        _bond = new BondTracker(_profile);
        _bond.KeepInUseItemsUnlocked();

        _focus = new FocusSession(_profile, _behaviorController, text => Say(text, 6), effect => _audioManager.Play(effect));
        _focus.Changed += OnFocusChanged;
        _lastDay = DateTime.Today;

        _cozy.OnMoved = (kind, fraction) => Dispatcher.InvokeAsync(() => MoveCozy(kind, fraction));
        _cozy.OnRemoved = kind => Dispatcher.InvokeAsync(() => RemoveCozy(kind));

        _quiet = new QuietModeMonitor(() => _profile.Settings.HideInFullscreen);
        _quiet.QuietChanged += SetQuiet;
    }

    /// <summary>Called once her window exists: registers the shortcut and starts the clocks.</summary>
    private void StartPresence(IntPtr windowHandle)
    {
        _hotKey.Attach(windowHandle);
        ApplyPresenceSettings();
        _quiet!.Start();
        _behaviorController.BeginDay();

        _dayTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        _dayTimer.Tick += (s, e) => CheckNewDay();
        _dayTimer.Start();

        After(TimeSpan.FromSeconds(2.5), SayGreeting);
        After(TimeSpan.FromSeconds(4), () =>
        {
            CelebrateIfNeeded();
            _bondTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            _bondTimer.Tick += (s, e) => CelebrateIfNeeded();
            _bondTimer.Start();
        });
    }

    private void After(TimeSpan delay, Action action)
    {
        var timer = new DispatcherTimer { Interval = delay };
        timer.Tick += (s, e) =>
        {
            timer.Stop();
            action();
        };
        timer.Start();
    }

    private void StopPresence()
    {
        _hotKey.Dispose();
        _quiet?.Stop();
        _focusTicker?.Stop();
        _dayTimer?.Stop();
        _bondTimer?.Stop();
        _cozy.CloseAll();
        _bubble?.Close();
        _bubble = null;
        _photoWindow?.Close();
    }

    // MARK: What she wears and says

    /// <summary>What she wears: the user's choices plus the day's seasonal outfit, which is only ever an overlay.</summary>
    internal CookieAppearanceConfig EffectiveAppearance()
    {
        if (!_profile.Settings.SeasonalOutfits) return _profile.Appearance;
        return _profile.Appearance.WithDailyOutfit(DateTime.Now, _profile.Statistics.FirstLaunchedAt?.ToLocalTime());
    }

    private void SayGreeting()
    {
        if (!_profile.Settings.TimeGreetings || _quiet?.IsQuiet == true) return;
        Say(DailyRhythm.Greeting(DateTime.Now, _profile.Statistics.FirstLaunchedAt?.ToLocalTime()), 5);
    }

    /// <summary>Cookie says something, if she is on screen.</summary>
    public void Say(string text, double seconds = 4.5)
    {
        if (!IsVisible || _quiet?.IsQuiet == true) return;
        if (_bubble == null)
        {
            _bubble = new BubbleWindow();
            ScreenSharingGuard.Apply(_bubble, _profile.Settings.HideFromScreenSharing);
        }
        _bubble.Say(text, this, seconds);
    }

    /// <summary>A new calendar day while she keeps running: another visit, and the outfit may change.</summary>
    private void CheckNewDay()
    {
        var today = DateTime.Today;
        if (today == _lastDay) return;

        _lastDay = today;
        _profile.Statistics.RecordVisit(DateTime.UtcNow);
        ApplyProfileAppearance();
        _settingsManager.DebouncedSave(_profile);
    }

    /// <summary>A new friendship level: she celebrates and says what it unlocked.</summary>
    private void CelebrateIfNeeded()
    {
        if (_bond.ClaimLevelUp() is not { } levelUp) return;

        _behaviorController.Celebrate();
        _audioManager.Play(SoundEffect.Welcome);

        string text = $"We're {levelUp.Level.Name} now!";
        if (levelUp.NewItems.Count > 0)
        {
            string names = string.Join(", ", levelUp.NewItems.Take(3).Select(item => item.DisplayName));
            int extra = levelUp.NewItems.Count - 3;
            text += $" Unlocked: {names}" + (extra > 0 ? $" and {extra} more" : "");
        }
        Say(text, 8);
        _settingsManager.DebouncedSave(_profile);
    }

    // MARK: Settings that touch the system

    /// <summary>Applies personality, screen-sharing exclusion, the shortcut and cozy items. Safe to call often.</summary>
    private void ApplyPresenceSettings()
    {
        if (_bond == null) return;

        _behaviorController.Personality = _profile.Personality;

        bool exclude = _profile.Settings.HideFromScreenSharing;
        ScreenSharingGuard.Apply(this, exclude);
        _cozy.SetExcludedFromCapture(exclude);
        if (_bubble != null) ScreenSharingGuard.Apply(_bubble, exclude);
        if (_worldItemWindow != null) ScreenSharingGuard.Apply(_worldItemWindow, exclude);
        if (_boxBackWindow != null) ScreenSharingGuard.Apply(_boxBackWindow, exclude);

        if (new WindowInteropHelper(this).Handle != IntPtr.Zero) _hotKey.Register(_profile.Settings.SummonShortcut);
        RefreshCozy(raiseCookie: false);
    }

    // MARK: Quiet mode and summoning

    /// <summary>Hides everything of hers while a full-screen app is up, and brings her back after.</summary>
    private void SetQuiet(bool quiet)
    {
        _audioManager.IsMuted = quiet;
        if (_bubble != null)
        {
            _bubble.IsSuppressed = quiet;
            _bubble.HideNow();
        }

        if (quiet)
        {
            _wasVisibleBeforeQuiet = IsVisible;
            _gameLoopTimer.Stop();
            Hide();
            _worldItemWindow?.Hide();
            _boxBackWindow?.Hide();
            _cozy.HideAll();
        }
        else if (_wasVisibleBeforeQuiet)
        {
            _lastTickTime = DateTime.UtcNow;
            _gameLoopTimer.Start();
            Show();
            _worldItemWindow?.Show();
            _boxBackWindow?.Show();
            RefreshCozy();
        }
    }

    /// <summary>Calls Cookie to the cursor and has her wave hello. It overrides full-screen hiding briefly.</summary>
    private void SummonCookie()
    {
        _quiet?.GrantOverride(20);
        if (!IsVisible)
        {
            _lastTickTime = DateTime.UtcNow;
            _gameLoopTimer.Start();
            Show();
        }

        var cursor = _screenService.GetCursorPositionDip() ?? new CorePoint(Left + Width / 2, Top + Height / 2);
        _behaviorController.Summon(cursor);
        _audioManager.Play(SoundEffect.Chirp);
        RefreshCozy();
    }

    // MARK: Cozy corner

    public void PlaceCozy(CozyKind kind)
    {
        if (!_bond.IsUnlocked(BondItem.Cozy(kind)) || _profile.CozyItems.Any(p => p.Kind == kind)) return;

        var area = SystemParameters.WorkArea;
        double direction = _behaviorController.Facing == CookieDirection.Right ? 1 : -1;
        double position = CozyLayout.NewPosition(Left + Width / 2 + direction * 190, area.Left, area.Width, _profile.CozyItems.Select(p => p.Position));
        _profile.CozyItems.Add(new CozyPlacement(kind, position));
        _settingsManager.DebouncedSave(_profile);
        RefreshCozy();
    }

    public void RemoveCozy(CozyKind kind)
    {
        _profile.CozyItems.RemoveAll(p => p.Kind == kind);
        _settingsManager.DebouncedSave(_profile);
        RefreshCozy();
    }

    private void MoveCozy(CozyKind kind, double fraction)
    {
        var placement = _profile.CozyItems.FirstOrDefault(p => p.Kind == kind);
        if (placement == null) return;

        placement.Position = fraction;
        _settingsManager.DebouncedSave(_profile);
        RefreshCozy(raiseCookie: false);
    }

    /// <summary>Brings the cozy windows in line with the profile and keeps her in front of them.</summary>
    private void RefreshCozy(bool raiseCookie = true)
    {
        _behaviorController.CozyPlacements = _profile.CozyItems.ToList();
        if (!IsVisible)
        {
            _cozy.HideAll();
            return;
        }

        _cozy.Update(_profile.CozyItems, _profile.Settings.CookieSize);
        if (raiseCookie)
        {
            // Topmost windows stack by when they became topmost, so asserting it again moves her to the front.
            Topmost = false;
            Topmost = true;
            if (_bubble?.IsVisible == true)
            {
                _bubble.Topmost = false;
                _bubble.Topmost = true;
            }
        }
    }

    // MARK: Focus

    public void StartFocus(int minutes)
    {
        _focus.Start(minutes);
    }

    public void StopFocus()
    {
        _focus.Stop();
    }

    private void OnFocusChanged()
    {
        _trayService?.UpdateTooltip(_focus.StatusTitle);

        if (_focus.Timer.IsActive)
        {
            if (_focusTicker == null)
            {
                _focusTicker = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                _focusTicker.Tick += (s, e) => _focus.Tick();
            }
            _focusTicker.Start();
        }
        else
        {
            _focusTicker?.Stop();
        }

        // Save when a phase starts or ends, not every second.
        if (_focus.Timer.Phase != _lastFocusPhase)
        {
            _lastFocusPhase = _focus.Timer.Phase;
            _settingsManager.DebouncedSave(_profile);
        }
    }

    // MARK: Photo mode

    public void OpenPhotoMode()
    {
        if (_photoWindow != null)
        {
            _photoWindow.Activate();
            return;
        }

        _photoWindow = new PhotoModeWindow(_profile, EffectiveAppearance);
        _photoWindow.Closed += (s, e) => _photoWindow = null;
        _photoWindow.Show();
    }
}
