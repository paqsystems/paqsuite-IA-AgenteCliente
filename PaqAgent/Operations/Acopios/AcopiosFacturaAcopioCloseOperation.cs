using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosFacturaAcopioCloseOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.FacturaAcopio.Close";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosFacturaAcopioCloseOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosFacturaAcopioCloseOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosFacturaAcopioCloseOperation> logger)
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
        var fechaUmo = GetString(parameters, "fecha_umo_acopio");

        if (id is null || id <= 0 || string.IsNullOrWhiteSpace(fechaUmo))
        {
            throw new InvalidOperationException(
                $"La operacion '{OperationName}' requiere id y fecha_umo_acopio.");
        }

        var spParams = new Dictionary<string, object?>
        {
            ["id"] = id.Value,
            ["fecha_umo_acopio"] = fechaUmo,
        };

        _logger.LogInformation("Ejecutando {Operation} id {Id}", OperationName, id.Value);

        var rows = await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var row = rows.FirstOrDefault()
            ?? throw new InvalidOperationException("respuestaVacia");

        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);
        var resultCode = GetString(keyed, "resultCode") ?? string.Empty;
        var resultId = GetInt(keyed, "id");

        if (!string.Equals(resultCode, "OK", StringComparison.OrdinalIgnoreCase)
            && !string.Equals(resultCode, "yaFinalizado", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(resultCode);
        }

        return new Dictionary<string, object?>
        {
            ["resultCode"] = resultCode,
            ["id"] = resultId,
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
