using System.Diagnostics;
using System.Text;
using System.Xml.Linq;

namespace PaqAgentInstaller;

/// <summary>
/// Registra la tarea de auto-update via schtasks.exe (sin NuGet).
/// schtasks /create solo acepta un /SC por invocación; para dos triggers
/// se usa /create /xml con ambos triggers en el mismo XML.
/// </summary>
internal static class TaskSchedulerHelper
{
    internal const string TASK_NAME = "PaqAgent-AutoUpdate";

    private static readonly XNamespace TaskNs =
        "http://schemas.microsoft.com/windows/2004/02/mit/task";

    public static void RegisterUpdateTask(string installerExePath)
    {
        if (string.IsNullOrWhiteSpace(installerExePath))
            throw new ArgumentException("La ruta del instalador es obligatoria.", nameof(installerExePath));

        var fullPath = Path.GetFullPath(installerExePath);
        if (!File.Exists(fullPath))
            throw new FileNotFoundException("No se encontró el ejecutable del instalador.", fullPath);

        // Si ya existe: eliminarla y recrearla.
        if (IsTaskRegistered())
            UnregisterUpdateTask();

        var xmlPath = Path.Combine(Path.GetTempPath(), $"PaqAgent-AutoUpdate-{Guid.NewGuid():N}.xml");
        try
        {
            File.WriteAllText(xmlPath, BuildTaskXml(fullPath), Encoding.Unicode);
            RunSchtasks($"/Create /TN \"{TASK_NAME}\" /XML \"{xmlPath}\" /F");
        }
        finally
        {
            try { File.Delete(xmlPath); } catch { /* ignore */ }
        }
    }

    public static void UnregisterUpdateTask()
    {
        if (!IsTaskRegistered())
            return;

        RunSchtasks($"/Delete /TN \"{TASK_NAME}\" /F");
    }

    public static bool IsTaskRegistered()
    {
        var psi = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            Arguments = $"/Query /TN \"{TASK_NAME}\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("No se pudo iniciar schtasks.exe.");

        _ = process.StandardOutput.ReadToEnd();
        _ = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return process.ExitCode == 0;
    }

    private static string BuildTaskXml(string installerExePath)
    {
        // StartBoundary del trigger diario: fecha fija + hora 03:00 (el día se repite).
        var dailyStart = new DateTime(2024, 1, 1, 3, 0, 0).ToString("yyyy-MM-ddTHH:mm:ss");

        var doc = new XDocument(
            new XDeclaration("1.0", "UTF-16", null),
            new XElement(TaskNs + "Task",
                new XAttribute("version", "1.2"),
                new XElement(TaskNs + "RegistrationInfo",
                    new XElement(TaskNs + "Description",
                        "PaqAgent auto-update (boot + diario 03:00)")),
                new XElement(TaskNs + "Triggers",
                    // Trigger 1: ONSTART + delay 60s (PT1M)
                    new XElement(TaskNs + "BootTrigger",
                        new XElement(TaskNs + "Enabled", "true"),
                        new XElement(TaskNs + "Delay", "PT1M")),
                    // Trigger 2: DAILY 03:00
                    new XElement(TaskNs + "CalendarTrigger",
                        new XElement(TaskNs + "StartBoundary", dailyStart),
                        new XElement(TaskNs + "Enabled", "true"),
                        new XElement(TaskNs + "ScheduleByDay",
                            new XElement(TaskNs + "DaysInterval", "1")))),
                new XElement(TaskNs + "Principals",
                    new XElement(TaskNs + "Principal",
                        new XAttribute("id", "Author"),
                        // SYSTEM
                        new XElement(TaskNs + "UserId", "S-1-5-18"),
                        new XElement(TaskNs + "RunLevel", "HighestAvailable"))),
                new XElement(TaskNs + "Settings",
                    new XElement(TaskNs + "MultipleInstancesPolicy", "IgnoreNew"),
                    new XElement(TaskNs + "DisallowStartIfOnBatteries", "false"),
                    new XElement(TaskNs + "StopIfGoingOnBatteries", "false"),
                    new XElement(TaskNs + "AllowHardTerminate", "true"),
                    new XElement(TaskNs + "StartWhenAvailable", "true"),
                    new XElement(TaskNs + "RunOnlyIfNetworkAvailable", "false"),
                    new XElement(TaskNs + "AllowStartOnDemand", "true"),
                    new XElement(TaskNs + "Enabled", "true"),
                    new XElement(TaskNs + "Hidden", "false"),
                    new XElement(TaskNs + "ExecutionTimeLimit", "PT2H"),
                    new XElement(TaskNs + "Priority", "7")),
                new XElement(TaskNs + "Actions",
                    new XAttribute("Context", "Author"),
                    new XElement(TaskNs + "Exec",
                        new XElement(TaskNs + "Command", installerExePath),
                        new XElement(TaskNs + "Arguments", "--update")))));

        return doc.Declaration + Environment.NewLine + doc.ToString();
    }

    private static void RunSchtasks(string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "schtasks.exe",
            Arguments = arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("No se pudo iniciar schtasks.exe.");

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
            throw new InvalidOperationException(
                $"schtasks.exe falló (exit {process.ExitCode}): {detail.Trim()}");
        }
    }
}
