using System;
using System.Collections.Concurrent;
using System.IO;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Audio;

public abstract class AudioManagerBase
{
    private readonly string _soundsDirectory;
    private readonly ConcurrentDictionary<SoundEffect, DateTime> _lastPlayTimes = new();

    public bool SoundEnabled { get; set; } = true;
    public double MasterVolume { get; set; } = 0.7;
    public double MeowVolume { get; set; } = 0.8;
    public bool InteractionSounds { get; set; } = true;
    public bool PurringSounds { get; set; } = true;

    protected AudioManagerBase(string? customSoundsDirectory = null)
    {
        _soundsDirectory = customSoundsDirectory ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sounds");
    }

    public virtual bool Play(SoundEffect sound)
    {
        if (!SoundEnabled) return false;

        if (sound.IsInteractionSound() && !InteractionSounds) return false;
        if (sound == SoundEffect.Purr && !PurringSounds) return false;

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

        string soundFile = Path.Combine(_soundsDirectory, sound.GetFileName());
        if (!File.Exists(soundFile))
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

    protected abstract void PlayInternal(string filePath, double volume);
}
