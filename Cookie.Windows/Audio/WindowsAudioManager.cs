using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Cookie.Windows.Core.Audio;

namespace Cookie.Windows.Audio;

/// <summary>Plays sounds through WPF's MediaPlayer, which supports volume and looping.</summary>
public class WindowsAudioManager : AudioManagerBase
{
    private const double FadeInSeconds = 0.25;
    private const double FadeOutSeconds = 0.9;

    private readonly HashSet<MediaPlayer> _playing = new();

    private MediaPlayer? _loop;
    private DispatcherTimer? _loopTimer;
    private DateTime _loopStarted;
    private DateTime _loopUntil;
    private double _loopVolume;

    public WindowsAudioManager(string? customSoundsDirectory = null)
        : base(customSoundsDirectory)
    {
    }

    private static Dispatcher UiDispatcher => Application.Current.Dispatcher;

    protected override void PlayInternal(string filePath, double volume)
    {
        UiDispatcher.BeginInvoke(() =>
        {
            var player = new MediaPlayer();
            _playing.Add(player);

            void Finished(object? sender, EventArgs e)
            {
                player.Close();
                _playing.Remove(player);
            }

            player.MediaEnded += Finished;
            player.MediaFailed += (s, e) => Finished(s, e);
            player.Open(new Uri(filePath, UriKind.Absolute));
            player.Volume = Math.Clamp(volume, 0, 1);
            player.Play();
        });
    }

    protected override void StartOrExtendLoop(string filePath, double volume, double holdSeconds)
    {
        UiDispatcher.BeginInvoke(() =>
        {
            _loopUntil = DateTime.UtcNow.AddSeconds(holdSeconds);
            _loopVolume = Math.Clamp(volume, 0, 1);
            if (_loop != null) return;

            var player = new MediaPlayer { Volume = 0 };
            player.MediaEnded += (s, e) =>
            {
                player.Position = TimeSpan.Zero;
                player.Play();
            };
            player.MediaFailed += (s, e) => StopLoop();
            player.Open(new Uri(filePath, UriKind.Absolute));
            player.Play();

            _loop = player;
            _loopStarted = DateTime.UtcNow;
            _loopTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(50) };
            _loopTimer.Tick += (s, e) => UpdateLoopVolume();
            _loopTimer.Start();
        });
    }

    private void UpdateLoopVolume()
    {
        if (_loop == null) return;
        if (!SoundEnabled || !PurringSounds || IsMuted)
        {
            StopLoop();
            return;
        }

        var now = DateTime.UtcNow;
        if (now < _loopUntil)
        {
            double fadeIn = (now - _loopStarted).TotalSeconds / FadeInSeconds;
            _loop.Volume = _loopVolume * Math.Min(1, fadeIn);
            return;
        }

        double fadeOut = (now - _loopUntil).TotalSeconds / FadeOutSeconds;
        if (fadeOut >= 1)
        {
            StopLoop();
        }
        else
        {
            _loop.Volume = _loopVolume * (1 - fadeOut);
        }
    }

    private void StopLoop()
    {
        _loopTimer?.Stop();
        _loopTimer = null;
        _loop?.Close();
        _loop = null;
    }
}
