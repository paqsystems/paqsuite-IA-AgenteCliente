using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Communication;
using PaqAgent.Configuration;
using PaqAgent.Database;
using PaqAgent.Models;
using PaqAgent.Security;

namespace PaqAgent.Services;

public class HeartbeatService : BackgroundService
{
    private readonly IAgentConnection _connection;
    private readonly AgentSettings _settings;
    private readonly AgentAuthenticator _authenticator;
    private readonly ILogger<HeartbeatService> _logger;

    public HeartbeatService(
        IAgentConnection connection,
        IOptions<AgentSettings> settings,
        AgentAuthenticator authenticator,
        ILogger<HeartbeatService> logger)
    {
        _connection = connection;
        _settings = settings.Value;
        _authenticator = authenticator;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromSeconds(_settings.HeartbeatSeconds);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (_connection.IsConnected)
                {
                    var heartbeat = new AgentHeartbeat
                    {
                        AgentId = _settings.AgentId,
                        ClientId = _settings.ClientId,
                        TimestampUtc = DateTime.UtcNow,
                        Status = AgentStatus.Online,
                        Version = _settings.Version,
                        MachineName = Environment.MachineName
                    };

                    await _connection.SendHeartbeatAsync(heartbeat, stoppingToken);
                    _logger.LogDebug("Heartbeat enviado");
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error al enviar heartbeat");
            }

            await Task.Delay(interval, stoppingToken);
        }
    }
}
