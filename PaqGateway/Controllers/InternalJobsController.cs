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

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=1 HTTP Request recibida | jobId={JobId} | agentId={AgentId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId);

        var timeoutSeconds = request.TimeoutSeconds is > 0
            ? request.TimeoutSeconds.Value
            : _settings.DefaultJobTimeoutSeconds;

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=2 Antes de buscar agente | jobId={JobId} | agentId={AgentId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId);

        if (!_registry.TryGetConnectionId(request.AgentId, out var connectionId)
            || string.IsNullOrWhiteSpace(connectionId))
        {
            _logger.LogWarning(
                "Job no enviado, agente offline: jobId={JobId}, agentId={AgentId}, operation={Operation}",
                jobId,
                request.AgentId,
                request.Operation);

            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=10 Antes de responder a Laravel | jobId={JobId} | agentId={AgentId}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId);

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

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=3 Agente encontrado | jobId={JobId} | agentId={AgentId} | connectionId={ConnectionId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId,
            connectionId);

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

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=4 Antes de serializar Job | jobId={JobId} | agentId={AgentId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId);

        var jobJson = JsonSerializer.Serialize(job, JobJsonOptions);

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=5 Después de serializar Job | jobId={JobId} | agentId={AgentId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId);

        _logger.LogInformation(
            "Enviando job al agente: jobId={JobId}, agentId={AgentId}, operation={Operation}",
            jobId,
            request.AgentId,
            request.Operation);

        _logger.LogInformation(
            "[PERF-DIAG] {Timestamp} | SendJob paso=8 Antes de esperar WaitForResultAsync | jobId={JobId} | agentId={AgentId}",
            DateTime.UtcNow.ToString("HH:mm:ss.fff"),
            jobId,
            request.AgentId);

        var waitTask = _jobCorrelation.WaitForResultAsync(
            jobId,
            TimeSpan.FromSeconds(timeoutSeconds),
            cancellationToken);

        try
        {
            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=6 Antes de SendAsync | jobId={JobId} | agentId={AgentId} | connectionId={ConnectionId}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId,
                connectionId);

            await _hubContext.Clients.Client(connectionId).SendAsync("ExecuteJob", jobJson, cancellationToken);

            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=7 Después de SendAsync | jobId={JobId} | agentId={AgentId} | connectionId={ConnectionId}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId,
                connectionId);

            var result = await waitTask;

            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=9 WaitForResultAsync devolvió resultado | jobId={JobId} | agentId={AgentId} | status={Status}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId,
                result.Status);

            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=10 Antes de responder a Laravel | jobId={JobId} | agentId={AgentId}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId);

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

            _logger.LogInformation(
                "[PERF-DIAG] {Timestamp} | SendJob paso=10 Antes de responder a Laravel | jobId={JobId} | agentId={AgentId}",
                DateTime.UtcNow.ToString("HH:mm:ss.fff"),
                jobId,
                request.AgentId);

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
