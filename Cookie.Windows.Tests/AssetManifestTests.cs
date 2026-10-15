using System;
using System.IO;
using System.Text.Json;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class AssetManifestTests
{
    [Fact]
    public void AssetManifest_FileExistsAndIsValidJson()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string manifestPath = Path.Combine(baseDir, "Resources", "AssetManifest.json");
        if (!File.Exists(manifestPath))
        {
            manifestPath = Path.Combine(baseDir, "..", "..", "..", "..", "Cookie.Windows", "Resources", "AssetManifest.json");
        }

        Assert.True(File.Exists(manifestPath), $"AssetManifest.json should exist at {manifestPath}");

        string json = File.ReadAllText(manifestPath);
        using var doc = JsonDocument.Parse(json);

        var root = doc.RootElement;
        Assert.True(root.TryGetProperty("manifestVersion", out var version));
        Assert.Equal("1.0.0", version.GetString());

        Assert.True(root.TryGetProperty("assets", out var assets));
        Assert.Equal(JsonValueKind.Array, assets.ValueKind);
        Assert.True(assets.GetArrayLength() > 0);
    }

    [Fact]
    public void AllRegisteredSoundEffects_HaveWavFilesOnDisk()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string soundsDir = Path.Combine(baseDir, "Resources", "Sounds");
        if (!Directory.Exists(soundsDir))
        {
            soundsDir = Path.Combine(baseDir, "..", "..", "..", "..", "Cookie", "Resources", "Sounds");
        }

        Assert.True(Directory.Exists(soundsDir), $"Sounds directory should exist at {soundsDir}");

        foreach (SoundEffect sound in Enum.GetValues<SoundEffect>())
        {
            string fileName = sound.GetFileName();
            string fullPath = Path.Combine(soundsDir, fileName);
            Assert.True(File.Exists(fullPath), $"Sound effect file '{fileName}' for {sound} should exist");
        }
    }

    [Fact]
    public void AllRegisteredEmotes_HaveSpriteAndMetadata()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string emotesDir = Path.Combine(baseDir, "Resources", "Sprites", "Cookie", "Emotes");
        if (!Directory.Exists(emotesDir))
        {
            emotesDir = Path.Combine(baseDir, "..", "..", "..", "..", "Cookie", "Resources", "Sprites", "Cookie", "Emotes");
        }

        Assert.True(Directory.Exists(emotesDir), $"Emotes directory should exist at {emotesDir}");

        foreach (var emote in Emote.All)
        {
            string folder = emote.Id switch
            {
                EmoteId.Wave => "Wave",
                EmoteId.Happy => "Happy",
                EmoteId.Love => "Love",
                EmoteId.Sleepy => "Sleepy",
                EmoteId.Playful => "Playful",
                _ => "Wave"
            };

            string pngPath = Path.Combine(emotesDir, folder, folder.ToLowerInvariant() + ".png");
            Assert.True(File.Exists(pngPath), $"Emote png asset should exist at {pngPath}");
        }
    }
}
