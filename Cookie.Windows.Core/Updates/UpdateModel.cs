using System;

namespace Cookie.Windows.Core.Updates;

public enum UpdateCheckStatus
{
    UpToDate,
    UpdateAvailable,
    NetworkError,
    InvalidMetadata,
    HostingNotConfigured
}

public enum UpdateDownloadStatus
{
    Success,
    DownloadFailed,
    IntegrityCheckFailed,
    Cancelled
}

public record UpdateManifest(
    string Version,
    string ReleaseNotes,
    string DownloadUrl,
    string Sha256Hash,
    DateTime ReleaseDate,
    long PackageSizeBytes = 0,
    string? MinimumOsVersion = null);

public record UpdateCheckResult(
    UpdateCheckStatus Status,
    bool IsUpdateAvailable,
    string CurrentVersion,
    UpdateManifest? AvailableRelease,
    string? Message = null);

public record UpdateDownloadResult(
    UpdateDownloadStatus Status,
    string? DownloadedFilePath,
    string? ErrorMessage = null);
