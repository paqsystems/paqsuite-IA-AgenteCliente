using Microsoft.Extensions.Options;
using PaqGateway.Authentication;
using PaqGateway.Configuration;
using PaqGateway.Hubs;
using PaqGateway.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<GatewaySettings>(builder.Configuration.GetSection(GatewaySettings.SectionName));
builder.Services.Configure<LaravelApiSettings>(
    builder.Configuration.GetSection(LaravelApiSettings.SectionName));

builder.Services.AddMemoryCache();
builder.Services.AddHttpClient(LaravelAgentAuthService.HttpClientName, (sp, client) =>
{
    var settings = sp.GetRequiredService<IOptions<LaravelApiSettings>>().Value;
    client.BaseAddress = new Uri(
        !string.IsNullOrWhiteSpace(settings.InternalUrl)
            ? settings.InternalUrl
            : settings.BaseUrl);
    // Cuando InternalUrl usa IP (ruta Tailscale), nginx del host Laravel necesita
    // el Host header para enrutar al vhost correcto entre varios sitios hospedados.
    if (!string.IsNullOrWhiteSpace(settings.InternalUrl) &&
        !string.IsNullOrWhiteSpace(settings.BaseUrl))
    {
        client.DefaultRequestHeaders.Host = new Uri(settings.BaseUrl).Host;
    }
    client.Timeout = TimeSpan.FromSeconds(settings.TimeoutSeconds);
})
.ConfigurePrimaryHttpMessageHandler(sp =>
{
    var settings = sp.GetRequiredService<IOptions<LaravelApiSettings>>().Value;
    var handler = new HttpClientHandler();
    if (settings.InternalSkipTlsValidation)
    {
        handler.ServerCertificateCustomValidationCallback =
            (message, cert, chain, sslPolicyErrors) => true;
    }
    return handler;
});

builder.Services.AddSingleton<IAgentConnectionRegistry, AgentConnectionRegistry>();
builder.Services.AddSingleton<IJobCorrelationService, JobCorrelationService>();
builder.Services.AddSingleton<ILaravelAgentAuthService, LaravelAgentAuthService>();
builder.Services.AddSingleton<IAgentTokenValidator, LaravelBackedAgentTokenValidator>();

builder.Services.AddSignalR(options =>
{
    options.MaximumReceiveMessageSize = 1024 * 1024; // 1MB
    options.KeepAliveInterval = TimeSpan.FromSeconds(15);
    options.ClientTimeoutInterval = TimeSpan.FromSeconds(90);
});
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();
app.MapHub<AgentHub>("/agent-hub");

app.Run();
