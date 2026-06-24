using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Database;
using PaqAgent.Models;

namespace PaqAgent.Operations;

public class AuthLoginOperation
{
    public const string OperationName = "auth.login";

    private const string StatusOk = "OK";
    private const string StatusNotFound = "NOT_FOUND";
    private const string StatusInactive = "INACTIVE";
    private const string StatusNoEmpresas = "NO_EMPRESAS";
    private const string StatusSqlError = "SQL_ERROR";

    private readonly ISqlExecutor _sqlExecutor;
    private readonly OperationSettings _settings;
    private readonly ILogger<AuthLoginOperation> _logger;

    public AuthLoginOperation(
        ISqlExecutor sqlExecutor,
        IOptions<OperationSettings> settings,
        ILogger<AuthLoginOperation> logger)
    {
        _sqlExecutor = sqlExecutor;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<AuthLoginOperationResult> ExecuteAsync(
        Dictionary<string, object?> parameters,
        int timeoutSeconds,
        CancellationToken cancellationToken = default)
    {
        if (!_settings.Definitions.TryGetValue(OperationName, out var definition)
            || !definition.Enabled
            || string.IsNullOrWhiteSpace(definition.StoredProcedure))
        {
            return AuthLoginOperationResult.Failure(
                ErrorCodes.OperationNotAllowed,
                "La operacion auth.login no esta habilitada o no esta configurada.");
        }

        var mapped = SqlParameterMapper.MapParameters(parameters, definition.Parameters);
        if (!mapped.TryGetValue("codigo", out var codigo) || codigo is null || string.IsNullOrWhiteSpace(codigo.ToString()))
        {
            return AuthLoginOperationResult.Failure(
                ErrorCodes.InvalidParameters,
                "El parametro codigo es obligatorio.");
        }

        var effectiveTimeout = definition.TimeoutSeconds > 0 ? definition.TimeoutSeconds : timeoutSeconds;

        _logger.LogInformation("Ejecutando auth.login para codigo de usuario (hash no se registra en logs)");

        var resultSets = await _sqlExecutor.ExecuteStoredProcedureMultiResultAsync(
            definition.StoredProcedure,
            mapped,
            effectiveTimeout,
            cancellationToken);

        if (resultSets.Count == 0 || resultSets[0].Count == 0)
        {
            return AuthLoginOperationResult.Failure(
                ErrorCodes.SqlError,
                "El procedimiento de login no devolvio datos.");
        }

        var header = resultSets[0][0];
        var status = GetString(header, "status") ?? string.Empty;

        return status.ToUpperInvariant() switch
        {
            StatusOk => BuildSuccessPayload(header, resultSets),
            StatusNotFound => AuthLoginOperationResult.Failure(
                ErrorCodes.AuthNotFound,
                "Credenciales invalidas."),
            StatusInactive => AuthLoginOperationResult.Failure(
                ErrorCodes.AuthInactive,
                "Usuario inactivo."),
            StatusNoEmpresas => AuthLoginOperationResult.Failure(
                ErrorCodes.AuthNoEmpresas,
                "No tiene empresas asignadas. Contacte al administrador."),
            StatusSqlError => AuthLoginOperationResult.Failure(
                ErrorCodes.SqlError,
                GetString(header, "error_message") ?? "Error interno al procesar la solicitud de autenticacion."),
            _ => AuthLoginOperationResult.Failure(
                ErrorCodes.InternalError,
                $"Estado de login no reconocido: {status}")
        };
    }

    private static AuthLoginOperationResult BuildSuccessPayload(
        IReadOnlyDictionary<string, object?> header,
        IReadOnlyList<IReadOnlyList<Dictionary<string, object?>>> resultSets)
    {
        var empresas = resultSets.Count > 1
            ? resultSets[1].Select(MapEmpresaRow).ToList()
            : new List<Dictionary<string, object?>>();

        var payload = new Dictionary<string, object?>
        {
            ["status"] = StatusOk,
            ["user"] = new Dictionary<string, object?>
            {
                ["id"] = header.GetValueOrDefault("user_id"),
                ["codigo"] = GetString(header, "codigo"),
                ["name_user"] = GetString(header, "name_user"),
                ["email"] = GetString(header, "email"),
                ["password_hash"] = GetString(header, "password_hash"),
                ["locale"] = GetString(header, "locale") ?? "es",
                ["menu_abrir_nueva_pestana"] = ToBool(header.GetValueOrDefault("menu_abrir_nueva_pestana")),
                ["sidebar_collapsed"] = ToBool(header.GetValueOrDefault("sidebar_collapsed"))
            },
            ["es_admin"] = ToBool(header.GetValueOrDefault("es_admin")),
            ["redirectTo"] = GetString(header, "redirectTo"),
            ["empresas"] = empresas,
            ["error_message"] = null
        };

        return AuthLoginOperationResult.Success(payload);
    }

    private static Dictionary<string, object?> MapEmpresaRow(IReadOnlyDictionary<string, object?> row) =>
        new()
        {
            ["id"] = row.GetValueOrDefault("id"),
            ["nombreEmpresa"] = GetString(row, "nombreEmpresa"),
            ["nombreBd"] = GetString(row, "nombreBd"),
            ["theme"] = GetString(row, "theme") ?? "default",
            ["imagen"] = GetString(row, "imagen")
        };

    private static string? GetString(IReadOnlyDictionary<string, object?> row, string key) =>
        row.TryGetValue(key, out var value) ? value?.ToString() : null;

    private static bool ToBool(object? value) => value switch
    {
        bool b => b,
        byte or sbyte or short or ushort or int or uint or long or ulong => Convert.ToInt64(value) != 0,
        _ => false
    };
}

public sealed class AuthLoginOperationResult
{
    public bool IsSuccess { get; init; }
    public object? Data { get; init; }
    public string? ErrorCode { get; init; }
    public string? ErrorMessage { get; init; }

    public static AuthLoginOperationResult Success(object data) =>
        new() { IsSuccess = true, Data = data };

    public static AuthLoginOperationResult Failure(string errorCode, string errorMessage) =>
        new() { IsSuccess = false, ErrorCode = errorCode, ErrorMessage = errorMessage };
}
