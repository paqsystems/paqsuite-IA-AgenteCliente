using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations;

/**
 * GEN-33 F3 — menú autorizado para snapshot gateway (host TANGO).
 * RS1 header: acceso_total, empresa_id
 * RS2 items: flat parentId (contrato TANGO HU-016)
 */
internal class MenuAuthorizedOperation : IOperationHandler
{
    public const string OperationKey = "menu.authorized";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<MenuAuthorizedOperation> _logger;
    private readonly string _storedProcedure;

    public string OperationName { get; }

    public MenuAuthorizedOperation(
        string operationName,
        string storedProcedure,
        ISqlExecutor sqlExecutor,
        ILogger<MenuAuthorizedOperation> logger)
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
        var userId = ToInt(parameters.GetValueOrDefault("user_id"));
        var empresaId = ToInt(parameters.GetValueOrDefault("empresa_id"));
        if (userId <= 0 || empresaId <= 0)
        {
            throw new InvalidOperationException(
                "menu.authorized requiere parametros user_id y empresa_id.");
        }

        _logger.LogInformation(
            "Ejecutando {Operation} user_id={UserId} empresa_id={EmpresaId}",
            OperationName,
            userId,
            empresaId);

        var spParams = new Dictionary<string, object?>
        {
            ["user_id"] = userId,
            ["empresa_id"] = empresaId,
        };

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        var header = resultSets.ElementAtOrDefault(0)?.FirstOrDefault();
        var accesoTotal = ToBool(header?.GetValueOrDefault("acceso_total"));
        var headerEmpresaId = ToInt(header?.GetValueOrDefault("empresa_id"));
        if (headerEmpresaId > 0)
        {
            empresaId = headerEmpresaId;
        }

        var itemRows = resultSets.ElementAtOrDefault(1) ?? Array.Empty<Dictionary<string, object?>>();
        var items = itemRows.Select(MapItem).ToList();

        var procedimientos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in items)
        {
            if (item.TryGetValue("procedimiento", out var procObj)
                && procObj is string proc
                && !string.IsNullOrWhiteSpace(proc))
            {
                procedimientos.Add(proc.Trim());
            }
        }

        return new Dictionary<string, object?>
        {
            ["empresaId"] = empresaId,
            ["accesoTotal"] = accesoTotal,
            ["items"] = items,
            ["procedimientos"] = procedimientos.ToList(),
        };
    }

    private static Dictionary<string, object?> MapItem(IReadOnlyDictionary<string, object?> row)
    {
        var parentRaw = row.GetValueOrDefault("parentId") ?? row.GetValueOrDefault("parent_id");
        int? parentId = null;
        var parentInt = ToInt(parentRaw);
        if (parentInt > 0)
        {
            parentId = parentInt;
        }

        return new Dictionary<string, object?>
        {
            ["id"] = ToInt(row.GetValueOrDefault("id")),
            ["text"] = GetString(row, "text") ?? string.Empty,
            ["parentId"] = parentId,
            ["orden"] = ToInt(row.GetValueOrDefault("orden") ?? row.GetValueOrDefault("order")),
            ["routeName"] = GetString(row, "routeName") ?? GetString(row, "route_name"),
            ["procedimiento"] = GetString(row, "procedimiento"),
            ["icon_name"] = GetString(row, "icon_name"),
            ["tipo_proceso"] = GetString(row, "tipo_proceso"),
        };
    }

    private static string? GetString(IReadOnlyDictionary<string, object?> row, string key) =>
        row.TryGetValue(key, out var value) ? value?.ToString() : null;

    private static int ToInt(object? value) => value switch
    {
        null => 0,
        int i => i,
        long l => (int)l,
        short s => s,
        byte b => b,
        decimal d => (int)d,
        string s when int.TryParse(s, out var parsed) => parsed,
        _ => int.TryParse(value.ToString(), out var p) ? p : 0,
    };

    private static bool ToBool(object? value) => value switch
    {
        bool b => b,
        byte or sbyte or short or ushort or int or uint or long or ulong => Convert.ToInt64(value) != 0,
        _ => false,
    };
}
