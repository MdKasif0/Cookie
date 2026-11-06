using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Cookie.Windows.Core.Updates;

// Release tooling for Cookie's Windows update feed. Run from the repository root:
//
//   dotnet run --project Tools/CookieUpdateTool -- keygen <private-key.pem>
//   dotnet run --project Tools/CookieUpdateTool -- manifest --version 1.2.0 --installer Cookie-Setup.exe \
//       --url https://github.com/MdKasif0/Cookie/releases/download/v1.2.0/Cookie-Setup.exe \
//       --notes-file notes.txt --out windows-update.json
//   dotnet run --project Tools/CookieUpdateTool -- sign windows-update.json --key-file private-key.pem
//   dotnet run --project Tools/CookieUpdateTool -- verify windows-update.json
//
// `sign` can also read the key from the COOKIE_UPDATE_SIGNING_KEY environment variable,
// which is how CI supplies it from a repository secret.

return Run(args);

static int Run(string[] args)
{
    if (args.Length == 0) return Usage();

    try
    {
        return args[0] switch
        {
            "keygen" => KeyGen(args),
            "manifest" => Manifest(args),
            "sign" => Sign(args),
            "verify" => Verify(args),
            _ => Usage()
        };
    }
    catch (Exception exception) when (exception is IOException or ArgumentException or CryptographicException or JsonException or UnauthorizedAccessException)
    {
        Console.Error.WriteLine($"error: {exception.Message}");
        return 1;
    }
}

static int Usage()
{
    Console.Error.WriteLine("""
        usage:
          keygen <private-key.pem>
          manifest --version V --installer FILE --url URL --notes-file FILE --out FILE [--min-os 10.0.19041]
          sign <manifest.json> [--key-file private-key.pem]    (or set COOKIE_UPDATE_SIGNING_KEY)
          verify <manifest.json> [--public-key BASE64]
        """);
    return 2;
}

static string? Option(string[] args, string name)
{
    int index = Array.IndexOf(args, name);
    return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
}

static string Required(string[] args, string name) =>
    Option(args, name) ?? throw new ArgumentException($"missing {name}");

static int KeyGen(string[] args)
{
    if (args.Length < 2) return Usage();
    string path = args[1];
    if (File.Exists(path)) throw new IOException($"{path} already exists; refusing to overwrite a signing key.");

    string pem = UpdateSigning.GenerateKeyPair(out string publicKey);
    File.WriteAllText(path, pem);
    if (!OperatingSystem.IsWindows())
    {
        File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
    }

    Console.WriteLine($"Private key written to {path}. Keep it secret and back it up.");
    Console.WriteLine("Public key (put this in UpdateSigning.TrustedPublicKeys):");
    Console.WriteLine(publicKey);
    return 0;
}

static int Manifest(string[] args)
{
    string installer = Required(args, "--installer");
    string version = Required(args, "--version");
    string url = Required(args, "--url");
    if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
    {
        throw new ArgumentException("--url must be an https address");
    }

    string notes = File.ReadAllText(Required(args, "--notes-file")).Trim();
    byte[] hash;
    using (var stream = File.OpenRead(installer))
    {
        hash = SHA256.HashData(stream);
    }

    var manifest = new UpdateManifest(
        Version: version,
        ReleaseNotes: notes,
        DownloadUrl: url,
        Sha256Hash: Convert.ToHexString(hash).ToLowerInvariant(),
        ReleaseDate: DateTime.UtcNow,
        PackageSizeBytes: new FileInfo(installer).Length,
        MinimumOsVersion: Option(args, "--min-os") ?? "10.0.19041");

    var options = new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    string output = Required(args, "--out");
    File.WriteAllText(output, JsonSerializer.Serialize(manifest, options) + "\n", new UTF8Encoding(false));
    Console.WriteLine($"Wrote {output} for {version} ({manifest.PackageSizeBytes} bytes, sha256 {manifest.Sha256Hash}).");
    return 0;
}

static int Sign(string[] args)
{
    if (args.Length < 2) return Usage();
    string file = args[1];

    string? pem = Option(args, "--key-file") is { } keyFile
        ? File.ReadAllText(keyFile)
        : Environment.GetEnvironmentVariable("COOKIE_UPDATE_SIGNING_KEY");
    if (string.IsNullOrWhiteSpace(pem))
    {
        throw new ArgumentException("no signing key: pass --key-file or set COOKIE_UPDATE_SIGNING_KEY");
    }

    byte[] data = File.ReadAllBytes(file);
    byte[] signature = UpdateSigning.Sign(pem, data);
    File.WriteAllText(file + ".sig", UpdateSigning.EncodeSignature(signature));

    // Never publish a signature the app would not accept.
    string publicKey = UpdateSigning.PublicKeyOf(pem);
    var verifier = new EcdsaManifestVerifier(new[] { publicKey });
    if (!verifier.IsValid(data, signature)) throw new CryptographicException("signature did not verify against its own key");

    Console.WriteLine($"Signed {file} -> {file}.sig");
    if (!UpdateSigning.TrustedPublicKeys.Contains(publicKey))
    {
        Console.Error.WriteLine("warning: this key is not in UpdateSigning.TrustedPublicKeys, so installed apps will reject this manifest.");
        return 3;
    }
    return 0;
}

static int Verify(string[] args)
{
    if (args.Length < 2) return Usage();
    string file = args[1];

    var keys = Option(args, "--public-key") is { } key ? new[] { key } : UpdateSigning.TrustedPublicKeys;
    var verifier = new EcdsaManifestVerifier(keys);

    if (!UpdateSigning.TryDecodeSignature(File.ReadAllText(file + ".sig"), out byte[] signature)
        || !verifier.IsValid(File.ReadAllBytes(file), signature))
    {
        Console.Error.WriteLine($"{file}: signature is NOT valid");
        return 1;
    }

    Console.WriteLine($"{file}: signature is valid");
    return 0;
}
