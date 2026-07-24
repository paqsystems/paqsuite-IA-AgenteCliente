using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosPedidoDetalleGetOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.PedidoDetalle.Get";
    private const string DatabaseParameterName = "_database";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosPedidoDetalleGetOperation> _logger;
    private readonly string _storedProcedure;
    private readonly bool _requiresCompanyDatabase;

    public string OperationName { get; }

    public AcopiosPedidoDetalleGetOperation(
        string operationName,
        string storedProcedure,
        string connection,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosPedidoDetalleGetOperation> logger)
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

        var talonPed = GetInt(parameters, "talon_ped");
        if (talonPed is null || talonPed <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'talon_ped' > 0.");

        var nroPedido = GetString(parameters, "nro_pedido");
        if (string.IsNullOrWhiteSpace(nroPedido))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'nro_pedido'.");

        var dictionaryDb = GetString(parameters, "dictionary_db");
        if (string.IsNullOrWhiteSpace(dictionaryDb))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'dictionary_db'.");

        var grupoId = GetInt(parameters, "grupo_id");
        if (grupoId is null || grupoId <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'grupo_id' > 0.");

        var empresaId = GetInt(parameters, "empresa_id");
        var empresaBd = GetString(parameters, "empresa_bd");

        var spParams = new Dictionary<string, object?>
        {
            ["talon_ped"] = talonPed.Value,
            ["nro_pedido"] = nroPedido,
            ["dictionary_db"] = dictionaryDb,
            ["grupo_id"] = grupoId.Value,
            ["empresa_id"] = empresaId is > 0 ? empresaId.Value : null,
            ["empresa_bd"] = string.IsNullOrWhiteSpace(empresaBd) ? null : empresaBd,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} talon {Talon} nro {Nro} grupo {GrupoId}",
            OperationName,
            talonPed.Value,
            nroPedido,
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
        var renglonesRs = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var detalle = renglonesRs.Select(MapRenglon).ToList();

        return new Dictionary<string, object?>
        {
            ["EmpresaId"] = GetInt(keyed, "empresaId"),
            ["EmpresaBd"] = GetString(keyed, "empresaBd") ?? string.Empty,
            ["EmpresaOrigen"] = GetString(keyed, "empresaOrigen"),
            ["TalonPed"] = GetInt(keyed, "talonPed"),
            ["NroPedido"] = GetString(keyed, "nroPedido"),
            ["CodClient"] = GetString(keyed, "codClient"),
            ["RazonSocial"] = GetString(keyed, "razonSocial"),
            ["FechaPedido"] = GetDateTime(keyed, "fechaPedido"),
            ["FechaEntrega"] = GetDateTime(keyed, "fechaEntrega"),
            ["TotalPedido"] = GetDecimal(keyed, "totalPedido"),
            ["Estado"] = GetInt(keyed, "estado"),
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
            ["PrecioPedido"] = GetDecimal(keyed, "precioPedido"),
            ["DescuentoPedido"] = GetDecimal(keyed, "descuentoPedido"),
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
