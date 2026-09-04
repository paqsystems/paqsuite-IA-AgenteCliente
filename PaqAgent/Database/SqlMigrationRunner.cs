using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;
using PaqAgent.Models;

namespace PaqAgent.Database;

public class SqlMigrationRunner : ISqlMigrationRunner
{
    private const string EnsureSchemaSql = """
        IF OBJECT_ID(N'dbo.paq_sp_migrations', N'U') IS NULL
        BEGIN
            CREATE TABLE dbo.paq_sp_migrations (
                id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_paq_sp_migrations PRIMARY KEY,
                migration NVARCHAR(150) NOT NULL CONSTRAINT UQ_paq_sp_migrations_migration UNIQUE,
                batch INT NOT NULL CONSTRAINT DF_paq_sp_migrations_batch DEFAULT 1,
                applied_at DATETIME2(3) NOT NULL CONSTRAINT DF_paq_sp_migrations_applied_at DEFAULT SYSUTCDATETIME(),
                checksum_sha256 CHAR(64) NULL
            );
        END
        """;

    private const string AppliedMigrationsSql =
        "SELECT migration + N'|' + ISNULL(checksum_sha256, N'') AS migration FROM dbo.paq_sp_migrations";

    private const string InsertMigrationSql = """
        INSERT INTO dbo.paq_sp_migrations (migration, batch, checksum_sha256)
        VALUES (@migration, @batch, @checksum_sha256)
        """;

    private const string UpdateMigrationSql = """
        UPDATE dbo.paq_sp_migrations
        SET checksum_sha256 = @checksum, applied_at = SYSUTCDATETIME()
        WHERE migration = @migration
        """;

    private const string ResolveNombreBdColumnSql = """
        SELECT TOP 1 COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = N'dbo'
          AND TABLE_NAME = N'pq_empresa'
          AND COLUMN_NAME IN (N'NombreBD', N'nombre_bd')
        ORDER BY CASE COLUMN_NAME WHEN N'NombreBD' THEN 0 ELSE 1 END
        """;

    private const string ResolveHabilitaColumnSql = """
        SELECT TOP 1 COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = N'dbo'
          AND TABLE_NAME = N'pq_empresa'
          AND COLUMN_NAME IN (N'Habilita', N'habilita')
        ORDER BY CASE COLUMN_NAME WHEN N'Habilita' THEN 0 ELSE 1 END
        """;

    private readonly ISqlExecutor _sqlExecutor;
    private readonly SqlMigrationSettings _settings;
    private readonly ILogger<SqlMigrationRunner> _logger;

    public SqlMigrationRunner(
        ISqlExecutor sqlExecutor,
        IOptions<SqlMigrationSettings> settings,
        ILogger<SqlMigrationRunner> logger)
    {
        _sqlExecutor = sqlExecutor;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        if (!_settings.Enabled)
        {
            _logger.LogInformation("Migraciones SQL embebidas deshabilitadas (SqlMigrations:Enabled=false)");
            return;
        }

        _logger.LogInformation("Iniciando migraciones SQL embebidas");

        var dictionaryScripts = SqlScriptLoader.ListDictionaryMigrationResourceNames();
        _logger.LogInformation(
            "Fase diccionario: {Count} migraciones embebidas",
            dictionaryScripts.Count);
        await RunMigrationsAsync(dictionaryScripts, databaseOverride: null, cancellationToken);

        var companyScripts = SqlScriptLoader.ListCompanyMigrationResourceNames();
        if (companyScripts.Count == 0)
        {
            _logger.LogInformation("Fase company: sin migraciones embebidas, omitiendo");
            return;
        }

        _logger.LogInformation(
            "Fase company: {Count} migraciones embebidas",
            companyScripts.Count);

        var nombreBdColumn = await ResolveNombreBdColumnAsync(cancellationToken);
        if (nombreBdColumn is null)
        {
            throw new InvalidOperationException(
                "No se encontro la columna NombreBD ni nombre_bd en dbo.pq_empresa del diccionario.");
        }

        var operativeDatabases = await ListOperativeDatabaseNamesAsync(nombreBdColumn, cancellationToken);
        if (operativeDatabases.Count == 0)
        {
            _logger.LogWarning(
                "Fase company: no hay bases operativas en pq_empresa.{Column}, omitiendo",
                nombreBdColumn);
            return;
        }

        foreach (var nombreBd in operativeDatabases)
        {
            _logger.LogInformation("Aplicando migraciones company en {NombreBD}", nombreBd);
            try
            {
                await RunMigrationsAsync(companyScripts, nombreBd, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "No se pudieron aplicar migraciones company en {NombreBD}: {Message}",
                    nombreBd,
                    ex.Message);
            }
        }

        _logger.LogInformation("Migraciones SQL embebidas finalizadas");
    }

    public async Task<MigrationStatusResponse> GetStatusAsync(
        CancellationToken cancellationToken = default)
    {
        try
        {
            _logger.LogInformation("GetStatusAsync: inicio");
            var results = new List<DatabaseMigrationStatus>();
            var dictionaryScripts = SqlScriptLoader.ListDictionaryMigrationResourceNames();
            var dictionaryName = await ResolveDictionaryDatabaseNameAsync(cancellationToken);

            try
            {
                _logger.LogInformation("GetStatusAsync: consultando diccionario {Db}", dictionaryName);
                results.Add(await GetDatabaseStatusAsync(
                    dictionaryScripts,
                    dictionaryName,
                    "dictionary",
                    databaseOverride: null,
                    cancellationToken));
                _logger.LogInformation("GetStatusAsync: diccionario OK");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "No se pudo consultar el estado de migraciones del diccionario {Database}",
                    dictionaryName);
                results.Add(new DatabaseMigrationStatus(
                    dictionaryName,
                    "dictionary",
                    Applied: 0,
                    Pending: 0,
                    PendingNames: [],
                    Error: ex.Message));
            }

            var companyScripts = SqlScriptLoader.ListCompanyMigrationResourceNames();
            if (companyScripts.Count == 0)
                return new MigrationStatusResponse(true, null, results);

            string nombreBdColumn;
            IReadOnlyList<string> operativeDatabases;
            try
            {
                nombreBdColumn = await ResolveNombreBdColumnAsync(cancellationToken)
                    ?? throw new InvalidOperationException(
                        "No se encontro la columna NombreBD ni nombre_bd en dbo.pq_empresa del diccionario.");
                operativeDatabases = await ListOperativeDatabaseNamesAsync(nombreBdColumn, cancellationToken);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "No se pudo listar las bases operativas para el estado de migraciones");
                return new MigrationStatusResponse(false, ex.Message, []);
            }

            _logger.LogInformation("GetStatusAsync: consultando {N} BDs operativas", operativeDatabases.Count);
            foreach (var nombreBd in operativeDatabases)
            {
                try
                {
                    _logger.LogInformation("GetStatusAsync: consultando company {Db}", nombreBd);
                    results.Add(await GetDatabaseStatusAsync(
                        companyScripts,
                        nombreBd,
                        "company",
                        nombreBd,
                        cancellationToken));
                    _logger.LogInformation("GetStatusAsync: company {Db} OK", nombreBd);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(
                        ex,
                        "No se pudo consultar el estado de migraciones en {NombreBD}",
                        nombreBd);
                    results.Add(new DatabaseMigrationStatus(
                        nombreBd,
                        "company",
                        Applied: 0,
                        Pending: 0,
                        PendingNames: [],
                        Error: ex.Message));
                }
            }

            return new MigrationStatusResponse(true, null, results);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error al consultar el estado de migraciones");
            return new MigrationStatusResponse(false, ex.Message, []);
        }
    }

    public async Task<MigrationRunResponse> RunAndReportAsync(
        CancellationToken cancellationToken = default)
    {
        if (!_settings.Enabled)
        {
            _logger.LogInformation("Migraciones SQL embebidas deshabilitadas (SqlMigrations:Enabled=false)");
            return new MigrationRunResponse(
                false,
                "Migraciones SQL embebidas deshabilitadas (SqlMigrations:Enabled=false)",
                []);
        }

        var results = new List<DatabaseMigrationResult>();
        var hadBdError = false;

        var dictionaryScripts = SqlScriptLoader.ListDictionaryMigrationResourceNames();
        var dictionaryName = await ResolveDictionaryDatabaseNameAsync(cancellationToken);

        _logger.LogInformation("RunAndReport: fase diccionario en {Database}", dictionaryName);
        try
        {
            results.Add(await ApplyMigrationsAndReportAsync(
                dictionaryScripts,
                dictionaryName,
                "dictionary",
                databaseOverride: null,
                cancellationToken));
        }
        catch (Exception ex)
        {
            hadBdError = true;
            _logger.LogWarning(
                ex,
                "No se pudieron aplicar migraciones del diccionario {Database}: {Message}",
                dictionaryName,
                ex.Message);
            results.Add(new DatabaseMigrationResult(
                dictionaryName,
                "dictionary",
                Applied: 0,
                Skipped: 0,
                Failed: 0,
                AppliedNames: [],
                FailedNames: [],
                Error: ex.Message));
        }

        var companyScripts = SqlScriptLoader.ListCompanyMigrationResourceNames();
        if (companyScripts.Count == 0)
        {
            var dictionaryOnlySuccess = !hadBdError && results.All(r => r.Failed == 0 && r.Error is null);
            return new MigrationRunResponse(
                dictionaryOnlySuccess,
                dictionaryOnlySuccess ? null : "Una o más bases tuvieron errores al aplicar migraciones.",
                results);
        }

        _logger.LogInformation(
            "RunAndReport: fase company, {Count} migraciones embebidas",
            companyScripts.Count);

        try
        {
            var nombreBdColumn = await ResolveNombreBdColumnAsync(cancellationToken)
                ?? throw new InvalidOperationException(
                    "No se encontro la columna NombreBD ni nombre_bd en dbo.pq_empresa del diccionario.");
            var operativeDatabases = await ListOperativeDatabaseNamesAsync(nombreBdColumn, cancellationToken);

            foreach (var nombreBd in operativeDatabases)
            {
                _logger.LogInformation("RunAndReport: aplicando migraciones company en {NombreBD}", nombreBd);
                try
                {
                    results.Add(await ApplyMigrationsAndReportAsync(
                        companyScripts,
                        nombreBd,
                        "company",
                        nombreBd,
                        cancellationToken));
                }
                catch (Exception ex)
                {
                    hadBdError = true;
                    _logger.LogWarning(
                        ex,
                        "No se pudieron aplicar migraciones company en {NombreBD}: {Message}",
                        nombreBd,
                        ex.Message);
                    results.Add(new DatabaseMigrationResult(
                        nombreBd,
                        "company",
                        Applied: 0,
                        Skipped: 0,
                        Failed: 0,
                        AppliedNames: [],
                        FailedNames: [],
                        Error: ex.Message));
                }
            }
        }
        catch (Exception ex)
        {
            hadBdError = true;
            _logger.LogWarning(ex, "No se pudo listar las bases operativas para aplicar migraciones");
            return new MigrationRunResponse(false, ex.Message, results);
        }

        var success = !hadBdError && results.All(r => r.Failed == 0 && r.Error is null);
        return new MigrationRunResponse(
            success,
            success ? null : "Una o más bases tuvieron errores al aplicar migraciones.",
            results);
    }

    private async Task<string> ResolveDictionaryDatabaseNameAsync(CancellationToken cancellationToken)
    {
        try
        {
            var names = await _sqlExecutor.QueryStringColumnAsync(
                "SELECT DB_NAME() AS NombreBD",
                "NombreBD",
                _settings.CommandTimeoutSeconds,
                databaseOverride: null,
                cancellationToken);
            var name = names.FirstOrDefault(n => !string.IsNullOrWhiteSpace(n));
            return string.IsNullOrWhiteSpace(name) ? "diccionario" : name;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "No se pudo resolver el nombre de la BD diccionario; se usa 'diccionario'");
            return "diccionario";
        }
    }

    private async Task<DatabaseMigrationStatus> GetDatabaseStatusAsync(
        IReadOnlyList<string> resourceNames,
        string databaseName,
        string databaseType,
        string? databaseOverride,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("GetDatabaseStatus: EnsureSchema en {Db}", databaseOverride ?? "diccionario");
        await EnsureSchemaAsync(databaseOverride, cancellationToken);
        _logger.LogInformation("GetDatabaseStatus: EnsureSchema OK en {Db}", databaseOverride ?? "diccionario");
        _logger.LogInformation("GetDatabaseStatus: LoadApplied en {Db}", databaseOverride ?? "diccionario");
        var appliedMigrations = await LoadAppliedMigrationsAsync(databaseOverride, cancellationToken);
        _logger.LogInformation("GetDatabaseStatus: LoadApplied OK en {Db} — {N} aplicadas",
            databaseOverride ?? "diccionario", appliedMigrations.Count);

        var pendingNames = new List<string>();
        var appliedCount = 0;

        foreach (var resourceName in resourceNames)
        {
            var migrationName = SqlScriptLoader.GetMigrationFileName(resourceName);
            var scriptContent = SqlScriptLoader.ReadEmbeddedMigrationContent(resourceName);
            var checksum = ComputeSha256Hex(scriptContent);

            if (appliedMigrations.TryGetValue(migrationName, out var storedChecksum)
                && string.Equals(storedChecksum, checksum, StringComparison.OrdinalIgnoreCase))
            {
                appliedCount++;
                continue;
            }

            pendingNames.Add(migrationName);
        }

        return new DatabaseMigrationStatus(
            databaseName,
            databaseType,
            appliedCount,
            pendingNames.Count,
            pendingNames,
            Error: null);
    }

    private async Task<DatabaseMigrationResult> ApplyMigrationsAndReportAsync(
        IReadOnlyList<string> resourceNames,
        string databaseName,
        string databaseType,
        string? databaseOverride,
        CancellationToken cancellationToken)
    {
        var appliedNames = new List<string>();
        var failedNames = new List<string>();
        var skippedCount = 0;
        var batch = 1;

        await EnsureSchemaAsync(databaseOverride, cancellationToken);
        var appliedMigrations = await LoadAppliedMigrationsAsync(databaseOverride, cancellationToken);

        foreach (var resourceName in resourceNames)
        {
            var migrationName = SqlScriptLoader.GetMigrationFileName(resourceName);
            var scriptContent = SqlScriptLoader.ReadEmbeddedMigrationContent(resourceName);
            var checksum = ComputeSha256Hex(scriptContent);

            if (appliedMigrations.TryGetValue(migrationName, out var storedChecksum)
                && string.Equals(storedChecksum, checksum, StringComparison.OrdinalIgnoreCase))
            {
                skippedCount++;
                continue;
            }

            var isReapply = appliedMigrations.ContainsKey(migrationName);

            try
            {
                foreach (var batchSql in SplitByGo(scriptContent))
                {
                    if (string.IsNullOrWhiteSpace(batchSql))
                        continue;

                    await _sqlExecutor.ExecuteNonQueryAsync(
                        batchSql,
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);
                }

                if (databaseOverride is not null)
                {
                    await EnsurePrimaryObjectExistsAsync(
                        migrationName,
                        scriptContent,
                        databaseOverride,
                        cancellationToken);
                }

                if (isReapply)
                {
                    await _sqlExecutor.ExecuteNonQueryAsync(
                        UpdateMigrationSql,
                        new Dictionary<string, object?>
                        {
                            ["migration"] = migrationName,
                            ["checksum"] = checksum
                        },
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);
                }
                else
                {
                    await _sqlExecutor.ExecuteNonQueryAsync(
                        InsertMigrationSql,
                        new Dictionary<string, object?>
                        {
                            ["migration"] = migrationName,
                            ["batch"] = batch,
                            ["checksum_sha256"] = checksum
                        },
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);
                }

                appliedMigrations[migrationName] = checksum;
                appliedNames.Add(migrationName);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    ex,
                    "Error al aplicar migracion {Migration} en {Database}: {Message}",
                    migrationName,
                    databaseName,
                    ex.Message);
                failedNames.Add(migrationName);
            }
        }

        return new DatabaseMigrationResult(
            databaseName,
            databaseType,
            appliedNames.Count,
            skippedCount,
            failedNames.Count,
            appliedNames,
            failedNames,
            Error: null);
    }

    private async Task RunMigrationsAsync(
        IReadOnlyList<string> resourceNames,
        string? databaseOverride,
        CancellationToken cancellationToken)
    {
        if (resourceNames.Count == 0)
            return;

        await EnsureSchemaAsync(databaseOverride, cancellationToken);

        var appliedMigrations = await LoadAppliedMigrationsAsync(databaseOverride, cancellationToken);

        var batch = 1;
        var appliedCount = 0;
        var skippedCount = 0;

        foreach (var resourceName in resourceNames)
        {
            var migrationName = SqlScriptLoader.GetMigrationFileName(resourceName);
            var scriptContent = SqlScriptLoader.ReadEmbeddedMigrationContent(resourceName);
            var checksum = ComputeSha256Hex(scriptContent);

            if (appliedMigrations.TryGetValue(migrationName, out var storedChecksum)
                && string.Equals(storedChecksum, checksum, StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogDebug(
                    "Migracion {Migration} ya aplicada en {Database}, omitiendo",
                    migrationName,
                    databaseOverride ?? "diccionario");
                skippedCount++;
                continue;
            }

            var isReapply = appliedMigrations.ContainsKey(migrationName);

            _logger.LogInformation(
                isReapply
                    ? "Re-aplicando migracion {Migration} en {Database} (checksum cambio)"
                    : "Aplicando migracion {Migration} en {Database}",
                migrationName,
                databaseOverride ?? "diccionario");

            try
            {
                foreach (var batchSql in SplitByGo(scriptContent))
                {
                    if (string.IsNullOrWhiteSpace(batchSql))
                        continue;

                    await _sqlExecutor.ExecuteNonQueryAsync(
                        batchSql,
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);
                }

                // Solo company: verificar que el SP/objeto principal quedó creado
                // antes de registrar la migración como aplicada.
                if (databaseOverride is not null)
                {
                    await EnsurePrimaryObjectExistsAsync(
                        migrationName,
                        scriptContent,
                        databaseOverride,
                        cancellationToken);
                }

                if (isReapply)
                {
                    await _sqlExecutor.ExecuteNonQueryAsync(
                        UpdateMigrationSql,
                        new Dictionary<string, object?>
                        {
                            ["migration"] = migrationName,
                            ["checksum"] = checksum
                        },
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);

                    appliedMigrations[migrationName] = checksum;
                    appliedCount++;

                    _logger.LogInformation(
                        "Migracion {Migration} re-aplicada en {Database} (checksum cambio)",
                        migrationName,
                        databaseOverride ?? "diccionario");
                }
                else
                {
                    await _sqlExecutor.ExecuteNonQueryAsync(
                        InsertMigrationSql,
                        new Dictionary<string, object?>
                        {
                            ["migration"] = migrationName,
                            ["batch"] = batch,
                            ["checksum_sha256"] = checksum
                        },
                        _settings.CommandTimeoutSeconds,
                        databaseOverride,
                        cancellationToken);

                    appliedMigrations[migrationName] = checksum;
                    appliedCount++;

                    _logger.LogInformation(
                        "Migracion {Migration} aplicada correctamente en {Database} (checksum {Checksum})",
                        migrationName,
                        databaseOverride ?? "diccionario",
                        checksum);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(
                    ex,
                    "Error al aplicar migracion {Migration} en {Database}",
                    migrationName,
                    databaseOverride ?? "diccionario");
                throw;
            }
        }

        _logger.LogInformation(
            "Migraciones en {Database}: {Applied} aplicadas, {Skipped} omitidas, {Total} embebidas",
            databaseOverride ?? "diccionario",
            appliedCount,
            skippedCount,
            resourceNames.Count);
    }

    private async Task<Dictionary<string, string?>> LoadAppliedMigrationsAsync(
        string? databaseOverride,
        CancellationToken cancellationToken)
    {
        var rows = await _sqlExecutor.QueryStringColumnAsync(
            AppliedMigrationsSql,
            "migration",
            _settings.CommandTimeoutSeconds,
            databaseOverride,
            cancellationToken);

        var appliedMigrations = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows)
        {
            if (string.IsNullOrEmpty(row))
                continue;

            var separatorIndex = row.IndexOf('|');
            if (separatorIndex < 0)
            {
                appliedMigrations[row] = null;
                continue;
            }

            var name = row[..separatorIndex];
            var storedChecksum = row[(separatorIndex + 1)..];
            appliedMigrations[name] = string.IsNullOrEmpty(storedChecksum) ? null : storedChecksum;
        }

        return appliedMigrations;
    }

    private async Task<string?> ResolveNombreBdColumnAsync(CancellationToken cancellationToken)
    {
        var columns = await _sqlExecutor.QueryStringColumnAsync(
            ResolveNombreBdColumnSql,
            "COLUMN_NAME",
            _settings.CommandTimeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        return columns.FirstOrDefault(column =>
            string.Equals(column, "NombreBD", StringComparison.OrdinalIgnoreCase)
            || string.Equals(column, "nombre_bd", StringComparison.OrdinalIgnoreCase));
    }

    private async Task<string?> ResolveHabilitaColumnAsync(CancellationToken cancellationToken)
    {
        var columns = await _sqlExecutor.QueryStringColumnAsync(
            ResolveHabilitaColumnSql,
            "COLUMN_NAME",
            _settings.CommandTimeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        return columns.FirstOrDefault(column =>
            string.Equals(column, "Habilita", StringComparison.OrdinalIgnoreCase)
            || string.Equals(column, "habilita", StringComparison.OrdinalIgnoreCase));
    }

    private async Task<IReadOnlyList<string>> ListOperativeDatabaseNamesAsync(
        string nombreBdColumn,
        CancellationToken cancellationToken)
    {
        var habilitaFilter = string.Empty;
        var habilitaColumn = await ResolveHabilitaColumnAsync(cancellationToken);
        if (habilitaColumn is not null)
        {
            habilitaFilter = $"\n  AND [{habilitaColumn}] = 1";
        }
        else
        {
            _logger.LogWarning(
                "No se encontro columna Habilita/habilita en dbo.pq_empresa; listando todas las bases con NombreBD definido");
        }

        var sql = $"""
            SELECT DISTINCT LTRIM(RTRIM(CAST([{nombreBdColumn}] AS NVARCHAR(256)))) AS NombreBD
            FROM dbo.pq_empresa
            WHERE [{nombreBdColumn}] IS NOT NULL
              AND LTRIM(RTRIM(CAST([{nombreBdColumn}] AS NVARCHAR(256)))) <> N''{habilitaFilter}
            """;

        var databaseNames = await _sqlExecutor.QueryStringColumnAsync(
            sql,
            "NombreBD",
            _settings.CommandTimeoutSeconds,
            databaseOverride: null,
            cancellationToken);

        return databaseNames
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private async Task EnsurePrimaryObjectExistsAsync(
        string migrationName,
        string migrationSql,
        string databaseOverride,
        CancellationToken cancellationToken)
    {
        var objectName = TryExtractObjectNameFromSql(migrationSql)
            ?? TryExtractObjectNameFromMigration(migrationName);
        if (objectName is null)
        {
            _logger.LogWarning(
                "No se pudo determinar el objeto SQL de la migracion {Migration}; se omite la verificacion post-DDL",
                migrationName);
            return;
        }

        // QueryStringColumnAsync no acepta parametros: el nombre ya fue validado
        // (solo [A-Za-z0-9_]) en TryExtractObjectNameFromSql / TryExtractObjectNameFromMigration.
        var sql = $"""
            SELECT CAST(COUNT(*) AS NVARCHAR(32)) AS object_count
            FROM sys.objects
            WHERE name = N'{objectName}'
              AND type IN (N'P', N'FN', N'IF', N'TF', N'V')
            """;

        var counts = await _sqlExecutor.QueryStringColumnAsync(
            sql,
            "object_count",
            _settings.CommandTimeoutSeconds,
            databaseOverride,
            cancellationToken);

        var countText = counts.FirstOrDefault();
        if (!int.TryParse(countText, out var count) || count <= 0)
        {
            _logger.LogError(
                "Migracion {Migration} ejecutada pero el objeto {ObjectName} no existe en {Database}",
                migrationName,
                objectName,
                databaseOverride);

            throw new InvalidOperationException(
                $"Migración {migrationName} ejecutada pero el objeto {objectName} " +
                $"no existe en {databaseOverride}. El DDL puede haber fallado silenciosamente.");
        }
    }

    /// <summary>
    /// Extrae el nombre del objeto SQL desde el contenido del script
    /// (CREATE OR ALTER PROCEDURE / CREATE PROCEDURE / CREATE OR ALTER FUNCTION).
    /// Ejemplo: "CREATE OR ALTER PROCEDURE dbo.PAQ_PartesProduccion_ParametrosList"
    ///          → "PAQ_PartesProduccion_ParametrosList"
    /// </summary>
    internal static string? TryExtractObjectNameFromSql(string sql)
    {
        if (string.IsNullOrWhiteSpace(sql))
            return null;

        var lines = sql.Split(
            ['\r', '\n'],
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        // Prefijos más largos primero para no confundir OR ALTER con CREATE PROCEDURE.
        string[] prefixes =
        [
            "CREATE OR ALTER PROCEDURE",
            "CREATE OR ALTER FUNCTION",
            "CREATE PROCEDURE",
        ];

        foreach (var line in lines.Take(20))
        {
            if (string.IsNullOrWhiteSpace(line))
                continue;

            if (line.StartsWith("--", StringComparison.Ordinal))
                continue;

            foreach (var prefix in prefixes)
            {
                if (!line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    continue;

                var remainder = line[prefix.Length..].Trim();
                if (remainder.Length == 0)
                    continue;

                var tokenEnd = remainder.IndexOfAny([' ', '(', '\t']);
                var qualified = tokenEnd < 0 ? remainder : remainder[..tokenEnd];
                qualified = qualified.Trim().Trim('[', ']');

                var lastDot = qualified.LastIndexOf('.');
                var objectName = lastDot >= 0 ? qualified[(lastDot + 1)..] : qualified;
                objectName = objectName.Trim().Trim('[', ']');

                if (string.IsNullOrEmpty(objectName))
                    continue;

                // Defensa contra inyeccion SQL al embeber el nombre en la consulta.
                if (objectName.Any(ch => !(char.IsAsciiLetterOrDigit(ch) || ch == '_')))
                    return null;

                return objectName;
            }
        }

        return null;
    }

    /// <summary>
    /// Extrae el nombre del objeto SQL desde el archivo de migracion.
    /// Ejemplo: 2026_07_20_000030_paq_tesoreria_listado_saldos.sql → PAQ_Tesoreria_ListadoSaldos
    /// Solo aplica cuando el sufijo empieza con "paq_" (omite update_/create_/fix_).
    /// </summary>
    internal static string? TryExtractObjectNameFromMigration(string migrationFileName)
    {
        var name = migrationFileName;
        if (name.EndsWith(".sql", StringComparison.OrdinalIgnoreCase))
            name = name[..^4];

        // YYYY_MM_DD_NNNNNN_suffix
        var parts = name.Split('_', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 5)
            return null;

        // parts[0]=YYYY, [1]=MM, [2]=DD, [3]=NNNNNN, [4..]=suffix
        if (parts[0].Length != 4 || !parts[0].All(char.IsDigit)
            || parts[1].Length != 2 || !parts[1].All(char.IsDigit)
            || parts[2].Length != 2 || !parts[2].All(char.IsDigit)
            || !parts[3].All(char.IsDigit))
            return null;

        var suffixParts = parts.Skip(4).ToArray();
        if (suffixParts.Length < 2
            || !string.Equals(suffixParts[0], "paq", StringComparison.OrdinalIgnoreCase))
            return null;

        var domain = ToPascalCase(suffixParts[1]);
        var feature = string.Concat(suffixParts.Skip(2).Select(ToPascalCase));

        var objectName = string.IsNullOrEmpty(feature)
            ? $"PAQ_{domain}"
            : $"PAQ_{domain}_{feature}";

        // Defensa contra inyeccion SQL al embeber el nombre en la consulta.
        if (objectName.Any(ch => !(char.IsAsciiLetterOrDigit(ch) || ch == '_')))
            return null;

        return objectName;
    }

    private static string ToPascalCase(string segment)
    {
        if (string.IsNullOrEmpty(segment))
            return string.Empty;

        var lower = segment.ToLowerInvariant();
        return char.ToUpperInvariant(lower[0]) + lower[1..];
    }

    private async Task EnsureSchemaAsync(string? databaseOverride, CancellationToken cancellationToken)
    {
        await _sqlExecutor.ExecuteNonQueryAsync(
            EnsureSchemaSql,
            _settings.CommandTimeoutSeconds,
            databaseOverride,
            cancellationToken);
    }

    private static string ComputeSha256Hex(string content)
    {
        var hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(content));
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    private static IEnumerable<string> SplitByGo(string script)
    {
        var batches = new List<string>();
        var currentBatch = new StringBuilder();

        using var reader = new StringReader(script);
        string? line;
        while ((line = reader.ReadLine()) is not null)
        {
            if (line.Trim().Equals("GO", StringComparison.OrdinalIgnoreCase))
            {
                batches.Add(currentBatch.ToString());
                currentBatch.Clear();
                continue;
            }

            currentBatch.AppendLine(line);
        }

        if (currentBatch.Length > 0)
            batches.Add(currentBatch.ToString());

        return batches;
    }
}
