using System.Text.Json;
using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations;

internal class VentasListadoSaldosOperation : IOperationHandler
{
    public const string OperationKey = "informes.ventas-listado-saldos";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<VentasListadoSaldosOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public VentasListadoSaldosOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<VentasListadoSaldosOperation> logger)
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
                    $"La operacion '{OperationName}' requiere el parametro '{DatabaseParameterName}' " +
                    "con el nombre de la base operativa de la empresa.");
            }

            databaseOverride = databaseValue.ToString()!.Trim();
            parameters = new Dictionary<string, object?>(parameters, StringComparer.OrdinalIgnoreCase);
            parameters.Remove(DatabaseParameterName);
        }

        var page = GetInt(parameters, "page", 1);
        var pageSize = GetInt(parameters, "page_size", 200);

        var spParams = new Dictionary<string, object?>
        {
            ["fecha_referencia"] = GetString(parameters, "fecha_referencia"),
            ["ignorar_saldo_cero"] = GetBit(parameters, "ignorar_saldo_cero", false),
            ["cod_client"] = GetString(parameters, "cod_client"),
            ["vendedor"] = GetString(parameters, "vendedor"),
            ["zona"] = GetString(parameters, "zona"),
            ["rubro"] = GetString(parameters, "rubro"),
            ["provincia"] = GetString(parameters, "provincia"),
            ["empresa"] = GetString(parameters, "empresa"),
            ["page"] = page,
            ["page_size"] = pageSize,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} pagina {Page} tamano {PageSize}",
            OperationName,
            page,
            pageSize);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var totalesRow = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        var totalFilas = totalesRow != null && totalesRow.TryGetValue("total_filas", out var tf)
            ? Convert.ToInt32(tf)
            : 0;
        var totalGeneral = totalesRow != null && totalesRow.TryGetValue("total_general", out var tg)
            ? Convert.ToDecimal(tg ?? 0m)
            : 0m;

        var filas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();

        return new Dictionary<string, object?>
        {
            ["total_filas"] = totalFilas,
            ["total_general"] = totalGeneral,
            ["page"] = page,
            ["page_size"] = pageSize,
            ["filas"] = filas,
        };
    }

    private static int GetInt(IReadOnlyDictionary<string, object?> parameters, string key, int defaultValue)
    {
        if (!parameters.TryGetValue(key, out var value) || value is null)
            return defaultValue;

        if (value is JsonElement element)
        {
            return element.ValueKind switch
            {
                JsonValueKind.Number when element.TryGetInt32(out var i) => i,
                JsonValueKind.String when int.TryParse(element.GetString(), out var parsed) => parsed,
                _ => defaultValue
            };
        }

        return Convert.ToInt32(value);
    }

    private static bool GetBit(IReadOnlyDictionary<string, object?> parameters, string key, bool defaultValue)
    {
        if (!parameters.TryGetValue(key, out var value) || value is null)
            return defaultValue;

        if (value is JsonElement element)
        {
            return element.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.Number => element.TryGetInt32(out var n) && n != 0,
                JsonValueKind.String when bool.TryParse(element.GetString(), out var b) => b,
                JsonValueKind.String when int.TryParse(element.GetString(), out var i) => i != 0,
                _ => defaultValue
            };
        }

        if (value is bool boolValue)
            return boolValue;

        return Convert.ToInt32(value) != 0;
    }

    private static string? GetString(IReadOnlyDictionary<string, object?> parameters, string key)
    {
        if (!parameters.TryGetValue(key, out var value) || value is null)
            return null;

        if (value is JsonElement element)
        {
            return element.ValueKind == JsonValueKind.String
                ? element.GetString()
                : element.ToString();
        }

        return value.ToString();
    }
}
