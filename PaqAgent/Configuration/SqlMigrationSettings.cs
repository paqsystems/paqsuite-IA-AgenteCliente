namespace PaqAgent.Configuration;

public class SqlMigrationSettings
{
    public const string SectionName = "SqlMigrations";

    public bool Enabled { get; set; } = true;
    public int CommandTimeoutSeconds { get; set; } = 120;
}
