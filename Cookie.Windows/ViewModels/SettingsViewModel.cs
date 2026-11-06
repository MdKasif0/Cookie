using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Core.Startup;

namespace Cookie.Windows.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    public CookieStatistics Statistics => _profile.Statistics;

    private readonly BondTracker _bond;

    private readonly CookieProfile _profile;
    private readonly SettingsManager _settingsManager;
    private readonly AudioManagerBase _audioManager;
    private readonly IStartupService? _startupService;
    private readonly Action? _onSettingsChanged;
    private readonly Action? _onCheckForUpdates;

    public event PropertyChangedEventHandler? PropertyChanged;

    public SettingsViewModel(
        CookieProfile profile,
        SettingsManager settingsManager,
        AudioManagerBase audioManager,
        Action? onSettingsChanged = null,
        IStartupService? startupService = null,
        Action? onCheckForUpdates = null)
    {
        _profile = profile;
        _bond = new BondTracker(profile);
        _settingsManager = settingsManager;
        _audioManager = audioManager;
        _onSettingsChanged = onSettingsChanged;
        _startupService = startupService;
        _onCheckForUpdates = onCheckForUpdates;

        if (_startupService != null)
        {
            _profile.Settings.LaunchAtLogin = _startupService.IsStartupEnabled();
        }

        CheckForUpdatesCommand = new RelayCommand(() =>
        {
            _onCheckForUpdates?.Invoke();
        });

        TestSoundCommand = new RelayCommand(() =>
        {
            _audioManager.Play(SoundEffect.Meow);
        });

        ResetPersonalityCommand = new RelayCommand(() =>
        {
            _profile.Personality = CookiePersonality.Playful;
            _profile.Settings.ResetPersonalityAndActivitySettings();
            SaveAndNotify();
            OnPropertyChanged(string.Empty);
        });

        ResetAppearanceCommand = new RelayCommand(() =>
        {
            _profile.Appearance = new CookieAppearanceConfig();
            SaveAndNotify();
            OnPropertyChanged(string.Empty);
        });

        RemoveAllAccessoriesCommand = new RelayCommand(() =>
        {
            foreach (var acc in _profile.Appearance.Accessories)
            {
                acc.IsEnabled = false;
            }
            SaveAndNotify();
            OnPropertyChanged(string.Empty);
        });

        ResetCursorCommand = new RelayCommand(() =>
        {
            _profile.Settings.ResetCursorInteractionSettings();
            SaveAndNotify();
            OnPropertyChanged(string.Empty);
        });

        ResetExplorationCommand = new RelayCommand(() =>
        {
            _profile.Settings.ResetDesktopExplorationSettings();
            SaveAndNotify();
            OnPropertyChanged(string.Empty);
        });
    }

    public ICommand TestSoundCommand { get; }
    public ICommand ResetPersonalityCommand { get; }
    public ICommand ResetAppearanceCommand { get; }
    public ICommand RemoveAllAccessoriesCommand { get; }
    public ICommand ResetCursorCommand { get; }
    public ICommand ResetExplorationCommand { get; }
    public ICommand CheckForUpdatesCommand { get; }

    public CookieProfile Profile => _profile;
    public CookieAppearanceConfig Appearance => _profile.Appearance;

    // General & Name
    public string CharacterName
    {
        get => _profile.DisplayName;
        set
        {
            if (_profile.DisplayName != value)
            {
                _profile.DisplayName = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }

    public bool LaunchAtLogin
    {
        get => _profile.Settings.LaunchAtLogin;
        set
        {
            if (_profile.Settings.LaunchAtLogin != value)
            {
                _profile.Settings.LaunchAtLogin = value;
                _startupService?.SetStartupEnabled(value);
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }

    public bool ShowOnStartup
    {
        get => _profile.Settings.ShowOnStartup;
        set { if (_profile.Settings.ShowOnStartup != value) { _profile.Settings.ShowOnStartup = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool RememberPosition
    {
        get => _profile.Settings.RememberPosition;
        set { if (_profile.Settings.RememberPosition != value) { _profile.Settings.RememberPosition = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool AutomaticallyCheckForUpdates
    {
        get => _profile.Settings.AutomaticallyCheckForUpdates;
        set { if (_profile.Settings.AutomaticallyCheckForUpdates != value) { _profile.Settings.AutomaticallyCheckForUpdates = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    // Appearance: Size & Animation
    public double CookieSize
    {
        get => _profile.Settings.CookieSize;
        set
        {
            double clamped = Math.Clamp(value, 0.7, 1.4);
            if (Math.Abs(_profile.Settings.CookieSize - clamped) > 0.01)
            {
                _profile.Settings.CookieSize = clamped;
                SaveAndNotify();
                OnPropertyChanged();
                OnPropertyChanged(nameof(CookieSizePercent));
            }
        }
    }

    public string CookieSizePercent => $"{(int)Math.Round(CookieSize * 100)}%";

    public double AnimationIntensity
    {
        get => _profile.Settings.AnimationIntensity;
        set
        {
            double clamped = Math.Clamp(value, 0.5, 1.5);
            if (Math.Abs(_profile.Settings.AnimationIntensity - clamped) > 0.01)
            {
                _profile.Settings.AnimationIntensity = clamped;
                SaveAndNotify();
                OnPropertyChanged();
                OnPropertyChanged(nameof(AnimationIntensityPercent));
            }
        }
    }

    public string AnimationIntensityPercent => $"{(int)Math.Round(AnimationIntensity * 100)}%";

    // Appearance: Fur, Eyes, Ears, Tail, Body
    public FurColor SelectedFurColor
    {
        get => _profile.Appearance.FurColor;
        set
        {
            if (_profile.Appearance.FurColor != value)
            {
                _profile.Appearance.FurColor = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<FurColor> AvailableFurColors => Enum.GetValues<FurColor>();

    public FurPattern SelectedFurPattern
    {
        get => _profile.Appearance.Pattern;
        set
        {
            if (_profile.Appearance.Pattern != value)
            {
                _profile.Appearance.Pattern = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    /// <summary>Coats unlock as the friendship grows; the one in use always stays listed.</summary>
    public IReadOnlyList<FurPattern> AvailableFurPatterns => Enum.GetValues<FurPattern>()
        .Where(pattern => pattern == _profile.Appearance.Pattern || _bond.IsUnlocked(BondItem.Coat(pattern)))
        .ToList();

    public bool HasLockedCoats => AvailableFurPatterns.Count < Enum.GetValues<FurPattern>().Length;

    /// <summary>Every accessory with its lock state, for the accessories list.</summary>
    public IReadOnlyList<AccessoryChoice> AccessoryChoices => Enum.GetValues<AccessoryKind>()
        .Select(kind => new AccessoryChoice(this, kind))
        .ToList();

    public sealed class AccessoryChoice : INotifyPropertyChanged
    {
        private readonly SettingsViewModel _owner;
        private readonly AccessoryKind _kind;

        public AccessoryChoice(SettingsViewModel owner, AccessoryKind kind)
        {
            _owner = owner;
            _kind = kind;
        }

        public event PropertyChangedEventHandler? PropertyChanged;

        public string Name => _kind.GetDisplayName();

        public bool IsOn
        {
            get => _owner._profile.Appearance.Accessory(_kind).IsEnabled;
            set
            {
                _owner.SetAccessory(_kind, value);
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(IsOn)));
            }
        }

        public bool IsLocked => !_owner._bond.IsUnlocked(BondItem.Accessory(_kind));

        /// <summary>A locked accessory can't be turned on, but one already on can always be turned off.</summary>
        public bool CanToggle => !IsLocked || IsOn;

        public string LockText => IsLocked && Bond.RequiredLevel(BondItem.Accessory(_kind)) is { } level
            ? $"Unlocks at {level.Name}"
            : string.Empty;
    }

    public EyeColor SelectedEyeColor
    {
        get => _profile.Appearance.EyeColor;
        set
        {
            if (_profile.Appearance.EyeColor != value)
            {
                _profile.Appearance.EyeColor = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<EyeColor> AvailableEyeColors => Enum.GetValues<EyeColor>();

    public EyeStyle SelectedEyeStyle
    {
        get => _profile.Appearance.EyeStyle;
        set
        {
            if (_profile.Appearance.EyeStyle != value)
            {
                _profile.Appearance.EyeStyle = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<EyeStyle> AvailableEyeStyles => Enum.GetValues<EyeStyle>();

    public EarVariation SelectedEarVariation
    {
        get => _profile.Appearance.EarVariation;
        set
        {
            if (_profile.Appearance.EarVariation != value)
            {
                _profile.Appearance.EarVariation = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<EarVariation> AvailableEarVariations => Enum.GetValues<EarVariation>();

    public TailVariation SelectedTailVariation
    {
        get => _profile.Appearance.TailVariation;
        set
        {
            if (_profile.Appearance.TailVariation != value)
            {
                _profile.Appearance.TailVariation = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<TailVariation> AvailableTailVariations => Enum.GetValues<TailVariation>();

    public BodyVariation SelectedBodyVariation
    {
        get => _profile.Appearance.BodyVariation;
        set
        {
            if (_profile.Appearance.BodyVariation != value)
            {
                _profile.Appearance.BodyVariation = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<BodyVariation> AvailableBodyVariations => Enum.GetValues<BodyVariation>();

    // Accessories
    public bool AccessoryCollar
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Collar).IsEnabled;
        set { SetAccessory(AccessoryKind.Collar, value); OnPropertyChanged(); }
    }

    public bool AccessoryBow
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Bow).IsEnabled;
        set { SetAccessory(AccessoryKind.Bow, value); OnPropertyChanged(); }
    }

    public bool AccessoryHat
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Hat).IsEnabled;
        set { SetAccessory(AccessoryKind.Hat, value); OnPropertyChanged(); }
    }

    public bool AccessoryGlasses
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Glasses).IsEnabled;
        set { SetAccessory(AccessoryKind.Glasses, value); OnPropertyChanged(); }
    }

    public bool AccessoryScarf
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Scarf).IsEnabled;
        set { SetAccessory(AccessoryKind.Scarf, value); OnPropertyChanged(); }
    }

    public bool AccessoryCrown
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Crown).IsEnabled;
        set { SetAccessory(AccessoryKind.Crown, value); OnPropertyChanged(); }
    }

    public bool AccessoryBandana
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Bandana).IsEnabled;
        set { SetAccessory(AccessoryKind.Bandana, value); OnPropertyChanged(); }
    }

    public bool AccessoryPumpkin
    {
        get => _profile.Appearance.Accessory(AccessoryKind.Pumpkin).IsEnabled;
        set { SetAccessory(AccessoryKind.Pumpkin, value); OnPropertyChanged(); }
    }

    public bool AccessorySantaHat
    {
        get => _profile.Appearance.Accessory(AccessoryKind.SantaHat).IsEnabled;
        set { SetAccessory(AccessoryKind.SantaHat, value); OnPropertyChanged(); }
    }

    private void SetAccessory(AccessoryKind kind, bool enabled)
    {
        var acc = _profile.Appearance.Accessory(kind);
        if (acc.IsEnabled != enabled)
        {
            acc.IsEnabled = enabled;
            SaveAndNotify();
        }
    }

    public ReducedMotionMode SelectedReducedMotion
    {
        get => _profile.Settings.ReducedMotion;
        set
        {
            if (_profile.Settings.ReducedMotion != value)
            {
                _profile.Settings.ReducedMotion = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<ReducedMotionMode> AvailableReducedMotionModes => Enum.GetValues<ReducedMotionMode>();

    // Personality
    public CookiePersonality SelectedPersonality
    {
        get => _profile.Personality;
        set
        {
            if (_profile.Personality != value)
            {
                _profile.Personality = value;
                SaveAndNotify();
                OnPropertyChanged();
                OnPropertyChanged(nameof(PersonalitySummary));
                OnPropertyChanged(nameof(PersonalityWalkSpeed));
                OnPropertyChanged(nameof(PersonalityPetTolerance));
            }
        }
    }
    public IReadOnlyList<CookiePersonality> AvailablePersonalities => Enum.GetValues<CookiePersonality>();

    public string PersonalitySummary => _profile.Personality.GetSummary();
    public string PersonalityWalkSpeed => $"{_profile.Personality.GetWalkSpeed()} pt/s";
    public string PersonalityPetTolerance => $"{_profile.Personality.GetPetTolerance()} strokes/min";

    public ActivityLevel SelectedActivity
    {
        get => _profile.Settings.Activity;
        set
        {
            if (_profile.Settings.Activity != value)
            {
                _profile.Settings.Activity = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<ActivityLevel> AvailableActivities => Enum.GetValues<ActivityLevel>();

    public bool AutonomousBehaviorEnabled
    {
        get => _profile.Settings.AutonomousBehaviorEnabled;
        set { if (_profile.Settings.AutonomousBehaviorEnabled != value) { _profile.Settings.AutonomousBehaviorEnabled = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool PauseAutonomousBehavior
    {
        get => _profile.Settings.PauseAutonomousBehavior;
        set { if (_profile.Settings.PauseAutonomousBehavior != value) { _profile.Settings.PauseAutonomousBehavior = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool RandomInteractions
    {
        get => _profile.Settings.RandomInteractions;
        set { if (_profile.Settings.RandomInteractions != value) { _profile.Settings.RandomInteractions = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public SleepBehavior SelectedSleepBehavior
    {
        get => _profile.Settings.Sleep;
        set
        {
            if (_profile.Settings.Sleep != value)
            {
                _profile.Settings.Sleep = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<SleepBehavior> AvailableSleepBehaviors => Enum.GetValues<SleepBehavior>();

    // Presence
    public bool HideInFullscreen
    {
        get => _profile.Settings.HideInFullscreen;
        set { if (_profile.Settings.HideInFullscreen != value) { _profile.Settings.HideInFullscreen = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool HideFromScreenSharing
    {
        get => _profile.Settings.HideFromScreenSharing;
        set { if (_profile.Settings.HideFromScreenSharing != value) { _profile.Settings.HideFromScreenSharing = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public SummonShortcut SelectedSummonShortcut
    {
        get => _profile.Settings.SummonShortcut;
        set
        {
            if (_profile.Settings.SummonShortcut == value) return;
            _profile.Settings.SummonShortcut = value;
            SaveAndNotify();
            OnPropertyChanged();
            OnPropertyChanged(nameof(SummonShortcutMessage));
        }
    }
    public IReadOnlyList<SummonShortcut> AvailableSummonShortcuts => Enum.GetValues<SummonShortcut>();

    /// <summary>Shown when another app already owns the chosen shortcut.</summary>
    public string SummonShortcutMessage =>
        Cookie.Windows.Desktop.SummonHotKeyService.IsUnavailable ? "Another app is using this shortcut. Choose a different one." : string.Empty;

    public bool SeasonalOutfits
    {
        get => _profile.Settings.SeasonalOutfits;
        set { if (_profile.Settings.SeasonalOutfits != value) { _profile.Settings.SeasonalOutfits = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool TimeGreetings
    {
        get => _profile.Settings.TimeGreetings;
        set { if (_profile.Settings.TimeGreetings != value) { _profile.Settings.TimeGreetings = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public int FocusMinutes
    {
        get => _profile.Settings.FocusMinutes;
        set
        {
            int clamped = Math.Clamp(value, 5, 120);
            if (_profile.Settings.FocusMinutes == clamped) return;
            _profile.Settings.FocusMinutes = clamped;
            SaveAndNotify();
            OnPropertyChanged();
            OnPropertyChanged(nameof(FocusMinutesText));
        }
    }
    public string FocusMinutesText => $"Focus length: {FocusMinutes} minutes";

    public int BreakMinutes
    {
        get => _profile.Settings.BreakMinutes;
        set
        {
            int clamped = Math.Clamp(value, 1, 30);
            if (_profile.Settings.BreakMinutes == clamped) return;
            _profile.Settings.BreakMinutes = clamped;
            SaveAndNotify();
            OnPropertyChanged();
            OnPropertyChanged(nameof(BreakMinutesText));
        }
    }
    public string BreakMinutesText => $"Break length: {BreakMinutes} minutes";

    // Friendship
    public string BondLevelName => _bond.Progress.Level.Name;
    public double BondFraction => _bond.Progress.Fraction;

    public string BondSummary => _bond.Progress.Next is { } next
        ? $"{_bond.Progress.PointsToNext} more points to reach {next.Name}. Pets, treats, play and focus sessions all count, and so does each new day together."
        : "You and Cookie are as close as can be.";

    public IReadOnlyList<BondLevelRow> BondUnlocks => Bond.Levels.Skip(1)
        .Select(level => new BondLevelRow(
            $"{level.Name} · {level.Points} points",
            string.Join(", ", level.Unlocks.Select(item => item.DisplayName)),
            _bond.Points >= level.Points))
        .ToList();

    public sealed record BondLevelRow(string Title, string Items, bool Reached)
    {
        public string Marker => Reached ? "Unlocked" : "Locked";
    }

    public string FocusSessionsText => Statistics.FocusSessions.ToString();
    public string FocusMinutesTotalText => Statistics.FocusMinutes.ToString();

    // Cursor
    public bool CursorInteraction
    {
        get => _profile.Settings.CursorInteraction;
        set { if (_profile.Settings.CursorInteraction != value) { _profile.Settings.CursorInteraction = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool CursorFollowingEnabled
    {
        get => _profile.Settings.CursorFollowingEnabled;
        set { if (_profile.Settings.CursorFollowingEnabled != value) { _profile.Settings.CursorFollowingEnabled = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool CursorDodgingEnabled
    {
        get => _profile.Settings.CursorDodgingEnabled;
        set { if (_profile.Settings.CursorDodgingEnabled != value) { _profile.Settings.CursorDodgingEnabled = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public CursorFollowingIntensity SelectedFollowingIntensity
    {
        get => _profile.Settings.FollowingIntensity;
        set
        {
            if (_profile.Settings.FollowingIntensity != value)
            {
                _profile.Settings.FollowingIntensity = value;
                SaveAndNotify();
                OnPropertyChanged();
            }
        }
    }
    public IReadOnlyList<CursorFollowingIntensity> AvailableFollowingIntensities => Enum.GetValues<CursorFollowingIntensity>();

    // Desktop Exploration
    public bool DockInteraction
    {
        get => _profile.Settings.DockInteraction;
        set { if (_profile.Settings.DockInteraction != value) { _profile.Settings.DockInteraction = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool AutonomousDockExploration
    {
        get => _profile.Settings.AutonomousDockExploration;
        set { if (_profile.Settings.AutonomousDockExploration != value) { _profile.Settings.AutonomousDockExploration = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public DockExplorationFrequency SelectedDockExplorationFrequency
    {
        get => _profile.Settings.DockExplorationFrequency;
        set { if (_profile.Settings.DockExplorationFrequency != value) { _profile.Settings.DockExplorationFrequency = value; SaveAndNotify(); OnPropertyChanged(); } }
    }
    public IReadOnlyList<DockExplorationFrequency> AvailableDockExplorationFrequencies => Enum.GetValues<DockExplorationFrequency>();

    public bool WindowInteraction
    {
        get => _profile.Settings.WindowInteraction;
        set { if (_profile.Settings.WindowInteraction != value) { _profile.Settings.WindowInteraction = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool WindowVerticalClimbing
    {
        get => _profile.Settings.WindowVerticalClimbing;
        set { if (_profile.Settings.WindowVerticalClimbing != value) { _profile.Settings.WindowVerticalClimbing = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public WindowExplorationFrequency SelectedWindowExplorationFrequency
    {
        get => _profile.Settings.WindowExplorationFrequency;
        set { if (_profile.Settings.WindowExplorationFrequency != value) { _profile.Settings.WindowExplorationFrequency = value; SaveAndNotify(); OnPropertyChanged(); } }
    }
    public IReadOnlyList<WindowExplorationFrequency> AvailableWindowExplorationFrequencies => Enum.GetValues<WindowExplorationFrequency>();

    public bool WindowJumpingEnabled
    {
        get => _profile.Settings.WindowJumpingEnabled;
        set { if (_profile.Settings.WindowJumpingEnabled != value) { _profile.Settings.WindowJumpingEnabled = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public JumpFrequency SelectedJumpFrequency
    {
        get => _profile.Settings.JumpFrequency;
        set { if (_profile.Settings.JumpFrequency != value) { _profile.Settings.JumpFrequency = value; SaveAndNotify(); OnPropertyChanged(); } }
    }
    public IReadOnlyList<JumpFrequency> AvailableJumpFrequencies => Enum.GetValues<JumpFrequency>();

    public JumpStyle SelectedJumpStyle
    {
        get => _profile.Settings.JumpStyle;
        set { if (_profile.Settings.JumpStyle != value) { _profile.Settings.JumpStyle = value; SaveAndNotify(); OnPropertyChanged(); } }
    }
    public IReadOnlyList<JumpStyle> AvailableJumpStyles => Enum.GetValues<JumpStyle>();

    // Sound
    public bool SoundEnabled
    {
        get => _profile.Settings.SoundEnabled;
        set { if (_profile.Settings.SoundEnabled != value) { _profile.Settings.SoundEnabled = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public double MasterVolume
    {
        get => _profile.Settings.MasterVolume;
        set
        {
            double clamped = Math.Clamp(value, 0.0, 1.0);
            if (Math.Abs(_profile.Settings.MasterVolume - clamped) > 0.01)
            {
                _profile.Settings.MasterVolume = clamped;
                SaveAndNotify();
                OnPropertyChanged();
                OnPropertyChanged(nameof(MasterVolumePercent));
            }
        }
    }
    public string MasterVolumePercent => $"{(int)Math.Round(MasterVolume * 100)}%";

    public double MeowVolume
    {
        get => _profile.Settings.MeowVolume;
        set
        {
            double clamped = Math.Clamp(value, 0.0, 1.0);
            if (Math.Abs(_profile.Settings.MeowVolume - clamped) > 0.01)
            {
                _profile.Settings.MeowVolume = clamped;
                SaveAndNotify();
                OnPropertyChanged();
                OnPropertyChanged(nameof(MeowVolumePercent));
            }
        }
    }
    public string MeowVolumePercent => $"{(int)Math.Round(MeowVolume * 100)}%";

    public bool InteractionSounds
    {
        get => _profile.Settings.InteractionSounds;
        set { if (_profile.Settings.InteractionSounds != value) { _profile.Settings.InteractionSounds = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public bool PurringSounds
    {
        get => _profile.Settings.PurringSounds;
        set { if (_profile.Settings.PurringSounds != value) { _profile.Settings.PurringSounds = value; SaveAndNotify(); OnPropertyChanged(); } }
    }

    public string AppVersion => "1.1.0";
    public string CopyrightText => "© 2026 Md Kasif Uddin. All rights reserved.";

    private void SaveAndNotify()
    {
        _settingsManager.DebouncedSave(_profile);
        _onSettingsChanged?.Invoke();
    }

    protected void OnPropertyChanged([CallerMemberName] string? name = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
