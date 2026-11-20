using System.Collections.Generic;
using Cookie.Windows.Core.Helpers;

namespace Cookie.Windows.Core.Models;

public enum ReducedMotionMode
{
    System,
    Always,
    Never
}

public enum ActivityLevel
{
    Calm,
    Balanced,
    Playful
}

public enum CursorFollowingIntensity
{
    Calm,
    Balanced,
    Intense
}

public enum WindowExplorationFrequency
{
    Rare,
    Occasional,
    Frequent
}

public enum JumpFrequency
{
    Calm,
    Balanced,
    Playful
}

public enum JumpStyle
{
    Gentle,
    Playful
}

public enum SleepBehavior
{
    Normal,
    Longer,
    None
}

public enum DockExplorationFrequency
{
    Rare,
    Occasional,
    Frequent
}

public class CookieSettings
{
    public int SchemaVersion { get; set; } = 1;

    // General
    public bool LaunchAtLogin { get; set; } = false;
    public bool ShowOnStartup { get; set; } = true;
    public bool RememberPosition { get; set; } = true;
    public double? SavedPositionX { get; set; } = null;
    public double? SavedPositionY { get; set; } = null;
    public bool HasCompletedOnboarding { get; set; } = false;

    // Appearance
    public double CookieSize { get; set; } = 1.0;
    public double AnimationIntensity { get; set; } = 1.0;
    public ReducedMotionMode ReducedMotion { get; set; } = ReducedMotionMode.System;

    // Sound
    public bool SoundEnabled { get; set; } = true;
    public double MasterVolume { get; set; } = 0.7;
    public double MeowVolume { get; set; } = 0.8;
    public bool InteractionSounds { get; set; } = true;
    public bool PurringSounds { get; set; } = true;

    // Behavior
    public ActivityLevel Activity { get; set; } = ActivityLevel.Balanced;
    public bool RandomInteractions { get; set; } = true;
    public bool AutonomousBehaviorEnabled { get; set; } = true;
    public bool PauseAutonomousBehavior { get; set; } = false;
    public bool CursorInteraction { get; set; } = true;
    public bool CursorFollowingEnabled { get; set; } = true;
    public bool CursorDodgingEnabled { get; set; } = true;
    public CursorFollowingIntensity FollowingIntensity { get; set; } = CursorFollowingIntensity.Balanced;
    public bool WindowInteraction { get; set; } = true;
    public bool WindowVerticalClimbing { get; set; } = false;
    public WindowExplorationFrequency WindowExplorationFrequency { get; set; } = WindowExplorationFrequency.Occasional;
    public bool WindowJumpingEnabled { get; set; } = true;
    public JumpFrequency JumpFrequency { get; set; } = JumpFrequency.Balanced;
    public JumpStyle JumpStyle { get; set; } = JumpStyle.Gentle;
    public SleepBehavior Sleep { get; set; } = SleepBehavior.Normal;
    public bool AutonomousToys { get; set; } = true;

    // Desktop & Taskbar Exploration
    public bool DockInteraction { get; set; } = true;
    public bool AutonomousDockExploration { get; set; } = true;
    public DockExplorationFrequency DockExplorationFrequency { get; set; } = DockExplorationFrequency.Occasional;

    // Daily rhythm
    /// <summary>Cookie dresses for the season and the occasion, from the local date.</summary>
    public bool SeasonalOutfits { get; set; } = true;

    /// <summary>She says good morning, good evening and good night when she first appears.</summary>
    public bool TimeGreetings { get; set; } = true;

    // Focus
    public int FocusMinutes { get; set; } = 25;
    public int BreakMinutes { get; set; } = 5;

    // Presence
    /// <summary>Hide during full-screen apps, games and presentations.</summary>
    public bool HideInFullscreen { get; set; } = true;

    /// <summary>Keep her out of screen sharing and recordings.</summary>
    public bool HideFromScreenSharing { get; set; } = true;

    public SummonShortcut SummonShortcut { get; set; } = SummonShortcut.ControlAltC;

    // Updates
    public bool AutomaticallyCheckForUpdates { get; set; } = true;

    // Helpers
    /// <summary>Break nudges that are switched on. All off until you choose them.</summary>
    public List<BreakNudge> BreakNudges { get; set; } = new();
    /// <summary>During a focus session she reacts when you switch to one of these apps.</summary>
    public bool FocusGuardEnabled { get; set; } = true;
    public List<DistractingApp> DistractingApps { get; set; } = new();
    public bool BedtimeEnabled { get; set; } = false;
    /// <summary>Minutes after midnight; 23:00 by default.</summary>
    public int BedtimeMinutes { get; set; } = 23 * 60;
    /// <summary>What the system watcher speaks up about. Needs no permission, so all on.</summary>
    public List<SystemAlertKind> SystemAlerts { get; set; } = new()
    {
        SystemAlertKind.Battery, SystemAlertKind.Cpu, SystemAlertKind.Disk, SystemAlertKind.Network
    };
    /// <summary>Watching Downloads and the Desktop starts off.</summary>
    public bool DownloadAlerts { get; set; } = false;
    public bool ScreenshotTidyOffers { get; set; } = false;
    public bool ShowStickyNotes { get; set; } = true;

    // Power tools
    /// <summary>cookie:// links.</summary>
    public bool AllowLinks { get; set; } = true;
    /// <summary>Dropping files on Cookie offers to file or zip them.</summary>
    public bool FileDropEnabled { get; set; } = true;
    /// <summary>The folder dropped files go to. Empty until you choose one.</summary>
    public string DropFolderPath { get; set; } = "";
    /// <summary>Keeps your last few copies in memory. Off until you turn it on.</summary>
    public bool ClipboardHistory { get; set; } = false;
    /// <summary>Chat with Cookie through the Claude API. Off until you turn it on and add a key.</summary>
    public bool AskCookieEnabled { get; set; } = false;

    public void ResetPersonalityAndActivitySettings()
    {
        Activity = ActivityLevel.Balanced;
        RandomInteractions = true;
        AutonomousBehaviorEnabled = true;
        PauseAutonomousBehavior = false;
        CursorInteraction = true;
        DockInteraction = true;
        WindowInteraction = true;
        WindowJumpingEnabled = true;
        AutonomousToys = true;
    }

    public void ResetCursorInteractionSettings()
    {
        CursorInteraction = true;
        CursorFollowingEnabled = true;
        CursorDodgingEnabled = true;
        FollowingIntensity = CursorFollowingIntensity.Balanced;
    }

    public void ResetDesktopExplorationSettings()
    {
        DockInteraction = true;
        AutonomousDockExploration = true;
        DockExplorationFrequency = DockExplorationFrequency.Occasional;
        WindowInteraction = true;
        WindowVerticalClimbing = false;
        WindowExplorationFrequency = WindowExplorationFrequency.Occasional;
        WindowJumpingEnabled = true;
        JumpFrequency = JumpFrequency.Balanced;
        JumpStyle = JumpStyle.Gentle;
    }
}
