using System;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Cookie.Windows.Core.Updates;

public interface IUpdateService
{
    string CurrentVersion { get; }
    string DefaultManifestUrl { get; set; }

    Task<UpdateCheckResult> CheckForUpdatesAsync(string? manifestUrl = null, string? currentVersion = null, CancellationToken ct = default);
    Task<UpdateDownloadResult> DownloadUpdateAsync(UpdateManifest manifest, string destinationDirectory, IProgress<double>? progress = null, CancellationToken ct = default);
    bool VerifyFileSha256(string filePath, string expectedHexHash);
}

public class UpdateService : IUpdateService, IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly bool _ownsClient;

    public string CurrentVersion { get; }
    public string DefaultManifestUrl { get; set; } = "https://getcookie.app/updates/windows/release.json";

    public UpdateService(HttpClient? httpClient = null, string? currentVersion = null)
    {
        if (httpClient != null)
        {
            _httpClient = httpClient;
            _ownsClient = false;
        }
        else
        {
            _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            _ownsClient = true;
        }

        CurrentVersion = currentVersion ??
                         typeof(UpdateService).Assembly.GetName().Version?.ToString(3) ??
                         "1.1.0";
    }

    public void Dispose()
    {
        if (_ownsClient)
        {
            _httpClient.Dispose();
        }
    }

    public async Task<UpdateCheckResult> CheckForUpdatesAsync(
        string? manifestUrl = null,
        string? currentVersion = null,
        CancellationToken ct = default)
    {
        string targetUrl = manifestUrl ?? DefaultManifestUrl;
        string activeVersion = currentVersion ?? CurrentVersion;

        if (string.IsNullOrWhiteSpace(targetUrl))
        {
            return new UpdateCheckResult(
                UpdateCheckStatus.HostingNotConfigured,
                false,
                activeVersion,
                null,
                "Update server URL is not configured.");
        }

        try
        {
            using var response = await _httpClient.GetAsync(targetUrl, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return new UpdateCheckResult(
                    UpdateCheckStatus.NetworkError,
                    false,
                    activeVersion,
                    null,
                    $"Server returned HTTP {(int)response.StatusCode}: {response.ReasonPhrase}");
            }

            string json = await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            var manifest = JsonSerializer.Deserialize<UpdateManifest>(json, options);

            if (manifest == null || string.IsNullOrWhiteSpace(manifest.Version) || string.IsNullOrWhiteSpace(manifest.DownloadUrl))
            {
                return new UpdateCheckResult(
                    UpdateCheckStatus.InvalidMetadata,
                    false,
                    activeVersion,
                    null,
                    "Invalid update manifest received.");
            }

            bool isNewer = IsVersionNewer(manifest.Version, activeVersion);

            return new UpdateCheckResult(
                isNewer ? UpdateCheckStatus.UpdateAvailable : UpdateCheckStatus.UpToDate,
                isNewer,
                activeVersion,
                isNewer ? manifest : null,
                isNewer ? $"New version {manifest.Version} is available." : "Cookie is up to date.");
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            return new UpdateCheckResult(
                UpdateCheckStatus.NetworkError,
                false,
                activeVersion,
                null,
                $"Could not check for updates: {ex.Message}");
        }
    }

    public async Task<UpdateDownloadResult> DownloadUpdateAsync(
        UpdateManifest manifest,
        string destinationDirectory,
        IProgress<double>? progress = null,
        CancellationToken ct = default)
    {
        Directory.CreateDirectory(destinationDirectory);
        string filename = Path.GetFileName(new Uri(manifest.DownloadUrl).LocalPath);
        if (string.IsNullOrWhiteSpace(filename))
        {
            filename = $"Cookie-Setup-{manifest.Version}.exe";
        }

        string tempFilePath = Path.Combine(destinationDirectory, filename + ".download." + Guid.NewGuid().ToString("N"));
        string targetFilePath = Path.Combine(destinationDirectory, filename);

        try
        {
            using var response = await _httpClient.GetAsync(manifest.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();

            long totalBytes = response.Content.Headers.ContentLength ?? manifest.PackageSizeBytes;

            await using (var contentStream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false))
            await using (var fileStream = new FileStream(tempFilePath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true))
            {
                byte[] buffer = new byte[8192];
                long totalRead = 0;
                int read;

                while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length, ct).ConfigureAwait(false)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, read, ct).ConfigureAwait(false);
                    totalRead += read;

                    if (totalBytes > 0 && progress != null)
                    {
                        double p = (double)totalRead / totalBytes;
                        progress.Report(Math.Min(1.0, Math.Max(0.0, p)));
                    }
                }
            }

            // Verify integrity before promoting file
            if (!VerifyFileSha256(tempFilePath, manifest.Sha256Hash))
            {
                try { File.Delete(tempFilePath); } catch { }
                return new UpdateDownloadResult(
                    UpdateDownloadStatus.IntegrityCheckFailed,
                    null,
                    "SHA-256 integrity checksum verification failed. The update package may be corrupted.");
            }

            if (File.Exists(targetFilePath))
            {
                File.Delete(targetFilePath);
            }
            File.Move(tempFilePath, targetFilePath);

            return new UpdateDownloadResult(UpdateDownloadStatus.Success, targetFilePath);
        }
        catch (OperationCanceledException)
        {
            try { if (File.Exists(tempFilePath)) File.Delete(tempFilePath); } catch { }
            return new UpdateDownloadResult(UpdateDownloadStatus.Cancelled, null, "Download was cancelled.");
        }
        catch (Exception ex)
        {
            try { if (File.Exists(tempFilePath)) File.Delete(tempFilePath); } catch { }
            return new UpdateDownloadResult(UpdateDownloadStatus.DownloadFailed, null, $"Download failed: {ex.Message}");
        }
    }

    public bool VerifyFileSha256(string filePath, string expectedHexHash)
    {
        if (!File.Exists(filePath) || string.IsNullOrWhiteSpace(expectedHexHash))
        {
            return false;
        }

        try
        {
            using var sha = SHA256.Create();
            using var stream = File.OpenRead(filePath);
            byte[] hashBytes = sha.ComputeHash(stream);
            string calculatedHex = Convert.ToHexString(hashBytes);

            return string.Equals(calculatedHex, expectedHexHash.Replace("-", "").Trim(), StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    public static bool IsVersionNewer(string remoteVersion, string localVersion)
    {
        if (Version.TryParse(CleanVersion(remoteVersion), out var remote) &&
            Version.TryParse(CleanVersion(localVersion), out var local))
        {
            return remote > local;
        }

        return string.Compare(remoteVersion, localVersion, StringComparison.OrdinalIgnoreCase) > 0;
    }

    private static string CleanVersion(string v)
    {
        v = v.TrimStart('v', 'V').Trim();
        int dashIdx = v.IndexOf('-');
        if (dashIdx > 0)
        {
            v = v.Substring(0, dashIdx);
        }
        return v;
    }
}
