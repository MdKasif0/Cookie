using System;
using System.Collections.Generic;
using System.Security.Cryptography;

namespace Cookie.Windows.Core.Updates;

/// <summary>Decides whether update information really came from Cookie's maintainer.</summary>
public interface IManifestVerifier
{
    bool IsValid(ReadOnlySpan<byte> manifest, ReadOnlySpan<byte> signature);
}

/// <summary>
/// Verifies ECDSA P-256 signatures over the exact bytes of an update manifest.
/// More than one key can be trusted at once, which lets the signing key be rotated
/// without stranding installed copies.
/// </summary>
public sealed class EcdsaManifestVerifier : IManifestVerifier
{
    private readonly List<ECDsa> _keys = new();

    /// <param name="publicKeysBase64">SubjectPublicKeyInfo keys, base64 encoded.</param>
    public EcdsaManifestVerifier(IEnumerable<string> publicKeysBase64)
    {
        foreach (string encoded in publicKeysBase64)
        {
            var key = ECDsa.Create();
            key.ImportSubjectPublicKeyInfo(Convert.FromBase64String(encoded.Trim()), out _);
            if (key.KeySize != 256)
            {
                key.Dispose();
                throw new CryptographicException("Update signing keys must use the NIST P-256 curve.");
            }
            _keys.Add(key);
        }
    }

    public bool IsValid(ReadOnlySpan<byte> manifest, ReadOnlySpan<byte> signature)
    {
        foreach (var key in _keys)
        {
            try
            {
                if (key.VerifyData(manifest, signature, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence))
                {
                    return true;
                }
            }
            catch (CryptographicException)
            {
                // A malformed signature is simply not a valid one.
            }
        }
        return false;
    }
}

public static class UpdateSigning
{
    /// <summary>
    /// Keys trusted to sign update manifests, as base64 SubjectPublicKeyInfo. The matching
    /// private key never leaves the maintainer: see DISTRIBUTION.md for creating and rotating it.
    /// </summary>
    public static readonly string[] TrustedPublicKeys =
    {
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEM4mWiSBPG42J5jATjktzTlhZnsKSAQGlzRCGyJ8ChnmQihy+UbODai+3l5lOqRcfg5L24GDM4JOJ8+LpkM0AhA=="
    };

    /// <summary>Where the detached signature for a manifest lives: next to it, with ".sig" added.</summary>
    public static string SignatureUrlFor(string manifestUrl) => manifestUrl + ".sig";

    /// <summary>Creates a new key pair. The private key is a PKCS#8 PEM; the public key is base64 SPKI.</summary>
    public static string GenerateKeyPair(out string publicKeyBase64)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        publicKeyBase64 = Convert.ToBase64String(key.ExportSubjectPublicKeyInfo());
        return key.ExportPkcs8PrivateKeyPem();
    }

    /// <summary>Signs data, returning the DER signature.</summary>
    public static byte[] Sign(string privateKeyPem, ReadOnlySpan<byte> data)
    {
        using var key = ECDsa.Create();
        key.ImportFromPem(privateKeyPem);
        return key.SignData(data, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
    }

    public static string PublicKeyOf(string privateKeyPem)
    {
        using var key = ECDsa.Create();
        key.ImportFromPem(privateKeyPem);
        return Convert.ToBase64String(key.ExportSubjectPublicKeyInfo());
    }

    /// <summary>Signature files hold base64 text; anything else is rejected.</summary>
    public static bool TryDecodeSignature(string text, out byte[] signature)
    {
        signature = Array.Empty<byte>();
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Length > 512) return false;

        try
        {
            signature = Convert.FromBase64String(trimmed);
            return signature.Length > 0;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    public static string EncodeSignature(ReadOnlySpan<byte> signature) => Convert.ToBase64String(signature) + "\n";
}
