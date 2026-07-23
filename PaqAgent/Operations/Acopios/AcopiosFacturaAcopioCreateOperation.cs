using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosFacturaAcopioCreateOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.FacturaAcopio.Create";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosFacturaAcopioCreateOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosFacturaAcopioCreateOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosFacturaAcopioCreateOperation> logger)
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
        var nComp = GetString(parameters, "n_comp");
        var codClient = GetString(parameters, "cod_client");
        var fechaVigencia = GetString(parameters, "fecha_vigencia");
        var listaPreciosId = GetInt(parameters, "lista_precios_id");
        var descuento = GetDecimal(parameters, "descuento");
        var importeNeto = GetDecimal(parameters, "importe_neto");
        var importeImpuestos = GetDecimal(parameters, "importe_impuestos");
        var importeTotal = GetDecimal(parameters, "importe_total");
        var fechaUmo = GetString(parameters, "fecha_umo_acopio");

        if (string.IsNullOrWhiteSpace(tComp)
            || string.IsNullOrWhiteSpace(nComp)
            || string.IsNullOrWhiteSpace(codClient)
            || string.IsNullOrWhiteSpace(fechaVigencia)
            || listaPreciosId is null
            || descuento is null
            || importeNeto is null
            || importeImpuestos is null
            || importeTotal is null
            || string.IsNullOrWhiteSpace(fechaUmo))
        {
            throw new InvalidOperationException(
                $"La operacion '{OperationName}' requiere t_comp, n_comp, cod_client, fecha_vigencia, lista_precios_id, descuento, importe_neto, importe_impuestos, importe_total, fecha_umo_acopio.");
        }

        var spParams = new Dictionary<string, object?>
        {
            ["t_comp"] = tComp,
            ["n_comp"] = nComp,
            ["cod_client"] = codClient,
            ["fecha_vigencia"] = fechaVigencia,
            ["lista_precios_id"] = listaPreciosId.Value,
            ["descuento"] = descuento.Value,
            ["importe_neto"] = importeNeto.Value,
            ["importe_impuestos"] = importeImpuestos.Value,
            ["importe_total"] = importeTotal.Value,
            ["fecha_umo_acopio"] = fechaUmo,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} {TComp} {NComp}",
            OperationName,
            tComp,
            nComp);

        var rows = await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);

        var row = rows.FirstOrDefault()
            ?? throw new InvalidOperationException("respuestaVacia");

        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);
        var resultCode = GetString(keyed, "resultCode") ?? string.Empty;
        var id = GetInt(keyed, "id");

        if (!string.Equals(resultCode, "OK", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException(resultCode);

        return new Dictionary<string, object?>
        {
            ["resultCode"] = "OK",
            ["id"] = id,
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
}
