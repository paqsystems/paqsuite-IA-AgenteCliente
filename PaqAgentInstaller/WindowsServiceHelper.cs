using System.Diagnostics;
using System.ServiceProcess;

namespace PaqAgentInstaller;

internal sealed class WindowsServiceHelper
{
    public bool IsServiceInstalled(string serviceName)
    {
        try
        {
            return ServiceController.GetServices()
                .Any(s => string.Equals(s.ServiceName, serviceName, StringComparison.OrdinalIgnoreCase));
        }
        catch
        {
            return false;
        }
    }

    public void InstallService(string serviceName, string displayName, string exePath)
    {
        if (!File.Exists(exePath))
            throw new FileNotFoundException($"No se encontró el ejecutable del agente: {exePath}", exePath);

        var binPath = $"\"{exePath}\"";
        var args =
            $"create \"{serviceName}\" binPath= {binPath} start= auto DisplayName= \"{displayName}\"";
        RunSc(args);

        // Descripción opcional (no falla la instalación si sc falla aquí).
        try
        {
            RunSc($"description \"{serviceName}\" \"Servicio PaqSuite Agent\"");
        }
        catch
        {
            // ignore
        }
    }

    public void UninstallService(string serviceName)
    {
        if (!IsServiceInstalled(serviceName))
            return;

        try
        {
            StopService(serviceName);
        }
        catch
        {
            // Continuar con delete aunque stop falle.
        }

        RunSc($"delete \"{serviceName}\"");

        // sc delete es asíncrono a veces; esperar a que desaparezca.
        for (var i = 0; i < 20; i++)
        {
            if (!IsServiceInstalled(serviceName))
                return;
            Thread.Sleep(250);
        }
    }

    public void StartService(string serviceName)
    {
        using var controller = new ServiceController(serviceName);
        if (controller.Status == ServiceControllerStatus.Running)
            return;

        controller.Start();
        controller.WaitForStatus(ServiceControllerStatus.Running, TimeSpan.FromSeconds(60));
    }

    public void StopService(string serviceName)
    {
        if (!IsServiceInstalled(serviceName))
            return;

        using var controller = new ServiceController(serviceName);
        if (controller.Status == ServiceControllerStatus.Stopped)
            return;

        if (controller.CanStop)
        {
            controller.Stop();
            controller.WaitForStatus(ServiceControllerStatus.Stopped, TimeSpan.FromSeconds(60));
        }
    }

    public string GetServiceStatus(string serviceName)
    {
        if (!IsServiceInstalled(serviceName))
            return "NotInstalled";

        try
        {
            using var controller = new ServiceController(serviceName);
            return controller.Status switch
            {
                ServiceControllerStatus.Running => "Running",
                ServiceControllerStatus.Stopped => "Stopped",
                _ => controller.Status.ToString(),
            };
        }
        catch
        {
            return "NotInstalled";
        }
    }

    private static void RunSc(string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "sc.exe",
            Arguments = arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("No se pudo iniciar sc.exe.");

        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
            throw new InvalidOperationException(
                $"sc.exe falló (exit {process.ExitCode}): {detail.Trim()}");
        }
    }
}
