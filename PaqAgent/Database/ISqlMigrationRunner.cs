namespace PaqAgent.Database;

public interface ISqlMigrationRunner
{
    Task RunAsync(CancellationToken cancellationToken = default);
}
