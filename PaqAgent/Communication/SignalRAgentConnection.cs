using System.Text.Json;
using Microsoft.AspNetCore.SignalR.Client;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Models;
using PaqAgent.Security;
using Polly;
using Polly.Retry;

namespace PaqAgent.Communication;

public class SignalRAgentConnection : IAgentConnection, IAsyncDisposable
{
    private readonly AgentSettings _settings;
    private readonly AgentAuthenticator _authenticator;
    private readonly TokenProvider _tokenProvider;
    private readonly ILogger<SignalRAgentConnection> _logger;
    private HubConnection? _connection;
    private readonly AsyncRetryPolicy _retryPolicy;

    public bool IsConnected => _connection?.State == HubConnectionState.Connected;

    public event Func<AgentJob, Task>? OnJobReceived;
    public event Func<Task>? OnDiagnosticsRequested;

    public SignalRAgentConnection(
        IOptions<AgentSettings> settings,
        AgentAuthenticator authenticator,
        TokenProvider tokenProvider,
        ILogger<SignalRAgentConnection> logger)
    {
        _settings = settings.Value;
        _authenticator = authenticator;
        _tokenProvider = tokenProvider;
        _logger = logger;

        var delays = new[] { 5, 10, 20, 30, 60 };
        _retryPolicy = Policy
            .Handle<Exception>()
            .WaitAndRetryAsync(
                delays.Select(d => TimeSpan.FromSeconds(d))
                    .Concat(Enumerable.Repeat(TimeSpan.FromSeconds(60), 100)),
                (exception, timeSpan, retryCount, _) =>
                {
                    _logger.LogWarning(exception,
                        "Reintento de conexion {RetryCount}, esperando {Delay}s",
                        retryCount, timeSpan.TotalSeconds);
                });
    }

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        await _retryPolicy.ExecuteAsync(async ct =>
        {
            if (_connection is not null)
            {
                await _connection.DisposeAsync();
            }

            _connection = BuildConnection();
            RegisterHandlers();

            _logger.LogInformation("Conectando al gateway {GatewayUrl}", _settings.GatewayUrl);
            await _connection.StartAsync(ct);

            var identity = _authenticator.BuildIdentity();
            await _connection.InvokeAsync("RegisterAgent", identity, ct);

            _logger.LogInformation("Conectado y registrado como agente {AgentId}", _settings.AgentId);
        }, cancellationToken);
    }

    public async Task DisconnectAsync(CancellationToken cancellationToken = default)
    {
        if (_connection is not null)
        {
            await _connection.StopAsync(cancellationToken);
            _logger.LogInformation("Desconectado del gateway");
        }
    }

    public async Task SendHeartbeatAsync(AgentHeartbeat heartbeat, CancellationToken cancellationToken = default)
    {
        if (_connection?.State != HubConnectionState.Connected)
            return;

        await _connection.InvokeAsync("SendHeartbeat", heartbeat, cancellationToken);
    }

    public async Task SendJobResultAsync(AgentJobResult result, CancellationToken cancellationToken = default)
    {
        if (_connection?.State != HubConnectionState.Connected)
            throw new InvalidOperationException("No hay conexion activa con el gateway");

        await _connection.InvokeAsync("SendJobResult", result, cancellationToken);
    }

    private HubConnection BuildConnection()
    {
        return new HubConnectionBuilder()
            .WithUrl(_settings.GatewayUrl, options =>
            {
                options.AccessTokenProvider = () => Task.FromResult<string?>(_tokenProvider.GetToken());
                options.Headers["X-Agent-Id"] = _settings.AgentId;
                options.Headers["X-Client-Id"] = _settings.ClientId;
            })
            .WithAutomaticReconnect(new[] { TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(10),
                TimeSpan.FromSeconds(20), TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(60) })
            .Build();
    }

    private void RegisterHandlers()
    {
        if (_connection is null) return;

        _connection.On<string>("ExecuteJob", async jobJson =>
        {
            try
            {
                var job = JsonSerializer.Deserialize<AgentJob>(jobJson,
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

                if (job is null)
                {
                    _logger.LogWarning("Job recibido con formato invalido");
                    return;
                }

                _logger.LogInformation("Job recibido: {JobId}, operacion: {Operation}", job.JobId, job.Operation);

                if (OnJobReceived is not null)
                    await OnJobReceived.Invoke(job);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al procesar job recibido");
            }
        });

        _connection.On("RunDiagnostics", async () =>
        {
            _logger.LogInformation("Solicitud de diagnostico recibida");
            if (OnDiagnosticsRequested is not null)
                await OnDiagnosticsRequested.Invoke();
        });

        _connection.Reconnecting += error =>
        {
            _logger.LogWarning(error, "Reconectando al gateway...");
            return Task.CompletedTask;
        };

        _connection.Reconnected += connectionId =>
        {
            _logger.LogInformation("Reconectado al gateway, connectionId: {ConnectionId}", connectionId);
            return Task.CompletedTask;
        };

        _connection.Closed += async error =>
        {
            if (error is not null)
                _logger.LogWarning(error, "Conexion cerrada, intentando reconectar...");

            await Task.Delay(TimeSpan.FromSeconds(5));
            try
            {
                await ConnectAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al reconectar");
            }
        };
    }

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null)
            await _connection.DisposeAsync();
    }
}
