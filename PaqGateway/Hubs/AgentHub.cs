using Microsoft.AspNetCore.SignalR;
using PaqContracts.Models;
using PaqGateway.Authentication;
using PaqGateway.Services;

namespace PaqGateway.Hubs;

public class AgentHub : Hub
{
    private readonly IAgentConnectionRegistry _registry;
    private readonly IJobCorrelationService _jobCorrelation;
    private readonly IAgentTokenValidator _tokenValidator;
    private readonly ILaravelAgentAuthService _laravelAuthService;
    private readonly ILogger<AgentHub> _logger;

    public AgentHub(
        IAgentConnectionRegistry registry,
        IJobCorrelationService jobCorrelation,
        IAgentTokenValidator tokenValidator,
        ILaravelAgentAuthService laravelAuthService,
        ILogger<AgentHub> logger)
    {
        _registry = registry;
        _jobCorrelation = jobCorrelation;
        _tokenValidator = tokenValidator;
        _laravelAuthService = laravelAuthService;
        _logger = logger;
    }

    public override Task OnConnectedAsync()
    {
        var httpContext = Context.GetHttpContext()
            ?? throw new HubException("Contexto HTTP no disponible");

        var agentId = AgentConnectionAuth.ExtractHeader(httpContext, AgentConnectionAuth.AgentIdHeader);
        var clientId = AgentConnectionAuth.ExtractHeader(httpContext, AgentConnectionAuth.ClientIdHeader);
        var agentVersion = AgentConnectionAuth.ExtractHeader(httpContext, AgentConnectionAuth.AgentVersionHeader);
        var token = AgentConnectionAuth.ExtractToken(httpContext);

        if (!_tokenValidator.TryValidate(agentId ?? string.Empty, clientId ?? string.Empty, token ?? string.Empty, out var reason))
        {
            _logger.LogWarning(
                "Conexion rechazada para agentId {AgentId}: {Reason}",
                agentId ?? "(vacío)",
                reason);
            throw new HubException(reason ?? "Autenticacion de agente fallida");
        }

        _ = _laravelAuthService.UpdateHeartbeatAsync(
            agentId ?? string.Empty,
            agentVersion ?? "unknown");

        _registry.RegisterConnection(Context.ConnectionId, () => Context.Abort());

        _logger.LogInformation(
            "Agente conectado: agentId={AgentId}, clientId={ClientId}, connectionId={ConnectionId}",
            agentId,
            clientId,
            Context.ConnectionId);

        return base.OnConnectedAsync();
    }

    public override Task OnDisconnectedAsync(Exception? exception)
    {
        _registry.UnregisterConnection(Context.ConnectionId);

        if (exception is not null)
        {
            _logger.LogWarning(
                exception,
                "Agente desconectado con error, connectionId={ConnectionId}",
                Context.ConnectionId);
        }
        else
        {
            _logger.LogInformation(
                "Agente desconectado, connectionId={ConnectionId}",
                Context.ConnectionId);
        }

        return base.OnDisconnectedAsync(exception);
    }

    public Task RegisterAgent(AgentIdentity identity)
    {
        var httpContext = Context.GetHttpContext();
        var headerAgentId = httpContext is null
            ? null
            : AgentConnectionAuth.ExtractHeader(httpContext, AgentConnectionAuth.AgentIdHeader);

        if (string.IsNullOrWhiteSpace(identity.AgentId))
            throw new HubException("AgentId requerido en RegisterAgent");

        if (!string.IsNullOrWhiteSpace(headerAgentId)
            && !string.Equals(headerAgentId, identity.AgentId, StringComparison.OrdinalIgnoreCase))
        {
            throw new HubException("AgentId del payload no coincide con X-Agent-Id");
        }

        _registry.RegisterAgent(identity.AgentId, Context.ConnectionId, identity);

        _logger.LogInformation(
            "Agente registrado: agentId={AgentId}, version={Version}, machine={MachineName}",
            identity.AgentId,
            identity.Version,
            identity.MachineName);

        return Task.CompletedTask;
    }

    public Task SendHeartbeat(AgentHeartbeat heartbeat)
    {
        if (string.IsNullOrWhiteSpace(heartbeat.AgentId))
            throw new HubException("AgentId requerido en SendHeartbeat");

        _registry.UpdateHeartbeat(heartbeat);

        _logger.LogDebug(
            "Heartbeat recibido: agentId={AgentId}, status={Status}",
            heartbeat.AgentId,
            heartbeat.Status);

        return Task.CompletedTask;
    }

    public Task SendJobResult(AgentJobResult result)
    {
        if (string.IsNullOrWhiteSpace(result.JobId))
            throw new HubException("JobId requerido en SendJobResult");

        var completed = _jobCorrelation.TryComplete(result.JobId, result);

        if (!completed)
        {
            _logger.LogWarning(
                "Resultado recibido sin correlacion pendiente: jobId={JobId}, agentId={AgentId}, status={Status}",
                result.JobId,
                result.AgentId,
                result.Status);
        }
        else
        {
            _logger.LogInformation(
                "Resultado de job recibido: jobId={JobId}, agentId={AgentId}, status={Status}",
                result.JobId,
                result.AgentId,
                result.Status);
        }

        return Task.CompletedTask;
    }
}
