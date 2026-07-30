using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.PartesProduccion;

internal class PartesProduccionInformesGestionOperation : IOperationHandler
{
    public const string OperationKey = "PartesProduccion.InformesGestion.List";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<PartesProduccionInformesGestionOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public PartesProduccionInformesGestionOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<PartesProduccionInformesGestionOperation> logger)
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
            ["FechaDesde"] = NullIfWhiteSpace(GetString(parameters, "fecha_desde")),
            ["FechaHasta"] = NullIfWhiteSpace(GetString(parameters, "fecha_hasta")),
            ["IdTurno"] = NullIfWhiteSpace(GetString(parameters, "id_turno")),
            ["IdOperario"] = NullIfWhiteSpace(GetString(parameters, "id_operario")),
            ["IdAsignacion"] = NullIfWhiteSpace(GetString(parameters, "id_asignacion")),
            ["IdOrdenTrabajo"] = NullIfWhiteSpace(GetString(parameters, "id_orden_trabajo")),
        };

        _logger.LogInformation("Ejecutando {Operation}", OperationName);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        // RS0: total_filas (consistencia multi-RS; sin paginación)
        _ = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();

        var filas = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var items = filas.Select(MapItem).ToList();

        var resumenRow = resultSets.ElementAtOrDefault(2)?.FirstOrDefault();
        var resumen = MapResumen(resumenRow);

        return new Dictionary<string, object?>
        {
            ["items"] = items,
            ["resumen"] = resumen,
        };
    }

    private static Dictionary<string, object?> MapItem(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["id_parte_entrada"] = GetInt(keyed, "id_parte_entrada"),
            ["fecha"] = GetDateTime(keyed, "fecha_parte"),
            ["id_turno"] = GetInt(keyed, "id_turno"),
            ["turno_codigo"] = GetString(keyed, "turno_codigo"),
            ["id_operario"] = GetInt(keyed, "id_operario"),
            ["operario_nombre"] = GetString(keyed, "operario_nombre"),
            ["id_orden_trabajo"] = GetInt(keyed, "id_orden_trabajo"),
            ["codigo_ot"] = GetString(keyed, "codigo_ot"),
            ["id_articulo"] = GetInt(keyed, "id_articulo"),
            ["id_operacion"] = GetInt(keyed, "id_operacion"),
            ["operacion_codigo"] = GetString(keyed, "operacion_codigo"),
            ["id_maquina"] = GetInt(keyed, "id_maquina"),
            ["maquina_codigo"] = GetString(keyed, "maquina_codigo"),
            ["unidad_negocio"] = GetString(keyed, "unidad_negocio"),
            ["id_tipo_tarea"] = GetInt(keyed, "id_tipo_tarea"),
            ["id_concepto_tiempo"] = GetInt(keyed, "id_concepto_tiempo"),
            ["concepto_codigo"] = GetString(keyed, "concepto_codigo"),
            ["productive_minutes"] = GetInt(keyed, "productive_minutes") ?? 0,
            ["non_productive_minutes"] = GetInt(keyed, "non_productive_minutes") ?? 0,
            ["units_done"] = GetDecimal(keyed, "units_done"),
            ["std_units_per_hour"] = GetDecimal(keyed, "std_units_per_hour"),
            ["theoretical_units"] = GetDecimal(keyed, "theoretical_units"),
            ["efficiency_pct"] = GetDecimal(keyed, "efficiency_pct"),
        };
    }

    private static Dictionary<string, object?> MapResumen(Dictionary<string, object?>? row)
    {
        if (row is null)
        {
            return new Dictionary<string, object?>
            {
                ["productive_minutes"] = 0,
                ["non_productive_minutes"] = 0,
                ["theoretical_units"] = 0m,
                ["efficiency_pct"] = null,
            };
        }

        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);
        var productive = GetInt(keyed, "total_productive_minutes") ?? 0;
        var nonProductive = GetInt(keyed, "total_non_productive_minutes") ?? 0;
        var theoretical = GetDecimal(keyed, "total_theoretical_units") ?? 0m;
        var unitsDone = GetDecimal(keyed, "total_units_done");

        decimal? efficiencyPct = null;
        if (theoretical > 0m && unitsDone is not null)
            efficiencyPct = Math.Round(unitsDone.Value / theoretical * 100m, 2);

        return new Dictionary<string, object?>
        {
            ["productive_minutes"] = productive,
            ["non_productive_minutes"] = nonProductive,
            ["theoretical_units"] = theoretical,
            ["efficiency_pct"] = efficiencyPct,
        };
    }

    private static string? NullIfWhiteSpace(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

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
        if (value is long l)
            return (int)l;
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
        if (value is double dbl)
            return (decimal)dbl;
        if (value is float f)
            return (decimal)f;
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
