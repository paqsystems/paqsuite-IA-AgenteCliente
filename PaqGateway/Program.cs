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
    client.BaseAddress = new Uri(settings.BaseUrl);
    client.Timeout = TimeSpan.FromSeconds(settings.TimeoutSeconds);
});

builder.Services.AddSingleton<IAgentConnectionRegistry, AgentConnectionRegistry>();
builder.Services.AddSingleton<IJobCorrelationService, JobCorrelationService>();
builder.Services.AddSingleton<ILaravelAgentAuthService, LaravelAgentAuthService>();
builder.Services.AddSingleton<IAgentTokenValidator, LaravelBackedAgentTokenValidator>();

builder.Services.AddSignalR();
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();
app.MapHub<AgentHub>("/agent-hub");

app.Run();
