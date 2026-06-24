using PaqAgent.Models;

namespace PaqAgent.Communication;

public interface IAgentConnection
{
    bool IsConnected { get; }
    event Func<AgentJob, Task>? OnJobReceived;
    event Func<Task>? OnDiagnosticsRequested;

    Task ConnectAsync(CancellationToken cancellationToken = default);
    Task DisconnectAsync(CancellationToken cancellationToken = default);
    Task SendHeartbeatAsync(AgentHeartbeat heartbeat, CancellationToken cancellationToken = default);
    Task SendJobResultAsync(AgentJobResult result, CancellationToken cancellationToken = default);
}
