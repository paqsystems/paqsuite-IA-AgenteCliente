using System.IO.Compression;
using System.Security.Principal;

namespace PaqAgentInstaller;

public sealed class MainForm : Form
{
    private readonly GitHubReleaseService _github = new();
    private readonly AgentSettingsService _settingsService = new();
    private readonly WindowsServiceHelper _serviceHelper = new();
    private readonly UpdateOrchestrator _updateOrchestrator;

    private TabControl _tabs = null!;

    // Install tab
    private TextBox _txtAgentId = null!;
    private TextBox _txtClientId = null!;
    private TextBox _txtGatewayUrl = null!;
    private TextBox _txtSqlServer = null!;
    private TextBox _txtSqlPort = null!;
    private TextBox _txtSqlDatabase = null!;
    private TextBox _txtSqlUser = null!;
    private TextBox _txtSqlPassword = null!;
    private TextBox _txtInstallPath = null!;
    private Button _btnTestConnection = null!;
    private Button _btnInstall = null!;
    private ProgressBar _progressInstall = null!;
    private RichTextBox _logInstall = null!;

    // Update tab
    private Label _lblInstalledVersion = null!;
    private Label _lblAvailableVersion = null!;
    private Button _btnCheckUpdate = null!;
    private Button _btnUpdate = null!;
    private ProgressBar _progressUpdate = null!;
    private RichTextBox _logUpdate = null!;

    private GitHubReleaseInfo? _pendingRelease;
    private string? _detectedInstallPath;

    public MainForm()
    {
        _updateOrchestrator = new UpdateOrchestrator(_github, _settingsService, _serviceHelper);

        Text = "PaqSuite Agent Installer";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(720, 640);
        Size = new Size(780, 700);
        Font = new Font("Segoe UI", 9F);

        BuildUi();
        Load += MainForm_Load;
    }

    private void MainForm_Load(object? sender, EventArgs e)
    {
        _detectedInstallPath = InstallerPreferences.ReadLastInstallPath();
        _txtInstallPath.Text = _detectedInstallPath;
        TryFillFromLocalSettings(_detectedInstallPath);

        RefreshInstalledVersionLabel();
        _lblAvailableVersion.Text = "Disponible: (sin verificar)";
        _btnUpdate.Enabled = false;
    }

    private void BuildUi()
    {
        _tabs = new TabControl { Dock = DockStyle.Fill };
        _tabs.TabPages.Add(BuildInstallTab());
        _tabs.TabPages.Add(BuildUpdateTab());
        Controls.Add(_tabs);
    }

    private TabPage BuildInstallTab()
    {
        var page = new TabPage("Instalar");
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(12),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        // Agent section
        var agentGroup = new GroupBox
        {
            Text = "Configuración del Agente",
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(10),
        };
        var agentLayout = CreateTwoColumnLayout();
        _txtAgentId = AddLabeledTextBox(agentLayout, "AgentId");
        _txtClientId = AddLabeledTextBox(agentLayout, "ClientId");
        _txtGatewayUrl = AddLabeledTextBox(agentLayout, "Gateway URL");
        agentGroup.Controls.Add(agentLayout);

        // SQL section
        var sqlGroup = new GroupBox
        {
            Text = "Configuración SQL",
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(10),
        };
        var sqlLayout = CreateTwoColumnLayout();
        _txtSqlServer = AddLabeledTextBox(sqlLayout, "Servidor SQL");
        _txtSqlPort = AddLabeledTextBox(sqlLayout, "Puerto SQL");
        _txtSqlPort.PlaceholderText = "Dejar vacío para puerto por defecto (1433)";
        _txtSqlDatabase = AddLabeledTextBox(sqlLayout, "Base de datos (diccionario)");
        _txtSqlUser = AddLabeledTextBox(sqlLayout, "Usuario");
        _txtSqlPassword = AddLabeledTextBox(sqlLayout, "Contraseña");
        _txtSqlPassword.UseSystemPasswordChar = true;

        _btnTestConnection = new Button
        {
            Text = "Probar conexión",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
        };
        _btnTestConnection.Click += async (_, _) => await TestConnectionAsync();
        sqlLayout.Controls.Add(new Label(), 0, sqlLayout.RowCount);
        sqlLayout.Controls.Add(_btnTestConnection, 1, sqlLayout.RowCount);
        sqlLayout.RowCount++;
        sqlLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        sqlGroup.Controls.Add(sqlLayout);

        // Install section
        var installGroup = new GroupBox
        {
            Text = "Instalación",
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(10),
        };
        var installLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2,
            RowCount = 3,
        };
        installLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 160));
        installLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        installLayout.Controls.Add(new Label { Text = "Carpeta destino", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        _txtInstallPath = new TextBox { Dock = DockStyle.Fill };
        installLayout.Controls.Add(_txtInstallPath, 1, 0);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
        };
        _btnInstall = new Button { Text = "Instalar", AutoSize = true, Width = 120 };
        _btnInstall.Click += async (_, _) => await InstallAsync();
        buttons.Controls.Add(_btnInstall);
        installLayout.Controls.Add(new Label(), 0, 1);
        installLayout.Controls.Add(buttons, 1, 1);

        _progressInstall = new ProgressBar { Dock = DockStyle.Fill, Height = 22, Minimum = 0, Maximum = 100 };
        installLayout.Controls.Add(new Label { Text = "Progreso", AutoSize = true }, 0, 2);
        installLayout.Controls.Add(_progressInstall, 1, 2);
        installGroup.Controls.Add(installLayout);

        _logInstall = CreateLogBox();

        root.Controls.Add(agentGroup, 0, 0);
        root.Controls.Add(sqlGroup, 0, 1);
        root.Controls.Add(installGroup, 0, 2);
        root.Controls.Add(_logInstall, 0, 3);
        page.Controls.Add(root);
        return page;
    }

    private TabPage BuildUpdateTab()
    {
        var page = new TabPage("Actualizar");
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            Padding = new Padding(12),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        _lblInstalledVersion = new Label
        {
            Text = "Instalada: (desconocida)",
            AutoSize = true,
            Padding = new Padding(0, 4, 0, 4),
        };
        _lblAvailableVersion = new Label
        {
            Text = "Disponible: (sin verificar)",
            AutoSize = true,
            Padding = new Padding(0, 4, 0, 8),
        };

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
        };
        _btnCheckUpdate = new Button { Text = "Verificar actualización", AutoSize = true };
        _btnUpdate = new Button { Text = "Actualizar", AutoSize = true, Enabled = false };
        _btnCheckUpdate.Click += async (_, _) => await CheckUpdateAsync();
        _btnUpdate.Click += async (_, _) => await UpdateAsync();
        buttons.Controls.Add(_btnCheckUpdate);
        buttons.Controls.Add(_btnUpdate);

        _progressUpdate = new ProgressBar { Dock = DockStyle.Top, Height = 22, Minimum = 0, Maximum = 100 };
        _logUpdate = CreateLogBox();

        root.Controls.Add(_lblInstalledVersion, 0, 0);
        root.Controls.Add(_lblAvailableVersion, 0, 1);
        root.Controls.Add(buttons, 0, 2);

        var bottom = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
        };
        bottom.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        bottom.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        bottom.Controls.Add(_progressUpdate, 0, 0);
        bottom.Controls.Add(_logUpdate, 0, 1);
        root.Controls.Add(bottom, 0, 3);

        page.Controls.Add(root);
        return page;
    }

    private static TableLayoutPanel CreateTwoColumnLayout()
    {
        var layout = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 2,
            RowCount = 0,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        return layout;
    }

    private static TextBox AddLabeledTextBox(TableLayoutPanel layout, string label)
    {
        var row = layout.RowCount;
        layout.RowCount++;
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        layout.Controls.Add(new Label
        {
            Text = label,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(3, 8, 3, 3),
        }, 0, row);

        var textBox = new TextBox
        {
            Dock = DockStyle.Fill,
            Margin = new Padding(3, 4, 3, 3),
        };
        layout.Controls.Add(textBox, 1, row);
        return textBox;
    }

    private static RichTextBox CreateLogBox()
    {
        return new RichTextBox
        {
            Dock = DockStyle.Fill,
            ReadOnly = true,
            BackColor = Color.Black,
            ForeColor = Color.LimeGreen,
            Font = new Font("Consolas", 9F),
            BorderStyle = BorderStyle.FixedSingle,
        };
    }

    private async Task TestConnectionAsync()
    {
        try
        {
            SetBusy(true);
            var settings = CollectSettingsFromForm();
            var ok = await _settingsService.TestConnectionAsync(settings);
            MessageBox.Show(
                this,
                ok ? "Conexión SQL exitosa." : "No se pudo conectar al SQL Server.",
                "Probar conexión",
                MessageBoxButtons.OK,
                ok ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task InstallAsync()
    {
        try
        {
            if (!ValidateInstallFields())
                return;

            if (!EnsureAdministrator())
                return;

            SetBusy(true);
            _progressInstall.Value = 0;
            AppendLog(_logInstall, "Obteniendo última versión de GitHub...");

            var release = await _github.GetLatestReleaseAsync();
            AppendLog(_logInstall, $"Release: {release.TagName}");

            var installPath = _txtInstallPath.Text.Trim();
            Directory.CreateDirectory(installPath);

            var tempRoot = Path.Combine(Path.GetTempPath(), "PaqAgentInstaller", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempRoot);
            var zipPath = Path.Combine(tempRoot, "release.zip");

            AppendLog(_logInstall, $"Descargando {release.Version}...");
            var progress = new Progress<int>(p =>
            {
                if (InvokeRequired)
                    BeginInvoke(() => _progressInstall.Value = p);
                else
                    _progressInstall.Value = p;
            });
            await _github.DownloadReleaseAsync(release.DownloadUrl, zipPath, progress);

            AppendLog(_logInstall, "Descomprimiendo...");
            var extractPath = Path.Combine(tempRoot, "extract");
            ZipFile.ExtractToDirectory(zipPath, extractPath, overwriteFiles: true);

            var sourceDir = FindPublishRoot(extractPath);
            CopyDirectory(sourceDir, installPath, preserveLocalSettings: false);

            AppendLog(_logInstall, "Guardando configuración...");
            _settingsService.WriteSettings(installPath, CollectSettingsFromForm());
            WriteInstalledVersion(installPath, release.Version);

            var exePath = Path.Combine(installPath, Constants.AGENT_EXE_NAME);
            if (!File.Exists(exePath))
                throw new FileNotFoundException($"No se encontró {Constants.AGENT_EXE_NAME} en {installPath}");

            AppendLog(_logInstall, "Registrando servicio Windows...");
            if (_serviceHelper.IsServiceInstalled(Constants.AGENT_SERVICE_NAME))
            {
                AppendLog(_logInstall, "Servicio existente detectado: deteniendo y eliminando...");
                _serviceHelper.StopService(Constants.AGENT_SERVICE_NAME);
                _serviceHelper.UninstallService(Constants.AGENT_SERVICE_NAME);
            }

            _serviceHelper.InstallService(
                Constants.AGENT_SERVICE_NAME,
                Constants.AGENT_DISPLAY_NAME,
                exePath);
            _serviceHelper.StartService(Constants.AGENT_SERVICE_NAME);

            // Copiar el instalador a la carpeta de instalación para que la tarea
            // de auto-update siempre apunte a una ubicación estable.
            var installerDest = Path.Combine(installPath, "PaqAgentInstaller.exe");
            try
            {
                File.Copy(Application.ExecutablePath, installerDest, overwrite: true);
                TaskSchedulerHelper.RegisterUpdateTask(installerDest);
                AppendLog(_logInstall, "Tarea de auto-actualización registrada en Task Scheduler.");
            }
            catch (Exception ex)
            {
                AppendLog(_logInstall, $"ADVERTENCIA: no se pudo registrar la tarea de auto-update: {ex.Message}");
            }

            _detectedInstallPath = installPath;
            try
            {
                InstallerPreferences.SaveLastInstallPath(installPath);
            }
            catch (Exception ex)
            {
                AppendLog(_logInstall, $"ADVERTENCIA: no se pudo guardar la carpeta de instalación: {ex.Message}");
            }

            RefreshInstalledVersionLabel();
            AppendLog(_logInstall, "✓ Instalación completada");
            MessageBox.Show(this, "Instalación completada.", "Instalar", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            AppendLog(_logInstall, $"ERROR: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Error de instalación", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task CheckUpdateAsync()
    {
        try
        {
            if (!EnsureAdministrator())
                return;

            SetBusy(true);
            _btnUpdate.Enabled = false;
            _pendingRelease = null;

            var installPath = ResolveInstallPath();
            if (!Directory.Exists(installPath))
            {
                AppendLog(_logUpdate, $"No se encontró instalación en {installPath}");
                MessageBox.Show(this, "No hay una instalación detectada.", "Actualizar", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            // Leer settings para confirmar que hay config (preservar en update).
            _ = _settingsService.ReadSettings(installPath);

            AppendLog(_logUpdate, "Consultando GitHub releases/latest...");
            var release = await _github.GetLatestReleaseAsync();
            _lblAvailableVersion.Text = $"Disponible: {release.Version}";

            var installed = ReadInstalledVersion(installPath);
            _lblInstalledVersion.Text = $"Instalada: {(string.IsNullOrWhiteSpace(installed) ? "(desconocida)" : installed)}";

            if (!string.IsNullOrWhiteSpace(installed)
                && string.Equals(NormalizeVersion(installed), NormalizeVersion(release.Version), StringComparison.OrdinalIgnoreCase))
            {
                AppendLog(_logUpdate, "Ya tenés la última versión");
                _btnUpdate.Enabled = false;
                return;
            }

            _pendingRelease = release;
            _btnUpdate.Enabled = true;
            AppendLog(_logUpdate, $"Nueva versión disponible: {release.Version}. Podés actualizar.");
        }
        catch (Exception ex)
        {
            AppendLog(_logUpdate, $"ERROR: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task UpdateAsync()
    {
        try
        {
            if (!EnsureAdministrator())
                return;

            if (_pendingRelease is null)
            {
                MessageBox.Show(this, "Primero verificá si hay una actualización.", "Actualizar", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            SetBusy(true);
            _progressUpdate.Value = 0;

            var installPath = ResolveInstallPath();
            var updated = await _updateOrchestrator.CheckAndUpdateAsync(
                installPath,
                message => AppendLog(_logUpdate, message),
                pct =>
                {
                    if (InvokeRequired)
                        BeginInvoke(() => _progressUpdate.Value = pct);
                    else
                        _progressUpdate.Value = pct;
                });

            RefreshInstalledVersionLabel();
            _btnUpdate.Enabled = false;
            _pendingRelease = null;

            if (updated)
                MessageBox.Show(this, "Actualización completada.", "Actualizar", MessageBoxButtons.OK, MessageBoxIcon.Information);
            else
                MessageBox.Show(this, "No hay actualización pendiente.", "Actualizar", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            AppendLog(_logUpdate, $"ERROR: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Error de actualización", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private AgentSettings CollectSettingsFromForm() => new()
    {
        AgentId = _txtAgentId.Text.Trim(),
        ClientId = _txtClientId.Text.Trim(),
        GatewayUrl = _txtGatewayUrl.Text.Trim(),
        SqlServer = _txtSqlServer.Text.Trim(),
        SqlPort = _txtSqlPort.Text.Trim(),
        SqlDatabase = _txtSqlDatabase.Text.Trim(),
        SqlUser = _txtSqlUser.Text.Trim(),
        SqlPassword = _txtSqlPassword.Text,
    };

    private bool ValidateInstallFields()
    {
        var required = new (string Label, string Value)[]
        {
            ("AgentId", _txtAgentId.Text),
            ("ClientId", _txtClientId.Text),
            ("Gateway URL", _txtGatewayUrl.Text),
            ("Servidor SQL", _txtSqlServer.Text),
            ("Base de datos", _txtSqlDatabase.Text),
            ("Usuario SQL", _txtSqlUser.Text),
            ("Contraseña SQL", _txtSqlPassword.Text),
            ("Carpeta destino", _txtInstallPath.Text),
        };

        foreach (var (label, value) in required)
        {
            if (!string.IsNullOrWhiteSpace(value))
                continue;

            MessageBox.Show(this, $"El campo '{label}' es obligatorio.", "Validación", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }

        return true;
    }

    private bool EnsureAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        if (principal.IsInRole(WindowsBuiltInRole.Administrator))
            return true;

        MessageBox.Show(
            this,
            "Debés ejecutar el instalador como Administrador.",
            "Permisos",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
        return false;
    }

    private void SetBusy(bool busy)
    {
        UseWaitCursor = busy;
        _btnInstall.Enabled = !busy;
        _btnTestConnection.Enabled = !busy;
        _btnCheckUpdate.Enabled = !busy;
        if (busy)
            _btnUpdate.Enabled = false;
        else if (_pendingRelease is not null)
            _btnUpdate.Enabled = true;
    }

    private void RefreshInstalledVersionLabel()
    {
        var path = ResolveInstallPath();
        var version = Directory.Exists(path) ? ReadInstalledVersion(path) : "";
        _lblInstalledVersion.Text = string.IsNullOrWhiteSpace(version)
            ? "Instalada: (desconocida)"
            : $"Instalada: {version}";
    }

    private void TryFillFromLocalSettings(string installPath)
    {
        try
        {
            var settingsPath = Path.Combine(installPath, Constants.LOCAL_SETTINGS_FILE);
            if (!File.Exists(settingsPath))
                return;

            var settings = _settingsService.ReadSettings(installPath);
            _txtAgentId.Text = settings.AgentId;
            _txtClientId.Text = settings.ClientId;
            _txtGatewayUrl.Text = settings.GatewayUrl;
            _txtSqlServer.Text = settings.SqlServer;
            _txtSqlPort.Text = settings.SqlPort;
            _txtSqlDatabase.Text = settings.SqlDatabase;
            _txtSqlUser.Text = settings.SqlUser;
            // Contraseña: no autocompletar.
        }
        catch
        {
            // Sin settings previos o JSON ilegible.
        }
    }

    private string ResolveInstallPath()
    {
        if (!string.IsNullOrWhiteSpace(_txtInstallPath?.Text))
            return _txtInstallPath.Text.Trim();

        if (!string.IsNullOrWhiteSpace(_detectedInstallPath))
            return _detectedInstallPath;

        return InstallerPreferences.ReadLastInstallPath();
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

    private static void AppendLog(RichTextBox box, string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}";
        if (box.InvokeRequired)
        {
            box.BeginInvoke(() =>
            {
                box.AppendText(line);
                box.ScrollToCaret();
            });
        }
        else
        {
            box.AppendText(line);
            box.ScrollToCaret();
        }
    }
}
