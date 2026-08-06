using System.IO.Compression;

namespace PaqAgentInstaller;

internal sealed class UpdateOrchestrator
{
    private readonly GitHubReleaseService _github;
    private readonly AgentSettingsService _settingsService;
    private readonly WindowsServiceHelper _serviceHelper;

    public UpdateOrchestrator(
        GitHubReleaseService github,
        AgentSettingsService settingsService,
        WindowsServiceHelper serviceHelper)
    {
        _github = github;
        _settingsService = settingsService;
        _serviceHelper = serviceHelper;
    }

    public async Task<bool> CheckAndUpdateAsync(
        string installPath,
        Action<string> log,
        Action<int>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(installPath))
        {
            log($"No se encontró instalación en {installPath}");
            return false;
        }

        // Confirmar que hay config (preservar en update).
        _ = _settingsService.ReadSettings(installPath);

        log("Consultando GitHub releases/latest...");
        var release = await _github.GetLatestReleaseAsync(cancellationToken);

        var installed = ReadInstalledVersion(installPath);
        log($"Instalada: {(string.IsNullOrWhiteSpace(installed) ? "(desconocida)" : installed)}");
        log($"Disponible: {release.Version}");

        if (!string.IsNullOrWhiteSpace(installed)
            && string.Equals(NormalizeVersion(installed), NormalizeVersion(release.Version), StringComparison.OrdinalIgnoreCase))
        {
            log("Ya tenés la última versión");
            return false;
        }

        log($"Nueva versión disponible: {release.Version}. Actualizando...");

        var existingSettings = _settingsService.ReadSettings(installPath);

        log("Deteniendo servicio...");
        if (_serviceHelper.IsServiceInstalled(Constants.AGENT_SERVICE_NAME))
            _serviceHelper.StopService(Constants.AGENT_SERVICE_NAME);

        var tempRoot = Path.Combine(Path.GetTempPath(), "PaqAgentInstaller", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        var zipPath = Path.Combine(tempRoot, "release.zip");

        log($"Descargando {release.Version}...");
        IProgress<int>? downloadProgress = progress is null
            ? null
            : new Progress<int>(progress);
        await _github.DownloadReleaseAsync(release.DownloadUrl, zipPath, downloadProgress, cancellationToken);

        log("Descomprimiendo...");
        var extractPath = Path.Combine(tempRoot, "extract");
        ZipFile.ExtractToDirectory(zipPath, extractPath, overwriteFiles: true);
        var sourceDir = FindPublishRoot(extractPath);

        log("Copiando binarios (preservando appsettings.local.json)...");
        CopyDirectory(sourceDir, installPath, preserveLocalSettings: true);

        // Reafirmar settings leídos (por si el zip traía un local vacío).
        _settingsService.WriteSettings(installPath, existingSettings);
        WriteInstalledVersion(installPath, release.Version);

        log("Iniciando servicio...");
        if (_serviceHelper.IsServiceInstalled(Constants.AGENT_SERVICE_NAME))
        {
            _serviceHelper.StartService(Constants.AGENT_SERVICE_NAME);
        }
        else
        {
            var exePath = Path.Combine(installPath, Constants.AGENT_EXE_NAME);
            _serviceHelper.InstallService(
                Constants.AGENT_SERVICE_NAME,
                Constants.AGENT_DISPLAY_NAME,
                exePath);
            _serviceHelper.StartService(Constants.AGENT_SERVICE_NAME);
        }

        log("✓ Actualización completada");

        // Registrar tarea de auto-update si no existe aún.
        // El instalador debe estar junto al agente en installPath.
        try
        {
            if (!TaskSchedulerHelper.IsTaskRegistered())
            {
                var installerExe = Path.Combine(installPath, "PaqAgentInstaller.exe");
                if (File.Exists(installerExe))
                {
                    TaskSchedulerHelper.RegisterUpdateTask(installerExe);
                    log("Tarea de auto-actualización registrada en Task Scheduler.");
                }
            }
        }
        catch (Exception ex)
        {
            log($"ADVERTENCIA: no se pudo registrar la tarea de auto-update: {ex.Message}");
        }

        return true;
    }

    private static string FindPublishRoot(string extractPath)
    {
        // Si el zip tiene PaqAgent.exe en la raíz, usarla.
        if (File.Exists(Path.Combine(extractPath, Constants.AGENT_EXE_NAME)))
            return extractPath;

        // Buscar en subcarpetas (un nivel / recursivo corto).
        var match = Directory.EnumerateFiles(extractPath, Constants.AGENT_EXE_NAME, SearchOption.AllDirectories)
            .FirstOrDefault();
        if (match is not null)
            return Path.GetDirectoryName(match)!;

        throw new InvalidOperationException(
            $"No se encontró {Constants.AGENT_EXE_NAME} dentro del zip descargado.");
    }

    private static void CopyDirectory(string sourceDir, string targetDir, bool preserveLocalSettings)
    {
        Directory.CreateDirectory(targetDir);

        foreach (var dir in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(sourceDir, dir);
            Directory.CreateDirectory(Path.Combine(targetDir, relative));
        }

        foreach (var file in Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(sourceDir, file);
            var fileName = Path.GetFileName(file);

            if (preserveLocalSettings
                && string.Equals(fileName, Constants.LOCAL_SETTINGS_FILE, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            // Saltear el instalador: puede estar en ejecución si el update fue
            // lanzado por la tarea programada (self-lock → IOException).
            // El instalador se actualizará en la siguiente ejecución del update.
            if (string.Equals(fileName, "PaqAgentInstaller.exe", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var dest = Path.Combine(targetDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
            File.Copy(file, dest, overwrite: true);
        }
    }

    private static string VersionFilePath(string installPath) =>
        Path.Combine(installPath, "installed-version.txt");

    private static void WriteInstalledVersion(string installPath, string version)
    {
        File.WriteAllText(VersionFilePath(installPath), version.Trim());
    }

    private static string ReadInstalledVersion(string installPath)
    {
        var path = VersionFilePath(installPath);
        if (File.Exists(path))
            return File.ReadAllText(path).Trim();

        // Fallback: FileVersion del exe.
        var exe = Path.Combine(installPath, Constants.AGENT_EXE_NAME);
        if (File.Exists(exe))
        {
            var info = System.Diagnostics.FileVersionInfo.GetVersionInfo(exe);
            return info.ProductVersion ?? info.FileVersion ?? "";
        }

        return "";
    }

    private static string NormalizeVersion(string version) =>
        version.Trim().TrimStart('v', 'V');
}
