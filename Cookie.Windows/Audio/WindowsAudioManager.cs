using System;
using System.Threading.Tasks;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Audio;

public class WindowsAudioManager : AudioManagerBase
{
    public WindowsAudioManager(string? customSoundsDirectory = null)
        : base(customSoundsDirectory)
    {
    }

    protected override void PlayInternal(string filePath, double volume)
    {
        // Execute on background thread
        Task.Run(() =>
        {
            try
            {
                string alias = "CookieSound_" + Guid.NewGuid().ToString("N");
                int mciVolume = (int)Math.Clamp(volume * 1000, 0, 1000);

                NativeMethods.mciSendString($"open \"{filePath}\" type waveaudio alias {alias}", null, 0, IntPtr.Zero);
                NativeMethods.mciSendString($"setaudio {alias} volume to {mciVolume}", null, 0, IntPtr.Zero);
                NativeMethods.mciSendString($"play {alias} wait", null, 0, IntPtr.Zero);
                NativeMethods.mciSendString($"close {alias}", null, 0, IntPtr.Zero);
            }
            catch
            {
                // Fallback: ignore non-critical audio errors
            }
        });
    }
}
