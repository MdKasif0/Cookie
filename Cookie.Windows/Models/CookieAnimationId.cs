using System.Text.Json.Serialization;

namespace Cookie.Windows.Models;

public enum CookieAnimationPriority
{
    Sleep = 0,
    Idle = 10,
    Walk = 20,
    Interaction = 30,
    Emote = 35,
    Special = 40
}

public enum CookieAnimationCategory
{
    Idle,
    Walk,
    Run,
    Sleep,
    Interaction,
    Emotions,
    Special,
    Emotes
}

public record CookieAnimationSpec(
    CookieAnimationCategory Category,
    string SheetName,
    CookieAnimationPriority Priority,
    bool IsLooping,
    double Fps,
    CookieDirection? Direction = null);

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookieAnimationId
{
    Idle,
    IdleBlink,
    WalkLeft,
    WalkRight,
    RunLeft,
    RunRight,
    Sit,
    Sleep,
    Wake,
    Stretch,
    Yawn,
    Groom,
    Happy,
    Surprised,
    Curious,
    Annoyed,
    Scared,
    Playful,
    Eat,
    Drink,
    Jump,
    Fall,
    PickedUp,
    Dropped,
    Pet,
    Meow,
    Investigate,
    Tired,
    InBox,
    BoxPeek,
    Wave,
    HappyEmote,
    Love,
    SleepyEmote,
    PlayfulEmote
}

public static class CookieAnimationExtensions
{
    public static CookieAnimationSpec GetSpec(this CookieAnimationId id)
    {
        return id switch
        {
            CookieAnimationId.Idle => new(CookieAnimationCategory.Idle, "idle", CookieAnimationPriority.Idle, true, 4),
            CookieAnimationId.IdleBlink => new(CookieAnimationCategory.Idle, "idleBlink", CookieAnimationPriority.Idle, false, 6),
            CookieAnimationId.WalkLeft => new(CookieAnimationCategory.Walk, "walk", CookieAnimationPriority.Walk, true, 6, CookieDirection.Left),
            CookieAnimationId.WalkRight => new(CookieAnimationCategory.Walk, "walk", CookieAnimationPriority.Walk, true, 6, CookieDirection.Right),
            CookieAnimationId.RunLeft => new(CookieAnimationCategory.Run, "run", CookieAnimationPriority.Walk, true, 10, CookieDirection.Left),
            CookieAnimationId.RunRight => new(CookieAnimationCategory.Run, "run", CookieAnimationPriority.Walk, true, 10, CookieDirection.Right),
            CookieAnimationId.Sit => new(CookieAnimationCategory.Idle, "sit", CookieAnimationPriority.Idle, true, 3),
            CookieAnimationId.Sleep => new(CookieAnimationCategory.Sleep, "sleep", CookieAnimationPriority.Sleep, true, 2),
            CookieAnimationId.Wake => new(CookieAnimationCategory.Sleep, "wake", CookieAnimationPriority.Sleep, false, 3),
            CookieAnimationId.Stretch => new(CookieAnimationCategory.Interaction, "stretch", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Yawn => new(CookieAnimationCategory.Interaction, "yawn", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Groom => new(CookieAnimationCategory.Interaction, "groom", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Happy => new(CookieAnimationCategory.Emotions, "happy", CookieAnimationPriority.Interaction, false, 5),
            CookieAnimationId.Surprised => new(CookieAnimationCategory.Emotions, "surprised", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Curious => new(CookieAnimationCategory.Emotions, "curious", CookieAnimationPriority.Interaction, false, 3),
            CookieAnimationId.Annoyed => new(CookieAnimationCategory.Emotions, "annoyed", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Scared => new(CookieAnimationCategory.Emotions, "scared", CookieAnimationPriority.Interaction, false, 6),
            CookieAnimationId.Playful => new(CookieAnimationCategory.Emotions, "playful", CookieAnimationPriority.Interaction, false, 6),
            CookieAnimationId.Eat => new(CookieAnimationCategory.Interaction, "eat", CookieAnimationPriority.Interaction, false, 5),
            CookieAnimationId.Drink => new(CookieAnimationCategory.Interaction, "drink", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Jump => new(CookieAnimationCategory.Special, "jump", CookieAnimationPriority.Special, false, 6),
            CookieAnimationId.Fall => new(CookieAnimationCategory.Special, "fall", CookieAnimationPriority.Special, true, 6),
            CookieAnimationId.PickedUp => new(CookieAnimationCategory.Interaction, "pickedUp", CookieAnimationPriority.Special, true, 4),
            CookieAnimationId.Dropped => new(CookieAnimationCategory.Interaction, "dropped", CookieAnimationPriority.Special, false, 5),
            CookieAnimationId.Pet => new(CookieAnimationCategory.Interaction, "pet", CookieAnimationPriority.Interaction, false, 5),
            CookieAnimationId.Meow => new(CookieAnimationCategory.Interaction, "meow", CookieAnimationPriority.Interaction, false, 5),
            CookieAnimationId.Investigate => new(CookieAnimationCategory.Interaction, "investigate", CookieAnimationPriority.Interaction, false, 4),
            CookieAnimationId.Tired => new(CookieAnimationCategory.Idle, "tired", CookieAnimationPriority.Idle, true, 3),
            CookieAnimationId.InBox => new(CookieAnimationCategory.Special, "inBox", CookieAnimationPriority.Interaction, true, 2),
            CookieAnimationId.BoxPeek => new(CookieAnimationCategory.Special, "boxPeek", CookieAnimationPriority.Interaction, false, 3),
            CookieAnimationId.Wave => new(CookieAnimationCategory.Emotes, "wave", CookieAnimationPriority.Emote, false, 4),
            CookieAnimationId.HappyEmote => new(CookieAnimationCategory.Emotes, "happy", CookieAnimationPriority.Emote, false, 5),
            CookieAnimationId.Love => new(CookieAnimationCategory.Emotes, "love", CookieAnimationPriority.Emote, false, 4),
            CookieAnimationId.SleepyEmote => new(CookieAnimationCategory.Emotes, "sleepy", CookieAnimationPriority.Emote, false, 4),
            CookieAnimationId.PlayfulEmote => new(CookieAnimationCategory.Emotes, "playful", CookieAnimationPriority.Emote, false, 5),
            _ => new(CookieAnimationCategory.Idle, "idle", CookieAnimationPriority.Idle, true, 4)
        };
    }
}
