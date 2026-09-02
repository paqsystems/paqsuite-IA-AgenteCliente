using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Database;
using PaqAgent.Models;

namespace PaqAgent.Services;

/// <summary>
/// BackgroundService que expone un named pipe local para que
/// PaqAgentInstaller consulte y dispare migraciones en caliente.
/// Comandos soportados: "status" y "run".
/// El pipe acepta una conexión a la vez (sin cola).
/// Solo accesible desde el mismo host (PipeDirection.InOut, local).
/// </summary>
public class MigrationPipeService : BackgroundService
{
    private readonly ISqlMigrationRunner _migrationRunner;
    private readonly PipeSettings _settings;
    private readonly AgentSettings _agentSettings;
    private readonly ILogger<MigrationPipeService> _logger;

    public MigrationPipeService(
        ISqlMigrationRunner migrationRunner,
        IOptions<PipeSettings> settings,
        IOptions<AgentSettings> agentSettings,
        ILogger<MigrationPipeService> logger)
    {
        _migrationRunner = migrationRunner;
        _settings = settings.Value;
        _agentSettings = agentSettings.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // El nombre del pipe incluye el AgentId para evitar colisiones.
        // Ejemplo: "paqagent-migrations-tecser-agent-01"
        var pipeName = $"{_settings.PipeName}-{_agentSettings.AgentId}";
        _logger.LogInformation("MigrationPipeService iniciado. Pipe: {PipeName}", pipeName);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Crear un nuevo NamedPipeServerStream por ciclo.
                // PipeTransmissionMode.Byte + StreamString funciona cross-process.
                // MaxNumberOfServerInstances=1: una conexión a la vez.
                using var pipeServer = new NamedPipeServerStream(
                    pipeName,
                    PipeDirection.InOut,
                    maxNumberOfServerInstances: 1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);

                _logger.LogDebug("Pipe esperando conexión...");

                await pipeServer.WaitForConnectionAsync(stoppingToken);

                _logger.LogInformation("Instalador conectado al pipe de migraciones.");

                await HandleConnectionAsync(pipeServer, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error en ciclo del pipe de migraciones. Reintentando en 5s.");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }

        _logger.LogInformation("MigrationPipeService detenido.");
    }

    private async Task HandleConnectionAsync(
        NamedPipeServerStream pipe,
        CancellationToken stoppingToken)
    {
        try
        {
            using var reader = new StreamReader(pipe, Encoding.UTF8, leaveOpen: true);
            await using var writer = new StreamWriter(pipe, Encoding.UTF8, leaveOpen: true)
            {
                AutoFlush = true
            };

            // Leer una línea de comando (JSON)
            var line = await reader.ReadLineAsync(stoppingToken);
            if (string.IsNullOrWhiteSpace(line))
            {
                _logger.LogWarning("Pipe recibió línea vacía. Cerrando conexión.");
                return;
            }

            _logger.LogDebug("Pipe recibió comando: {Line}", line);

            // Parsear comando
            string command;
            try
            {
                using var doc = JsonDocument.Parse(line);
                command = doc.RootElement.GetProperty("command").GetString()?.ToLowerInvariant()
                          ?? string.Empty;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Pipe recibió JSON inválido: {Line}", line);
                var errorResponse = new MigrationStatusResponse(
                    false, "JSON inválido en el comando recibido.", []);
                await writer.WriteLineAsync(
                    JsonSerializer.Serialize(errorResponse).AsMemory(), stoppingToken);
                return;
            }

            // Despachar comando
            switch (command)
            {
                case "status":
                    await HandleStatusAsync(writer, stoppingToken);
                    break;

                case "run":
                    await HandleRunAsync(writer, stoppingToken);
                    break;

                default:
                    _logger.LogWarning("Pipe recibió comando desconocido: {Command}", command);
                    var unknownResponse = new MigrationStatusResponse(
                        false, $"Comando desconocido: {command}", []);
                    await writer.WriteLineAsync(
                        JsonSerializer.Serialize(unknownResponse).AsMemory(), stoppingToken);
                    break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al manejar conexión del pipe de migraciones.");
        }
        finally
        {
            if (pipe.IsConnected)
                pipe.Disconnect();
        }
    }

    private async Task HandleStatusAsync(
        StreamWriter writer,
        CancellationToken stoppingToken)
    {
        _logger.LogInformation("Pipe: ejecutando comando 'status'.");
        var response = await _migrationRunner.GetStatusAsync(stoppingToken);
        var json = JsonSerializer.Serialize(response);
        await writer.WriteLineAsync(json.AsMemory(), stoppingToken);
        _logger.LogInformation(
            "Pipe: status respondido. BDs: {Count}, Pendientes totales: {Pending}",
            response.Databases.Count,
            response.Databases.Sum(d => d.Pending));
    }

    private async Task HandleRunAsync(
        StreamWriter writer,
        CancellationToken stoppingToken)
    {
        _logger.LogInformation("Pipe: ejecutando comando 'run'.");
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        cts.CancelAfter(TimeSpan.FromSeconds(_settings.RunTimeoutSeconds));

        var response = await _migrationRunner.RunAndReportAsync(cts.Token);
        var json = JsonSerializer.Serialize(response);
        await writer.WriteLineAsync(json.AsMemory(), stoppingToken);
        _logger.LogInformation(
            "Pipe: run completado. BDs: {Count}, Éxito: {Success}",
            response.Databases.Count,
            response.Success);
    }
}
