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

    private const string AppliedMigrationsSql = "SELECT migration FROM dbo.paq_sp_migrations";

    private const string InsertMigrationSql = """
        INSERT INTO dbo.paq_sp_migrations (migration, batch, checksum_sha256)
        VALUES (@migration, @batch, @checksum_sha256)
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

        await EnsureSchemaAsync(cancellationToken);

        var appliedMigrations = new HashSet<string>(
            await _sqlExecutor.QueryStringColumnAsync(
                AppliedMigrationsSql,
                "migration",
                _settings.CommandTimeoutSeconds,
                cancellationToken),
            StringComparer.OrdinalIgnoreCase);

        var embeddedResources = SqlScriptLoader.ListEmbeddedMigrationResourceNames();
        var batch = 1;
        var appliedCount = 0;
        var skippedCount = 0;

        foreach (var resourceName in embeddedResources)
        {
            var migrationName = SqlScriptLoader.GetMigrationFileName(resourceName);

            if (appliedMigrations.Contains(migrationName))
            {
                _logger.LogDebug("Migracion {Migration} ya aplicada, omitiendo", migrationName);
                skippedCount++;
                continue;
            }

            _logger.LogInformation("Aplicando migracion {Migration}", migrationName);

            var scriptContent = SqlScriptLoader.ReadEmbeddedMigrationContent(resourceName);
            var checksum = ComputeSha256Hex(scriptContent);

            try
            {
                foreach (var batchSql in SplitByGo(scriptContent))
                {
                    if (string.IsNullOrWhiteSpace(batchSql))
                        continue;

                    await _sqlExecutor.ExecuteNonQueryAsync(
                        batchSql,
                        _settings.CommandTimeoutSeconds,
                        cancellationToken);
                }

                await _sqlExecutor.ExecuteNonQueryAsync(
                    InsertMigrationSql,
                    new Dictionary<string, object?>
                    {
                        ["migration"] = migrationName,
                        ["batch"] = batch,
                        ["checksum_sha256"] = checksum
                    },
                    _settings.CommandTimeoutSeconds,
                    cancellationToken);

                appliedMigrations.Add(migrationName);
                appliedCount++;

                _logger.LogInformation(
                    "Migracion {Migration} aplicada correctamente (checksum {Checksum})",
                    migrationName,
                    checksum);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error al aplicar migracion {Migration}", migrationName);
                throw;
            }
        }

        _logger.LogInformation(
            "Migraciones SQL embebidas finalizadas: {Applied} aplicadas, {Skipped} omitidas, {Total} embebidas",
            appliedCount,
            skippedCount,
            embeddedResources.Count);
    }

    private async Task EnsureSchemaAsync(CancellationToken cancellationToken)
    {
        await _sqlExecutor.ExecuteNonQueryAsync(
            EnsureSchemaSql,
            _settings.CommandTimeoutSeconds,
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
