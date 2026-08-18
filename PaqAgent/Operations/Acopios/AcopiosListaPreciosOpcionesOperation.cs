using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosListaPreciosOpcionesOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.ListaPrecios.Opciones";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosListaPreciosOpcionesOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosListaPreciosOpcionesOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosListaPreciosOpcionesOperation> logger)
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

        // El SP solo recibe @_database; no hay parámetros de negocio adicionales.
        var spParams = new Dictionary<string, object?>
        {
            ["_database"] = databaseOverride,
        };

        _logger.LogInformation("Ejecutando {Operation}", OperationName);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var totalesRow = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        var totalFilas = 0;
        if (totalesRow is not null)
        {
            var keyed = new Dictionary<string, object?>(totalesRow, StringComparer.OrdinalIgnoreCase);
            totalFilas = GetInt(keyed, "total_filas") ?? 0;
        }

        var filasRs = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var filas = filasRs.Select(MapFila).ToList();

        return new Dictionary<string, object?>
        {
            ["total_filas"] = totalFilas,
            ["filas"] = filas,
        };
    }

    private static Dictionary<string, object?> MapFila(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["Id"] = GetInt(keyed, "id") ?? 0,
            ["Numero"] = GetString(keyed, "numero") ?? string.Empty,
            ["Nombre"] = GetString(keyed, "nombre") ?? string.Empty,
            ["Label"] = GetString(keyed, "label") ?? string.Empty,
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
