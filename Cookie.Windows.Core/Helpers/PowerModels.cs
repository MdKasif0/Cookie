using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Helpers;

// MARK: - cookie:// links

public enum CookieCommandKind
{
    Say,
    Remind,
    StartFocus,
    StopFocus,
    Quiet,
    ToggleQuiet,
    Show,
    Hide,
    Summon,
    Pet,
    Emote,
    AddTodo,
    AddNote,
    Ask
}

/// <summary>
/// Something you can ask Cookie to do from outside the app: a <c>cookie://</c> link from a script,
/// Power Automate, PowerToys Run, a shortcut file or a browser bookmark.
/// </summary>
/// <example>
/// cookie://say?text=Hello · cookie://remind?minutes=20&amp;text=Call%20Mom · cookie://timer?minutes=5 ·
/// cookie://focus/start?minutes=25 · cookie://focus/stop · cookie://quiet/on?minutes=60 · cookie://quiet/off ·
/// cookie://quiet/toggle · cookie://show · cookie://hide · cookie://summon · cookie://pet ·
/// cookie://emote?name=wave · cookie://todo/add?text=… · cookie://note?text=… · cookie://ask
/// </example>
public record CookieCommand(CookieCommandKind Kind, string Text = "", int? Minutes = null, bool On = true, EmoteId Emote = EmoteId.Wave)
{
    public const string Scheme = "cookie";
    /// <summary>Longest text a link may carry, so a link can't flood the screen.</summary>
    public const int MaximumText = 280;

    /// <summary>Parses a link. Returns null and an explanation for anything it doesn't understand.</summary>
    public static CookieCommand? Parse(string link, out string? error)
    {
        error = null;
        if (!Uri.TryCreate(link.Trim(), UriKind.Absolute, out var uri) || !uri.Scheme.Equals(Scheme, StringComparison.OrdinalIgnoreCase))
        {
            error = "not a cookie:// link";
            return null;
        }

        var query = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string pair in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            int equals = pair.IndexOf('=');
            string key = Uri.UnescapeDataString((equals < 0 ? pair : pair[..equals]).Replace('+', ' '));
            string value = equals < 0 ? "" : Uri.UnescapeDataString(pair[(equals + 1)..].Replace('+', ' '));
            query[key] = value;
        }
        string route = string.Join('/', new[] { uri.Host }.Concat(uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries)))
            .Trim('/').ToLowerInvariant();

        string? Text()
        {
            if (!query.TryGetValue("text", out string? raw) || string.IsNullOrWhiteSpace(raw)) return null;
            string trimmed = raw.Trim();
            return trimmed.Length > MaximumText ? trimmed[..MaximumText] : trimmed;
        }
        int? Minutes(int min = 1, int max = 24 * 60)
        {
            if ((query.TryGetValue("minutes", out string? raw) || query.TryGetValue("min", out raw)) && int.TryParse(raw, out int value))
                return Math.Clamp(value, min, max);
            return null;
        }

        switch (route)
        {
            case "say":
                if (Text() is not { } message) { error = "missing text"; return null; }
                return new(CookieCommandKind.Say, message);
            case "remind" or "reminder":
                if (Minutes() is not { } remindIn) { error = "missing minutes"; return null; }
                return new(CookieCommandKind.Remind, Text() ?? "", remindIn);
            case "timer":
                if (Minutes() is not { } timer) { error = "missing minutes"; return null; }
                return new(CookieCommandKind.Remind, "", timer);
            case "focus" or "focus/start":
                return new(CookieCommandKind.StartFocus, Minutes: Minutes(5, 180));
            case "focus/stop":
                return new(CookieCommandKind.StopFocus);
            case "quiet" or "quiet/on":
                return new(CookieCommandKind.Quiet, Minutes: Minutes(), On: true);
            case "quiet/off":
                return new(CookieCommandKind.Quiet, On: false);
            case "quiet/toggle":
                return new(CookieCommandKind.ToggleQuiet);
            case "show": return new(CookieCommandKind.Show);
            case "hide": return new(CookieCommandKind.Hide);
            case "summon" or "come": return new(CookieCommandKind.Summon);
            case "pet": return new(CookieCommandKind.Pet);
            case "emote":
                if (!query.TryGetValue("name", out string? name)) { error = "missing name"; return null; }
                if (!Enum.TryParse(name, ignoreCase: true, out EmoteId id) || !Enum.IsDefined(id) || int.TryParse(name, out _))
                {
                    error = $"unknown emote {name}";
                    return null;
                }
                return new(CookieCommandKind.Emote, Emote: id);
            case "todo" or "todo/add":
                if (Text() is not { } task) { error = "missing text"; return null; }
                return new(CookieCommandKind.AddTodo, task);
            case "note" or "note/add":
                if (Text() is not { } note) { error = "missing text"; return null; }
                return new(CookieCommandKind.AddNote, note);
            case "ask" or "chat":
                return new(CookieCommandKind.Ask);
            default:
                error = $"unknown command {(route.Length == 0 ? "(empty)" : route)}";
                return null;
        }
    }

    /// <summary>The link for this command.</summary>
    public string ToLink()
    {
        static string Q(string key, string value) => $"{key}={Uri.EscapeDataString(value)}";
        string MinutesPart() => Minutes is { } m ? "?" + Q("minutes", m.ToString()) : "";
        return Kind switch
        {
            CookieCommandKind.Say => $"cookie://say?{Q("text", Text)}",
            CookieCommandKind.Remind => Text.Length == 0
                ? $"cookie://remind?minutes={Minutes}"
                : $"cookie://remind?minutes={Minutes}&{Q("text", Text)}",
            CookieCommandKind.StartFocus => $"cookie://focus/start{MinutesPart()}",
            CookieCommandKind.StopFocus => "cookie://focus/stop",
            CookieCommandKind.Quiet => On ? $"cookie://quiet/on{MinutesPart()}" : "cookie://quiet/off",
            CookieCommandKind.ToggleQuiet => "cookie://quiet/toggle",
            CookieCommandKind.Show => "cookie://show",
            CookieCommandKind.Hide => "cookie://hide",
            CookieCommandKind.Summon => "cookie://summon",
            CookieCommandKind.Pet => "cookie://pet",
            CookieCommandKind.Emote => $"cookie://emote?name={Emote.ToString().ToLowerInvariant()}",
            CookieCommandKind.AddTodo => $"cookie://todo/add?{Q("text", Text)}",
            CookieCommandKind.AddNote => $"cookie://note?{Q("text", Text)}",
            _ => "cookie://ask"
        };
    }
}

// MARK: - Clipboard buddy

/// <summary>
/// The last few things you copied, newest first. It lives only in memory: never written to disk, and gone
/// when Cookie quits.
/// </summary>
public class ClipboardHistory
{
    public const int Capacity = 10;
    /// <summary>Huge copies (a whole document) are skipped.</summary>
    public const int MaximumLength = 20_000;

    /// <summary>
    /// Clipboard formats that password managers and Windows itself use to say "don't keep this".
    /// </summary>
    public static readonly string[] PrivateFormats =
    {
        "ExcludeClipboardContentFromMonitorProcessing",
        "Clipboard Viewer Ignore",
        "CanIncludeInClipboardHistory"
    };

    private readonly List<string> _items = new();

    public IReadOnlyList<string> Items => _items;

    /// <summary>
    /// Adds a copy. Blank and very long text is ignored; copying something again moves it to the top.
    /// </summary>
    public bool Add(string text)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length > MaximumLength) return false;
        _items.Remove(text);
        _items.Insert(0, text);
        if (_items.Count > Capacity) _items.RemoveRange(Capacity, _items.Count - Capacity);
        return true;
    }

    public void Clear() => _items.Clear();

    /// <summary>One line for the menu: whitespace collapsed, cut to <paramref name="length"/>.</summary>
    public static string Preview(string text, int length = 48)
    {
        string flat = string.Join(' ', text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return flat.Length > length ? flat[..(length - 1)] + "…" : flat;
    }
}

// MARK: - File drop zone

public enum FileDropActionKind
{
    Move,
    Copy,
    Zip
}

public static class FileDrop
{
    public static string Summary(int count, FileDropActionKind action, string? folder)
    {
        string things = count == 1 ? "it" : $"all {count}";
        string folderName = folder == null ? "" : Path.GetFileName(folder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        return action switch
        {
            FileDropActionKind.Move => $"Filed {things} in {folderName}!",
            FileDropActionKind.Copy => $"Copied {things} to {folderName}!",
            _ => count == 1 ? "Zipped it up!" : $"Zipped all {count} together!"
        };
    }

    /// <summary>
    /// Moves or copies <paramref name="paths"/> (files or folders) into <paramref name="folder"/>. Nothing is
    /// overwritten. Returns how many were handled.
    /// </summary>
    public static int MoveOrCopy(IReadOnlyList<string> paths, string folder, bool copy)
    {
        var existing = new HashSet<string>(
            Directory.Exists(folder) ? Directory.EnumerateFileSystemEntries(folder).Select(p => Path.GetFileName(p)!) : Enumerable.Empty<string>(),
            StringComparer.OrdinalIgnoreCase);
        string folderFull = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar);
        int done = 0;
        foreach (string path in paths)
        {
            string source = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
            // Moving something into the folder it's already in: nothing to do, and it's filed.
            if (!copy && string.Equals(Path.GetDirectoryName(source), folderFull, StringComparison.OrdinalIgnoreCase))
            {
                done++;
                continue;
            }
            string name = ScreenshotTidy.UniqueName(Path.GetFileName(source), existing);
            string target = Path.Combine(folder, name);
            try
            {
                if (Directory.Exists(source))
                {
                    if (copy) CopyDirectory(source, target);
                    else Directory.Move(source, target);
                }
                else if (copy)
                {
                    File.Copy(source, target, overwrite: false);
                }
                else
                {
                    File.Move(source, target, overwrite: false);
                }
                existing.Add(name);
                done++;
            }
            catch
            {
                // Skip what can't be moved; the summary says how many worked.
            }
        }
        return done;
    }

    private static void CopyDirectory(string source, string target)
    {
        Directory.CreateDirectory(target);
        foreach (string file in Directory.EnumerateFiles(source))
            File.Copy(file, Path.Combine(target, Path.GetFileName(file)), overwrite: false);
        foreach (string directory in Directory.EnumerateDirectories(source))
            CopyDirectory(directory, Path.Combine(target, Path.GetFileName(directory)));
    }

    /// <summary>
    /// Zips <paramref name="paths"/> next to the first one: one item becomes "Name.zip", several become
    /// "Archive.zip". Never overwrites. Returns the zip's path, or null if it failed.
    /// </summary>
    public static string? Zip(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return null;
        string first = Path.GetFullPath(paths[0]).TrimEnd(Path.DirectorySeparatorChar);
        string folder = Path.GetDirectoryName(first)!;
        var existing = new HashSet<string>(Directory.EnumerateFileSystemEntries(folder).Select(p => Path.GetFileName(p)!), StringComparer.OrdinalIgnoreCase);
        string stem = paths.Count == 1 ? Path.GetFileNameWithoutExtension(first) : "Archive";
        string zipPath = Path.Combine(folder, ScreenshotTidy.UniqueName($"{stem}.zip", existing));
        try
        {
            using var archive = ZipFile.Open(zipPath, ZipArchiveMode.Create);
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in paths)
            {
                string full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);
                string root = ScreenshotTidy.UniqueName(Path.GetFileName(full), names);
                names.Add(root);
                if (Directory.Exists(full))
                {
                    foreach (string file in Directory.EnumerateFiles(full, "*", SearchOption.AllDirectories))
                    {
                        string relative = Path.GetRelativePath(full, file).Replace('\\', '/');
                        archive.CreateEntryFromFile(file, $"{root}/{relative}", CompressionLevel.Optimal);
                    }
                }
                else
                {
                    archive.CreateEntryFromFile(full, root, CompressionLevel.Optimal);
                }
            }
            return zipPath;
        }
        catch
        {
            try { File.Delete(zipPath); } catch { }
            return null;
        }
    }
}

// MARK: - Ask Cookie

public enum ChatSpeaker
{
    You,
    Cookie,
    Notice
}

public record ChatLine(ChatSpeaker Speaker, string Text);

public abstract record AskReply
{
    public sealed record Text(string Reply, JsonArray Content) : AskReply;
    public sealed record Declined : AskReply;
    public sealed record Failed(string Message) : AskReply;
}

/// <summary>The Claude API request and response for the "Ask Cookie" chat.</summary>
public static class AskCookie
{
    /// <summary>Claude Opus 5.5, at low effort: chat is short and quick, and doesn't need deep thinking.</summary>
    public const string Model = "claude-opus-5-5";
    public const string Endpoint = "https://api.anthropic.com/v1/messages";
    public const string ApiVersion = "2026-10-21";
    /// <summary>Lets the API answer from another model when this one declines, instead of failing.</summary>
    public const string FallbackBeta = "server-side-fallback-2026-07-01";
    public const int MaxTokens = 4096;
    /// <summary>A conversation is started over after this many messages rather than trimmed.</summary>
    public const int MaximumMessages = 40;
    public const int MaximumQuestion = 2000;

    public static string SystemPrompt(string name, string personality) =>
        $"You are {name}, a small {personality} cat who lives on the user's Windows desktop as a companion app. " +
        "You chat with the person who looks after you. Stay in character as a friendly cat: warm, a little playful, " +
        "occasionally cat-like (a purr, a stretch, a slow blink), but still genuinely helpful when asked a real question. " +
        "Keep replies short: one to three sentences unless the person asks for more detail. Use plain text without " +
        "Markdown headings or tables, because your words appear in a small chat window. You can't see the screen, " +
        "files, or anything on the PC, and you can't take actions; if asked to, say so kindly and suggest what the " +
        "person could do instead. Never ask for passwords or personal details.";

    /// <summary>
    /// The Messages API request body. <paramref name="messages"/> holds earlier turns exactly as they came back,
    /// so any thinking blocks are passed back unchanged.
    /// </summary>
    public static JsonObject RequestBody(string system, JsonArray messages) => new()
    {
        ["model"] = Model,
        ["max_tokens"] = MaxTokens,
        ["system"] = system,
        ["messages"] = messages,
        ["output_config"] = new JsonObject { ["effort"] = "low" },
        ["fallbacks"] = "default"
    };

    public static HttpRequestMessage Request(string apiKey, JsonObject body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, Endpoint)
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json")
        };
        request.Headers.Add("x-api-key", apiKey);
        request.Headers.Add("anthropic-version", ApiVersion);
        request.Headers.Add("anthropic-beta", FallbackBeta);
        return request;
    }

    /// <summary>Reads a Messages API response: the reply text, plus the content blocks to send back next turn.</summary>
    public static AskReply Parse(string body, int status)
    {
        JsonObject? json;
        try
        {
            json = JsonNode.Parse(body) as JsonObject;
        }
        catch (JsonException)
        {
            json = null;
        }
        if (json == null) return new AskReply.Failed($"Cookie got a reply she couldn't read (HTTP {status}).");

        if (status is < 200 or >= 300)
        {
            var error = json["error"] as JsonObject;
            string type = error?["type"]?.GetValue<string>() ?? "";
            string message = error?["message"]?.GetValue<string>() ?? $"HTTP {status}";
            return status switch
            {
                401 => new AskReply.Failed("That API key didn't work. Check it in Settings → Power Tools."),
                403 => new AskReply.Failed("That API key isn't allowed to use this model."),
                429 => new AskReply.Failed("Too many questions at once. Try again in a moment."),
                529 or >= 500 => new AskReply.Failed("Claude is busy right now. Try again in a moment."),
                _ => new AskReply.Failed(type.Length == 0 ? message : $"{type}: {message}")
            };
        }

        if (json["stop_reason"]?.GetValue<string>() == "refusal") return new AskReply.Declined();
        var content = json["content"] as JsonArray ?? new JsonArray();
        string text = string.Concat(content
            .OfType<JsonObject>()
            .Where(block => block["type"]?.GetValue<string>() == "text")
            .Select(block => block["text"]?.GetValue<string>() ?? "")).Trim();
        if (text.Length == 0) return new AskReply.Failed("Cookie didn't have anything to say. Try asking again.");
        return new AskReply.Text(text, (JsonArray)content.DeepClone());
    }
}

/// <summary>
/// The chat itself. Each question goes to the Claude API with the user's own key; the conversation lives only
/// in memory.
/// </summary>
public class ChatSession
{
    private readonly Func<CookieProfile> _profile;
    private readonly List<ChatLine> _lines = new();
    private JsonArray _messages = new();
    private CancellationTokenSource? _cts;

    /// <summary>Sends a request and returns the body and HTTP status. Replaced in tests.</summary>
    public Func<HttpRequestMessage, CancellationToken, Task<(string Body, int Status)>> Send { get; set; }
    public Func<string?> ApiKey { get; set; } = () => null;

    public IReadOnlyList<ChatLine> Lines => _lines;
    public bool IsThinking { get; private set; }
    public event Action? Changed;
    /// <summary>Raised when Cookie answers, so she can look pleased.</summary>
    public event Action? Answered;

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(2) };

    public ChatSession(Func<CookieProfile> profile)
    {
        _profile = profile;
        Send = async (request, token) =>
        {
            using var response = await Http.SendAsync(request, token).ConfigureAwait(false);
            return (await response.Content.ReadAsStringAsync(token).ConfigureAwait(false), (int)response.StatusCode);
        };
    }

    public bool IsReady => _profile().Settings.AskCookieEnabled && !string.IsNullOrEmpty(ApiKey());

    public async Task AskAsync(string question)
    {
        string trimmed = question.Trim();
        if (trimmed.Length > AskCookie.MaximumQuestion) trimmed = trimmed[..AskCookie.MaximumQuestion];
        if (trimmed.Length == 0 || IsThinking) return;

        var profile = _profile();
        if (!profile.Settings.AskCookieEnabled)
        {
            Notice("Ask Cookie is turned off. Turn it on in Settings → Power Tools.");
            return;
        }
        if (ApiKey() is not { Length: > 0 } key)
        {
            Notice("Add your Claude API key in Settings → Power Tools first.");
            return;
        }
        if (_messages.Count >= AskCookie.MaximumMessages)
        {
            _messages = new JsonArray();
            Notice("That was a long chat! Starting a fresh one.");
        }

        _lines.Add(new ChatLine(ChatSpeaker.You, trimmed));
        var outgoing = (JsonArray)_messages.DeepClone();
        outgoing.Add(new JsonObject { ["role"] = "user", ["content"] = trimmed });
        IsThinking = true;
        Changed?.Invoke();

        _cts = new CancellationTokenSource();
        AskReply reply;
        try
        {
            var body = AskCookie.RequestBody(AskCookie.SystemPrompt(profile.DisplayName, profile.Personality.ToString().ToLowerInvariant()), (JsonArray)outgoing.DeepClone());
            using var request = AskCookie.Request(key, body);
            var (text, status) = await Send(request, _cts.Token).ConfigureAwait(true);
            reply = AskCookie.Parse(text, status);
        }
        catch (OperationCanceledException) when (_cts.IsCancellationRequested)
        {
            return;
        }
        catch (Exception)
        {
            reply = new AskReply.Failed("Cookie couldn't reach Claude. Check your internet connection.");
        }

        IsThinking = false;
        switch (reply)
        {
            case AskReply.Text answer:
                outgoing.Add(new JsonObject { ["role"] = "assistant", ["content"] = answer.Content });
                _messages = outgoing;
                _lines.Add(new ChatLine(ChatSpeaker.Cookie, answer.Reply));
                Answered?.Invoke();
                break;
            case AskReply.Declined:
                // The question isn't kept, so the conversation can carry on.
                _lines.Add(new ChatLine(ChatSpeaker.Notice, "Cookie can't help with that one. Try asking something else."));
                break;
            case AskReply.Failed failed:
                _lines.Add(new ChatLine(ChatSpeaker.Notice, failed.Message));
                break;
        }
        Changed?.Invoke();
    }

    private void Notice(string text)
    {
        _lines.Add(new ChatLine(ChatSpeaker.Notice, text));
        Changed?.Invoke();
    }

    public void Reset()
    {
        _cts?.Cancel();
        _cts = null;
        IsThinking = false;
        _messages = new JsonArray();
        _lines.Clear();
        Changed?.Invoke();
    }
}
