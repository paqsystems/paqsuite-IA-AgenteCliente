using PaqGateway.Authentication;
using PaqGateway.Configuration;
using PaqGateway.Hubs;
using PaqGateway.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<GatewaySettings>(builder.Configuration.GetSection(GatewaySettings.SectionName));

builder.Services.AddSingleton<IAgentConnectionRegistry, AgentConnectionRegistry>();
builder.Services.AddSingleton<IJobCorrelationService, JobCorrelationService>();
builder.Services.AddSingleton<IAgentTokenValidator, AgentTokenValidator>();

builder.Services.AddSignalR();
builder.Services.AddControllers();

var app = builder.Build();

app.MapControllers();
app.MapHub<AgentHub>("/agent-hub");

app.Run();
