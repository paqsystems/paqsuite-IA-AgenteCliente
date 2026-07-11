using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using PaqAgent.Database;

namespace PaqAgent.Operations;

internal class AuthSessionOperation : IOperationHandler
{
    public const string OperationKey = "auth.session";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly ILogger<AuthSessionOperation> _logger;
    private readonly string _storedProcedure;

    public string OperationName { get; }

    public AuthSessionOperation(
        string operationName,
        string storedProcedure,
        ISqlExecutor sqlExecutor,
        ILogger<AuthSessionOperation> logger)
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
        var token = GetString(parameters, "token");
        if (string.IsNullOrWhiteSpace(token))
        {
            _logger.LogInformation("Ejecutando {Operation} sin token", OperationName);
            return NotFound();
        }

        var pipeIndex = token.IndexOf('|');
        if (pipeIndex <= 0 || pipeIndex >= token.Length - 1)
        {
            _logger.LogInformation("Ejecutando {Operation} con formato de token invalido", OperationName);
            return NotFound();
        }

        var tokenIdPart = token[..pipeIndex];
        var plaintext = token[(pipeIndex + 1)..];

        if (!int.TryParse(tokenIdPart, out var tokenId) || tokenId <= 0 || string.IsNullOrEmpty(plaintext))
        {
            _logger.LogInformation("Ejecutando {Operation} con token_id invalido", OperationName);
            return NotFound();
        }

        var tokenHash = ComputeSha256Hex(plaintext);

        _logger.LogInformation(
            "Ejecutando {Operation} para token_id {TokenId} (hash no se registra en logs)",
            OperationName,
            tokenId);

        var spParams = new Dictionary<string, object?>
        {
            ["token_id"] = tokenId,
            ["token_hash"] = tokenHash,
        };

        var rows = await _sqlExecutor.ExecuteStoredProcedureAsync(
            _storedProcedure,
            spParams,
            timeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        var row = rows.FirstOrDefault();
        if (row is null)
            return NotFound();

        return new Dictionary<string, object?>
        {
            ["status"] = "OK",
            ["user_id"] = row.GetValueOrDefault("user_id"),
            ["user_code"] = GetString(row, "user_code"),
        };
    }

    private static Dictionary<string, object?> NotFound() =>
        new()
        {
            ["status"] = "NOT_FOUND",
        };

    private static string ComputeSha256Hex(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static string? GetString(IReadOnlyDictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var value) || value is null)
            return null;

        if (value is JsonElement element)
        {
            return element.ValueKind == JsonValueKind.String
                ? element.GetString()
                : element.ToString();
        }

        return value.ToString();
    }
}
