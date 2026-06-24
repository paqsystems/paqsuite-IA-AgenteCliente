using System.Text.Json.Serialization;

namespace PaqAgent.Models;

public class AgentJobResult
{
    [JsonPropertyName("jobId")]
    public string JobId { get; set; } = string.Empty;

    [JsonPropertyName("agentId")]
    public string AgentId { get; set; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; set; } = JobStatus.Pending;

    [JsonPropertyName("durationMs")]
    public long DurationMs { get; set; }

    [JsonPropertyName("data")]
    public object? Data { get; set; }

    [JsonPropertyName("error")]
    public AgentError? Error { get; set; }
}

public class AgentError
{
    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;
}

public static class JobStatus
{
    public const string Pending = "pending";
    public const string Received = "received";
    public const string Running = "running";
    public const string Success = "success";
    public const string Failed = "failed";
    public const string Timeout = "timeout";
    public const string Cancelled = "cancelled";
}

public static class ErrorCodes
{
    public const string OperationNotAllowed = "OPERATION_NOT_ALLOWED";
    public const string SqlConnectionFailed = "SQL_CONNECTION_FAILED";
    public const string SqlTimeout = "SQL_TIMEOUT";
    public const string SqlError = "SQL_ERROR";
    public const string InvalidParameters = "INVALID_PARAMETERS";
    public const string InternalError = "INTERNAL_ERROR";
    public const string JobTimeout = "JOB_TIMEOUT";
    public const string AuthNotFound = "NOT_FOUND";
    public const string AuthInactive = "INACTIVE";
    public const string AuthNoEmpresas = "NO_EMPRESAS";
}
