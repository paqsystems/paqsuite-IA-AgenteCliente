namespace PaqAgent.Configuration;

public class AgentSettings
{
    public const string SectionName = "Agent";

    public string AgentId { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Version { get; set; } = "1.0.0";
    public string GatewayUrl { get; set; } = string.Empty;
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string AgentToken { get; set; } = string.Empty;
    public int HeartbeatSeconds { get; set; } = 30;
    public int DefaultTimeoutSeconds { get; set; } = 30;
    public int MaxTimeoutSeconds { get; set; } = 120;
}
