using System.Text;
using System.Text.Json;

namespace PaqAgentInstaller;

internal static class InstallerPreferences
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    public static string ConfigDirectory =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            Constants.INSTALLER_CONFIG_FOLDER_NAME);

    public static string ConfigPath =>
        Path.Combine(ConfigDirectory, Constants.INSTALLER_CONFIG_FILE);

    public static string ReadLastInstallPath()
    {
        try
        {
            if (!File.Exists(ConfigPath))
                return Constants.DEFAULT_INSTALL_PATH;

            using var doc = JsonDocument.Parse(File.ReadAllText(ConfigPath));
            if (doc.RootElement.TryGetProperty("LastInstallPath", out var prop)
                && prop.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(prop.GetString()))
            {
                return prop.GetString()!.Trim();
            }
        }
        catch
        {
            // JSON ausente o corrupto: usar default.
        }

        return Constants.DEFAULT_INSTALL_PATH;
    }

    public static void SaveLastInstallPath(string installPath)
    {
        if (string.IsNullOrWhiteSpace(installPath))
            throw new ArgumentException("La carpeta de instalación es obligatoria.", nameof(installPath));

        Directory.CreateDirectory(ConfigDirectory);
        var json = JsonSerializer.Serialize(
            new Dictionary<string, string> { ["LastInstallPath"] = installPath.Trim() },
            JsonOptions);
        File.WriteAllText(ConfigPath, json, Encoding.UTF8);
    }
}
