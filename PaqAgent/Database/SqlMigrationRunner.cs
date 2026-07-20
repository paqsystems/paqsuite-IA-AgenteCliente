using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PaqAgent.Configuration;

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
