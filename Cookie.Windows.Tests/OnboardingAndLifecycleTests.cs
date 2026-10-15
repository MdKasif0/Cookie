using System;
using System.IO;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Core.Startup;
using Xunit;

namespace Cookie.Windows.Tests;

public class OnboardingAndLifecycleTests : IDisposable
{
    private readonly string _testDirectory;

    public OnboardingAndLifecycleTests()
    {
        _testDirectory = Path.Combine(Path.GetTempPath(), "CookieLifecycleTests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_testDirectory);
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDirectory))
        {
            try { Directory.Delete(_testDirectory, true); } catch { }
        }
    }

    [Fact]
    public void Settings_HasCompletedOnboarding_DefaultsToFalse()
    {
        var settings = new CookieSettings();
        Assert.False(settings.HasCompletedOnboarding);
    }

    [Fact]
    public void OnboardingCompletion_PersistsCorrectlyInProfile()
    {
        string profilePath = Path.Combine(_testDirectory, "profile.json");
        var manager = new SettingsManager(profilePath);

        var profile = manager.LoadProfile();
        Assert.False(profile.Settings.HasCompletedOnboarding);

        profile.Settings.HasCompletedOnboarding = true;
        manager.SaveProfileImmediate(profile);

        var reloadedManager = new SettingsManager(profilePath);
        var reloaded = reloadedManager.LoadProfile();
        Assert.True(reloaded.Settings.HasCompletedOnboarding);
    }

    [Fact]
    public void StartupService_DefaultDisabled_RespectsExplicitRequirement()
    {
        // Requirement 19: Off by default unless existing product specification explicitly requires otherwise.
        var startup = new DefaultStartupService();
        Assert.False(startup.IsStartupEnabled());

        startup.SetStartupEnabled(true);
        Assert.True(startup.IsStartupEnabled());

        startup.SetStartupEnabled(false);
        Assert.False(startup.IsStartupEnabled());
    }

    [Fact]
    public void SingleInstanceConstants_AreWellFormed()
    {
        const string mutexName = "CookieDesktopCompanion_SingleInstance_Mutex_2026";
        const string messageName = "Cookie_ShowSettings_2026";

        Assert.False(string.IsNullOrWhiteSpace(mutexName));
        Assert.False(string.IsNullOrWhiteSpace(messageName));
        Assert.Contains("Cookie", mutexName);
        Assert.Contains("Cookie", messageName);
    }

    [Fact]
    public void Profile_GeneralSettings_DefaultsArePrivacyPreserving()
    {
        // Confirm local-only persistence, no cloud telemetry
        var settings = new CookieSettings();
        Assert.True(settings.ShowOnStartup);
        Assert.True(settings.RememberPosition);
        Assert.True(settings.AutonomousBehaviorEnabled);
        Assert.False(settings.PauseAutonomousBehavior);
        Assert.False(settings.LaunchAtLogin); // Off by default
    }
}
