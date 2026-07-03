using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using PaqGateway.Configuration;

namespace PaqGateway.Authentication;

public interface ILaravelAgentAuthService
{
    Task<AgentAuthResult> AuthenticateAsync(
        string agentId, string clientId, string token,
        CancellationToken ct = default);

    Task UpdateHeartbeatAsync(
        string agentId, string version,
        CancellationToken ct = default);
}

public record AgentAuthResult(bool Valid, bool Enabled, string? Reason);

public class LaravelAgentAuthService : ILaravelAgentAuthService
{
    public const string HttpClientName = "laravel";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IMemoryCache _cache;
    private readonly LaravelApiSettings _settings;
    private readonly ILogger<LaravelAgentAuthService> _logger;

    public LaravelAgentAuthService(
        IHttpClientFactory httpClientFactory,
        IMemoryCache cache,
        IOptions<LaravelApiSettings> settings,
        ILogger<LaravelAgentAuthService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _cache = cache;
        _settings = settings.Value;
        _logger = logger;
    }

    public static string BuildCacheKey(string agentId) => $"agent_auth:{agentId}";

    public async Task<AgentAuthResult> AuthenticateAsync(
        string agentId, string clientId, string token,
        CancellationToken ct = default)
    {
        var cacheKey = BuildCacheKey(agentId);

        if (_cache.TryGetValue(cacheKey, out AgentAuthResult? cached) && cached is not null)
            return cached;

        try
        {
            var client = _httpClientFactory.CreateClient(HttpClientName);
            using var request = new HttpRequestMessage(HttpMethod.Post, "/api/internal/gateway/authenticate");
            request.Headers.TryAddWithoutValidation("X-Internal-Api-Key", _settings.InternalApiKey);
            request.Content = JsonContent.Create(new LaravelAuthenticateRequest(agentId, clientId, token));

            using var response = await client.SendAsync(request, ct);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Laravel rechazó autenticación de agente {AgentId}: HTTP {StatusCode}",
                    agentId,
                    (int)response.StatusCode);

                return new AgentAuthResult(false, false, "Autenticacion rechazada por Laravel");
            }

            var body = await response.Content.ReadFromJsonAsync<LaravelAuthenticateResponse>(cancellationToken: ct);
            var result = body is null
                ? new AgentAuthResult(false, false, "Respuesta invalida de Laravel")
                : new AgentAuthResult(body.Valid, body.Enabled, body.Reason);

            _cache.Set(
                cacheKey,
                result,
                TimeSpan.FromSeconds(_settings.AuthCacheTtlSeconds));

            return result;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error consultando autenticación de agente {AgentId} en Laravel", agentId);
            return new AgentAuthResult(false, false, "Laravel no disponible");
        }
    }

    public Task UpdateHeartbeatAsync(string agentId, string version, CancellationToken ct = default)
    {
        _ = SendHeartbeatAsync(agentId, version, ct);
        return Task.CompletedTask;
    }

    private async Task SendHeartbeatAsync(string agentId, string version, CancellationToken ct)
    {
        try
        {
            var client = _httpClientFactory.CreateClient(HttpClientName);
            using var request = new HttpRequestMessage(
                HttpMethod.Patch,
                $"/api/internal/gateway/agents/{Uri.EscapeDataString(agentId)}/heartbeat");
            request.Headers.TryAddWithoutValidation("X-Internal-Api-Key", _settings.InternalApiKey);
            request.Content = JsonContent.Create(new LaravelHeartbeatRequest(version));

            using var response = await client.SendAsync(request, ct);

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Laravel rechazó heartbeat de agente {AgentId}: HTTP {StatusCode}",
                    agentId,
                    (int)response.StatusCode);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error enviando heartbeat de agente {AgentId} a Laravel", agentId);
        }
    }

    private sealed record LaravelAuthenticateRequest(
        [property: JsonPropertyName("agentId")] string AgentId,
        [property: JsonPropertyName("clientId")] string ClientId,
        [property: JsonPropertyName("token")] string Token);

    private sealed record LaravelHeartbeatRequest(
        [property: JsonPropertyName("version")] string Version);

    private sealed class LaravelAuthenticateResponse
    {
        [JsonPropertyName("valid")]
        public bool Valid { get; set; }

        [JsonPropertyName("enabled")]
        public bool Enabled { get; set; }

        [JsonPropertyName("reason")]
        public string? Reason { get; set; }
    }
}
