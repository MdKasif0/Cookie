namespace Cookie.Windows.Core.Startup;

/// <summary>
/// Service abstraction for querying and configuring optional launch-at-login behavior on Windows.
/// </summary>
public interface IStartupService
{
    bool IsStartupEnabled();
    bool SetStartupEnabled(bool enable);
}

/// <summary>
/// In-memory implementation of IStartupService for unit tests and cross-platform execution.
/// </summary>
public class DefaultStartupService : IStartupService
{
    private bool _isEnabled;

    public DefaultStartupService(bool initialEnabled = false)
    {
        _isEnabled = initialEnabled;
    }

    public bool IsStartupEnabled() => _isEnabled;

    public bool SetStartupEnabled(bool enable)
    {
        _isEnabled = enable;
        return true;
    }
}
