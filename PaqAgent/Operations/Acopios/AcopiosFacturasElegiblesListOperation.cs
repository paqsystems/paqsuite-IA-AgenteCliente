using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosFacturasElegiblesListOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.FacturasElegibles.List";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosFacturasElegiblesListOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosFacturasElegiblesListOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosFacturasElegiblesListOperation> logger)
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

        var prefijo = GetString(parameters, "prefijo_articulo");
        if (string.IsNullOrWhiteSpace(prefijo))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'prefijo_articulo'.");

        var dictionaryDb = GetString(parameters, "dictionary_db");
        if (string.IsNullOrWhiteSpace(dictionaryDb))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'dictionary_db'.");

        var grupoId = GetInt(parameters, "grupo_id");
        if (grupoId is null || grupoId <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'grupo_id' > 0.");

        var spParams = new Dictionary<string, object?>
        {
            ["prefijo_articulo"] = prefijo,
            ["cliente"] = GetString(parameters, "cliente"),
            ["fecha_desde"] = GetString(parameters, "fecha_desde"),
            ["fecha_hasta"] = GetString(parameters, "fecha_hasta"),
            ["dictionary_db"] = dictionaryDb,
            ["grupo_id"] = grupoId.Value,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} grupo {GrupoId} prefijo {Prefijo}",
            OperationName,
            grupoId.Value,
            prefijo);

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
        var facturas = filas.Select(MapFactura).ToList();

        return new Dictionary<string, object?>
        {
            ["facturas"] = facturas,
            ["total"] = total,
        };
    }

    private static Dictionary<string, object?> MapFactura(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["EmpresaBd"] = GetString(keyed, "empresaBd") ?? string.Empty,
            ["TComp"] = GetString(keyed, "tComp") ?? string.Empty,
            ["NComp"] = GetString(keyed, "nComp") ?? string.Empty,
            ["CodClient"] = GetString(keyed, "codClient") ?? string.Empty,
            ["RazonSocial"] = GetString(keyed, "razonSocial"),
            ["FechaEmision"] = GetDateTime(keyed, "fechaEmision"),
            ["ImporteTotal"] = GetDecimal(keyed, "importeTotal") ?? 0m,
            ["Estado"] = GetString(keyed, "estado") ?? string.Empty,
            ["Configurada"] = GetBool(keyed, "configurada") ?? false,
            ["AcopioId"] = GetInt(keyed, "acopioId"),
            ["ListaPreciosId"] = GetInt(keyed, "listaPreciosId"),
            ["FechaVigencia"] = GetDateTime(keyed, "fechaVigencia"),
            ["Descuento"] = GetDecimal(keyed, "descuento"),
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
