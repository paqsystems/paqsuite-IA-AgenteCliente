using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Communication;
using PaqAgent.Configuration;
using PaqAgent.Jobs;
using PaqAgent.Models;

namespace PaqAgent.Services;

public class AgentWorker : BackgroundService
{
    private readonly IAgentConnection _connection;
    private readonly JobDispatcher _jobDispatcher;
    private readonly DiagnosticsService _diagnosticsService;
    private readonly AgentSettings _settings;
    private readonly ILogger<AgentWorker> _logger;

    public AgentWorker(
        IAgentConnection connection,
        JobDispatcher jobDispatcher,
        DiagnosticsService diagnosticsService,
        IOptions<AgentSettings> settings,
        ILogger<AgentWorker> logger)
    {
        _connection = connection;
        _jobDispatcher = jobDispatcher;
        _diagnosticsService = diagnosticsService;
        _settings = settings.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _connection.OnJobReceived += HandleJobAsync;
        _connection.OnDiagnosticsRequested += HandleDiagnosticsAsync;

        _logger.LogInformation("PaqAgent v{Version} iniciando, AgentId: {AgentId}",
            _settings.Version, _settings.AgentId);

        try
        {
            await _connection.ConnectAsync(stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            _logger.LogInformation("Detencion solicitada");
        }
        catch (Exception ex)
        {
            _logger.LogCritical(ex, "Error fatal en el agente");
            throw;
        }
        finally
        {
            _connection.OnJobReceived -= HandleJobAsync;
            _connection.OnDiagnosticsRequested -= HandleDiagnosticsAsync;
            await _connection.DisconnectAsync(CancellationToken.None);
            _logger.LogInformation("PaqAgent detenido");
        }
    }

    private async Task HandleJobAsync(AgentJob job)
    {
        var result = await _jobDispatcher.DispatchAsync(job);

        try
        {
            await _connection.SendJobResultAsync(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "No se pudo enviar resultado del job {JobId}", job.JobId);
        }
    }

    private async Task HandleDiagnosticsAsync()
    {
        try
        {
            var diagnostics = await _diagnosticsService.RunDiagnosticsAsync();
            var result = new AgentJobResult
            {
                JobId = $"diag_{DateTime.UtcNow:yyyyMMddHHmmss}",
                AgentId = _settings.AgentId,
                Status = JobStatus.Success,
                Data = diagnostics
            };
            await _connection.SendJobResultAsync(result);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al ejecutar diagnostico remoto");
        }
    }
}
