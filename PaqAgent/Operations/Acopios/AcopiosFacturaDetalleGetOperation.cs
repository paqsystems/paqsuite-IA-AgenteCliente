using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosFacturaDetalleGetOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.FacturaDetalle.Get";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosFacturaDetalleGetOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosFacturaDetalleGetOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosFacturaDetalleGetOperation> logger)
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

        var tComp = GetString(parameters, "t_comp");
        if (string.IsNullOrWhiteSpace(tComp))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 't_comp'.");

        var nComp = GetString(parameters, "n_comp");
        if (string.IsNullOrWhiteSpace(nComp))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'n_comp'.");

        var prefijo = GetString(parameters, "prefijo_articulo");
        if (string.IsNullOrWhiteSpace(prefijo))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'prefijo_articulo'.");

        var dictionaryDb = GetString(parameters, "dictionary_db");
        if (string.IsNullOrWhiteSpace(dictionaryDb))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'dictionary_db'.");

        var grupoId = GetInt(parameters, "grupo_id");
        if (grupoId is null || grupoId <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'grupo_id' > 0.");

        var empresaBd = GetString(parameters, "empresa_bd");

        var spParams = new Dictionary<string, object?>
        {
            ["t_comp"] = tComp,
            ["n_comp"] = nComp,
            ["prefijo_articulo"] = prefijo,
            ["dictionary_db"] = dictionaryDb,
            ["grupo_id"] = grupoId.Value,
            ["empresa_bd"] = string.IsNullOrWhiteSpace(empresaBd) ? null : empresaBd,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} {TComp} {NComp} grupo {GrupoId}",
            OperationName,
            tComp,
            nComp,
            grupoId.Value);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var cabeceraRow = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        if (cabeceraRow is null)
            return null;

        var keyed = new Dictionary<string, object?>(cabeceraRow, StringComparer.OrdinalIgnoreCase);
        var importeGravado = GetDecimal(keyed, "importeGravado") ?? 0m;
        var importeExento = GetDecimal(keyed, "importeExento") ?? 0m;
        var importeImpuestos = GetDecimal(keyed, "importeImpuestos") ?? 0m;
        var importeTotal = GetDecimal(keyed, "importeTotal") ?? 0m;

        var importeNeto = importeGravado + importeExento;
        if (importeNeto <= 0m)
            importeNeto = Math.Max(0m, importeTotal - importeImpuestos);

        var renglonesRs = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var detalle = renglonesRs.Select(MapRenglon).ToList();

        return new Dictionary<string, object?>
        {
            ["EmpresaBd"] = GetString(keyed, "empresaBd") ?? string.Empty,
            ["EmpresaOrigen"] = GetString(keyed, "empresaOrigen"),
            ["TComp"] = GetString(keyed, "tComp") ?? string.Empty,
            ["NComp"] = GetString(keyed, "nComp") ?? string.Empty,
            ["CodClient"] = GetString(keyed, "codClient") ?? string.Empty,
            ["RazonSocial"] = GetString(keyed, "razonSocial"),
            ["FechaEmision"] = GetDateTime(keyed, "fechaEmision"),
            ["ImporteGravado"] = importeGravado,
            ["ImporteExento"] = importeExento,
            ["ImporteImpuestos"] = importeImpuestos,
            ["ImporteTotal"] = importeTotal,
            ["ImporteNeto"] = importeNeto,
            ["Estado"] = GetString(keyed, "estado"),
            ["Detalle"] = detalle,
        };
    }

    private static Dictionary<string, object?> MapRenglon(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);

        return new Dictionary<string, object?>
        {
            ["CodArticu"] = GetString(keyed, "codArticu") ?? string.Empty,
            ["Cantidad"] = GetDecimal(keyed, "cantidad") ?? 0m,
            ["PrecioNeto"] = GetDecimal(keyed, "precioNeto"),
            ["ImporteNeto"] = GetDecimal(keyed, "importeNeto") ?? 0m,
            ["Descuento"] = GetDecimal(keyed, "descuento"),
            ["PorcIva"] = GetDecimal(keyed, "porcIva"),
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
