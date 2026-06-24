using Microsoft.Extensions.Configuration;
using Serilog;
using Serilog.Events;

namespace PaqAgent.Logging;

public static class LogConfiguration
{
    public static void Configure(IConfiguration configuration)
    {
        var logDirectory = configuration["Logging:LogDirectory"] ?? "logs";
        var minimumLevel = configuration["Logging:MinimumLevel"] ?? "Information";
        var level = Enum.TryParse<LogEventLevel>(minimumLevel, true, out var parsed)
            ? parsed
            : LogEventLevel.Information;

        Directory.CreateDirectory(logDirectory);

        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Is(level)
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("System", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("MachineName", Environment.MachineName)
            .WriteTo.Console(
                outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.File(
                Path.Combine(logDirectory, "agent.log"),
                rollingInterval: RollingInterval.Day,
                retainedFileCountLimit: 30,
                outputTemplate: "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj}{NewLine}{Exception}")
            .WriteTo.Logger(lc => lc
                .Filter.ByIncludingOnly(e => e.Properties.ContainsKey("Category") &&
                    e.Properties["Category"].ToString().Contains("Connection"))
                .WriteTo.File(
                    Path.Combine(logDirectory, "connection.log"),
                    rollingInterval: RollingInterval.Day,
                    retainedFileCountLimit: 30))
            .WriteTo.Logger(lc => lc
                .Filter.ByIncludingOnly(e => e.Properties.ContainsKey("Category") &&
                    e.Properties["Category"].ToString().Contains("Job"))
                .WriteTo.File(
                    Path.Combine(logDirectory, "jobs.log"),
                    rollingInterval: RollingInterval.Day,
                    retainedFileCountLimit: 30))
            .WriteTo.Logger(lc => lc
                .Filter.ByIncludingOnly(e => e.Level >= LogEventLevel.Error)
                .WriteTo.File(
                    Path.Combine(logDirectory, "errors.log"),
                    rollingInterval: RollingInterval.Day,
                    retainedFileCountLimit: 90))
            .CreateLogger();
    }
}
