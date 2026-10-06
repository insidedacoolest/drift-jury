# DriftFactoryPlugin (AssettoServer)

Serves the Drift Factory Judge App online script (`online/driftfactory.lua`)
to every CSP player who joins, from AssettoServer itself — for hosts that
don't let you link an online script from GitHub (Pitlane Hosting only
accepts Pastebin links there).

When the server starts, the plugin downloads the current
`online/driftfactory.lua` from this repository's `master` branch and hands
it to AssettoServer's own script provider (`CSPServerScriptProvider`), which
adds it to the CSP extra options sent to clients and serves it from the
server's HTTP port. If GitHub can't be reached, the copy built into the
plugin is used. New versions of the app therefore only need a push to
GitHub and a server restart — no new plugin upload.

Needs `EnableClientMessages: true` in `extra_cfg.yml` for the shared
leaderboard (the plugin logs a warning if it's off).

## Building

Built against AssettoServer **v0.0.54** (the version Pitlane runs), .NET 8:

```
git clone https://github.com/compujuckel/AssettoServer.git
git -C AssettoServer checkout v0.0.54
dotnet publish server-plugin/DriftFactoryPlugin/DriftFactoryPlugin.csproj -c Release -o dist/plugin/DriftFactoryPlugin -p:AssettoServerSrc=<path to AssettoServer checkout>
```

(AssettoServer's build needs a full clone, not a shallow one — it derives
its version number from git history.) Zip the `DriftFactoryPlugin` folder
and upload it to the server's plugins; enable it with
`EnablePlugins: [DriftFactoryPlugin]`.

Tested against a local AssettoServer v0.0.54: the plugin loads, fetches the
script from GitHub, and `/api/scripts/0` serves it byte-for-byte.
