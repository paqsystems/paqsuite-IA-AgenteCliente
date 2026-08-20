using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;

namespace PaqAgentInstaller;

internal sealed class AgentSettingsService
{
    private static readonly JsonSerializerOptions WriteOptions = new()
    {
        WriteIndented = true,
    };

    public AgentSettings ReadSettings(string installPath)
    {
        var path = Path.Combine(installPath, Constants.LOCAL_SETTINGS_FILE);
        if (!File.Exists(path))
            return new AgentSettings();

        var json = File.ReadAllText(path);
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        var settings = new AgentSettings();

        if (root.TryGetProperty("Agent", out var agent))
        {
            settings.AgentId = GetString(agent, "AgentId");
            settings.ClientId = GetString(agent, "ClientId");
            settings.GatewayUrl = GetString(agent, "GatewayUrl");
        }

        if (root.TryGetProperty("SqlConnection", out var sql))
        {
            settings.SqlServer = GetString(sql, "Server");
            settings.SqlPort = GetString(sql, "Port");
            settings.SqlDatabase = GetString(sql, "Database");
            settings.SqlUser = GetString(sql, "User");
            settings.SqlPassword = GetString(sql, "Password");
        }

        return settings;
    }

    public void WriteSettings(string installPath, AgentSettings settings)
    {
        Directory.CreateDirectory(installPath);
        var path = Path.Combine(installPath, Constants.LOCAL_SETTINGS_FILE);

        // Preservar AgentToken si ya existe en el archivo.
        var agentToken = "dev-agent-token";
        if (File.Exists(path))
        {
            try
            {
                using var existing = JsonDocument.Parse(File.ReadAllText(path));
                if (existing.RootElement.TryGetProperty("Agent", out var agent)
                    && agent.TryGetProperty("AgentToken", out var tokenProp)
                    && tokenProp.ValueKind == JsonValueKind.String
                    && !string.IsNullOrWhiteSpace(tokenProp.GetString()))
                {
                    agentToken = tokenProp.GetString()!;
                }
            }
            catch
            {
                // Si el JSON existente está corrupto, se usa el default.
            }
        }

        var root = new JsonObject
        {
            ["Agent"] = new JsonObject
            {
                ["AgentId"] = settings.AgentId ?? "",
                ["ClientId"] = settings.ClientId ?? "",
                ["AgentToken"] = agentToken,
                ["GatewayUrl"] = settings.GatewayUrl ?? "",
            },
            ["SqlConnection"] = new JsonObject
            {
                ["Server"] = settings.SqlServer ?? "",
                ["Port"] = settings.SqlPort ?? "",
                ["Database"] = settings.SqlDatabase ?? "",
                ["User"] = settings.SqlUser ?? "",
                ["Password"] = settings.SqlPassword ?? "",
            },
        };

        File.WriteAllText(path, root.ToJsonString(WriteOptions), Encoding.UTF8);
    }

    public async Task<bool> TestConnectionAsync(AgentSettings settings, CancellationToken cancellationToken = default)
    {
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = BuildDataSource(settings),
            InitialCatalog = settings.SqlDatabase,
            UserID = settings.SqlUser,
            Password = settings.SqlPassword,
            Encrypt = false,
            TrustServerCertificate = true,
            ConnectTimeout = 8,
        };

        try
        {
            await using var connection = new SqlConnection(builder.ConnectionString);
            await connection.OpenAsync(cancellationToken);
            return connection.State == System.Data.ConnectionState.Open;
        }
        catch
        {
            return false;
        }
    }

    private static string BuildDataSource(AgentSettings settings)
    {
        var server = settings.SqlServer?.Trim() ?? "";
        var port = settings.SqlPort?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(port) || port == "1433")
            return server;

        return $"{server},{port}";
    }

    private static string GetString(JsonElement parent, string name)
    {
        if (!parent.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String)
            return "";
        return value.GetString() ?? "";
    }
}
