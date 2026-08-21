using System.Diagnostics;

namespace PaqAgentInstaller;

internal static class Program
{
    [STAThread]
    private static async Task Main(string[] args)
    {
        if (args.Contains("--update"))
        {
            Environment.Exit(await RunHeadlessUpdateAsync());
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }

    private static async Task<int> RunHeadlessUpdateAsync()
    {
        try
        {
            var installPath = InstallerPreferences.ReadLastInstallPath();
            var settingsPath = Path.Combine(installPath, Constants.LOCAL_SETTINGS_FILE);
            if (!Directory.Exists(installPath) || !File.Exists(settingsPath))
                return 0;

            var settingsService = new AgentSettingsService();
            var settings = settingsService.ReadSettings(installPath);
            if (string.IsNullOrWhiteSpace(settings.AgentId))
                return 0;

            var github = new GitHubReleaseService();
            var serviceHelper = new WindowsServiceHelper();
            var orchestrator = new UpdateOrchestrator(github, settingsService, serviceHelper);

            void Log(string message)
            {
                Console.WriteLine(message);
                WriteEventLog(message, EventLogEntryType.Information);
            }

            var updated = await orchestrator.CheckAndUpdateAsync(installPath, Log);
            WriteEventLog(
                updated
                    ? "PaqAgent auto-update: se aplicó una actualización."
                    : "PaqAgent auto-update: sin cambios (ya actualizado o sin instalación).",
                EventLogEntryType.Information);

            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR: {ex.Message}");
            WriteEventLog($"PaqAgent auto-update falló: {ex}", EventLogEntryType.Error);
            return 1;
        }
    }

    private static void WriteEventLog(string message, EventLogEntryType type)
    {
        try
        {
            const string source = "PaqAgent";
            if (!EventLog.SourceExists(source))
                EventLog.CreateEventSource(source, "Application");

            EventLog.WriteEntry(source, message, type);
        }
        catch
        {
            // Sin permisos u otros errores: no abortar el update.
        }
    }
}
