using Microsoft.Extensions.Options;
using PaqGateway.Configuration;

namespace PaqGateway.Authentication;

public interface IAgentTokenValidator
{
    bool TryValidate(string agentId, string clientId, string token, out string? failureReason);
}

public class StaticAgentTokenValidator : IAgentTokenValidator
{
    private readonly GatewaySettings _settings;

    public StaticAgentTokenValidator(IOptions<GatewaySettings> settings)
    {
        _settings = settings.Value;
    }

    public bool TryValidate(string agentId, string clientId, string token, out string? failureReason)
    {
        failureReason = null;

        if (string.IsNullOrWhiteSpace(agentId))
        {
            failureReason = "X-Agent-Id requerido";
            return false;
        }

        if (string.IsNullOrWhiteSpace(clientId))
        {
            failureReason = "X-Client-Id requerido";
            return false;
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            failureReason = "Token de agente requerido";
            return false;
        }

        var registered = _settings.Agents.FirstOrDefault(a =>
            string.Equals(a.AgentId, agentId, StringComparison.OrdinalIgnoreCase));

        if (registered is null)
        {
            failureReason = "Agente no registrado en gateway";
            return false;
        }

        if (!registered.Enabled)
        {
            failureReason = "Agente deshabilitado";
            return false;
        }

        if (!string.Equals(registered.ClientId, clientId, StringComparison.OrdinalIgnoreCase))
        {
            failureReason = "ClientId no coincide";
            return false;
        }

        if (!string.Equals(registered.Token, token, StringComparison.Ordinal))
        {
            failureReason = "Token invalido";
            return false;
        }

        return true;
    }
}

public class LaravelBackedAgentTokenValidator : IAgentTokenValidator
{
    private readonly ILaravelAgentAuthService _laravelAuth;

    public LaravelBackedAgentTokenValidator(ILaravelAgentAuthService laravelAuth)
    {
        _laravelAuth = laravelAuth;
    }

    public bool TryValidate(string agentId, string clientId, string token, out string? failureReason)
    {
        failureReason = null;

        if (string.IsNullOrWhiteSpace(agentId))
        {
            failureReason = "X-Agent-Id requerido";
            return false;
        }

        if (string.IsNullOrWhiteSpace(clientId))
        {
            failureReason = "X-Client-Id requerido";
            return false;
        }

        if (string.IsNullOrWhiteSpace(token))
        {
            failureReason = "Token de agente requerido";
            return false;
        }

        var result = _laravelAuth.AuthenticateAsync(agentId, clientId, token)
            .GetAwaiter()
            .GetResult();

        if (!result.Valid)
        {
            failureReason = result.Reason ?? "Token invalido";
            return false;
        }

        if (!result.Enabled)
        {
            failureReason = result.Reason ?? "Agente deshabilitado";
            return false;
        }

        return true;
    }
}

public static class AgentConnectionAuth
{
    public const string AgentIdHeader = "X-Agent-Id";
    public const string ClientIdHeader = "X-Client-Id";
    public const string AgentVersionHeader = "X-Agent-Version";

    public static string? ExtractToken(HttpContext httpContext)
    {
        var queryToken = httpContext.Request.Query["access_token"].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(queryToken))
            return queryToken;

        if (httpContext.Request.Headers.TryGetValue("Authorization", out var authHeader))
        {
            var value = authHeader.ToString();
            if (value.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                return value["Bearer ".Length..].Trim();
        }

        return null;
    }

    public static string? ExtractHeader(HttpContext httpContext, string headerName)
    {
        if (!httpContext.Request.Headers.TryGetValue(headerName, out var values))
            return null;

        return values.FirstOrDefault();
    }
}
