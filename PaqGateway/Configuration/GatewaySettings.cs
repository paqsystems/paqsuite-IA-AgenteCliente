namespace PaqGateway.Configuration;

public class GatewaySettings
{
    public const string SectionName = "Gateway";

    public string InternalApiKey { get; set; } = string.Empty;

    public int DefaultJobTimeoutSeconds { get; set; } = 30;

    public List<RegisteredAgentSettings> Agents { get; set; } = [];
}

public class RegisteredAgentSettings
{
    public string AgentId { get; set; } = string.Empty;

    public string ClientId { get; set; } = string.Empty;

    public string Token { get; set; } = string.Empty;

    public bool Enabled { get; set; } = true;
}
