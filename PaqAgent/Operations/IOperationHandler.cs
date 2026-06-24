using PaqAgent.Models;

namespace PaqAgent.Operations;

public interface IOperationHandler
{
    string OperationName { get; }
    Task<object?> ExecuteAsync(Dictionary<string, object?> parameters, int timeoutSeconds, CancellationToken cancellationToken);
}
