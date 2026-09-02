using Microsoft.Extensions.DependencyInjection;
using PaqAgent.Communication;
using PaqAgent.Configuration;
using PaqAgent.Database;
using PaqAgent.Jobs;
using PaqAgent.Logging;
using PaqAgent.Operations;
using PaqAgent.Security;
using PaqAgent.Services;
using Serilog;

var builder = Host.CreateApplicationBuilder(args);

builder.Configuration.AddJsonFile("appsettings.local.json", optional: true, reloadOnChange: false);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "PaqAgent";
});

LogConfiguration.Configure(builder.Configuration);
builder.Services.AddSerilog();

builder.Services.Configure<AgentSettings>(builder.Configuration.GetSection(AgentSettings.SectionName));
builder.Services.Configure<SqlConnectionSettings>(builder.Configuration.GetSection(SqlConnectionSettings.SectionName));
builder.Services.Configure<SqlMigrationSettings>(builder.Configuration.GetSection(SqlMigrationSettings.SectionName));
builder.Services.Configure<PipeSettings>(
    builder.Configuration.GetSection(PipeSettings.SectionName));
builder.Services.Configure<OperationSettings>(builder.Configuration.GetSection(OperationSettings.SectionName));

builder.Services.AddSingleton<TokenProvider>();
builder.Services.AddSingleton<AgentAuthenticator>();
builder.Services.AddSingleton<ISqlExecutor, SqlExecutor>();
builder.Services.AddSingleton<ISqlMigrationRunner, SqlMigrationRunner>();
builder.Services.AddSingleton<OperationRegistry>();
builder.Services.AddSingleton<AuthLoginOperation>();
builder.Services.AddSingleton<JobDispatcher>();
builder.Services.AddSingleton<DiagnosticsService>();

builder.Services.AddSingleton<IAgentConnection, SignalRAgentConnection>();

builder.Services.AddHostedService<AgentWorker>();
builder.Services.AddHostedService<HeartbeatService>();
builder.Services.AddHostedService<MigrationPipeService>();

var host = builder.Build();

using (var scope = host.Services.CreateScope())
{
    var migrationRunner = scope.ServiceProvider.GetRequiredService<ISqlMigrationRunner>();
    const int maxAttempts = 5;
    var delaySeconds = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++)
    {
        try
        {
            await migrationRunner.RunAsync(CancellationToken.None);
            break;
        }
        catch (Exception ex) when (attempt < maxAttempts)
        {
            Log.Warning(
                ex,
                "Fallo en migraciones SQL (intento {Attempt}/{MaxAttempts}). Reintento en {DelaySeconds}s...",
                attempt, maxAttempts, delaySeconds);
            await Task.Delay(TimeSpan.FromSeconds(delaySeconds));
            delaySeconds *= 2;
        }
        catch (Exception ex)
        {
            Log.Fatal(
                ex,
                "PaqAgent no pudo iniciar: fallo en migraciones SQL tras {MaxAttempts} intentos. El servicio no se conectará al Gateway.",
                maxAttempts);
            await Log.CloseAndFlushAsync();
            Environment.Exit(1);
        }
    }
}

try
{
    Log.Information("Iniciando PaqAgent Worker Service");
    await host.RunAsync();
}
catch (Exception ex)
{
    Log.Fatal(ex, "PaqAgent termino inesperadamente");
}
finally
{
    await Log.CloseAndFlushAsync();
}
