using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using PaqGateway.Configuration;

namespace PaqGateway.Authentication;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class InternalApiKeyAttribute : Attribute, IAuthorizationFilter
{
    public const string HeaderName = "X-Internal-Api-Key";

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var settings = context.HttpContext.RequestServices
            .GetRequiredService<IOptions<GatewaySettings>>().Value;

        if (string.IsNullOrWhiteSpace(settings.InternalApiKey))
        {
            context.Result = new ObjectResult(new { error = "Internal API key no configurada en gateway" })
            {
                StatusCode = StatusCodes.Status503ServiceUnavailable
            };
            return;
        }

        if (!context.HttpContext.Request.Headers.TryGetValue(HeaderName, out var providedKey)
            || !string.Equals(providedKey.ToString(), settings.InternalApiKey, StringComparison.Ordinal))
        {
            context.Result = new UnauthorizedObjectResult(new { error = "API key interna invalida" });
        }
    }
}
