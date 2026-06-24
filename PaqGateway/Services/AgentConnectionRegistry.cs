using PaqContracts.Models;

namespace PaqGateway.Services;

public class AgentConnectionRegistry : IAgentConnectionRegistry
{
    private readonly object _sync = new();
    private readonly Dictionary<string, AgentRegistryEntry> _agentsById = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _connectionToAgent = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Action> _abortByConnection = new(StringComparer.Ordinal);

    public void RegisterConnection(string connectionId, Action abortConnection)
    {
        lock (_sync)
        {
            _abortByConnection[connectionId] = abortConnection;
        }
    }

    public void UnregisterConnection(string connectionId)
    {
        lock (_sync)
        {
            _abortByConnection.Remove(connectionId);

            if (_connectionToAgent.TryGetValue(connectionId, out var agentId))
            {
                _connectionToAgent.Remove(connectionId);

                if (_agentsById.TryGetValue(agentId, out var entry))
                {
                    entry.Status = AgentStatus.Offline;
                    entry.ConnectionId = string.Empty;
                }
            }
        }
    }

    public void RegisterAgent(string agentId, string connectionId, AgentIdentity identity)
    {
        lock (_sync)
        {
            if (_connectionToAgent.TryGetValue(connectionId, out var previousAgentId)
                && !string.Equals(previousAgentId, agentId, StringComparison.OrdinalIgnoreCase)
                && _agentsById.TryGetValue(previousAgentId, out var previousEntry))
            {
                previousEntry.Status = AgentStatus.Offline;
                previousEntry.ConnectionId = string.Empty;
            }

            foreach (var pair in _connectionToAgent.Where(p =>
                         string.Equals(p.Value, agentId, StringComparison.OrdinalIgnoreCase)
                         && !string.Equals(p.Key, connectionId, StringComparison.Ordinal)).ToList())
            {
                _connectionToAgent.Remove(pair.Key);
            }

            var entry = _agentsById.GetValueOrDefault(agentId) ?? new AgentRegistryEntry { AgentId = agentId };

            entry.ConnectionId = connectionId;
            entry.ClientId = identity.ClientId;
            entry.Version = identity.Version;
            entry.MachineName = identity.MachineName;
            entry.DisplayName = identity.DisplayName;
            entry.OsVersion = identity.OsVersion;
            entry.SqlServerName = identity.SqlServerName;
            entry.SqlDatabase = identity.SqlDatabase;
            entry.Status = AgentStatus.Online;
            entry.LastSeenAt = DateTime.UtcNow;

            _agentsById[agentId] = entry;
            _connectionToAgent[connectionId] = agentId;
        }
    }

    public void UpdateHeartbeat(AgentHeartbeat heartbeat)
    {
        lock (_sync)
        {
            if (!_agentsById.TryGetValue(heartbeat.AgentId, out var entry))
                return;

            entry.LastSeenAt = heartbeat.TimestampUtc == default ? DateTime.UtcNow : heartbeat.TimestampUtc;
            entry.Status = string.IsNullOrWhiteSpace(heartbeat.Status) ? AgentStatus.Online : heartbeat.Status;
            entry.Version = heartbeat.Version;
            entry.MachineName = heartbeat.MachineName;
            entry.ClientId = heartbeat.ClientId;
        }
    }

    public bool TryGetConnectionId(string agentId, out string? connectionId)
    {
        lock (_sync)
        {
            if (_agentsById.TryGetValue(agentId, out var entry)
                && entry.Status == AgentStatus.Online
                && !string.IsNullOrWhiteSpace(entry.ConnectionId))
            {
                connectionId = entry.ConnectionId;
                return true;
            }

            connectionId = null;
            return false;
        }
    }

    public AgentRegistryEntry? GetAgent(string agentId)
    {
        lock (_sync)
        {
            return _agentsById.TryGetValue(agentId, out var entry) ? CloneEntry(entry) : null;
        }
    }

    public bool DisconnectAgent(string agentId)
    {
        lock (_sync)
        {
            if (!_agentsById.TryGetValue(agentId, out var entry)
                || string.IsNullOrWhiteSpace(entry.ConnectionId))
            {
                return false;
            }

            var connectionId = entry.ConnectionId;

            if (_abortByConnection.TryGetValue(connectionId, out var abort))
            {
                abort.Invoke();
            }

            entry.Status = AgentStatus.Offline;
            entry.ConnectionId = string.Empty;
            _connectionToAgent.Remove(connectionId);
            return true;
        }
    }

    private static AgentRegistryEntry CloneEntry(AgentRegistryEntry source) => new()
    {
        AgentId = source.AgentId,
        ConnectionId = source.ConnectionId,
        ClientId = source.ClientId,
        Status = source.Status,
        LastSeenAt = source.LastSeenAt,
        Version = source.Version,
        MachineName = source.MachineName,
        DisplayName = source.DisplayName,
        OsVersion = source.OsVersion,
        SqlServerName = source.SqlServerName,
        SqlDatabase = source.SqlDatabase
    };
}
