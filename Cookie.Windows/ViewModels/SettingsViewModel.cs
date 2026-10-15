using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using Cookie.Windows.Audio;
using Cookie.Windows.Models;
using Cookie.Windows.Persistence;

namespace Cookie.Windows.ViewModels;

public class SettingsViewModel : INotifyPropertyChanged
{
    private readonly CookieProfile _profile;
    private readonly SettingsManager _settingsManager;
    private readonly WindowsAudioManager _audioManager;
    private readonly Action? _onSettingsChanged;

    public event PropertyChangedEventHandler? PropertyChanged;

    public SettingsViewModel(
        CookieProfile profile,
        SettingsManager settingsManager,
        WindowsAudioManager audioManager,
        Action? onSettingsChanged = null)
    {
        _profile = profile;
        _settingsManager = settingsManager;
        _audioManager = audioManager;
        _onSettingsChanged = onSettingsChanged;

        TestSoundCommand = new RelayCommand(() =>
        {
            _audioManager.Play(SoundEffect.Meow);
        });

        ResetPersonalityCommand = new RelayCommand(() =>
        {
            _profile.Settings.ResetPersonalityAndActivitySettings();
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
    public ICommand ResetCursorCommand { get; }
    public ICommand ResetExplorationCommand { get; }

    // General
    public string CharacterName
    {
        get => _profile.DisplayName;
        set
        {
            if (_profile.DisplayName != value)
            {
                _profile.DisplayName = value;
                SaveAndNotify();
            }
        }
    }

    public bool LaunchAtLogin
    {
        get => _profile.Settings.LaunchAtLogin;
        set { if (_profile.Settings.LaunchAtLogin != value) { _profile.Settings.LaunchAtLogin = value; SaveAndNotify(); } }
    }

    public bool ShowOnStartup
    {
        get => _profile.Settings.ShowOnStartup;
        set { if (_profile.Settings.ShowOnStartup != value) { _profile.Settings.ShowOnStartup = value; SaveAndNotify(); } }
    }

    public bool RememberPosition
    {
        get => _profile.Settings.RememberPosition;
        set { if (_profile.Settings.RememberPosition != value) { _profile.Settings.RememberPosition = value; SaveAndNotify(); } }
    }

    public bool AutomaticallyCheckForUpdates
    {
        get => _profile.Settings.AutomaticallyCheckForUpdates;
        set { if (_profile.Settings.AutomaticallyCheckForUpdates != value) { _profile.Settings.AutomaticallyCheckForUpdates = value; SaveAndNotify(); } }
    }

    // Appearance
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
                OnPropertyChanged(nameof(AnimationIntensityPercent));
            }
        }
    }

    public string AnimationIntensityPercent => $"{(int)Math.Round(AnimationIntensity * 100)}%";

    public FurColor SelectedFurColor
    {
        get => _profile.Appearance.FurColor;
        set
        {
            if (_profile.Appearance.FurColor != value)
            {
                _profile.Appearance.FurColor = value;
                SaveAndNotify();
            }
        }
    }

    public IReadOnlyList<FurColor> AvailableFurColors => Enum.GetValues<FurColor>();

    public EyeColor SelectedEyeColor
    {
        get => _profile.Appearance.EyeColor;
        set
        {
            if (_profile.Appearance.EyeColor != value)
            {
                _profile.Appearance.EyeColor = value;
                SaveAndNotify();
            }
        }
    }

    public IReadOnlyList<EyeColor> AvailableEyeColors => Enum.GetValues<EyeColor>();

    public ReducedMotionMode SelectedReducedMotion
    {
        get => _profile.Settings.ReducedMotion;
        set
        {
            if (_profile.Settings.ReducedMotion != value)
            {
                _profile.Settings.ReducedMotion = value;
                SaveAndNotify();
            }
        }
    }

    public IReadOnlyList<ReducedMotionMode> AvailableReducedMotionModes => Enum.GetValues<ReducedMotionMode>();

    // Personality
    public ActivityLevel SelectedActivity
    {
        get => _profile.Settings.Activity;
        set
        {
            if (_profile.Settings.Activity != value)
            {
                _profile.Settings.Activity = value;
                SaveAndNotify();
            }
        }
    }

    public IReadOnlyList<ActivityLevel> AvailableActivities => Enum.GetValues<ActivityLevel>();

    public bool AutonomousBehaviorEnabled
    {
        get => _profile.Settings.AutonomousBehaviorEnabled;
        set { if (_profile.Settings.AutonomousBehaviorEnabled != value) { _profile.Settings.AutonomousBehaviorEnabled = value; SaveAndNotify(); } }
    }

    public bool PauseAutonomousBehavior
    {
        get => _profile.Settings.PauseAutonomousBehavior;
        set { if (_profile.Settings.PauseAutonomousBehavior != value) { _profile.Settings.PauseAutonomousBehavior = value; SaveAndNotify(); } }
    }

    public bool RandomInteractions
    {
        get => _profile.Settings.RandomInteractions;
        set { if (_profile.Settings.RandomInteractions != value) { _profile.Settings.RandomInteractions = value; SaveAndNotify(); } }
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
            }
        }
    }

    public IReadOnlyList<SleepBehavior> AvailableSleepBehaviors => Enum.GetValues<SleepBehavior>();

    // Cursor
    public bool CursorInteraction
    {
        get => _profile.Settings.CursorInteraction;
        set { if (_profile.Settings.CursorInteraction != value) { _profile.Settings.CursorInteraction = value; SaveAndNotify(); } }
    }

    public bool CursorFollowingEnabled
    {
        get => _profile.Settings.CursorFollowingEnabled;
        set { if (_profile.Settings.CursorFollowingEnabled != value) { _profile.Settings.CursorFollowingEnabled = value; SaveAndNotify(); } }
    }

    public bool CursorDodgingEnabled
    {
        get => _profile.Settings.CursorDodgingEnabled;
        set { if (_profile.Settings.CursorDodgingEnabled != value) { _profile.Settings.CursorDodgingEnabled = value; SaveAndNotify(); } }
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
            }
        }
    }

    public IReadOnlyList<CursorFollowingIntensity> AvailableFollowingIntensities => Enum.GetValues<CursorFollowingIntensity>();

    // Desktop Exploration
    public bool DockInteraction
    {
        get => _profile.Settings.DockInteraction;
        set { if (_profile.Settings.DockInteraction != value) { _profile.Settings.DockInteraction = value; SaveAndNotify(); } }
    }

    public bool AutonomousDockExploration
    {
        get => _profile.Settings.AutonomousDockExploration;
        set { if (_profile.Settings.AutonomousDockExploration != value) { _profile.Settings.AutonomousDockExploration = value; SaveAndNotify(); } }
    }

    public bool WindowInteraction
    {
        get => _profile.Settings.WindowInteraction;
        set { if (_profile.Settings.WindowInteraction != value) { _profile.Settings.WindowInteraction = value; SaveAndNotify(); } }
    }

    public bool WindowJumpingEnabled
    {
        get => _profile.Settings.WindowJumpingEnabled;
        set { if (_profile.Settings.WindowJumpingEnabled != value) { _profile.Settings.WindowJumpingEnabled = value; SaveAndNotify(); } }
    }

    // Sound
    public bool SoundEnabled
    {
        get => _profile.Settings.SoundEnabled;
        set { if (_profile.Settings.SoundEnabled != value) { _profile.Settings.SoundEnabled = value; SaveAndNotify(); } }
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
                OnPropertyChanged(nameof(MeowVolumePercent));
            }
        }
    }

    public string MeowVolumePercent => $"{(int)Math.Round(MeowVolume * 100)}%";

    public bool InteractionSounds
    {
        get => _profile.Settings.InteractionSounds;
        set { if (_profile.Settings.InteractionSounds != value) { _profile.Settings.InteractionSounds = value; SaveAndNotify(); } }
    }

    public bool PurringSounds
    {
        get => _profile.Settings.PurringSounds;
        set { if (_profile.Settings.PurringSounds != value) { _profile.Settings.PurringSounds = value; SaveAndNotify(); } }
    }

    // App Information
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
