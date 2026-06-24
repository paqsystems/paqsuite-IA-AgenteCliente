using PaqAgent.Models;

namespace PaqAgent.Jobs;

public static class JobResultFactory
{
    public static AgentJobResult Success(string jobId, string agentId, long durationMs, object? data) =>
        new()
        {
            JobId = jobId,
            AgentId = agentId,
            Status = JobStatus.Success,
            DurationMs = durationMs,
            Data = data,
            Error = null
        };

    public static AgentJobResult Failed(string jobId, string agentId, long durationMs, string errorCode, string message) =>
        new()
        {
            JobId = jobId,
            AgentId = agentId,
            Status = JobStatus.Failed,
            DurationMs = durationMs,
            Data = null,
            Error = new AgentError { Code = errorCode, Message = message }
        };

    public static AgentJobResult Timeout(string jobId, string agentId, long durationMs) =>
        new()
        {
            JobId = jobId,
            AgentId = agentId,
            Status = JobStatus.Timeout,
            DurationMs = durationMs,
            Data = null,
            Error = new AgentError
            {
                Code = ErrorCodes.JobTimeout,
                Message = "El job supero el tiempo maximo permitido."
            }
        };
}
