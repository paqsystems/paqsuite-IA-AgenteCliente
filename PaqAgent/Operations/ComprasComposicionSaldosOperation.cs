using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations;

internal class ComprasComposicionSaldosOperation : IOperationHandler
{
    public const string OperationKey = "informes.compras-composicion-saldos";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<ComprasComposicionSaldosOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public ComprasComposicionSaldosOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<ComprasComposicionSaldosOperation> logger)
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
            ["cod_provee"] = GetString(parameters, "cod_provee"),
            ["empresa"] = GetString(parameters, "empresa"),
            ["sort"] = GetString(parameters, "sort") ?? "fecha_emis",
            ["sort_dir"] = GetString(parameters, "sort_dir") ?? "desc",
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

        var rawFilas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var filas = rawFilas.Select(MapFila).ToList();

        return new Dictionary<string, object?>
        {
            ["total_filas"] = totalFilas,
            ["page"] = page,
            ["page_size"] = pageSize,
            ["filas"] = filas,
        };
    }

    private static Dictionary<string, object?> MapFila(IReadOnlyDictionary<string, object?> row)
    {
        return new Dictionary<string, object?>
        {
            ["cod_provee"] = GetRowString(row, "cod_provee"),
            ["razon_soci"] = GetRowString(row, "razon_soci"),
            ["t_comp"] = GetRowString(row, "t_comp"),
            ["n_comp"] = GetRowString(row, "n_comp"),
            ["fecha_emis"] = FormatDate(row, "fecha_emis"),
            ["fecha_vencimiento"] = FormatDate(row, "fecha_vencimiento"),
            ["importe_cuota"] = GetRowDecimalNullable(row, "importe_cuota"),
            ["saldo_cuota"] = GetRowDecimalNullable(row, "saldo_cuota"),
            ["empresa"] = GetRowString(row, "empresa"),
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

    private static decimal GetDecimal(IReadOnlyDictionary<string, object?> parameters, string key, decimal defaultValue)
    {
        if (!parameters.TryGetValue(key, out var value) || value is null)
            return defaultValue;

        if (value is JsonElement element)
        {
            return element.ValueKind switch
            {
                JsonValueKind.Number when element.TryGetDecimal(out var d) => d,
                JsonValueKind.String when decimal.TryParse(
                    element.GetString(),
                    NumberStyles.Number,
                    CultureInfo.InvariantCulture,
                    out var parsed) => parsed,
                _ => defaultValue
            };
        }

        return Convert.ToDecimal(value, CultureInfo.InvariantCulture);
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

    private static string? GetRowString(IReadOnlyDictionary<string, object?> row, string key)
    {
        if (!TryGetRowValue(row, key, out var value) || value is null || value is DBNull)
            return null;

        return value.ToString();
    }

    private static decimal? GetRowDecimalNullable(IReadOnlyDictionary<string, object?> row, string key)
    {
        if (!TryGetRowValue(row, key, out var value) || value is null || value is DBNull)
            return null;

        return Convert.ToDecimal(value, CultureInfo.InvariantCulture);
    }

    private static string? FormatDate(IReadOnlyDictionary<string, object?> row, string key)
    {
        if (!TryGetRowValue(row, key, out var value) || value is null || value is DBNull)
            return null;

        if (value is DateTime dateTime)
            return dateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        if (value is DateTimeOffset dateTimeOffset)
            return dateTimeOffset.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        if (DateTime.TryParse(
                value.ToString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeLocal,
                out var parsed))
            return parsed.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        return value.ToString();
    }

    private static bool TryGetRowValue(
        IReadOnlyDictionary<string, object?> row,
        string key,
        out object? value)
    {
        if (row.TryGetValue(key, out value))
            return true;

        foreach (var pair in row)
        {
            if (string.Equals(pair.Key, key, StringComparison.OrdinalIgnoreCase))
            {
                value = pair.Value;
                return true;
            }
        }

        value = null;
        return false;
    }
}
