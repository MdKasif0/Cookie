using System;
using System.Linq;
using Cookie.Windows.Core.Desktop;

namespace Cookie.Windows.Core.Context;

/// <summary>
/// Broad, privacy-conscious categorization of active Windows desktop applications.
/// No document contents, keystrokes, browser tabs, or user intentions are inferred.
/// </summary>
public enum ApplicationCategory
{
    Browser,
    CodeEditor,
    Creative,
    Communication,
    FileManager,
    Other,
    Unknown
}

public static class ApplicationCategoryExtensions
{
    public static string GetDisplayName(this ApplicationCategory category)
    {
        return category switch
        {
            ApplicationCategory.Browser => "Web Browser",
            ApplicationCategory.CodeEditor => "Code / Text Editor",
            ApplicationCategory.Creative => "Creative Tool",
            ApplicationCategory.Communication => "Communication",
            ApplicationCategory.FileManager => "File Manager",
            ApplicationCategory.Other => "Other",
            _ => "Unknown"
        };
    }

    /// <summary>
    /// Classifies an application based on process name and window title.
    /// Falls back safely to Other or Unknown without assuming user intent.
    /// </summary>
    public static ApplicationCategory Classify(string? processName, string? windowTitle)
    {
        string proc = (processName ?? string.Empty).ToLowerInvariant().Trim();
        string title = (windowTitle ?? string.Empty).ToLowerInvariant().Trim();

        if (string.IsNullOrEmpty(proc) && string.IsNullOrEmpty(title))
        {
            return ApplicationCategory.Unknown;
        }

        // 1. File Manager
        if (proc == "explorer" || title == "file explorer" || title == "windows explorer")
        {
            return ApplicationCategory.FileManager;
        }

        // 2. Web Browsers
        string[] browserTokens = { "chrome", "msedge", "firefox", "browser", "brave", "opera", "vivaldi", "arc", "waterfox" };
        if (browserTokens.Any(token => proc.Contains(token) || title.Contains(token)))
        {
            return ApplicationCategory.Browser;
        }

        // 3. Code / Text Editors & IDEs
        string[] editorTokens =
        {
            "devenv", "code", "cursor", "notepad", "notepad++", "sublime_text",
            "idea64", "pycharm64", "webstorm64", "clion64", "rider64", "windowsterminal",
            "cmd", "powershell", "mintty", "alacritty", "neovim", "gvim", "emacs"
        };
        if (editorTokens.Any(token => proc.Contains(token) || title.Contains(token)))
        {
            return ApplicationCategory.CodeEditor;
        }

        // 4. Creative Applications
        string[] creativeTokens =
        {
            "photoshop", "illustrator", "figma", "blender", "premiere", "afterfx",
            "audacity", "canva", "gimp", "inkscape", "cinema4d", "affinity", "paint.net"
        };
        if (creativeTokens.Any(token => proc.Contains(token) || title.Contains(token)))
        {
            return ApplicationCategory.Creative;
        }

        // 5. Communication & Messaging
        string[] commTokens =
        {
            "slack", "discord", "teams", "telegram", "whatsapp", "signal",
            "zoom", "outlook", "thunderbird", "skype", "wechat", "mattermost"
        };
        if (commTokens.Any(token => proc.Contains(token) || title.Contains(token)))
        {
            return ApplicationCategory.Communication;
        }

        return ApplicationCategory.Other;
    }
}

/// <summary>
/// State of the active desktop context.
/// </summary>
public enum DesktopContextState
{
    CookieActive,
    AnotherAppActive,
    DesktopVisible,
    Unknown
}

/// <summary>
/// Minimal, privacy-conscious model of the active Windows application context.
/// Contains no sensitive content, URLs, document text, or keystroke information.
/// </summary>
public record ApplicationContext(
    DesktopContextState State,
    string? ProcessName,
    string? ApplicationTitle,
    int? ProcessId,
    ApplicationCategory Category,
    bool IsCookieActive,
    CoreRect? FrontmostWindowBounds,
    DateTime Timestamp)
{
    public static ApplicationContext Unknown => new(
        DesktopContextState.Unknown,
        null,
        null,
        null,
        ApplicationCategory.Unknown,
        false,
        null,
        DateTime.MinValue);
}
