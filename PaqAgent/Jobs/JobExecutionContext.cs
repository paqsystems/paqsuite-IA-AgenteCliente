using PaqAgent.Models;

namespace PaqAgent.Jobs;

public class JobExecutionContext
{
    public AgentJob Job { get; init; } = new();
    public DateTime StartedAtUtc { get; init; } = DateTime.UtcNow;
    public string Status { get; set; } = JobStatus.Received;
}
