using Microsoft.Extensions.Options;
using PaqAgent.Configuration;

namespace PaqAgent.Security;

public class TokenProvider
{
    private readonly AgentSettings _settings;

    public TokenProvider(IOptions<AgentSettings> settings)
    {
        _settings = settings.Value;
    }

    public string GetToken() => _settings.AgentToken;

    public string GetAuthorizationHeader() => $"Bearer {_settings.AgentToken}";
}
