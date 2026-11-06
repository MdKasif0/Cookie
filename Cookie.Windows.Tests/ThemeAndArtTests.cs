using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class ThemeAndArtTests
{
    private static string RepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null && !File.Exists(Path.Combine(directory.FullName, "Cookie.Windows.sln")))
        {
            directory = directory.Parent;
        }
        return directory?.FullName ?? throw new DirectoryNotFoundException();
    }

    private static string[] PaletteKeys(string variant)
    {
        string xaml = File.ReadAllText(Path.Combine(RepoRoot(), "Cookie.Windows", "Themes", $"Palette.{variant}.xaml"));
        return Regex.Matches(xaml, "x:Key=\"(\\w+)\"").Select(match => match.Groups[1].Value).OrderBy(key => key).ToArray();
    }

    /// <summary>A key missing from one palette would turn into an invisible surface or text.</summary>
    [Fact]
    public void LightAndDarkPalettes_DefineTheSameKeys()
    {
        Assert.NotEmpty(PaletteKeys("Light"));
        Assert.Equal(PaletteKeys("Light"), PaletteKeys("Dark"));
    }

    [Fact]
    public void Windows_UseOnlyKeysThePaletteDefines()
    {
        var keys = PaletteKeys("Light").ToHashSet();
        var fluent = new[] { "AccentButtonStyle", "EmoteTileButtonStyle" };
        foreach (string file in Directory.GetFiles(Path.Combine(RepoRoot(), "Cookie.Windows", "Views"), "*.xaml"))
        {
            foreach (Match match in Regex.Matches(File.ReadAllText(file), "\\{(?:Dynamic|Static)Resource (\\w+)\\}"))
            {
                string key = match.Groups[1].Value;
                Assert.True(keys.Contains(key) || fluent.Contains(key), $"{Path.GetFileName(file)} uses unknown resource {key}");
            }
        }
    }

    [Fact]
    public void Windows_HaveNoHardCodedColors()
    {
        foreach (string file in Directory.GetFiles(Path.Combine(RepoRoot(), "Cookie.Windows", "Views"), "*.xaml"))
        {
            var match = Regex.Match(File.ReadAllText(file), "#[0-9A-Fa-f]{6,8}\\b");
            Assert.False(match.Success, $"{Path.GetFileName(file)} hard-codes {match.Value}");
        }
    }

    [Fact]
    public void Windows_HaveNoEmoji()
    {
        var emoji = new Regex("[\\u2600-\\u27BF]|[\\uD83C-\\uD83E][\\uDC00-\\uDFFF]");
        foreach (string file in Directory.GetFiles(Path.Combine(RepoRoot(), "Cookie.Windows", "Views"), "*.xaml")
                     .Concat(new[] { Path.Combine(RepoRoot(), "Cookie.Windows", "Desktop", "CareMenuBuilder.cs") }))
        {
            Assert.False(emoji.IsMatch(File.ReadAllText(file)), $"{Path.GetFileName(file)} contains emoji");
        }
    }

    private static string Art(string folder, string name) =>
        Path.Combine(RepoRoot(), "Cookie", "Resources", "Sprites", "Cookie", folder, name + ".png");

    [Fact]
    public void EveryToyAndFood_HasArtAndAnIcon()
    {
        foreach (var toy in Enum.GetValues<ToyKind>())
        {
            Assert.True(File.Exists(Art("Items", toy.GetAssetName())), toy.ToString());
            Assert.True(File.Exists(Art("Icons", "item-" + toy.GetAssetName())), toy.ToString());
        }
        foreach (var food in Enum.GetValues<FoodKind>())
        {
            Assert.True(File.Exists(Art("Items", food.GetAssetName())), food.ToString());
            Assert.True(File.Exists(Art("Icons", "item-" + food.GetAssetName())), food.ToString());
        }
        Assert.True(File.Exists(Art("Items", "box-front")));
        Assert.True(File.Exists(Art("Items", "box-back")));
    }

    [Fact]
    public void EveryAccessory_HasArt()
    {
        foreach (var kind in Enum.GetValues<AccessoryKind>())
        {
            string name = kind.ToString();
            Assert.True(File.Exists(Art("Accessories", char.ToLowerInvariant(name[0]) + name[1..])), name);
        }
    }

    [Fact]
    public void EveryEmote_HasAnIcon()
    {
        foreach (var emote in Enum.GetValues<EmoteId>())
        {
            Assert.True(File.Exists(Art("Icons", "emote-" + emote.ToString().ToLowerInvariant())), emote.ToString());
        }
    }
}

public class OnboardingDirectorTests
{
    private readonly CookieAnimationController _animation = new();
    private readonly TestAudioManager _audio = new();

    private OnboardingDirector Make(bool reduceMotion = false) =>
        new(_animation, _audio, "Cookie", CookiePersonality.Playful, reduceMotion);

    private static void Run(OnboardingDirector director, double seconds)
    {
        for (double t = 0; t < seconds; t += 0.05) director.Update(0.05);
    }

    [Fact]
    public void Starts_OffstageWalkingIn()
    {
        var director = Make();

        Assert.False(director.HasArrived);
        Assert.Equal(1.0, director.WalkRemaining);
        Assert.Equal(CookieAnimationId.WalkRight, _animation.CurrentAnimationId);
    }

    [Fact]
    public void Walk_EasesIntoPlaceThenGreets()
    {
        var director = Make();
        Run(director, OnboardingDirector.WalkInSeconds / 2);
        double halfway = director.WalkRemaining;
        Assert.InRange(halfway, 0.2, 0.3);

        Run(director, OnboardingDirector.WalkInSeconds);

        Assert.True(director.HasArrived);
        Assert.Equal(0.0, director.WalkRemaining);
        Assert.Equal("cookie-welcome.wav", _audio.LastPlayedSoundFile);
    }

    [Fact]
    public void ReducedMotion_SkipsTheWalk()
    {
        var director = Make(reduceMotion: true);

        Assert.True(director.HasArrived);
        Assert.Equal(0.0, director.WalkRemaining);
        Assert.Equal(CookieAnimationId.Idle, _animation.CurrentAnimationId);
    }

    [Fact]
    public void Typing_MakesHerCuriousThenSettles()
    {
        var director = Make(reduceMotion: true);

        director.Name = "Biscuit";
        Assert.Equal(CookieAnimationId.Curious, _animation.CurrentAnimationId);
        Assert.Equal("Hi, I'm Biscuit!", director.Greeting);

        Run(director, 1.5);
        Assert.Equal(CookieAnimationId.Idle, _animation.CurrentAnimationId);
    }

    [Fact]
    public void Typing_ChirpsOnlyOncePerBurst()
    {
        var director = Make(reduceMotion: true);
        int plays = 0;
        _audio.SoundEnabled = true;

        director.Name = "B";
        if (_audio.LastPlayedSoundFile == "cookie-chirp.wav") plays++;
        typeof(TestAudioManager).GetProperty(nameof(TestAudioManager.LastPlayedSoundFile))!.SetValue(_audio, null);
        director.Name = "Bi";

        Assert.Equal(1, plays);
        Assert.Null(_audio.LastPlayedSoundFile);
    }

    [Theory]
    [InlineData("   ", "Cookie")]
    [InlineData("", "Cookie")]
    [InlineData("  Mochi ", "Mochi")]
    public void BlankNames_FallBackToCookie(string typed, string expected)
    {
        var director = Make(reduceMotion: true);

        director.Name = typed;

        Assert.Equal(expected, director.ResolvedName);
    }

    [Theory]
    [InlineData(CookiePersonality.Sleepy, CookieAnimationId.Sleep)]
    [InlineData(CookiePersonality.Energetic, CookieAnimationId.RunRight)]
    [InlineData(CookiePersonality.Grumpy, CookieAnimationId.Annoyed)]
    public void ChoosingAPersonality_ActsItOut(CookiePersonality personality, CookieAnimationId expected)
    {
        var director = Make(reduceMotion: true);

        director.Personality = personality;

        Assert.Equal(expected, _animation.CurrentAnimationId);
        Assert.Equal(personality, director.Personality);
    }

    [Fact]
    public void ChoosesBeforeArrival_AreKeptWithoutInterruptingTheWalk()
    {
        var director = Make();

        director.Personality = CookiePersonality.Sleepy;

        Assert.Equal(CookieAnimationId.WalkRight, _animation.CurrentAnimationId);
        Assert.Equal(CookiePersonality.Sleepy, director.Personality);
    }
}

public class SoundTakesTests
{
    private class RecordingAudio : TestAudioManager
    {
        public readonly System.Collections.Generic.List<string> Loops = new();
        public double? LoopHold;

        protected override void StartOrExtendLoop(string filePath, double volume, double holdSeconds)
        {
            Loops.Add(Path.GetFileName(filePath));
            LoopHold = holdSeconds;
        }
    }

    private static string SoundsFolder()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (!File.Exists(Path.Combine(directory!.FullName, "Cookie.Windows.sln"))) directory = directory.Parent;
        return Path.Combine(directory.FullName, "Cookie", "Resources", "Sounds");
    }

    [Fact]
    public void EveryTakeOfEverySound_Exists()
    {
        foreach (var sound in Enum.GetValues<SoundEffect>())
        {
            foreach (string file in sound.GetFileNames())
            {
                Assert.True(File.Exists(Path.Combine(SoundsFolder(), file)), file);
            }
        }
    }

    [Fact]
    public void RepeatedMeows_NeverPlayTheSameTakeTwiceInARow()
    {
        var audio = new RandomizedAudio();
        string? previous = null;

        for (int i = 0; i < 30; i++)
        {
            audio.ResetThrottle(SoundEffect.Meow);
            Assert.True(audio.Play(SoundEffect.Meow));
            Assert.NotEqual(previous, audio.LastPlayedSoundFile);
            previous = audio.LastPlayedSoundFile;
        }
    }

    [Fact]
    public void Purring_UsesTheLoopAndIsNotThrottled()
    {
        var audio = new RecordingAudio();

        Assert.True(audio.Play(SoundEffect.Purr));
        Assert.True(audio.Play(SoundEffect.Purr));

        Assert.Equal(new[] { "cookie-purr.wav", "cookie-purr.wav" }, audio.Loops);
        Assert.Equal(AudioManagerBase.PurrHoldSeconds, audio.LoopHold);
    }

    [Fact]
    public void Purring_RespectsSettings()
    {
        var audio = new RecordingAudio { PurringSounds = false };
        Assert.False(audio.Play(SoundEffect.Purr));

        audio = new RecordingAudio { SoundEnabled = false };
        Assert.False(audio.Play(SoundEffect.Purr));

        audio = new RecordingAudio { MasterVolume = 0 };
        Assert.False(audio.Play(SoundEffect.Purr));
        Assert.Empty(audio.Loops);
    }

    [Fact]
    public void PurrLoop_FileIsLongEnoughToLoopNaturally()
    {
        long bytes = new FileInfo(Path.Combine(SoundsFolder(), "cookie-purr.wav")).Length;

        // 16-bit mono at 44.1 kHz: at least six seconds, several breaths.
        Assert.True(bytes > 44100 * 2 * 6);
    }

    private class RandomizedAudio : AudioManagerBase
    {
        public string? LastPlayedSoundFile { get; private set; }
        protected override bool ValidateFileExists => false;
        protected override void PlayInternal(string filePath, double volume) => LastPlayedSoundFile = Path.GetFileName(filePath);

        public void ResetThrottle(SoundEffect sound)
        {
            var field = typeof(AudioManagerBase).GetField("_lastPlayTimes", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!;
            ((System.Collections.Concurrent.ConcurrentDictionary<SoundEffect, DateTime>)field.GetValue(this)!).TryRemove(sound, out _);
        }
    }
}
