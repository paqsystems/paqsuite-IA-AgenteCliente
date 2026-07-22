using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Database;

namespace PaqAgent.Operations;

public class OperationRegistry
{
    private readonly OperationSettings _settings;
    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILoggerFactory _loggerFactory;
    private readonly Dictionary<string, IOperationHandler> _handlers;

    public OperationRegistry(
        IOptions<OperationSettings> settings,
        ISqlExecutor sqlExecutor,
        ILoggerFactory loggerFactory)
    {
        _settings = settings.Value;
        _sqlExecutor = sqlExecutor;
        _loggerFactory = loggerFactory;
        _handlers = BuildHandlers();
    }

    public bool IsAllowed(string operation)
    {
        if (!_settings.Definitions.TryGetValue(operation, out var def) || !def.Enabled)
            return false;

        if (string.Equals(operation, AuthLoginOperation.OperationName, StringComparison.OrdinalIgnoreCase))
            return !string.IsNullOrWhiteSpace(def.StoredProcedure);

        return _handlers.ContainsKey(operation);
    }

    public IReadOnlyCollection<string> GetAllowedOperations() =>
        _handlers.Keys.Where(k => _settings.Definitions[k].Enabled).ToList();

    public async Task<object?> ExecuteAsync(
        string operation,
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        if (!_handlers.TryGetValue(operation, out var handler))
            throw new OperationNotAllowedException(operation);

        return await handler.ExecuteAsync(parameters, timeoutSeconds, cancellationToken);
    }

    private Dictionary<string, IOperationHandler> BuildHandlers()
    {
        var handlers = new Dictionary<string, IOperationHandler>(StringComparer.OrdinalIgnoreCase);

        foreach (var (name, definition) in _settings.Definitions)
        {
            if (string.Equals(name, AuthLoginOperation.OperationName, StringComparison.OrdinalIgnoreCase))
                continue;

            if (string.IsNullOrWhiteSpace(definition.StoredProcedure))
                continue;

            if (string.Equals(name, AuthSessionOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new AuthSessionOperation(
                    name,
                    definition.StoredProcedure,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<AuthSessionOperation>());
                continue;
            }

            if (string.Equals(name, RobinetDeudasOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new RobinetDeudasOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<RobinetDeudasOperation>());
                continue;
            }

            if (string.Equals(name, RobinetPedidosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new RobinetPedidosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<RobinetPedidosOperation>());
                continue;
            }

            if (string.Equals(name, RobinetCobranzasOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new RobinetCobranzasOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<RobinetCobranzasOperation>());
                continue;
            }

            if (string.Equals(name, VentasListadoSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new VentasListadoSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<VentasListadoSaldosOperation>());
                continue;
            }

            if (string.Equals(name, VentasResumenCuentaOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new VentasResumenCuentaOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<VentasResumenCuentaOperation>());
                continue;
            }

            if (string.Equals(name, ComprasResumenCuentaOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new ComprasResumenCuentaOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<ComprasResumenCuentaOperation>());
                continue;
            }

            if (string.Equals(name, VentasIvaVentasOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new VentasIvaVentasOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<VentasIvaVentasOperation>());
                continue;
            }

            if (string.Equals(name, ComprasIvaComprasOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new ComprasIvaComprasOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<ComprasIvaComprasOperation>());
                continue;
            }

            if (string.Equals(name, VentasComposicionSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new VentasComposicionSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<VentasComposicionSaldosOperation>());
                continue;
            }

            if (string.Equals(name, ComprasListadoSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new ComprasListadoSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<ComprasListadoSaldosOperation>());
                continue;
            }

            if (string.Equals(name, ComprasComposicionSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new ComprasComposicionSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<ComprasComposicionSaldosOperation>());
                continue;
            }

            if (string.Equals(name, TesoreriaListadoSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new TesoreriaListadoSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<TesoreriaListadoSaldosOperation>());
                continue;
            }

            if (string.Equals(name, TesoreriaMayorCuentaOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new TesoreriaMayorCuentaOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<TesoreriaMayorCuentaOperation>());
                continue;
            }

            if (string.Equals(name, StockListadoSaldosOperation.OperationKey, StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new StockListadoSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<StockListadoSaldosOperation>());
                continue;
            }

            if (string.Equals(name, StockPartidaListadoSaldosOperation.OperationKey,
                StringComparison.OrdinalIgnoreCase))
            {
                handlers[name] = new StockPartidaListadoSaldosOperation(
                    name,
                    definition.StoredProcedure,
                    definition.Connection,
                    _sqlExecutor,
                    _loggerFactory.CreateLogger<StockPartidaListadoSaldosOperation>());
                continue;
            }

            handlers[name] = new StoredProcedureOperation(
                name,
                definition.StoredProcedure,
                definition.Parameters,
                definition.Connection,
                _sqlExecutor);
        }

        return handlers;
    }
}

public class OperationNotAllowedException : Exception
{
    public string Operation { get; }

    public OperationNotAllowedException(string operation)
        : base($"La operacion '{operation}' no esta permitida o no esta configurada.")
    {
        Operation = operation;
    }
}

internal class StoredProcedureOperation : IOperationHandler
{
    private const string DatabaseParameterName = "_database";

    private readonly string _storedProcedure;
    private readonly List<string> _allowedParameters;
    private readonly bool _isDynamic;
    private readonly ISqlExecutor _sqlExecutor;

    public string OperationName { get; }

    public StoredProcedureOperation(
        string operationName,
        string storedProcedure,
        List<string> allowedParameters,
        string connection,
        ISqlExecutor sqlExecutor)
    {
        OperationName = operationName;
        _storedProcedure = storedProcedure;
        _allowedParameters = allowedParameters;
        _isDynamic = string.Equals(connection, "company", StringComparison.OrdinalIgnoreCase);
        _sqlExecutor = sqlExecutor;
    }

    public async Task<object?> ExecuteAsync(
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        string? databaseOverride = null;

        if (_isDynamic)
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

        var mapped = SqlParameterMapper.MapParameters(parameters, _allowedParameters);
        return await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure,
            mapped,
            timeoutSeconds,
            databaseOverride,
            cancellationToken);
    }
}
