using System.Text.Json.Serialization;

namespace Cookie.Windows.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookieState
{
    Idle,
    Walking,
    Running,
    Sitting,
    Sleeping,
    Yawning,
    Stretching,
    Grooming,
    Curious,
    Playing,
    Eating,
    Drinking,
    FollowingCursor,
    BeingDragged,
    Reacting,
    Special,
    Investigating,
    Tired,
    InBox,
    Emoting
}

public static class CookieStateExtensions
{
    public static bool IsLocomotion(this CookieState state)
    {
        return state is CookieState.Walking or CookieState.Running or CookieState.FollowingCursor;
    }
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookieReaction
{
    Happy,
    Annoyed,
    Surprised,
    Meow,
    Shy,
    Embarrassed,
    Dropped
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookieDirection
{
    Left,
    Right
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum CookieZone
{
    Nose,
    Head,
    Tail,
    Feet,
    Body
}
