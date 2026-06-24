using PaqContracts.Models;

namespace PaqGateway.Services;

public interface IJobCorrelationService
{
    Task<AgentJobResult> WaitForResultAsync(string jobId, TimeSpan timeout, CancellationToken cancellationToken = default);

    bool TryComplete(string jobId, AgentJobResult result);

    void Cancel(string jobId);
}
