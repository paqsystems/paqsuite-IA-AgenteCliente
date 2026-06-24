using Microsoft.Extensions.Options;
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

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "PaqAgent";
});

LogConfiguration.Configure(builder.Configuration);
builder.Services.AddSerilog();

builder.Services.Configure<AgentSettings>(builder.Configuration.GetSection(AgentSettings.SectionName));
builder.Services.Configure<SqlConnectionSettings>(builder.Configuration.GetSection(SqlConnectionSettings.SectionName));
builder.Services.Configure<OperationSettings>(builder.Configuration.GetSection(OperationSettings.SectionName));

builder.Services.AddSingleton<TokenProvider>();
builder.Services.AddSingleton<AgentAuthenticator>();
builder.Services.AddSingleton<ISqlExecutor, SqlExecutor>();
builder.Services.AddSingleton<OperationRegistry>();
builder.Services.AddSingleton<AuthLoginOperation>();
builder.Services.AddSingleton<JobDispatcher>();
builder.Services.AddSingleton<DiagnosticsService>();

builder.Services.AddSingleton<IAgentConnection, SignalRAgentConnection>();

builder.Services.AddHostedService<AgentWorker>();
builder.Services.AddHostedService<HeartbeatService>();

var host = builder.Build();

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
