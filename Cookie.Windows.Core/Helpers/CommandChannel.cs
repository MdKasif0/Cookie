using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace Cookie.Windows.Core.Helpers;

/// <summary>
/// Passes <c>cookie://</c> links from a second launch of Cookie (which Windows starts when a link is opened)
/// to the copy that is already running, over a named pipe only the same user can reach.
/// </summary>
public sealed class CommandChannel : IDisposable
{
    public const int MaximumMessage = 4096;

    private readonly string _pipeName;
    private readonly CancellationTokenSource _cts = new();

    /// <summary>Called on a background thread with each link received.</summary>
    public event Action<string>? Received;

    public CommandChannel(string pipeName) => _pipeName = pipeName;

    /// <summary>The pipe name for this user, so two people signed in to one PC don't share it.</summary>
    public static string PipeNameForCurrentUser() => $"Cookie.Commands.{Environment.UserName}";

    public void StartListening()
    {
        _ = Task.Run(ListenLoop);
    }

    private async Task ListenLoop()
    {
        while (!_cts.IsCancellationRequested)
        {
            try
            {
                using var server = new NamedPipeServerStream(_pipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await server.WaitForConnectionAsync(_cts.Token).ConfigureAwait(false);
                var buffer = new byte[MaximumMessage];
                int total = 0;
                int read;
                while (total < buffer.Length && (read = await server.ReadAsync(buffer.AsMemory(total), _cts.Token).ConfigureAwait(false)) > 0)
                {
                    total += read;
                }
                string message = Encoding.UTF8.GetString(buffer, 0, total).Trim();
                if (message.Length > 0) Received?.Invoke(message);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (IOException)
            {
                // A client that hung up early: wait for the next one.
                try { await Task.Delay(100, _cts.Token).ConfigureAwait(false); } catch (OperationCanceledException) { return; }
            }
        }
    }

    /// <summary>Sends a link to the running copy. Returns false if nobody is listening.</summary>
    public static bool Send(string pipeName, string message, int timeoutMilliseconds = 2000)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.Out, PipeOptions.CurrentUserOnly);
            client.Connect(timeoutMilliseconds);
            byte[] bytes = Encoding.UTF8.GetBytes(message.Length > MaximumMessage / 2 ? message[..(MaximumMessage / 2)] : message);
            client.Write(bytes, 0, bytes.Length);
            client.Flush();
            return true;
        }
        catch (Exception exception) when (exception is TimeoutException or IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    public void Dispose()
    {
        _cts.Cancel();
        _cts.Dispose();
    }
}
