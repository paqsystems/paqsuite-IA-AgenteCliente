using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Options;
using PaqContracts.Models;
using PaqGateway.Authentication;
using PaqGateway.Configuration;
using PaqGateway.Hubs;
using PaqGateway.Models;
using PaqGateway.Services;

namespace PaqGateway.Controllers;

[ApiController]
[Route("internal")]
[InternalApiKey]
public class InternalJobsController : ControllerBase
{
    private static readonly JsonSerializerOptions JobJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly IAgentConnectionRegistry _registry;
    private readonly IJobCorrelationService _jobCorrelation;
    private readonly IHubContext<AgentHub> _hubContext;
    private readonly GatewaySettings _settings;
    private readonly ILogger<InternalJobsController> _logger;

    public InternalJobsController(
        IAgentConnectionRegistry registry,
        IJobCorrelationService jobCorrelation,
        IHubContext<AgentHub> hubContext,
        IOptions<GatewaySettings> settings,
        ILogger<InternalJobsController> logger)
    {
        _registry = registry;
        _jobCorrelation = jobCorrelation;
        _hubContext = hubContext;
        _settings = settings.Value;
        _logger = logger;
    }

    [HttpPost("jobs/send")]
    public async Task<ActionResult<GatewayJobResponse>> SendJob(
        [FromBody] SendJobRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.AgentId))
            return BadRequest(new { error = "agentId es requerido" });

        if (string.IsNullOrWhiteSpace(request.Operation))
            return BadRequest(new { error = "operation es requerida" });

        var jobId = Guid.NewGuid().ToString("N");
        var timeoutSeconds = request.TimeoutSeconds is > 0
            ? request.TimeoutSeconds.Value
            : _settings.DefaultJobTimeoutSeconds;

        if (!_registry.TryGetConnectionId(request.AgentId, out var connectionId)
            || string.IsNullOrWhiteSpace(connectionId))
        {
            _logger.LogWarning(
                "Job no enviado, agente offline: jobId={JobId}, agentId={AgentId}, operation={Operation}",
                jobId,
                request.AgentId,
                request.Operation);

            return Ok(new GatewayJobResponse
            {
                JobId = jobId,
                AgentId = request.AgentId,
                Status = "offline",
                Error = new AgentError
                {
                    Code = "AGENT_OFFLINE",
                    Message = $"El agente {request.AgentId} no esta conectado"
                }
            });
        }

        var job = new AgentJob
        {
            JobId = jobId,
            ClientId = request.ClientId,
            AgentId = request.AgentId,
            Operation = request.Operation,
            Parameters = request.Parameters,
            TimeoutSeconds = timeoutSeconds,
            RequestedAtUtc = DateTime.UtcNow
        };

        var jobJson = JsonSerializer.Serialize(job, JobJsonOptions);

        _logger.LogInformation(
            "Enviando job al agente: jobId={JobId}, agentId={AgentId}, operation={Operation}",
            jobId,
            request.AgentId,
            request.Operation);

        var waitTask = _jobCorrelation.WaitForResultAsync(
            jobId,
            TimeSpan.FromSeconds(timeoutSeconds),
            cancellationToken);

        try
        {
            await _hubContext.Clients.Client(connectionId).SendAsync("ExecuteJob", jobJson, cancellationToken);

            var result = await waitTask;
            return Ok(MapToGatewayResponse(result));
        }
        catch (TimeoutException)
        {
            _jobCorrelation.Cancel(jobId);

            _logger.LogWarning(
                "Timeout esperando respuesta del agente: jobId={JobId}, agentId={AgentId}, operation={Operation}",
                jobId,
                request.AgentId,
                request.Operation);

            return Ok(new GatewayJobResponse
            {
                JobId = jobId,
                AgentId = request.AgentId,
                Status = JobStatus.Timeout,
                Error = new AgentError
                {
                    Code = "AGENT_TIMEOUT",
                    Message = $"El agente no respondio dentro de {timeoutSeconds}s"
                }
            });
        }
    }

    [HttpGet("agents/{agentId}/status")]
    public ActionResult<AgentStatusResponse> GetAgentStatus(string agentId)
    {
        var entry = _registry.GetAgent(agentId);

        if (entry is null)
        {
            return Ok(new AgentStatusResponse
            {
                AgentId = agentId,
                Status = AgentStatus.Offline
            });
        }

        return Ok(new AgentStatusResponse
        {
            AgentId = entry.AgentId,
            Status = entry.Status,
            LastSeenAt = entry.LastSeenAt,
            Version = entry.Version,
            ConnectionId = string.IsNullOrWhiteSpace(entry.ConnectionId) ? null : entry.ConnectionId,
            ClientId = entry.ClientId,
            MachineName = entry.MachineName
        });
    }

    [HttpPost("agents/{agentId}/disconnect")]
    public ActionResult<DisconnectAgentResponse> DisconnectAgent(string agentId)
    {
        var disconnected = _registry.DisconnectAgent(agentId);

        if (!disconnected)
        {
            return Ok(new DisconnectAgentResponse
            {
                AgentId = agentId,
                Disconnected = false,
                Message = "El agente no estaba conectado"
            });
        }

        _logger.LogInformation("Desconexion forzada del agente {AgentId}", agentId);

        return Ok(new DisconnectAgentResponse
        {
            AgentId = agentId,
            Disconnected = true,
            Message = "Conexion del agente cerrada"
        });
    }

    private static GatewayJobResponse MapToGatewayResponse(AgentJobResult result) => new()
    {
        JobId = result.JobId,
        AgentId = result.AgentId,
        Status = result.Status,
        DurationMs = result.DurationMs,
        Data = result.Data,
        Error = result.Error
    };
}
