using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosSaldosListOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.Saldos.List";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosSaldosListOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosSaldosListOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosSaldosListOperation> logger)
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

        var spParams = new Dictionary<string, object?>
        {
            ["cliente"] = GetString(parameters, "cliente"),
            ["fecha_desde"] = GetString(parameters, "fecha_desde"),
            ["fecha_hasta"] = GetString(parameters, "fecha_hasta"),
            ["comprobante"] = GetString(parameters, "comprobante"),
        };

        _logger.LogInformation("Ejecutando {Operation}", OperationName);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var totalesRow = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        var total = totalesRow != null && totalesRow.TryGetValue("total_filas", out var tf) && tf is not null
            ? Convert.ToInt32(tf)
            : 0;

        var filas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var items = filas.Select(MapSaldo).ToList();

        return new Dictionary<string, object?>
        {
            ["items"] = items,
            ["total"] = total,
        };
    }

    private static Dictionary<string, object?> MapSaldo(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["Id"] = GetInt(keyed, "id") ?? 0,
            ["TComp"] = GetString(keyed, "tComp") ?? string.Empty,
            ["NComp"] = GetString(keyed, "nComp") ?? string.Empty,
            ["CodClient"] = GetString(keyed, "codClient") ?? string.Empty,
            ["RazonSocial"] = GetString(keyed, "razonSocial"),
            ["FechaVigencia"] = GetDateTime(keyed, "fechaVigencia"),
            ["ListaPreciosId"] = GetInt(keyed, "listaPreciosId"),
            ["ListaPreciosNumero"] = GetString(keyed, "listaPreciosNumero"),
            ["ListaPreciosNombre"] = GetString(keyed, "listaPreciosNombre"),
            ["Descuento"] = GetDecimal(keyed, "descuento") ?? 0m,
            ["ImporteNeto"] = GetDecimal(keyed, "importeNeto") ?? 0m,
            ["ImporteImpuestos"] = GetDecimal(keyed, "importeImpuestos") ?? 0m,
            ["ImporteTotal"] = GetDecimal(keyed, "importeTotal") ?? 0m,
            ["FechaUmoAcopio"] = GetDateTime(keyed, "fechaUmoAcopio"),
            ["SaldoAnterior"] = GetDecimal(keyed, "saldoAnterior") ?? 0m,
            ["Estado"] = GetInt(keyed, "estado") ?? 0,
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
