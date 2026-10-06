using System.Reflection;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Server.Plugin;
using Serilog;

namespace DriftFactoryPlugin;

/// <summary>
/// Hands the Drift Factory Judge App online script to every CSP client that
/// joins, served by AssettoServer itself (no third-party host needed).
/// The script is fetched from GitHub when the server starts, so a new
/// version only needs a push to the repository and a server restart; if
/// GitHub can't be reached, the copy built into this plugin is used.
/// </summary>
public class DriftFactoryScript : IAssettoServerAutostart
{
    private const string ScriptUrl =
        "https://raw.githubusercontent.com/insidedacoolest/drift-jury/master/online/driftfactory.lua";

    private const string EmbeddedResourceName = "DriftFactoryPlugin.driftfactory.lua";

    // Every build of the online script starts with this header line, so a
    // GitHub error page or an unrelated file is never handed to players.
    private const string ScriptMarker = "Drift Factory Judge App";

    public DriftFactoryScript(CSPServerScriptProvider scriptProvider, ACServerConfiguration serverConfiguration)
    {
        if (!serverConfiguration.Extra.EnableClientMessages)
        {
            Log.Warning("DriftFactoryPlugin: CSP client messages are disabled; the shared leaderboard needs EnableClientMessages: true");
        }

        var script = Download() ?? LoadEmbedded();
        scriptProvider.AddScript(script, "driftfactory.lua");
    }

    private static string? Download()
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            http.DefaultRequestHeaders.UserAgent.ParseAdd("DriftFactoryPlugin/0.2.0");
            var script = http.GetStringAsync(ScriptUrl).GetAwaiter().GetResult();
            if (script.Contains(ScriptMarker))
            {
                Log.Information("DriftFactoryPlugin: serving the online script from GitHub ({Bytes} bytes)", script.Length);
                return script;
            }

            Log.Warning("DriftFactoryPlugin: GitHub returned something that isn't the online script, using the built-in copy");
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "DriftFactoryPlugin: could not download the online script, using the built-in copy");
        }

        return null;
    }

    private static string LoadEmbedded()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(EmbeddedResourceName)
                           ?? throw new InvalidOperationException("DriftFactoryPlugin: built-in online script missing");
        using var reader = new StreamReader(stream);
        var script = reader.ReadToEnd();
        Log.Information("DriftFactoryPlugin: serving the built-in online script ({Bytes} bytes)", script.Length);
        return script;
    }

    public Task StartAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
