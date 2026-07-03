namespace PaqGateway.Configuration;

public class LaravelApiSettings
{
    public const string SectionName = "LaravelApi";

    public string BaseUrl { get; set; } = string.Empty;

    public string InternalApiKey { get; set; } = string.Empty;

    public int AuthCacheTtlSeconds { get; set; } = 300;

    public int TimeoutSeconds { get; set; } = 5;
}
