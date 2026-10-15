using Cookie.Windows.Audio;
using Cookie.Windows.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class AudioVolumeAndThrottlingTests
{
    [Fact]
    public void SoundEffect_ThrottlingRules()
    {
        // Purr interval is 1.0s, other sounds are 0.35s
        Assert.Equal(1.0, SoundEffect.Purr.GetMinimumIntervalSeconds());
        Assert.Equal(0.35, SoundEffect.Meow.GetMinimumIntervalSeconds());
        Assert.Equal(0.35, SoundEffect.Happy.GetMinimumIntervalSeconds());
        Assert.Equal(0.35, SoundEffect.Drop.GetMinimumIntervalSeconds());
    }

    [Fact]
    public void SoundEffect_VolumeCategoryRules()
    {
        Assert.True(SoundEffect.Meow.UsesMeowVolume());
        Assert.True(SoundEffect.Mew.UsesMeowVolume());
        Assert.True(SoundEffect.Happy.UsesMeowVolume());
        Assert.True(SoundEffect.Chirp.UsesMeowVolume());

        Assert.False(SoundEffect.Purr.UsesMeowVolume());
        Assert.False(SoundEffect.Drop.UsesMeowVolume());
        Assert.False(SoundEffect.Eat.UsesMeowVolume());
    }

    [Fact]
    public void AudioManager_WhenSoundDisabled_DoesNotPlay()
    {
        var manager = new WindowsAudioManager();
        manager.SoundEnabled = false;

        bool played = manager.Play(SoundEffect.Meow);

        Assert.False(played);
    }

    [Fact]
    public void AudioManager_ThrottlesRapidRepeatsOfSameSound()
    {
        var manager = new WindowsAudioManager();
        manager.SoundEnabled = true;

        // First play might succeed or fail if file not at exact path, but subsequent play within interval is always throttled
        manager.Play(SoundEffect.Purr);
        bool secondPlay = manager.Play(SoundEffect.Purr);

        Assert.False(secondPlay); // Blocked by 1.0s throttle
    }
}
