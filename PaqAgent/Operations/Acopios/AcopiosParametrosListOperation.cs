using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosParametrosListOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.Parametros.List";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosParametrosListOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosParametrosListOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosParametrosListOperation> logger)
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

        _logger.LogInformation("Ejecutando {Operation}", OperationName);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            new Dictionary<string, object?>(),
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        // RS0: total_filas (consumido por consistencia dual-RS; sin paginación)
        _ = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();

        var filas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var parametros = filas.Select(MapParametro).ToList();

        return new Dictionary<string, object?>
        {
            ["parametros"] = parametros,
        };
    }

    private static Dictionary<string, object?> MapParametro(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["Clave"] = GetString(keyed, "Clave") ?? string.Empty,
            ["TipoValor"] = GetString(keyed, "Tipo_Valor") ?? GetString(keyed, "TipoValor"),
            ["ValorBool"] = GetBool(keyed, "Valor_Bool") ?? GetBool(keyed, "ValorBool"),
            ["ValorInt"] = GetInt(keyed, "Valor_Int") ?? GetInt(keyed, "ValorInt"),
            ["ValorDecimal"] = GetDecimal(keyed, "Valor_Decimal") ?? GetDecimal(keyed, "ValorDecimal"),
            ["ValorString"] = GetString(keyed, "Valor_String") ?? GetString(keyed, "ValorString"),
            ["ValorDateTime"] = GetDateTime(keyed, "Valor_DateTime") ?? GetDateTime(keyed, "ValorDateTime"),
            ["ValorText"] = GetString(keyed, "Valor_Text") ?? GetString(keyed, "ValorText"),
        };
    }

    private static string? GetString(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        return value.ToString();
    }

    private static bool? GetBool(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        if (value is bool b)
            return b;
        if (bool.TryParse(value.ToString(), out var parsed))
            return parsed;
        if (int.TryParse(value.ToString(), out var asInt))
            return asInt != 0;
        return null;
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

    private static decimal? GetDecimal(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        if (value is decimal d)
            return d;
        if (decimal.TryParse(value.ToString(), out var parsed))
            return parsed;
        return null;
    }

    private static DateTime? GetDateTime(Dictionary<string, object?> row, string key)
    {
        if (!row.TryGetValue(key, out var value) || value is null || value is DBNull)
            return null;
        if (value is DateTime dt)
            return dt;
        if (DateTime.TryParse(value.ToString(), out var parsed))
            return parsed;
        return null;
    }
}
