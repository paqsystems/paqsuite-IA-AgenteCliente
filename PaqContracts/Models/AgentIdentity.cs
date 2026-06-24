namespace PaqContracts.Models;

public class AgentIdentity
{
    public string AgentId { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string MachineName { get; set; } = string.Empty;
    public string OsVersion { get; set; } = string.Empty;
    public string SqlServerName { get; set; } = string.Empty;
    public string SqlDatabase { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
}
