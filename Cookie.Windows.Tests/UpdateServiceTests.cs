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
    [InlineData("1.0.1", "1.0.0", true)]
    [InlineData("1.1.0", "1.0.0", true)]
    [InlineData("2.0.0", "1.0.0", true)]
    [InlineData("1.0.0", "1.0.0", false)]
    [InlineData("1.0.0", "1.1.0", false)]
    [InlineData("1.9.9", "2.0.0", false)]
    public void IsVersionNewer_EvaluatesSemVerCorrectly(string remote, string local, bool expected)
    {
        bool result = UpdateService.IsVersionNewer(remote, local);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void UpdateManifest_SerializationRoundTrip()
    {
        var original = new UpdateManifest(
            Version: "1.2.0",
            ReleaseNotes: "Premium polish and performance optimizations.",
            DownloadUrl: "https://releases.getcookie.app/CookieSetup-1.2.0.exe",
            Sha256Hash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            ReleaseDate: new DateTime(2026, 10, 15, 12, 0, 0, DateTimeKind.Utc),
            PackageSizeBytes: 15728640,
            MinimumOsVersion: "10.0.19041");

        string json = JsonSerializer.Serialize(original, new JsonSerializerOptions { WriteIndented = true });
        var deserialized = JsonSerializer.Deserialize<UpdateManifest>(json);

        Assert.NotNull(deserialized);
        Assert.Equal(original.Version, deserialized.Version);
        Assert.Equal(original.DownloadUrl, deserialized.DownloadUrl);
        Assert.Equal(original.Sha256Hash, deserialized.Sha256Hash);
        Assert.Equal(original.PackageSizeBytes, deserialized.PackageSizeBytes);
        Assert.Equal(original.ReleaseNotes, deserialized.ReleaseNotes);
        Assert.Equal(original.MinimumOsVersion, deserialized.MinimumOsVersion);
    }

    [Fact]
    public void VerifyFileSha256_ComputesAndMatchesCorrectly()
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

        var service = new UpdateService();
        bool isValid = service.VerifyFileSha256(sampleFile, expectedHash);
        Assert.True(isValid);

        bool isTampered = service.VerifyFileSha256(sampleFile, "0000000000000000000000000000000000000000000000000000000000000000");
        Assert.False(isTampered);
    }

    [Fact]
    public async Task CheckForUpdatesAsync_WhenHostingNotConfigured_ReturnsHostingNotConfigured()
    {
        var service = new UpdateService();
        service.DefaultManifestUrl = string.Empty;
        var result = await service.CheckForUpdatesAsync();

        Assert.Equal(UpdateCheckStatus.HostingNotConfigured, result.Status);
        Assert.Null(result.AvailableRelease);
    }

    [Fact]
    public async Task CheckForUpdatesAsync_WhenFeedUrlIsInvalid_ReturnsNetworkError()
    {
        var service = new UpdateService();
        service.DefaultManifestUrl = "https://127.0.0.1:59999/nonexistent-update-feed.json";
        var result = await service.CheckForUpdatesAsync();

        Assert.Equal(UpdateCheckStatus.NetworkError, result.Status);
        Assert.NotNull(result.Message);
    }

    [Fact]
    public async Task DownloadUpdateAsync_WhenChecksumDoesNotMatch_RejectsPackageAndCleansUp()
    {
        string mockServerFile = Path.Combine(_testDir, "fake-installer.exe");
        File.WriteAllText(mockServerFile, "Actual downloaded installer contents");

        var manifest = new UpdateManifest(
            Version: "2.0.0",
            ReleaseNotes: "Test release notes",
            DownloadUrl: new Uri(mockServerFile).AbsoluteUri,
            Sha256Hash: "0000000000000000000000000000000000000000000000000000000000000000", // Intentional mismatch
            ReleaseDate: DateTime.UtcNow,
            PackageSizeBytes: 100);

        var service = new UpdateService();
        string downloadDir = Path.Combine(_testDir, "downloads");
        var result = await service.DownloadUpdateAsync(manifest, downloadDir);

        Assert.Equal(UpdateDownloadStatus.IntegrityCheckFailed, result.Status);
        Assert.Null(result.DownloadedFilePath);

        var remainingFiles = Directory.GetFiles(downloadDir, "*.exe");
        Assert.Empty(remainingFiles);
    }
}
