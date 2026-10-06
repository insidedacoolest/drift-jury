using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace DriftFactoryPlugin;

/// <summary>
/// Public, read-only data for the Drift Virtual page on driftfactory.pt,
/// served on the server's HTTP port: <c>GET /driftfactory/site.json</c>.
/// </summary>
[ApiController]
public class SiteController : ControllerBase
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private readonly DriftFactoryCommunity _community;

    public SiteController(DriftFactoryCommunity community)
    {
        _community = community;
    }

    [HttpGet("/driftfactory/site.json")]
    public ContentResult Site()
    {
        Response.Headers.CacheControl = "public, max-age=30";
        Response.Headers.AccessControlAllowOrigin = "*";
        return Content(JsonSerializer.Serialize(_community.SiteSnapshot(), JsonOptions), "application/json; charset=utf-8");
    }
}
