using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Cookie.Windows.Core.Updates;
using Xunit;

namespace Cookie.Windows.Tests;

public class UpdateServiceTests : IDisposable
{
    private readonly string _testDir;

    public UpdateServiceTests()
    {
        _testDir = Path.Combine(Path.GetTempPath(), "CookieUpdateTests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_testDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_testDir))
        {
            try { Directory.Delete(_testDir, true); } catch { }
        }
    }

    [Theory]
    [InlineData("1.0.0", "1.0.1", true)]
    [InlineData("1.0.0", "1.1.0", true)]
    [InlineData("1.0.0", "2.0.0", true)]
    [InlineData("1.0.0", "1.0.0", false)]
    [InlineData("1.1.0", "1.0.0", false)]
    [InlineData("2.0.0", "1.9.9", false)]
    [InlineData("1.0.0-preview", "1.0.0", true)]
    [InlineData("1.0.0-rc1", "1.0.0-rc2", true)]
    public void IsNewerVersion_EvaluatesSemVerCorrectly(string current, string candidate, bool expected)
    {
        bool result = UpdateService.IsNewerVersion(current, candidate);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void UpdateManifest_SerializationRoundTrip()
    {
        var original = new UpdateManifest
        {
            Version = "1.2.0",
            ReleaseDate = new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc),
            DownloadUrl = "https://releases.getcookie.app/CookieSetup-1.2.0.exe",
            Sha256Checksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            FileSizeBytes = 15728640,
            ReleaseNotes = "Premium polish and performance optimizations.",
            MinimumOsVersion = "10.0.19041"
        };

        string json = JsonSerializer.Serialize(original, new JsonSerializerOptions { WriteIndented = true });
        var deserialized = JsonSerializer.Deserialize<UpdateManifest>(json);

        Assert.NotNull(deserialized);
        Assert.Equal(original.Version, deserialized.Version);
        Assert.Equal(original.DownloadUrl, deserialized.DownloadUrl);
        Assert.Equal(original.Sha256Checksum, deserialized.Sha256Checksum);
        Assert.Equal(original.FileSizeBytes, deserialized.FileSizeBytes);
        Assert.Equal(original.ReleaseNotes, deserialized.ReleaseNotes);
        Assert.Equal(original.MinimumOsVersion, deserialized.MinimumOsVersion);
    }

    [Fact]
    public void ComputeSha256_ComputesMatchingHash()
    {
        string sampleFile = Path.Combine(_testDir, "test-payload.bin");
        byte[] payload = Encoding.UTF8.GetBytes("Cookie Desktop Companion Release Payload Verification");
        File.WriteAllBytes(sampleFile, payload);

        string expectedHash;
        using (var sha = SHA256.Create())
        {
            byte[] hashBytes = sha.ComputeHash(payload);
            expectedHash = Convert.ToHexString(hashBytes).ToLowerInvariant();
        }

        string computedHash = UpdateService.ComputeSha256(sampleFile);
        Assert.Equal(expectedHash, computedHash);
    }

    [Fact]
    public async Task CheckForUpdatesAsync_WhenHostingNotConfigured_ReturnsHostingNotConfigured()
    {
        var service = new UpdateService(manifestUrl: string.Empty);
        var result = await service.CheckForUpdatesAsync();

        Assert.Equal(UpdateCheckStatus.HostingNotConfigured, result.Status);
        Assert.Null(result.AvailableRelease);
    }

    [Fact]
    public async Task CheckForUpdatesAsync_WhenFeedUrlIsInvalid_ReturnsNetworkError()
    {
        var service = new UpdateService(manifestUrl: "https://127.0.0.1:59999/nonexistent-update-feed.json");
        var result = await service.CheckForUpdatesAsync();

        Assert.Equal(UpdateCheckStatus.NetworkError, result.Status);
        Assert.NotNull(result.Message);
    }

    [Fact]
    public async Task DownloadUpdateAsync_WhenManifestIsNull_ReturnsError()
    {
        var service = new UpdateService();
        var result = await service.DownloadUpdateAsync(null!, _testDir);

        Assert.Equal(UpdateDownloadStatus.Failed, result.Status);
        Assert.Equal("Invalid release manifest.", result.ErrorMessage);
    }

    [Fact]
    public async Task DownloadUpdateAsync_WhenChecksumDoesNotMatch_RejectsPackageAndCleansUp()
    {
        // Serve a fake local file via file URI to test validation
        string mockServerFile = Path.Combine(_testDir, "fake-installer.exe");
        File.WriteAllText(mockServerFile, "Actual downloaded installer contents");

        var manifest = new UpdateManifest
        {
            Version = "2.0.0",
            DownloadUrl = new Uri(mockServerFile).AbsoluteUri,
            Sha256Checksum = "0000000000000000000000000000000000000000000000000000000000000000", // Intentional mismatch
            FileSizeBytes = 100
        };

        var service = new UpdateService();
        string downloadDir = Path.Combine(_testDir, "downloads");
        var result = await service.DownloadUpdateAsync(manifest, downloadDir);

        Assert.Equal(UpdateDownloadStatus.ChecksumMismatch, result.Status);
        Assert.Null(result.DownloadedFilePath);

        // Ensure corrupted or mismatch files are cleaned up
        var remainingFiles = Directory.GetFiles(downloadDir, "*.exe");
        Assert.Empty(remainingFiles);
    }
}
