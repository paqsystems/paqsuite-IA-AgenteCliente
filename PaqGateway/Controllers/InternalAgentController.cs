using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using PaqGateway.Authentication;

namespace PaqGateway.Controllers;

[ApiController]
[Route("internal/agents")]
[InternalApiKey]
public class InternalAgentController : ControllerBase
{
    private readonly IMemoryCache _cache;

    public InternalAgentController(IMemoryCache cache)
    {
        _cache = cache;
    }

    [HttpPost("{agentId}/invalidate-cache")]
    public ActionResult<InvalidateAgentCacheResponse> InvalidateCache(string agentId)
    {
        _cache.Remove(LaravelAgentAuthService.BuildCacheKey(agentId));

        return Ok(new InvalidateAgentCacheResponse { Invalidated = true });
    }
}

public class InvalidateAgentCacheResponse
{
    public bool Invalidated { get; set; }
}
