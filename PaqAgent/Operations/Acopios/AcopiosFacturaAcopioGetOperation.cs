using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosFacturaAcopioGetOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.FacturaAcopio.Get";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosFacturaAcopioGetOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosFacturaAcopioGetOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosFacturaAcopioGetOperation> logger)
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

        var row = rows.FirstOrDefault();
        if (row is null)
            return null;

        return MapRecord(row);
    }

    private static Dictionary<string, object?> MapRecord(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["Id"] = GetInt(keyed, "id") ?? 0,
            ["TComp"] = GetString(keyed, "tComp") ?? string.Empty,
            ["NComp"] = GetString(keyed, "nComp") ?? string.Empty,
            ["CodClient"] = GetString(keyed, "codClient") ?? string.Empty,
            ["RazonSocial"] = GetString(keyed, "razonSocial"),
            ["FechaVigencia"] = FormatDateYmd(GetDateTime(keyed, "fechaVigencia")),
            ["ListaPreciosId"] = GetInt(keyed, "listaPreciosId") ?? 0,
            ["ListaPreciosNumero"] = GetString(keyed, "listaPreciosNumero"),
            ["ListaPreciosNombre"] = GetString(keyed, "listaPreciosNombre"),
            ["Descuento"] = GetDecimal(keyed, "descuento") ?? 0m,
            ["ImporteNeto"] = GetDecimal(keyed, "importeNeto") ?? 0m,
            ["ImporteImpuestos"] = GetDecimal(keyed, "importeImpuestos") ?? 0m,
            ["ImporteTotal"] = GetDecimal(keyed, "importeTotal") ?? 0m,
            ["FechaUmoAcopio"] = FormatDateIso(GetDateTime(keyed, "fechaUmoAcopio")),
            ["SaldoAnterior"] = GetDecimal(keyed, "saldoAnterior") ?? 0m,
            ["Estado"] = GetInt(keyed, "estado") ?? 0,
        };
    }

    private static string? FormatDateYmd(DateTime? value) =>
        value?.ToString("yyyy-MM-dd");

    private static string? FormatDateIso(DateTime? value) =>
        value?.ToString("yyyy-MM-ddTHH:mm:ss");

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
