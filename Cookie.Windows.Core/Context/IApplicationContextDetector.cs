using System;

namespace Cookie.Windows.Core.Context;

/// <summary>
/// Service abstraction for detecting active application switches and foreground window changes.
/// </summary>
public interface IApplicationContextDetector
{
    ApplicationContext CurrentContext { get; }
    ApplicationContext? PreviousContext { get; }

    ApplicationContext RefreshContext();

    event Action<ApplicationContext>? OnApplicationSwitched;
}

/// <summary>
/// Default in-memory implementation of IApplicationContextDetector for unit tests and cross-platform execution.
/// </summary>
public class DefaultApplicationContextDetector : IApplicationContextDetector
{
    private ApplicationContext _currentContext = ApplicationContext.Unknown;
    private ApplicationContext? _previousContext;

    public ApplicationContext CurrentContext => _currentContext;
    public ApplicationContext? PreviousContext => _previousContext;

    public Func<DateTime> Now { get; set; } = () => DateTime.UtcNow;

    public event Action<ApplicationContext>? OnApplicationSwitched;

    public void SetContext(ApplicationContext context)
    {
        if (_currentContext != context)
        {
            _previousContext = _currentContext;
            _currentContext = context with { Timestamp = Now() };
            OnApplicationSwitched?.Invoke(_currentContext);
        }
    }

    public ApplicationContext RefreshContext()
    {
        return _currentContext;
    }
}
