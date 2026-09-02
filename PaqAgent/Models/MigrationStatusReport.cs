namespace PaqAgent.Models;

/// <summary>
/// Estado de una base de datos individual respecto a migraciones pendientes.
/// </summary>
public record DatabaseMigrationStatus(
    string DatabaseName,
    string DatabaseType,          // "dictionary" | "company"
    int Applied,
    int Pending,
    IReadOnlyList<string> PendingNames,
    string? Error
);

/// <summary>
/// Respuesta al comando "status" del named pipe.
/// </summary>
public record MigrationStatusResponse(
    bool Success,
    string? Error,
    IReadOnlyList<DatabaseMigrationStatus> Databases
);

/// <summary>
/// Resultado de aplicar migraciones sobre una base de datos individual.
/// </summary>
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

/// <summary>
/// Respuesta al comando "run" del named pipe.
/// </summary>
public record MigrationRunResponse(
    bool Success,
    string? Error,
    IReadOnlyList<DatabaseMigrationResult> Databases
);
