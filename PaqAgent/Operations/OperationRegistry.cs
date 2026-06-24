using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Database;

namespace PaqAgent.Operations;

public class OperationRegistry
{
    private readonly OperationSettings _settings;
    private readonly ISqlExecutor _sqlExecutor;
    private readonly Dictionary<string, StoredProcedureOperation> _handlers;

    public OperationRegistry(IOptions<OperationSettings> settings, ISqlExecutor sqlExecutor)
    {
        _settings = settings.Value;
        _sqlExecutor = sqlExecutor;
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

    private Dictionary<string, StoredProcedureOperation> BuildHandlers()
    {
        var handlers = new Dictionary<string, StoredProcedureOperation>(StringComparer.OrdinalIgnoreCase);

        foreach (var (name, definition) in _settings.Definitions)
        {
            if (string.Equals(name, AuthLoginOperation.OperationName, StringComparison.OrdinalIgnoreCase))
                continue;

            if (string.IsNullOrWhiteSpace(definition.StoredProcedure))
                continue;

            handlers[name] = new StoredProcedureOperation(
                name,
                definition.StoredProcedure,
                definition.Parameters,
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
    private readonly string _storedProcedure;
    private readonly List<string> _allowedParameters;
    private readonly ISqlExecutor _sqlExecutor;

    public string OperationName { get; }

    public StoredProcedureOperation(
        string operationName,
        string storedProcedure,
        List<string> allowedParameters,
        ISqlExecutor sqlExecutor)
    {
        OperationName = operationName;
        _storedProcedure = storedProcedure;
        _allowedParameters = allowedParameters;
        _sqlExecutor = sqlExecutor;
    }

    public async Task<object?> ExecuteAsync(
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        var mapped = SqlParameterMapper.MapParameters(parameters, _allowedParameters);
        return await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure, mapped, timeoutSeconds, cancellationToken);
    }
}
