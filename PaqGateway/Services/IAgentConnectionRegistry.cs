using PaqContracts.Models;

namespace PaqGateway.Services;

public interface IAgentConnectionRegistry
{
    void RegisterConnection(string connectionId, Action abortConnection);

    void UnregisterConnection(string connectionId);

    void RegisterAgent(string agentId, string connectionId, AgentIdentity identity);

    void UpdateHeartbeat(AgentHeartbeat heartbeat);

    bool TryGetConnectionId(string agentId, out string? connectionId);

    AgentRegistryEntry? GetAgent(string agentId);

    bool DisconnectAgent(string agentId);
}

public class AgentRegistryEntry
{
    public string AgentId { get; init; } = string.Empty;

    public string ConnectionId { get; set; } = string.Empty;

    public string ClientId { get; set; } = string.Empty;

    public string Status { get; set; } = AgentStatus.Offline;

    public DateTime? LastSeenAt { get; set; }

    public string? Version { get; set; }

    public string? MachineName { get; set; }

    public string? DisplayName { get; set; }

    public string? OsVersion { get; set; }

    public string? SqlServerName { get; set; }

    public string? SqlDatabase { get; set; }
}
