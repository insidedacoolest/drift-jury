using JetBrains.Annotations;

namespace DriftFactoryPlugin;

/// <summary>
/// Optional settings, from the <c>!DriftFactoryConfiguration</c> section of
/// extra_cfg.yml. Without them the plugin still serves the online script and
/// records results; Discord posting is off until the webhook URLs are set.
/// </summary>
[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class DriftFactoryConfiguration
{
    /// <summary>Webhook of the #estado-servidores channel (live server status).</summary>
    public string? StatusWebhookUrl { get; init; }

    /// <summary>Webhook of the #classificação channel (weekly leaderboard per track).</summary>
    public string? LeaderboardWebhookUrl { get; init; }

    /// <summary>Webhook of the #runs channel (new weekly bests, weekly winners).</summary>
    public string? RunsWebhookUrl { get; init; }

    /// <summary>Content Manager join link shown in the status message.</summary>
    public string? JoinUrl { get; init; }

    /// <summary>Where the Drift Virtual page on driftfactory.pt receives the live data.</summary>
    public string SiteSyncUrl { get; init; } = "https://driftfactory.pt/api/virtual/sync";

    /// <summary>Key the site checks before accepting data; sending to the site is off without it.</summary>
    public string? SiteSyncKey { get; init; }

    /// <summary>How often the status message (and the site's data) is refreshed.</summary>
    public int StatusIntervalSeconds { get; init; } = 60;

    /// <summary>Weeks run Monday 00:00 to Sunday 23:59 in this time zone.</summary>
    public string TimeZone { get; init; } = "Europe/Lisbon";

    /// <summary>Where results are kept, relative to the server's working folder.</summary>
    public string DataDirectory { get; init; } = "driftfactory-data";
}
