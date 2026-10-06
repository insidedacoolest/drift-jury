using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Serilog;

namespace DriftFactoryPlugin;

/// <summary>
/// Sends <see cref="DriftFactoryCommunity.SiteSnapshot"/> to the Drift
/// Virtual page on driftfactory.pt. The site's hosting can't reach the game
/// server's HTTP port, so the server pushes over HTTPS instead.
/// </summary>
public class SitePublisher
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private readonly Uri _url;
    private readonly string _key;
    private bool _lastFailed;

    private SitePublisher(Uri url, string key)
    {
        _url = url;
        _key = key;
    }

    public static SitePublisher? FromConfiguration(DriftFactoryConfiguration configuration)
    {
        if (string.IsNullOrWhiteSpace(configuration.SiteSyncKey)) return null;
        if (!Uri.TryCreate(configuration.SiteSyncUrl, UriKind.Absolute, out var url))
        {
            Log.Warning("DriftFactoryPlugin: SiteSyncUrl {Url} is not a valid address, not sending to the site", configuration.SiteSyncUrl);
            return null;
        }
        return new SitePublisher(url, configuration.SiteSyncKey.Trim());
    }

    public async Task PublishAsync(object snapshot, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, _url)
        {
            Content = new StringContent(JsonSerializer.Serialize(snapshot, JsonOptions), Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _key);

        try
        {
            using var response = await Http.SendAsync(request, token);
            if (!response.IsSuccessStatusCode)
            {
                throw new HttpRequestException($"{(int)response.StatusCode} {await response.Content.ReadAsStringAsync(token)}");
            }
            if (_lastFailed) Log.Information("DriftFactoryPlugin: sending to the site works again");
            _lastFailed = false;
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !token.IsCancellationRequested)
        {
            // Log once per outage, not every minute.
            if (!_lastFailed) Log.Warning("DriftFactoryPlugin: could not send to the site: {Error}", ex.Message);
            _lastFailed = true;
        }
    }
}
