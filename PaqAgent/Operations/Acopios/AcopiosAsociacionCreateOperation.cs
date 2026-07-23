using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosAsociacionCreateOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.Asociacion.Create";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosAsociacionCreateOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosAsociacionCreateOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosAsociacionCreateOperation> logger)
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
        var talonPed = GetInt(parameters, "talon_ped");
        var nroPedido = GetString(parameters, "nro_pedido");
        var codClientPed = GetString(parameters, "cod_client_ped");
        var dictionaryDb = GetString(parameters, "dictionary_db");
        var grupoId = GetInt(parameters, "grupo_id");
        var renglonesJson = GetString(parameters, "renglones_json");
        var saldoDisponible = GetDecimal(parameters, "saldo_disponible");

        if (string.IsNullOrWhiteSpace(tComp)
            || string.IsNullOrWhiteSpace(nComp)
            || talonPed is null
            || string.IsNullOrWhiteSpace(nroPedido)
            || string.IsNullOrWhiteSpace(codClientPed)
            || string.IsNullOrWhiteSpace(renglonesJson)
            || saldoDisponible is null)
        {
            throw new InvalidOperationException(
                $"La operacion '{OperationName}' requiere t_comp, n_comp, talon_ped, nro_pedido, cod_client_ped, renglones_json, saldo_disponible.");
        }

        var spParams = new Dictionary<string, object?>
        {
            ["t_comp"] = tComp,
            ["n_comp"] = nComp,
            ["talon_ped"] = talonPed.Value,
            ["nro_pedido"] = nroPedido,
            ["cod_client_ped"] = codClientPed,
            ["dictionary_db"] = dictionaryDb,
            ["grupo_id"] = grupoId,
            ["renglones_json"] = renglonesJson,
            ["saldo_disponible"] = saldoDisponible.Value,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} {TComp} {NComp} pedido {Talon}/{Nro}",
            OperationName,
            tComp,
            nComp,
            talonPed.Value,
            nroPedido);

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

        if (!string.Equals(resultCode, "OK", StringComparison.OrdinalIgnoreCase))
        {
            var pedidoCli = GetString(keyed, "pedidoCodClient");
            var acopioCli = GetString(keyed, "acopioCodClient");
            var importe = GetDecimal(keyed, "importeValorizado");
            var saldo = GetDecimal(keyed, "saldoDisponible");

            var detail = resultCode;
            if (string.Equals(resultCode, "clienteIncompatible", StringComparison.OrdinalIgnoreCase))
                detail = $"{resultCode}|pedido={pedidoCli}|acopio={acopioCli}";
            else if (string.Equals(resultCode, "saldoInsuficiente", StringComparison.OrdinalIgnoreCase))
                detail = $"{resultCode}|saldo={saldo}|importe={importe}";

            throw new InvalidOperationException(detail);
        }

        return new Dictionary<string, object?>
        {
            ["resultCode"] = "OK",
            ["id"] = GetInt(keyed, "id"),
            ["importeValorizado"] = GetDecimal(keyed, "importeValorizado"),
            ["saldoDisponible"] = GetDecimal(keyed, "saldoDisponible"),
            ["saldoRestante"] = GetDecimal(keyed, "saldoRestante"),
            ["pedidoCodClient"] = GetString(keyed, "pedidoCodClient"),
            ["acopioCodClient"] = GetString(keyed, "acopioCodClient"),
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
