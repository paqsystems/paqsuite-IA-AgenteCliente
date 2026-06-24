namespace PaqAgent.Configuration;

public class OperationSettings
{
    public const string SectionName = "Operations";

    public Dictionary<string, OperationDefinition> Definitions { get; set; } = new();
}

public class OperationDefinition
{
    public string StoredProcedure { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool Enabled { get; set; } = true;
    public int TimeoutSeconds { get; set; } = 30;
    public List<string> Parameters { get; set; } = new();
}
