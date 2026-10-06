using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Serilog;

namespace DriftFactoryPlugin;

/// <summary>
/// Minimal Discord webhook client: post a message (returning its id) and
/// edit a previously posted one, so live messages update in place.
/// </summary>
public class DiscordWebhook
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private readonly string _url;

    public DiscordWebhook(string url)
    {
        _url = url.TrimEnd('/');
    }

    public static DiscordWebhook? FromUrl(string? url) =>
        string.IsNullOrWhiteSpace(url) ? null : new DiscordWebhook(url.Trim());

    /// <summary>Posts a message and returns its id, or null if Discord refused it.</summary>
    public async Task<string?> PostAsync(object payload, CancellationToken token = default)
    {
        using var response = await SendAsync(HttpMethod.Post, $"{_url}?wait=true", payload, token);
        if (response is not { IsSuccessStatusCode: true }) return null;
        var body = await response.Content.ReadFromJsonAsync<JsonObject>(cancellationToken: token);
        return body?["id"]?.GetValue<string>();
    }

    /// <summary>Edits a message this webhook posted. False if it no longer exists.</summary>
    public async Task<bool> EditAsync(string messageId, object payload, CancellationToken token = default)
    {
        using var response = await SendAsync(HttpMethod.Patch, $"{_url}/messages/{messageId}", payload, token);
        return response is { IsSuccessStatusCode: true };
    }

    /// <summary>Edits the message if there is one, otherwise posts a new one; returns the id in use.</summary>
    public async Task<string?> UpsertAsync(string? messageId, object payload, CancellationToken token = default)
    {
        if (messageId != null && await EditAsync(messageId, payload, token)) return messageId;
        return await PostAsync(payload, token);
    }

    private static async Task<HttpResponseMessage?> SendAsync(HttpMethod method, string url, object payload, CancellationToken token)
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                var request = new HttpRequestMessage(method, url) { Content = JsonContent.Create(payload) };
                var response = await Http.SendAsync(request, token);
                if (response.StatusCode != HttpStatusCode.TooManyRequests) return LogFailure(response);

                // Rate limited: wait as long as Discord asks, then retry.
                var body = await response.Content.ReadFromJsonAsync<JsonObject>(cancellationToken: token);
                var retryAfter = body?["retry_after"]?.GetValue<double>() ?? 1.0;
                response.Dispose();
                await Task.Delay(TimeSpan.FromSeconds(Math.Min(retryAfter, 30)), token);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
            {
                Log.Warning("DriftFactoryPlugin: Discord request failed: {Message}", ex.Message);
                return null;
            }
        }

        return null;
    }

    private static HttpResponseMessage LogFailure(HttpResponseMessage response)
    {
        // A missing message (404) is expected when someone deleted it; the caller reposts.
        if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.NotFound)
        {
            Log.Warning("DriftFactoryPlugin: Discord answered {Status}", (int)response.StatusCode);
        }

        return response;
    }
}
