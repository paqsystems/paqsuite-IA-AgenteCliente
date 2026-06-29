namespace PaqAgent.Database;

public static class SqlScriptLoader
{
    private const string MigrationResourceMarker = ".sql.migrations.";

    public static IReadOnlyList<string> ListEmbeddedMigrationResourceNames()
    {
        return typeof(SqlScriptLoader).Assembly
            .GetManifestResourceNames()
            .Where(name => name.Contains(MigrationResourceMarker, StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToList();
    }

    public static string ReadEmbeddedMigrationContent(string resourceName)
    {
        using var stream = typeof(SqlScriptLoader).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Recurso embebido no encontrado: {resourceName}");

        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    public static string GetMigrationFileName(string resourceName)
    {
        var markerIndex = resourceName.IndexOf(MigrationResourceMarker, StringComparison.Ordinal);
        if (markerIndex < 0)
            throw new ArgumentException($"El recurso no es una migracion embebida: {resourceName}", nameof(resourceName));

        return resourceName[(markerIndex + MigrationResourceMarker.Length)..];
    }
}
