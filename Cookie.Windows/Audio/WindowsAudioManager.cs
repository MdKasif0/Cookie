using System;
using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Cookie.Windows.Interop;
using Cookie.Windows.Models;

namespace Cookie.Windows.Audio;

public class WindowsAudioManager
{
    private readonly string _soundsDirectory;
    private readonly ConcurrentDictionary<SoundEffect, DateTime> _lastPlayTimes = new();
    private readonly object _lock = new();

    public bool SoundEnabled { get; set; } = true;
    public double MasterVolume { get; set; } = 0.7;
    public double MeowVolume { get; set; } = 0.8;
    public bool InteractionSounds { get; set; } = true;
    public bool PurringSounds { get; set; } = true;

    public WindowsAudioManager(string? customSoundsDirectory = null)
    {
        _soundsDirectory = customSoundsDirectory ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sounds");
    }

    public bool Play(SoundEffect sound)
    {
        if (!SoundEnabled) return false;

        if (sound.IsInteractionSound() && !InteractionSounds) return false;
        if (sound == SoundEffect.Purr && !PurringSounds) return false;

        // Throttling: avoid rapid overlapping repeats
        var now = DateTime.UtcNow;
        double minInterval = sound.GetMinimumIntervalSeconds();

        if (_lastPlayTimes.TryGetValue(sound, out var lastPlay))
        {
            if ((now - lastPlay).TotalSeconds < minInterval)
            {
                return false; // Throttled
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

        // Fire-and-forget on background thread to stay completely off rendering and UI paths
        Task.Run(() => PlaySoundInternal(soundFile, effectiveVolume));
        return true;
    }

    private void PlaySoundInternal(string filePath, double volume)
    {
        try
        {
            string alias = "CookieSound_" + Guid.NewGuid().ToString("N");
            int mciVolume = (int)Math.Clamp(volume * 1000, 0, 1000);

            // Open wave file via MCI
            NativeMethods.mciSendString($"open \"{filePath}\" type waveaudio alias {alias}", null, 0, IntPtr.Zero);
            NativeMethods.mciSendString($"setaudio {alias} volume to {mciVolume}", null, 0, IntPtr.Zero);
            NativeMethods.mciSendString($"play {alias} wait", null, 0, IntPtr.Zero);
            NativeMethods.mciSendString($"close {alias}", null, 0, IntPtr.Zero);
        }
        catch
        {
            // Fallback: ignore non-critical audio errors
        }
    }
}
