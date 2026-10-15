using System;
using System.Text.Json.Serialization;

namespace Cookie.Windows.Models;

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

    // Updates
    public bool AutomaticallyCheckForUpdates { get; set; } = true;

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
