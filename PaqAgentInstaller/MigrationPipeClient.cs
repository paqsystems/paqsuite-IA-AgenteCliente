using System.IO.Pipes;
using System.Text;
using System.Text.Json;

namespace PaqAgentInstaller;

/// <summary>
/// Cliente named pipe para comunicarse con MigrationPipeService del agente.
/// Una instancia por operación (no reutilizar entre llamadas).
/// </summary>
public class MigrationPipeClient
{
    private const int ConnectTimeoutMs = 3_000;

    private readonly string _pipeName;

    public MigrationPipeClient(string agentId, string pipeBaseName = "paqagent-migrations")
    {
        _pipeName = $"{pipeBaseName}-{agentId}";
    }

    /// <summary>
    /// Consulta el estado de migraciones sin ejecutar nada.
    /// Retorna null si no puede conectar (agente detenido o pipe no disponible).
    /// </summary>
    public async Task<MigrationStatusResponse?> GetStatusAsync(
        CancellationToken cancellationToken = default)
    {
        return await SendCommandAsync<MigrationStatusResponse>(
            "{\"command\":\"status\"}", cancellationToken);
    }

    /// <summary>
    /// Dispara la ejecución de migraciones pendientes en el agente.
    /// Retorna null si no puede conectar.
    /// </summary>
    public async Task<MigrationRunResponse?> RunAsync(
        CancellationToken cancellationToken = default)
    {
        return await SendCommandAsync<MigrationRunResponse>(
            "{\"command\":\"run\"}", cancellationToken);
    }

    private async Task<T?> SendCommandAsync<T>(
        string commandJson,
        CancellationToken cancellationToken) where T : class
    {
        using var pipeClient = new NamedPipeClientStream(
            ".",           // servidor local
            _pipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous);

        try
        {
            await pipeClient.ConnectAsync(ConnectTimeoutMs, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (TimeoutException) { return null; }
        catch (Exception) { return null; }

        // Timeout total de la operación: 5 minutos
        using var timeoutCts = CancellationTokenSource
            .CreateLinkedTokenSource(cancellationToken);
        timeoutCts.CancelAfter(TimeSpan.FromMinutes(5));

        await using var writer = new StreamWriter(pipeClient, Encoding.UTF8, leaveOpen: true)
        {
            AutoFlush = true
        };

        await writer.WriteLineAsync(commandJson.AsMemory(), timeoutCts.Token)
            .ConfigureAwait(false);
        await writer.FlushAsync(timeoutCts.Token)
            .ConfigureAwait(false);

        using var reader = new StreamReader(pipeClient, Encoding.UTF8, bufferSize: 1, leaveOpen: true);

        string? responseLine;
        try
        {
            responseLine = await reader.ReadLineAsync(timeoutCts.Token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // Fue nuestro timeout de 5 min, no una cancelación externa
            const string message =
                "El agente no respondió en el tiempo esperado (5 min). Las migraciones pueden estar tardando — reintentá en unos segundos.";
            if (typeof(T) == typeof(MigrationStatusResponse))
                return (T)(object)new MigrationStatusResponse(false, message, []);
            if (typeof(T) == typeof(MigrationRunResponse))
                return (T)(object)new MigrationRunResponse(false, message, []);
            return null;
        }

        if (string.IsNullOrWhiteSpace(responseLine))
            return null;

        return JsonSerializer.Deserialize<T>(responseLine,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }
}

// DTOs espejo de PaqAgent.Models (copiados para no referenciar el proyecto del agente)

public record DatabaseMigrationStatus(
    string DatabaseName,
    string DatabaseType,
    int Applied,
    int Pending,
    IReadOnlyList<string> PendingNames,
    string? Error
);

public record MigrationStatusResponse(
    bool Success,
    string? Error,
    IReadOnlyList<DatabaseMigrationStatus> Databases
);

public record DatabaseMigrationResult(
    string DatabaseName,
    string DatabaseType,
    int Applied,
    int Skipped,
    int Failed,
    IReadOnlyList<string> AppliedNames,
    IReadOnlyList<string> FailedNames,
    string? Error
);

public record MigrationRunResponse(
    bool Success,
    string? Error,
    IReadOnlyList<DatabaseMigrationResult> Databases
);
