namespace PaqAgent.Configuration;

public class PipeSettings
{
    public const string SectionName = "Pipe";

    /// <summary>
    /// Nombre base del named pipe. El AgentId se añade como sufijo
    /// para evitar colisiones si hubiera dos instalaciones en el mismo host.
    /// Resultado final: "paqagent-migrations-{AgentId}"
    /// </summary>
    public string PipeName { get; set; } = "paqagent-migrations";

    /// <summary>
    /// Tiempo máximo en segundos para que run-migrations complete.
    /// Debe ser mayor que SqlMigrations:CommandTimeoutSeconds * número de BDs.
    /// </summary>
    public int RunTimeoutSeconds { get; set; } = 600;
}
