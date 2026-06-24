using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Models;

namespace PaqAgent.Security;

public class AgentAuthenticator
{
    private readonly AgentSettings _settings;
    private readonly SqlConnectionSettings _sqlSettings;

    public AgentAuthenticator(
        IOptions<AgentSettings> agentSettings,
        IOptions<SqlConnectionSettings> sqlSettings)
    {
        _settings = agentSettings.Value;
        _sqlSettings = sqlSettings.Value;
    }

    public AgentIdentity BuildIdentity()
    {
        return new AgentIdentity
        {
            AgentId = _settings.AgentId,
            ClientId = _settings.ClientId,
            Version = _settings.Version,
            MachineName = Environment.MachineName,
            OsVersion = Environment.OSVersion.VersionString,
            SqlServerName = _sqlSettings.Server,
            SqlDatabase = _sqlSettings.Database,
            DisplayName = _settings.DisplayName
        };
    }

    public bool ValidateJob(AgentJob job)
    {
        if (string.IsNullOrWhiteSpace(job.AgentId))
            return true;

        return string.Equals(job.AgentId, _settings.AgentId, StringComparison.OrdinalIgnoreCase);
    }
}
