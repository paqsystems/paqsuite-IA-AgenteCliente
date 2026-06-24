using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Communication;
using PaqAgent.Configuration;
using PaqAgent.Database;
using PaqAgent.Jobs;
using PaqAgent.Models;
using PaqAgent.Operations;
using PaqAgent.Security;

namespace PaqAgent.Services;

public class DiagnosticsService
{
    private readonly AgentSettings _agentSettings;
    private readonly SqlConnectionSettings _sqlSettings;
    private readonly ISqlExecutor _sqlExecutor;
    private readonly IAgentConnection _connection;
    private readonly AgentAuthenticator _authenticator;
    private readonly OperationRegistry _operationRegistry;
    private readonly ILogger<DiagnosticsService> _logger;

    public DiagnosticsService(
        IOptions<AgentSettings> agentSettings,
        IOptions<SqlConnectionSettings> sqlSettings,
        ISqlExecutor sqlExecutor,
        IAgentConnection connection,
        AgentAuthenticator authenticator,
        OperationRegistry operationRegistry,
        ILogger<DiagnosticsService> logger)
    {
        _agentSettings = agentSettings.Value;
        _sqlSettings = sqlSettings.Value;
        _sqlExecutor = sqlExecutor;
        _connection = connection;
        _authenticator = authenticator;
        _operationRegistry = operationRegistry;
        _logger = logger;
    }

    public async Task<Dictionary<string, object>> RunDiagnosticsAsync(CancellationToken cancellationToken = default)
    {
        _logger.LogInformation("Ejecutando diagnostico local");

        var results = new Dictionary<string, object>
        {
            ["agentId"] = _agentSettings.AgentId,
            ["version"] = _agentSettings.Version,
            ["machineName"] = Environment.MachineName,
            ["timestampUtc"] = DateTime.UtcNow
        };

        results["configurationValid"] = ValidateConfiguration();
        results["gatewayConnected"] = _connection.IsConnected;
        results["sqlConnectionOk"] = await _sqlExecutor.TestConnectionAsync(cancellationToken);
        results["allowedOperations"] = _operationRegistry.GetAllowedOperations();
        results["identity"] = _authenticator.BuildIdentity();

        var allOk = (bool)results["configurationValid"]
                    && (bool)results["sqlConnectionOk"];

        results["status"] = allOk ? "healthy" : "degraded";

        return results;
    }

    private bool ValidateConfiguration()
    {
        return !string.IsNullOrWhiteSpace(_agentSettings.AgentId)
               && !string.IsNullOrWhiteSpace(_agentSettings.AgentToken)
               && !string.IsNullOrWhiteSpace(_agentSettings.GatewayUrl)
               && !string.IsNullOrWhiteSpace(_sqlSettings.Server)
               && !string.IsNullOrWhiteSpace(_sqlSettings.Database);
    }
}
