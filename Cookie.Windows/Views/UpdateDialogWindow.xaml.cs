using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows;
using Cookie.Windows.Core.Updates;

namespace Cookie.Windows.Views;

public partial class UpdateDialogWindow : Window
{
    private readonly IUpdateService _updateService;
    private UpdateManifest? _availableManifest;
    private CancellationTokenSource? _downloadCts;
    private bool _isDownloading = false;

    public UpdateDialogWindow(IUpdateService updateService)
    {
        InitializeComponent();
        _updateService = updateService;

        Loaded += async (s, e) => await CheckForUpdatesAsync();
    }

    private async System.Threading.Tasks.Task CheckForUpdatesAsync()
    {
        StatusTitleText.Text = "Checking for Updates...";
        StatusSubtitleText.Text = "Connecting securely to update server...";
        ReleaseNotesText.Text = "Querying latest release information...";
        ActionBtn.Visibility = Visibility.Collapsed;

        var result = await _updateService.CheckForUpdatesAsync();

        if (result.Status == UpdateCheckStatus.UpToDate)
        {
            StatusTitleText.Text = "You're Up to Date! 🍪";
            StatusSubtitleText.Text = $"Cookie v{result.CurrentVersion} is currently the newest version available.";
            ReleaseNotesText.Text = "No newer releases are available at this time. Cookie will continue checking automatically according to your preferences.";
            ActionBtn.Visibility = Visibility.Collapsed;
        }
        else if (result.Status == UpdateCheckStatus.UpdateAvailable && result.AvailableRelease != null)
        {
            _availableManifest = result.AvailableRelease;
            StatusTitleText.Text = $"Version {_availableManifest.Version} Available!";
            StatusSubtitleText.Text = $"Published on {_availableManifest.ReleaseDate:MMMM d, yyyy}";
            ReleaseNotesText.Text = _availableManifest.ReleaseNotes;

            ActionBtn.Content = "Download & Install";
            ActionBtn.Visibility = Visibility.Visible;
        }
        else if (result.Status == UpdateCheckStatus.HostingNotConfigured)
        {
            StatusTitleText.Text = "Updates Not Configured";
            StatusSubtitleText.Text = "Production release hosting is pending distribution setup.";
            ReleaseNotesText.Text = "This build is running in pre-release or local testing mode. When public distribution is deployed, update packages and release manifests will be hosted securely over HTTPS.";
            ActionBtn.Visibility = Visibility.Collapsed;
        }
        else
        {
            StatusTitleText.Text = "Update Check Failed";
            StatusSubtitleText.Text = result.Message ?? "Could not reach update server.";
            ReleaseNotesText.Text = "Please verify your network connection and try again later. Your current version will continue to function normally.";
            ActionBtn.Content = "Try Again";
            ActionBtn.Visibility = Visibility.Visible;
        }
    }

    private async void ActionBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_availableManifest == null)
        {
            await CheckForUpdatesAsync();
            return;
        }

        if (_isDownloading)
        {
            _downloadCts?.Cancel();
            return;
        }

        _isDownloading = true;
        ActionBtn.Content = "Cancel Download";
        ProgressPanel.Visibility = Visibility.Visible;
        DownloadProgressBar.Value = 0;
        _downloadCts = new CancellationTokenSource();

        string tempDir = Path.Combine(Path.GetTempPath(), "CookieUpdates");
        var progress = new Progress<double>(p =>
        {
            Dispatcher.Invoke(() =>
            {
                DownloadProgressBar.Value = p * 100.0;
                ProgressText.Text = $"Downloading update package... {Math.Round(p * 100.0)}%";
            });
        });

        var downloadResult = await _updateService.DownloadUpdateAsync(
            _availableManifest,
            tempDir,
            progress,
            _downloadCts.Token);

        _isDownloading = false;

        if (downloadResult.Status == UpdateDownloadStatus.Success && !string.IsNullOrEmpty(downloadResult.DownloadedFilePath))
        {
            StatusTitleText.Text = "Ready to Install!";
            StatusSubtitleText.Text = "Package downloaded and verified successfully.";
            ReleaseNotesText.Text = "Click 'Launch Installer' to complete the update. Cookie will close and the installer will upgrade your companion safely.";

            ActionBtn.Content = "Launch Installer";
            ActionBtn.Click -= ActionBtn_Click;
            ActionBtn.Click += (s, args) =>
            {
                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = downloadResult.DownloadedFilePath,
                        UseShellExecute = true
                    });
                    Application.Current.Shutdown();
                }
                catch (Exception ex)
                {
                    MessageBox.Show($"Could not launch installer: {ex.Message}", "Update Error", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            };
        }
        else if (downloadResult.Status == UpdateDownloadStatus.IntegrityCheckFailed)
        {
            StatusTitleText.Text = "Verification Failed";
            StatusSubtitleText.Text = "Checksum mismatch detected.";
            ReleaseNotesText.Text = "The downloaded file did not match the expected SHA-256 signature and has been removed for your protection. Please try downloading again.";
            ActionBtn.Content = "Retry";
            ProgressPanel.Visibility = Visibility.Collapsed;
        }
        else if (downloadResult.Status == UpdateDownloadStatus.Cancelled)
        {
            StatusTitleText.Text = "Download Cancelled";
            ProgressPanel.Visibility = Visibility.Collapsed;
            ActionBtn.Content = "Download & Install";
        }
        else
        {
            StatusTitleText.Text = "Download Failed";
            StatusSubtitleText.Text = downloadResult.ErrorMessage ?? "Network error during download.";
            ProgressPanel.Visibility = Visibility.Collapsed;
            ActionBtn.Content = "Retry";
        }
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e)
    {
        _downloadCts?.Cancel();
        Close();
    }
}
