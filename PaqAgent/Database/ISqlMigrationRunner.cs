using PaqAgent.Models;

namespace PaqAgent.Database;

public interface ISqlMigrationRunner
{
    /// <summary>
    /// Ejecuta todas las migraciones pendientes. Usado al startup.
    /// Lanza excepción si falla; no devuelve resultado estructurado.
    /// </summary>
    Task RunAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Consulta qué migraciones están pendientes SIN ejecutar ninguna.
    /// Seguro para llamar en cualquier momento; solo lectura.
    /// </summary>
    Task<MigrationStatusResponse> GetStatusAsync(
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Ejecuta las migraciones pendientes y devuelve el resultado detallado.
    /// Usado por el named pipe cuando el instalador pide "run".
    /// </summary>
    Task<MigrationRunResponse> RunAndReportAsync(
        CancellationToken cancellationToken = default);
}
