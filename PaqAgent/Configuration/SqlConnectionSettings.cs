namespace PaqAgent.Configuration;

public class SqlConnectionSettings
{
    public const string SectionName = "SqlConnection";

    public string Server { get; set; } = string.Empty;
    public string Database { get; set; } = string.Empty;
    public string User { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public bool Encrypt { get; set; }
    public bool TrustServerCertificate { get; set; } = true;
    public int ConnectionTimeoutSeconds { get; set; } = 15;
    public int CommandTimeoutSeconds { get; set; } = 30;

    public string BuildConnectionString() => BuildConnectionString(Database);

    public string BuildConnectionString(string databaseOverride)
    {
        var builder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder
        {
            DataSource = Server,
            InitialCatalog = databaseOverride,
            UserID = User,
            Password = Password,
            Encrypt = Encrypt,
            TrustServerCertificate = TrustServerCertificate,
            ConnectTimeout = ConnectionTimeoutSeconds
        };
        return builder.ConnectionString;
    }
}
