using System.Text.Json.Serialization;

namespace PaqContracts.Models;

public class AgentJob
{
    [JsonPropertyName("jobId")]
    public string JobId { get; set; } = string.Empty;

    [JsonPropertyName("clientId")]
    public string ClientId { get; set; } = string.Empty;

    [JsonPropertyName("agentId")]
    public string AgentId { get; set; } = string.Empty;

    [JsonPropertyName("operation")]
    public string Operation { get; set; } = string.Empty;

    [JsonPropertyName("parameters")]
    public Dictionary<string, object?> Parameters { get; set; } = new();

    [JsonPropertyName("timeoutSeconds")]
    public int TimeoutSeconds { get; set; } = 30;

    [JsonPropertyName("requestedAtUtc")]
    public DateTime? RequestedAtUtc { get; set; }
}
