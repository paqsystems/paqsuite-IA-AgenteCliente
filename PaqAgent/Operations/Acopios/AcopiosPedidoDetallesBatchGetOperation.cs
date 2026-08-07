using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations.Acopios;

internal class AcopiosPedidoDetallesBatchGetOperation : IOperationHandler
{
    public const string OperationKey = "Acopios.PedidoDetallesBatch.Get";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AcopiosPedidoDetallesBatchGetOperation> _logger;
    private readonly string _storedProcedure;

    public string OperationName { get; }

    public AcopiosPedidoDetallesBatchGetOperation(
        string operationName,
        string storedProcedure,
        ISqlExecutor sqlExecutor,
        ILogger<AcopiosPedidoDetallesBatchGetOperation> logger)
    {
        OperationName = operationName;
        _storedProcedure = storedProcedure;
        _sqlExecutor = sqlExecutor;
        _logger = logger;
    }

    public async Task<object?> ExecuteAsync(
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        var pedidosXml = GetString(parameters, "pedidos_xml");
        if (string.IsNullOrWhiteSpace(pedidosXml))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'pedidos_xml'.");

        var dictionaryDb = GetString(parameters, "dictionary_db");
        if (string.IsNullOrWhiteSpace(dictionaryDb))
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'dictionary_db'.");

        var grupoId = GetInt(parameters, "grupo_id");
        if (grupoId is null || grupoId <= 0)
            throw new InvalidOperationException($"La operacion '{OperationName}' requiere 'grupo_id' > 0.");

        var spParams = new Dictionary<string, object?>
        {
            ["pedidos_xml"] = pedidosXml,
            ["dictionary_db"] = dictionaryDb,
            ["grupo_id"] = grupoId.Value,
        };

        _logger.LogInformation(
            "Ejecutando {Operation} grupo {GrupoId}",
            OperationName,
            grupoId.Value);

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        var cabecerasRs = resultSets.ElementAtOrDefault(0) ?? Array.Empty<Dictionary<string, object?>>();
        if (cabecerasRs.Count == 0)
            return new List<Dictionary<string, object?>>();

        var renglonesRs = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();

        var renglonesByKey = renglonesRs
            .GroupBy(row => BuildPedidoKey(row), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.OrdinalIgnoreCase);

        var result = new List<Dictionary<string, object?>>(cabecerasRs.Count);

        foreach (var cabeceraRow in cabecerasRs)
        {
            var keyed = new Dictionary<string, object?>(cabeceraRow, StringComparer.OrdinalIgnoreCase);
            var key = BuildPedidoKey(keyed);

            var detalleRows = renglonesByKey.TryGetValue(key, out var matched)
                ? matched
                : new List<Dictionary<string, object?>>();

            var detalle = detalleRows.Select(MapRenglon).ToList();

            result.Add(new Dictionary<string, object?>
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
            });
        }

        return result;
    }

    private static string BuildPedidoKey(Dictionary<string, object?> row)
    {
        var keyed = new Dictionary<string, object?>(row, StringComparer.OrdinalIgnoreCase);
        var talon = GetInt(keyed, "talonPed")?.ToString() ?? string.Empty;
        var nro = (GetString(keyed, "nroPedido") ?? string.Empty).Trim();
        return $"{talon}|{nro}";
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
