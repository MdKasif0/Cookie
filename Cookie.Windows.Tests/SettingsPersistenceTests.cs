using System;
using System.IO;
using Cookie.Windows.Models;
using Cookie.Windows.Persistence;
using Xunit;

namespace Cookie.Windows.Tests;

public class SettingsPersistenceTests : IDisposable
{
    private readonly string _testDirectory;

    public SettingsPersistenceTests()
    {
        _testDirectory = Path.Combine(Path.GetTempPath(), "CookieTests_" + Guid.NewGuid().ToString("N"));
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
    public void LoadProfile_WhenFileDoesNotExist_CreatesAndReturnsDefaultProfile()
    {
        string filePath = Path.Combine(_testDirectory, "profile.json");
        var manager = new SettingsManager(filePath);

        var profile = manager.LoadProfile();

        Assert.NotNull(profile);
        Assert.Equal("Cookie", profile.DisplayName);
        Assert.Equal(1, profile.Version);
        Assert.True(File.Exists(filePath));
    }

    [Fact]
    public void SaveAndLoad_PersistsCustomSettingsCorrectly()
    {
        string filePath = Path.Combine(_testDirectory, "profile.json");
        var manager = new SettingsManager(filePath);

        var profile = manager.LoadProfile();
        profile.DisplayName = "Biscuit";
        profile.Appearance.FurColor = FurColor.Charcoal;
        profile.Settings.CookieSize = 1.25;
        profile.Settings.SoundEnabled = false;
        profile.Settings.SavedPositionX = 350;
        profile.Settings.SavedPositionY = 420;

        manager.SaveProfileImmediate(profile);

        // Read again in a new manager instance
        var reloadedManager = new SettingsManager(filePath);
        var reloadedProfile = reloadedManager.LoadProfile();

        Assert.Equal("Biscuit", reloadedProfile.DisplayName);
        Assert.Equal(FurColor.Charcoal, reloadedProfile.Appearance.FurColor);
        Assert.Equal(1.25, reloadedProfile.Settings.CookieSize, 2);
        Assert.False(reloadedProfile.Settings.SoundEnabled);
        Assert.Equal(350, reloadedProfile.Settings.SavedPositionX);
        Assert.Equal(420, reloadedProfile.Settings.SavedPositionY);
    }

    [Fact]
    public void LoadProfile_WhenJsonIsCorrupt_BacksUpAndRecoversWithDefault()
    {
        string filePath = Path.Combine(_testDirectory, "profile.json");
        File.WriteAllText(filePath, "{ corrupt json !!! invalid syntax }");

        var manager = new SettingsManager(filePath);
        var profile = manager.LoadProfile();

        Assert.NotNull(profile);
        Assert.Equal("Cookie", profile.DisplayName);

        // Check that a corrupt backup file was created
        var backupFiles = Directory.GetFiles(_testDirectory, "profile.corrupt.*.json");
        Assert.NotEmpty(backupFiles);
    }

    [Fact]
    public void SaveProfileImmediate_WritesAtomicallyWithoutLeavingTempFiles()
    {
        string filePath = Path.Combine(_testDirectory, "profile.json");
        var manager = new SettingsManager(filePath);

        var profile = new CookieProfile();
        manager.SaveProfileImmediate(profile);

        Assert.True(File.Exists(filePath));
        var tempFiles = Directory.GetFiles(_testDirectory, "*.tmp.*");
        Assert.Empty(tempFiles);
    }
}
