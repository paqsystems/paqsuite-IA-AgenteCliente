using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosAsociacionDeleteOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.Asociacion.Delete";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosAsociacionDeleteOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosAsociacionDeleteOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosAsociacionDeleteOperation> logger)
    {
        OperationName = operationName;
        _storedProcedure = storedProcedure;
        _requiresCompanyDatabase = string.Equals(connection, "company", StringComparison.OrdinalIgnoreCase);
        _sqlExecutor = sqlExecutor;
        _logger = logger;
    }

    public async Task<object?> ExecuteAsync(
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        string? databaseOverride = null;
        if (_requiresCompanyDatabase)
        {
            if (!parameters.TryGetValue(DatabaseParameterName, out var databaseValue)
                || databaseValue is null
                || string.IsNullOrWhiteSpace(databaseValue.ToString()))
            {
                throw new InvalidOperationException(
                    $"La operacion '{OperationName}' requiere el parametro '{DatabaseParameterName}'.");
            }

            databaseOverride = databaseValue.ToString()!.Trim();
            parameters = new Dictionary<string, object?>(parameters, StringComparer.OrdinalIgnoreCase);
            parameters.Remove(DatabaseParameterName);
        }

        var id = GetInt(parameters, "id");
        if (id is null || id <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'id' > 0.");

        _logger.LogInformation("Ejecutando {Operation} id {Id}", OperationName, id.Value);

        var rows = await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure,
            new Dictionary<string, object?> { ["id"] = id.Value },
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var row = rows.FirstOrDefault()
            ?? throw new InvalidOperationException("respuestaVacia");

        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);
        var resultCode = GetString(keyed, "resultCode") ?? string.Empty;

        if (!string.Equals(resultCode, "OK", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(resultCode);

        return new Dictionary<string, object?>
        {
            ["resultCode"] = "OK",
            ["id"] = GetInt(keyed, "id"),
            ["tComp"] = GetString(keyed, "tComp"),
            ["nComp"] = GetString(keyed, "nComp"),
            ["talonPed"] = GetInt(keyed, "talonPed"),
            ["nroPedido"] = GetString(keyed, "nroPedido"),
        };
    }

    private static string? GetString(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        return value.ToString();
    }

    private static int? GetInt(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        if (value is int i)
            return i;
        if (int.TryParse(value.ToString(), out var parsed))
            return parsed;
        return null;
    }
}
