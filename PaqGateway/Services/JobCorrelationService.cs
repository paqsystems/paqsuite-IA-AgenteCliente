using PaqContracts.Models;

namespace PaqGateway.Services;

public class JobCorrelationService : IJobCorrelationService
{
    private readonly object _sync = new();
    private readonly Dictionary<string, TaskCompletionSource<AgentJobResult>> _pending = new(StringComparer.Ordinal);

    public async Task<AgentJobResult> WaitForResultAsync(
        string jobId,
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        TaskCompletionSource<AgentJobResult> tcs;

        lock (_sync)
        {
            if (_pending.ContainsKey(jobId))
                throw new InvalidOperationException($"Ya existe una correlacion pendiente para jobId {jobId}");

            tcs = new TaskCompletionSource<AgentJobResult>(TaskCreationOptions.RunContinuationsAsynchronously);
            _pending[jobId] = tcs;
        }

        try
        {
            return await tcs.Task.WaitAsync(timeout, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            lock (_sync)
            {
                _pending.Remove(jobId);
            }
        }
    }

    public bool TryComplete(string jobId, AgentJobResult result)
    {
        TaskCompletionSource<AgentJobResult>? tcs;

        lock (_sync)
        {
            if (!_pending.Remove(jobId, out tcs))
                return false;
        }

        return tcs.TrySetResult(result);
    }

    public void Cancel(string jobId)
    {
        TaskCompletionSource<AgentJobResult>? tcs;

        lock (_sync)
        {
            if (!_pending.Remove(jobId, out tcs))
                return;
        }

        tcs.TrySetCanceled();
    }
}
