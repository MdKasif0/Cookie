using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

/// <summary>The keyboard shortcuts offered for calling Cookie to your cursor.</summary>
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SummonShortcut
{
    ControlAltC,
    ControlAltSpace,
    ControlShiftAltC,
    Off
}

public static class SummonShortcutExtensions
{
    public const uint ModAlt = 0x1;
    public const uint ModControl = 0x2;
    public const uint ModShift = 0x4;

    public static string GetDisplayName(this SummonShortcut shortcut) => shortcut switch
    {
        SummonShortcut.ControlAltC => "Ctrl+Alt+C",
        SummonShortcut.ControlAltSpace => "Ctrl+Alt+Space",
        SummonShortcut.ControlShiftAltC => "Ctrl+Shift+Alt+C",
        _ => "Off"
    };

    /// <summary>Windows virtual-key code, or null when the shortcut is off.</summary>
    public static uint? GetVirtualKey(this SummonShortcut shortcut) => shortcut switch
    {
        SummonShortcut.ControlAltC or SummonShortcut.ControlShiftAltC => 0x43,
        SummonShortcut.ControlAltSpace => 0x20,
        _ => null
    };

    public static uint GetModifiers(this SummonShortcut shortcut) => shortcut switch
    {
        SummonShortcut.ControlAltC or SummonShortcut.ControlAltSpace => ModControl | ModAlt,
        SummonShortcut.ControlShiftAltC => ModControl | ModShift | ModAlt,
        _ => 0
    };
}
