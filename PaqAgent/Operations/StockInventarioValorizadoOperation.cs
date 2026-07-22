using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations;

internal class StockInventarioValorizadoOperation : IOperationHandler
{
    public const string OperationKey = "informes.stock-inventario-valorizado";
    private const string DatabaseParameterName = "_database";
    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<StockInventarioValorizadoOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;
    public string OperationName { get; }

    public StockInventarioValorizadoOperation(string operationName, string storedProcedure, string connection,
        ISqlExecutor sqlExecutor, ILogger<StockInventarioValorizadoOperation> logger)
    {
        OperationName = operationName;
        _storedProcedure = storedProcedure;
        _requiresCompanyDatabase = string.Equals(connection, "company", StringComparison.OrdinalIgnoreCase);
        _sqlExecutor = sqlExecutor;
        _logger = logger;
    }

    public async Task<object?> ExecuteAsync(Dictionary<string, object?> parameters, int timeoutSeconds, CancellationToken cancellationToken)
    {
        string? databaseOverride = null;
        if (_requiresCompanyDatabase)
        {
            if (!parameters.TryGetValue(DatabaseParameterName, out var databaseValue)
                || databaseValue is null || string.IsNullOrWhiteSpace(databaseValue.ToString()))
                throw new InvalidOperationException($"La operacion '{OperationName}' requiere el parametro '{DatabaseParameterName}'.");
            databaseOverride = databaseValue.ToString()!.Trim();
            parameters = new Dictionary<string, object?>(parameters, StringComparer.OrdinalIgnoreCase);
            parameters.Remove(DatabaseParameterName);
        }
        var page = GetInt(parameters, "page", 1);
        var pageSize = GetInt(parameters, "page_size", 200);
        var ignorarSaldoCero = GetBool(parameters, "ignorar_saldo_cero", true);
        var spParams = new Dictionary<string, object?>
        {
            ["fecha_referencia"] = GetString(parameters, "fecha_referencia"),
            ["ignorar_saldo_cero"] = ignorarSaldoCero,
            ["cod_articu"] = GetString(parameters, "cod_articu"),
            ["cod_deposi"] = GetString(parameters, "cod_deposi"),
            ["empresa"] = GetString(parameters, "empresa"),
            ["page"] = page,
            ["page_size"] = pageSize,
        };
        _logger.LogInformation("Ejecutando {Operation} pagina {Page} tamano {PageSize}", OperationName, page, pageSize);
        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(_storedProcedure, spParams, timeoutSeconds, databaseOverride, cancellationToken);
        var totalesRow = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        var totalFilas = totalesRow != null && totalesRow.TryGetValue("total_filas", out var tf) ? Convert.ToInt32(tf) : 0;
        var filas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        return new Dictionary<string, object?> { ["total_filas"] = totalFilas, ["page"] = page, ["page_size"] = pageSize, ["filas"] = filas };
    }

    private static int GetInt(Dictionary<string, object?> p, string key, int def)
        => p.TryGetValue(key, out var v) && v is not null && int.TryParse(v.ToString(), out var i) ? i : def;
    private static bool GetBool(Dictionary<string, object?> p, string key, bool def)
        => p.TryGetValue(key, out var v) && v is not null && bool.TryParse(v.ToString(), out var b) ? b : def;
    private static string? GetString(Dictionary<string, object?> p, string key)
        => p.TryGetValue(key, out var v) && v is not null ? v.ToString() : null;
}
