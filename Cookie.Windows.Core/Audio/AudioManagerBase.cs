using System;
using System.Collections.Concurrent;
using System.IO;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Audio;

public abstract class AudioManagerBase
{
    private readonly string _soundsDirectory;
    private readonly ConcurrentDictionary<SoundEffect, DateTime> _lastPlayTimes = new();
    private readonly ConcurrentDictionary<SoundEffect, string> _lastTakes = new();
    private readonly Random _random = new();

    /// <summary>How long purring continues after the last thing that made her purr.</summary>
    public const double PurrHoldSeconds = 5.0;

    public bool SoundEnabled { get; set; } = true;
    public double MasterVolume { get; set; } = 0.7;
    public double MeowVolume { get; set; } = 0.8;
    public bool InteractionSounds { get; set; } = true;
    public bool PurringSounds { get; set; } = true;

    /// <summary>Set while Cookie is hidden for a full-screen app: nothing plays.</summary>
    public bool IsMuted { get; set; }

    protected virtual bool ValidateFileExists => true;

    protected AudioManagerBase(string? customSoundsDirectory = null)
    {
        _soundsDirectory = customSoundsDirectory ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sounds");
    }

    public virtual bool Play(SoundEffect sound)
    {
        if (!SoundEnabled || IsMuted) return false;

        if (sound.IsInteractionSound() && !InteractionSounds) return false;
        if (sound == SoundEffect.Purr && !PurringSounds) return false;

        if (sound == SoundEffect.Purr)
        {
            string purrFile = Path.Combine(_soundsDirectory, sound.GetFileName());
            if (ValidateFileExists && !File.Exists(purrFile)) return false;
            if (MasterVolume <= 0.001) return false;
            StartOrExtendLoop(purrFile, MasterVolume, PurrHoldSeconds);
            return true;
        }

        var now = DateTime.UtcNow;
        double minInterval = sound.GetMinimumIntervalSeconds();

        if (_lastPlayTimes.TryGetValue(sound, out var lastPlay))
        {
            if ((now - lastPlay).TotalSeconds < minInterval)
            {
                return false;
            }
        }

        _lastPlayTimes[sound] = now;

        string soundFile = Path.Combine(_soundsDirectory, ChooseTake(sound));
        if (ValidateFileExists && !File.Exists(soundFile))
        {
            return false;
        }

        double effectiveVolume = MasterVolume * (sound.UsesMeowVolume() ? MeowVolume : 1.0);
        if (effectiveVolume <= 0.001)
        {
            return false;
        }

        PlayInternal(soundFile, effectiveVolume);
        return true;
    }

    /// <summary>Picks a take at random, avoiding the one just heard.</summary>
    private string ChooseTake(SoundEffect sound)
    {
        string[] takes = sound.GetFileNames();
        if (takes.Length == 1) return takes[0];

        _lastTakes.TryGetValue(sound, out string? last);
        var choices = Array.FindAll(takes, take => take != last);
        string chosen = choices[PickIndex(choices.Length)];
        _lastTakes[sound] = chosen;
        return chosen;
    }

    protected virtual int PickIndex(int count) => _random.Next(count);

    protected abstract void PlayInternal(string filePath, double volume);

    /// <summary>
    /// Starts a loop, or keeps it going if it's already playing, until holdSeconds pass
    /// with no further calls. Platforms without looping can leave this as a single play.
    /// </summary>
    protected virtual void StartOrExtendLoop(string filePath, double volume, double holdSeconds)
    {
        PlayInternal(filePath, volume);
    }
}
