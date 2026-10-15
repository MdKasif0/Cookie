using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Cookie.Windows.Models;

namespace Cookie.Windows.Persistence;

public class SettingsManager
{
    public const int CurrentSchemaVersion = 1;
    private readonly string _settingsFilePath;
    private readonly string _settingsDirectory;
    private readonly object _fileLock = new();

    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() }
    };

    private CancellationTokenSource? _debounceCts;

    public string SettingsFilePath => _settingsFilePath;

    public SettingsManager(string? customPath = null)
    {
        if (!string.IsNullOrEmpty(customPath))
        {
            _settingsFilePath = customPath;
            _settingsDirectory = Path.GetDirectoryName(customPath) ?? AppDomain.CurrentDomain.BaseDirectory;
        }
        else
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _settingsDirectory = Path.Combine(appData, "Cookie");
            _settingsFilePath = Path.Combine(_settingsDirectory, "profile.json");
        }
    }

    public CookieProfile LoadProfile()
    {
        lock (_fileLock)
        {
            try
            {
                if (!File.Exists(_settingsFilePath))
                {
                    var newProfile = new CookieProfile();
                    SaveProfileImmediate(newProfile);
                    return newProfile;
                }

                string json = File.ReadAllText(_settingsFilePath);
                var profile = JsonSerializer.Deserialize<CookieProfile>(json, _jsonOptions);

                if (profile == null)
                {
                    return HandleCorruptSettings("Deserialized profile was null");
                }

                // Check version migrations if future versions are introduced
                if (profile.Version < CurrentSchemaVersion)
                {
                    MigrateProfile(profile);
                    SaveProfileImmediate(profile);
                }

                return profile;
            }
            catch (Exception ex)
            {
                return HandleCorruptSettings(ex.Message);
            }
        }
    }

    private CookieProfile HandleCorruptSettings(string reason)
    {
        try
        {
            if (File.Exists(_settingsFilePath))
            {
                string backupPath = Path.Combine(
                    _settingsDirectory,
                    $"profile.corrupt.{DateTime.UtcNow:yyyyMMddHHmmss}.json");
                File.Copy(_settingsFilePath, backupPath, overwrite: true);
            }
        }
        catch
        {
            // Ignore backup failures
        }

        var defaultProfile = new CookieProfile();
        SaveProfileImmediate(defaultProfile);
        return defaultProfile;
    }

    private void MigrateProfile(CookieProfile profile)
    {
        profile.Version = CurrentSchemaVersion;
    }

    public void SaveProfileImmediate(CookieProfile profile)
    {
        lock (_fileLock)
        {
            Directory.CreateDirectory(_settingsDirectory);

            profile.LastModified = DateTime.UtcNow;
            string json = JsonSerializer.Serialize(profile, _jsonOptions);

            // Atomic save: write to temporary file first, then replace target file
            string tempFilePath = _settingsFilePath + ".tmp." + Guid.NewGuid().ToString("N");

            try
            {
                File.WriteAllText(tempFilePath, json);

                if (File.Exists(_settingsFilePath))
                {
                    File.Move(tempFilePath, _settingsFilePath, overwrite: true);
                }
                else
                {
                    File.Move(tempFilePath, _settingsFilePath);
                }
            }
            finally
            {
                if (File.Exists(tempFilePath))
                {
                    try { File.Delete(tempFilePath); } catch { }
                }
            }
        }
    }

    public void DebouncedSave(CookieProfile profile, int delayMilliseconds = 500)
    {
        _debounceCts?.Cancel();
        _debounceCts = new CancellationTokenSource();
        var token = _debounceCts.Token;

        Task.Delay(delayMilliseconds, token).ContinueWith(t =>
        {
            if (!t.IsCanceled)
            {
                SaveProfileImmediate(profile);
            }
        }, TaskScheduler.Default);
    }
}
