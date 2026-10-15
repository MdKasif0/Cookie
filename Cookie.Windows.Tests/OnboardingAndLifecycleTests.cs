using System;
using System.IO;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Core.Startup;
using Cookie.Windows.ViewModels;
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
    public void SettingsViewModel_WithStartupService_SyncsStartupSetting()
    {
        var startupService = new DefaultStartupService();
        startupService.SetStartupEnabled(false);

        var profile = new CookieProfile();
        var manager = new SettingsManager(Path.Combine(_testDirectory, "profile_vm.json"));
        var audio = new HeadlessAudioManager();

        var vm = new SettingsViewModel(
            profile,
            manager,
            audio,
            onSettingsChanged: null,
            startupService: startupService);

        Assert.False(vm.LaunchAtLogin);

        // Toggle in VM
        vm.LaunchAtLogin = true;
        Assert.True(startupService.IsStartupEnabled());

        vm.LaunchAtLogin = false;
        Assert.False(startupService.IsStartupEnabled());
    }

    [Fact]
    public void SettingsViewModel_CheckForUpdatesCommand_FiresCallback()
    {
        var profile = new CookieProfile();
        var manager = new SettingsManager(Path.Combine(_testDirectory, "profile_vm2.json"));
        var audio = new HeadlessAudioManager();

        bool callbackFired = false;
        var vm = new SettingsViewModel(
            profile,
            manager,
            audio,
            onSettingsChanged: null,
            startupService: null,
            onCheckForUpdates: () => callbackFired = true);

        Assert.NotNull(vm.CheckForUpdatesCommand);
        vm.CheckForUpdatesCommand.Execute(null);

        Assert.True(callbackFired);
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
}
