using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SoundEffect
{
    Purr,
    Meow,
    Happy,
    Mew,
    Chirp,
    Surprise,
    Eat,
    Toy,
    Drop,
    Sleep,
    Welcome
}

public static class SoundEffectExtensions
{
    /// <summary>Alternate takes, so repeated sounds don't feel mechanical. The first is the default.</summary>
    public static string[] GetFileNames(this SoundEffect sound)
    {
        return sound switch
        {
            SoundEffect.Meow => new[] { "cookie-meow.wav", "cookie-meow-2.wav", "cookie-meow-3.wav" },
            SoundEffect.Mew => new[] { "cookie-mew.wav", "cookie-mew-2.wav" },
            SoundEffect.Happy => new[] { "cookie-happy.wav", "cookie-happy-2.wav" },
            _ => new[] { sound.GetFileName() }
        };
    }

    public static string GetFileName(this SoundEffect sound)
    {
        return sound switch
        {
            SoundEffect.Purr => "cookie-purr.wav",
            SoundEffect.Meow => "cookie-meow.wav",
            SoundEffect.Happy => "cookie-happy.wav",
            SoundEffect.Mew => "cookie-mew.wav",
            SoundEffect.Chirp => "cookie-chirp.wav",
            SoundEffect.Surprise => "cookie-surprise.wav",
            SoundEffect.Eat => "cookie-eat.wav",
            SoundEffect.Toy => "cookie-toy.wav",
            SoundEffect.Drop => "cookie-drop.wav",
            SoundEffect.Sleep => "cookie-sleep.wav",
            SoundEffect.Welcome => "cookie-welcome.wav",
            _ => "cookie-meow.wav"
        };
    }

    public static double GetMinimumIntervalSeconds(this SoundEffect sound)
    {
        return sound == SoundEffect.Purr ? 1.0 : 0.35;
    }

    public static bool IsInteractionSound(this SoundEffect sound)
    {
        return sound is SoundEffect.Meow or SoundEffect.Mew or SoundEffect.Happy or
               SoundEffect.Chirp or SoundEffect.Surprise or SoundEffect.Toy or
               SoundEffect.Drop or SoundEffect.Eat;
    }

    public static bool UsesMeowVolume(this SoundEffect sound)
    {
        return sound is SoundEffect.Meow or SoundEffect.Mew or SoundEffect.Happy or SoundEffect.Chirp;
    }
}
