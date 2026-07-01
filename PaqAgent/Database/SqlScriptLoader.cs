namespace PaqAgent.Database;

public static class SqlScriptLoader
{
    private const string MigrationResourceMarker = ".sql.migrations.";
    private const string DictionaryResourceMarker = ".sql.migrations.dictionary.";
    private const string CompanyResourceMarker = ".sql.migrations.company.";

    public static IReadOnlyList<string> ListEmbeddedMigrationResourceNames()
    {
        return typeof(SqlScriptLoader).Assembly
            .GetManifestResourceNames()
            .Where(name => name.Contains(MigrationResourceMarker, StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToList();
    }

    public static IReadOnlyList<string> ListDictionaryMigrationResourceNames()
    {
        return typeof(SqlScriptLoader).Assembly
            .GetManifestResourceNames()
            .Where(name => name.Contains(DictionaryResourceMarker, StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToList();
    }

    public static IReadOnlyList<string> ListCompanyMigrationResourceNames()
    {
        return typeof(SqlScriptLoader).Assembly
            .GetManifestResourceNames()
            .Where(name => name.Contains(CompanyResourceMarker, StringComparison.Ordinal))
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

        var relativeName = resourceName[(markerIndex + MigrationResourceMarker.Length)..];

        const string dictionaryPrefix = "dictionary.";
        const string companyPrefix = "company.";

        if (relativeName.StartsWith(dictionaryPrefix, StringComparison.OrdinalIgnoreCase))
            return relativeName[dictionaryPrefix.Length..];

        if (relativeName.StartsWith(companyPrefix, StringComparison.OrdinalIgnoreCase))
            return relativeName[companyPrefix.Length..];

        return relativeName;
    }
}
