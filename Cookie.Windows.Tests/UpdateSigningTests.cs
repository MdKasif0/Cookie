using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Cookie.Windows.Core.Updates;
using Xunit;

namespace Cookie.Windows.Tests;

public class UpdateSigningTests
{
    private const string FeedUrl = "https://updates.example.test/windows/release.json";

    private static readonly string KeyPem = UpdateSigning.GenerateKeyPair(out PublicKey);
    private static readonly string PublicKey;
    private static readonly string OtherKeyPem = UpdateSigning.GenerateKeyPair(out OtherPublicKey);
    private static readonly string OtherPublicKey;

    private static byte[] ManifestJson(string version = "9.9.9", string url = "https://example.test/Cookie-Setup.exe") =>
        Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
        {
            version,
            releaseNotes = "Notes",
            downloadUrl = url,
            sha256Hash = new string('a', 64),
            releaseDate = "2026-11-06T00:00:00Z",
            packageSizeBytes = 1234
        }));

    /// <summary>A fake update server: path to body, anything else is a 404.</summary>
    private sealed class FakeFeed : HttpMessageHandler
    {
        public readonly System.Collections.Generic.Dictionary<string, byte[]> Files = new();

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (Files.TryGetValue(request.RequestUri!.ToString(), out var body))
            {
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(body) });
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        }
    }

    private static UpdateService ServiceFor(FakeFeed feed, string trustedKey) =>
        new(new HttpClient(feed), currentVersion: "1.0.0", verifier: new EcdsaManifestVerifier(new[] { trustedKey }));

    private static FakeFeed SignedFeed(byte[] manifest, string signingKeyPem)
    {
        var feed = new FakeFeed();
        feed.Files[FeedUrl] = manifest;
        feed.Files[FeedUrl + ".sig"] = Encoding.UTF8.GetBytes(UpdateSigning.EncodeSignature(UpdateSigning.Sign(signingKeyPem, manifest)));
        return feed;
    }

    [Fact]
    public async Task ASignedManifest_OffersTheUpdate()
    {
        var service = ServiceFor(SignedFeed(ManifestJson(), KeyPem), PublicKey);

        var result = await service.CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.UpdateAvailable, result.Status);
        Assert.Equal("9.9.9", result.AvailableRelease!.Version);
    }

    [Fact]
    public async Task AManifestWithoutASignature_IsRejected()
    {
        var feed = new FakeFeed();
        feed.Files[FeedUrl] = ManifestJson();

        var result = await ServiceFor(feed, PublicKey).CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.SignatureInvalid, result.Status);
        Assert.Null(result.AvailableRelease);
    }

    [Fact]
    public async Task ATamperedManifest_IsRejected()
    {
        var feed = SignedFeed(ManifestJson(), KeyPem);
        // An attacker keeps the real signature but points the download somewhere else.
        feed.Files[FeedUrl] = ManifestJson(url: "https://evil.example.test/Cookie-Setup.exe");

        var result = await ServiceFor(feed, PublicKey).CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.SignatureInvalid, result.Status);
        Assert.Null(result.AvailableRelease);
    }

    [Fact]
    public async Task AManifestSignedByAnotherKey_IsRejected()
    {
        var service = ServiceFor(SignedFeed(ManifestJson(), OtherKeyPem), PublicKey);

        var result = await service.CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.SignatureInvalid, result.Status);
    }

    [Theory]
    [InlineData("")]
    [InlineData("not base64 at all!!")]
    [InlineData("AAAA")]
    public async Task GarbageSignatures_AreRejectedWithoutCrashing(string signatureText)
    {
        var feed = new FakeFeed();
        feed.Files[FeedUrl] = ManifestJson();
        feed.Files[FeedUrl + ".sig"] = Encoding.UTF8.GetBytes(signatureText);

        var result = await ServiceFor(feed, PublicKey).CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.SignatureInvalid, result.Status);
    }

    [Fact]
    public async Task AnOversizedManifest_IsRejectedBeforeItIsVerified()
    {
        var feed = new FakeFeed();
        feed.Files[FeedUrl] = new byte[300 * 1024];

        var result = await ServiceFor(feed, PublicKey).CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.InvalidMetadata, result.Status);
    }

    [Fact]
    public async Task ASignedButUnreadableManifest_IsInvalidMetadata()
    {
        byte[] junk = Encoding.UTF8.GetBytes("{ this is not json");

        var result = await ServiceFor(SignedFeed(junk, KeyPem), PublicKey).CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.InvalidMetadata, result.Status);
    }

    [Fact]
    public async Task AValidSignedOlderManifest_OffersNothing()
    {
        var service = ServiceFor(SignedFeed(ManifestJson(version: "0.9.0"), KeyPem), PublicKey);

        var result = await service.CheckForUpdatesAsync(FeedUrl);

        Assert.Equal(UpdateCheckStatus.UpToDate, result.Status);
    }

    [Fact]
    public void WhenTwoKeysAreTrusted_EitherCanSign()
    {
        var verifier = new EcdsaManifestVerifier(new[] { PublicKey, OtherPublicKey });
        byte[] data = ManifestJson();

        Assert.True(verifier.IsValid(data, UpdateSigning.Sign(KeyPem, data)));
        Assert.True(verifier.IsValid(data, UpdateSigning.Sign(OtherKeyPem, data)));
    }

    [Fact]
    public void NonP256Keys_AreRefused()
    {
        using var p384 = ECDsa.Create(ECCurve.NamedCurves.nistP384);

        Assert.Throws<CryptographicException>(() =>
            new EcdsaManifestVerifier(new[] { Convert.ToBase64String(p384.ExportSubjectPublicKeyInfo()) }));
    }

    [Fact]
    public void TheShippedKey_IsARealP256PublicKey()
    {
        // Throws if the placeholder or a malformed key is ever committed.
        var verifier = new EcdsaManifestVerifier(UpdateSigning.TrustedPublicKeys);

        Assert.False(verifier.IsValid(new byte[] { 1, 2, 3 }, new byte[] { 4, 5, 6 }));
    }

    [Theory]
    [InlineData("http://insecure.example.test/Cookie-Setup.exe")]
    [InlineData("ftp://insecure.example.test/Cookie-Setup.exe")]
    [InlineData("not a url")]
    public async Task DownloadsOverInsecureOrInvalidAddresses_AreRefused(string url)
    {
        string folder = Path.Combine(Path.GetTempPath(), "CookieSigningTests_" + Guid.NewGuid().ToString("N"));
        try
        {
            var manifest = new UpdateManifest("2.0.0", "Notes", url, new string('0', 64), DateTime.UtcNow, 100);

            var result = await new UpdateService().DownloadUpdateAsync(manifest, folder);

            Assert.Equal(UpdateDownloadStatus.DownloadFailed, result.Status);
            Assert.False(Directory.Exists(folder));
        }
        finally
        {
            if (Directory.Exists(folder)) Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void Signatures_RoundTripThroughTheirFileFormat()
    {
        byte[] data = ManifestJson();
        byte[] signature = UpdateSigning.Sign(KeyPem, data);

        Assert.True(UpdateSigning.TryDecodeSignature(UpdateSigning.EncodeSignature(signature), out var decoded));
        Assert.Equal(signature, decoded);
        Assert.EndsWith(".sig", UpdateSigning.SignatureUrlFor(FeedUrl));
    }
}
