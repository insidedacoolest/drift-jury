using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Server.Plugin;
using AssettoServer.Shared.Services;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace DriftFactoryPlugin;

/// <summary>
/// Receives every run result from the online script, keeps the weekly
/// leaderboards (and the permanent record) via <see cref="ResultsStore"/>,
/// and mirrors them to Discord: a live server-status message, one
/// leaderboard message per track per week (edited in place), and
/// announcements of new weekly bests and weekly winners.
/// </summary>
public class DriftFactoryCommunity : CriticalBackgroundService, IAssettoServerAutostart
{
    private const int LeaderColor = 0xD4FF3F;   // brand lime
    private const int MutedColor = 0x2B2F36;
    private const int FinalColor = 0xFF3EC8;    // brand magenta
    private static readonly string[] Months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

    private readonly DriftFactoryConfiguration _configuration;
    private readonly ACServerConfiguration _serverConfiguration;
    private readonly EntryCarManager _entryCarManager;
    private readonly ResultsStore _store;
    private readonly DiscordWebhook? _statusHook;
    private readonly DiscordWebhook? _leaderboardHook;
    private readonly DiscordWebhook? _runsHook;
    private readonly SitePublisher? _site;
    private readonly Channel<Announcement> _announcements = Channel.CreateUnbounded<Announcement>();
    private readonly Dictionary<string, (float, bool, float, float, float)> _lastPayload = new();
    private readonly Dictionary<string, string> _displayNames = new();
    private readonly string _track;

    private record Announcement(string Driver, string Car, float Score, RecordOutcome Outcome);

    public DriftFactoryCommunity(DriftFactoryConfiguration configuration,
        ACServerConfiguration serverConfiguration,
        EntryCarManager entryCarManager,
        CSPClientMessageTypeManager clientMessages,
        IHostApplicationLifetime applicationLifetime) : base(applicationLifetime)
    {
        _configuration = configuration;
        _serverConfiguration = serverConfiguration;
        _entryCarManager = entryCarManager;
        _store = new ResultsStore(configuration);
        _statusHook = DiscordWebhook.FromUrl(configuration.StatusWebhookUrl);
        _leaderboardHook = DiscordWebhook.FromUrl(configuration.LeaderboardWebhookUrl);
        _runsHook = DiscordWebhook.FromUrl(configuration.RunsWebhookUrl);
        _site = SitePublisher.FromConfiguration(configuration);
        _track = string.IsNullOrEmpty(serverConfiguration.Server.TrackConfig)
            ? serverConfiguration.Server.Track
            : $"{serverConfiguration.Server.Track}/{serverConfiguration.Server.TrackConfig}";

        clientMessages.RegisterOnlineEvent<RunResultEvent>(OnRunResult);

        if (_statusHook == null && _leaderboardHook == null && _runsHook == null)
        {
            Log.Information("DriftFactoryPlugin: no Discord webhooks configured, results are only recorded");
        }
    }

    private void OnRunResult(ACTcpClient sender, RunResultEvent run)
    {
        // Registering this message type stops AssettoServer from relaying it,
        // so pass it on to everyone else: their on-screen leaderboards need it.
        run.SessionId = sender.SessionId;
        _entryCarManager.BroadcastPacket(run, sender);

        var driver = sender.Name ?? $"Carro {sender.SessionId}";
        var driverKey = sender.Guid != 0 ? sender.Guid.ToString(CultureInfo.InvariantCulture) : driver;

        // CSP resends a driver's last result whenever someone joins; that's a
        // repeat, not a new run.
        var payload = (run.Score, run.Valid, run.Line, run.Angle, run.StyleSpeed);
        lock (_lastPayload)
        {
            if (_lastPayload.TryGetValue(driverKey, out var last) && last == payload) return;
            _lastPayload[driverKey] = payload;
        }

        var car = CarName(sender.EntryCar.Model);
        var outcome = _store.Record(_track, car, driver, driverKey, run);
        Log.Information("DriftFactoryPlugin: {Driver} {Result} {Score:0.0} on {Track}",
            driver, run.Valid ? "scored" : "invalid run,", run.Score, _track);
        if (outcome.NewWeeklyBest)
        {
            _announcements.Writer.TryWrite(new Announcement(driver, car, run.Score, outcome));
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _store.State.LastClosedWeek ??= _store.WeekKey(DateTime.UtcNow.AddDays(-7));
        await UpdateLeaderboardAsync(_store.CurrentWeek(), final: false, stoppingToken);

        var nextStatus = DateTime.MinValue;
        while (!stoppingToken.IsCancellationRequested)
        {
            // The site gets the same refresh as the Discord status, and right
            // away after a new weekly best.
            var siteDue = false;
            try
            {
                await CloseFinishedWeeksAsync(stoppingToken);

                while (_announcements.Reader.TryRead(out var announcement))
                {
                    siteDue = true;
                    await AnnounceAsync(announcement, stoppingToken);
                    await UpdateLeaderboardAsync(announcement.Outcome.Week, final: false, stoppingToken);
                }

                if (DateTime.UtcNow >= nextStatus)
                {
                    siteDue = true;
                    nextStatus = DateTime.UtcNow.AddSeconds(Math.Max(15, _configuration.StatusIntervalSeconds));
                    await UpdateStatusAsync(stoppingToken);
                }
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                Log.Error(ex, "DriftFactoryPlugin: Discord update failed");
            }

            if (siteDue && _site != null)
            {
                await _site.PublishAsync(SiteSnapshot(), stoppingToken);
            }

            // Wake up for the next status refresh or as soon as a result arrives.
            var wait = nextStatus - DateTime.UtcNow;
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            timeout.CancelAfter(wait > TimeSpan.Zero ? wait : TimeSpan.FromSeconds(1));
            try
            {
                await _announcements.Reader.WaitToReadAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested)
            {
            }
        }
    }

    // ---- Discord messages ------------------------------------------------

    private async Task UpdateStatusAsync(CancellationToken token)
    {
        if (_statusHook == null) return;

        var drivers = _entryCarManager.EntryCars
            .Where(car => car.Client is { HasSentFirstUpdate: true })
            .Select(car => Escape(car.Client!.Name ?? "?"))
            .ToList();
        var cars = _serverConfiguration.EntryList.Cars
            .Select(car => CarName(car.Model)).Distinct().ToList();

        var fields = new List<object>
        {
            new { name = "Pista", value = TrackName(), inline = true },
            new { name = "Pilotos", value = $"{drivers.Count}/{_serverConfiguration.Server.MaxClients}", inline = true },
            new { name = "Carros", value = cars.Count > 0 ? string.Join("\n", cars) : "—", inline = false },
        };
        if (drivers.Count > 0)
        {
            fields.Add(new { name = "A conduzir agora", value = Truncate(string.Join(", ", drivers), 1000), inline = false });
        }
        if (!string.IsNullOrWhiteSpace(_configuration.JoinUrl))
        {
            fields.Add(new { name = "Entrar", value = $"[Abrir no Content Manager]({_configuration.JoinUrl})", inline = false });
        }

        var payload = new
        {
            embeds = new[]
            {
                new
                {
                    title = _serverConfiguration.Server.Name,
                    color = drivers.Count > 0 ? LeaderColor : MutedColor,
                    fields,
                    footer = new { text = "Atualiza a cada minuto" },
                    timestamp = DateTime.UtcNow.ToString("o"),
                }
            }
        };

        var id = await _statusHook.UpsertAsync(_store.State.StatusMessageId, payload, token);
        if (id != null && id != _store.State.StatusMessageId)
        {
            _store.State.StatusMessageId = id;
            _store.Save();
        }
    }

    private async Task UpdateLeaderboardAsync(string week, bool final, CancellationToken token)
    {
        if (_leaderboardHook == null) return;

        var ranked = ResultsStore.Ranked(_store.Board(week, _track));
        var rows = new StringBuilder();
        for (var i = 0; i < Math.Min(ranked.Count, 20); i++)
        {
            var entry = ranked[i];
            var place = i switch { 0 => "🥇", 1 => "🥈", 2 => "🥉", _ => $"`{i + 1,2}`" };
            rows.AppendLine($"{place} **{Escape(entry.Driver)}** — `{Score(entry.Score)}` · {Escape(entry.Car)}");
        }
        if (ranked.Count == 0) rows.AppendLine("_Ainda sem runs válidas esta semana._");

        var payload = new
        {
            embeds = new[]
            {
                new
                {
                    title = (final ? "🏁 FINAL · " : "") + $"Classificação · {TrackName()}",
                    description = $"**{WeekLabel(week)}**\n\n{rows}",
                    color = final ? FinalColor : LeaderColor,
                    footer = new { text = "Melhor run válida de cada piloto · nova semana à segunda-feira" },
                    timestamp = DateTime.UtcNow.ToString("o"),
                }
            }
        };

        var key = $"{week}|{_track}";
        _store.State.LeaderboardMessageIds.TryGetValue(key, out var messageId);
        var id = await _leaderboardHook.UpsertAsync(messageId, payload, token);
        if (id != null && id != messageId)
        {
            _store.State.LeaderboardMessageIds[key] = id;
            _store.Save();
        }
    }

    private async Task AnnounceAsync(Announcement announcement, CancellationToken token)
    {
        if (_runsHook == null) return;
        var outcome = announcement.Outcome;
        var headline = outcome.NewLeader
            ? $"🥇 **{Escape(announcement.Driver)}** é o novo líder da semana em {TrackName()}!"
            : $"**{Escape(announcement.Driver)}** subiu para {outcome.Position}.º lugar em {TrackName()}";
        await _runsHook.PostAsync(new
        {
            embeds = new[]
            {
                new
                {
                    description = $"{headline}\n`{Score(announcement.Score)}` pontos · {Escape(announcement.Car)}",
                    color = outcome.NewLeader ? LeaderColor : MutedColor,
                    timestamp = DateTime.UtcNow.ToString("o"),
                }
            }
        }, token);
    }

    /// <summary>
    /// Once a week is over: mark its leaderboard final and announce the
    /// winner. Results stay in state.json and runs.jsonl for good.
    /// </summary>
    private async Task CloseFinishedWeeksAsync(CancellationToken token)
    {
        var current = _store.CurrentWeek();
        var finished = _store.State.Weeks.Keys
            .Where(week => string.CompareOrdinal(week, current) < 0
                           && string.CompareOrdinal(week, _store.State.LastClosedWeek) > 0)
            .OrderBy(week => week, StringComparer.Ordinal)
            .ToList();

        foreach (var week in finished)
        {
            await UpdateLeaderboardAsync(week, final: true, token);
            var winner = ResultsStore.Ranked(_store.Board(week, _track)).FirstOrDefault();
            if (winner != null && _runsHook != null)
            {
                await _runsHook.PostAsync(new
                {
                    embeds = new[]
                    {
                        new
                        {
                            description = $"🏆 **{Escape(winner.Driver)}** venceu a {WeekLabel(week).ToLowerInvariant()} em {TrackName()} com `{Score(winner.Score)}` pontos!",
                            color = FinalColor,
                        }
                    }
                }, token);
            }

            _store.State.LastClosedWeek = week;
            _store.Save();
        }

        if (string.CompareOrdinal(_store.State.LastClosedWeek, current) < 0 && finished.Count > 0)
        {
            // A new week has started: give it a fresh leaderboard message.
            await UpdateLeaderboardAsync(current, final: false, token);
        }
    }

    // ---- Website ---------------------------------------------------------

    /// <summary>
    /// Everything the Drift Virtual page on driftfactory.pt shows: the server
    /// right now, this week's leaderboard and the finished weeks. Only what's
    /// already public in Discord — no Steam ids.
    /// </summary>
    public object SiteSnapshot()
    {
        var drivers = _entryCarManager.EntryCars
            .Where(car => car.Client is { HasSentFirstUpdate: true })
            .Select(car => car.Client!.Name ?? "?")
            .ToList();
        var cars = _serverConfiguration.EntryList.Cars
            .Select(car => car.Model).Distinct()
            .Select(model => new { id = model, name = CarName(model) })
            .ToList();
        var current = _store.CurrentWeek();

        return _store.Read(state =>
        {
            object Board(string week, string track, int limit) =>
                (state.Weeks.TryGetValue(week, out var tracks) && tracks.TryGetValue(track, out var board)
                    ? ResultsStore.Ranked(board) : [])
                .Take(limit)
                .Select((entry, index) => new
                {
                    pos = index + 1, driver = entry.Driver, car = entry.Car,
                    score = Math.Round(entry.Score, 1), line = Math.Round(entry.Line, 1),
                    angle = Math.Round(entry.Angle, 1), style = Math.Round(entry.StyleSpeed, 1),
                    timeUtc = entry.TimeUtc,
                })
                .ToList();

            object Week(string week, string track, int limit)
            {
                var (monday, sunday) = ResultsStore.WeekRange(week);
                return new
                {
                    key = week, label = WeekLabel(week),
                    start = monday.ToString("yyyy-MM-dd"), end = sunday.ToString("yyyy-MM-dd"),
                    track = new { id = track, name = TrackName(track) },
                    board = Board(week, track, limit),
                };
            }

            var history = state.Weeks
                .Where(week => string.CompareOrdinal(week.Key, current) < 0)
                .OrderByDescending(week => week.Key, StringComparer.Ordinal)
                .SelectMany(week => week.Value
                    .Where(track => track.Value.Count > 0)
                    .OrderBy(track => track.Key, StringComparer.Ordinal)
                    .Select(track => Week(week.Key, track.Key, 10)))
                .Take(52)
                .ToList();

            return new
            {
                updatedUtc = DateTime.UtcNow,
                server = new
                {
                    name = _serverConfiguration.Server.Name,
                    online = true,
                    track = new { id = _track, name = TrackName() },
                    players = drivers.Count,
                    maxPlayers = _serverConfiguration.Server.MaxClients,
                    drivers,
                    cars,
                    joinUrl = _configuration.JoinUrl,
                },
                week = Week(current, _track, 50),
                history,
            };
        });
    }

    // ---- Names and formatting --------------------------------------------

    private string TrackName() => TrackName(_track);

    /// <summary>Display name of a "track" or "track/layout" id, from its ui_track.json when the server has it.</summary>
    private string TrackName(string track)
    {
        var parts = track.Split('/', 2);
        var folder = Path.Combine("content", "tracks", parts[0], "ui");
        var file = parts.Length == 1 ? Path.Combine(folder, "ui_track.json") : Path.Combine(folder, parts[1], "ui_track.json");
        return DisplayName(file, track);
    }

    private string CarName(string model) =>
        DisplayName(Path.Combine("content", "cars", model, "ui", "ui_car.json"), model);

    /// <summary>The "name" from a Kunos ui_*.json, or a tidied-up folder id if there's none on the server.</summary>
    private string DisplayName(string uiFile, string fallbackId)
    {
        lock (_displayNames)
        {
            if (_displayNames.TryGetValue(uiFile, out var cached)) return cached;
            var name = Tidy(fallbackId);
            try
            {
                if (File.Exists(uiFile))
                {
                    using var document = JsonDocument.Parse(File.ReadAllText(uiFile),
                        new JsonDocumentOptions { AllowTrailingCommas = true, CommentHandling = JsonCommentHandling.Skip });
                    if (document.RootElement.TryGetProperty("name", out var value) && value.GetString() is { Length: > 0 } text)
                    {
                        name = text;
                    }
                }
            }
            catch (Exception)
            {
                // Plenty of mods ship slightly broken ui json; the tidied id will do.
            }

            return _displayNames[uiFile] = name;
        }
    }

    private static string Tidy(string id)
    {
        var words = id.Replace('/', ' ').Replace('_', ' ').Replace('-', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(word => word.Length <= 3 && word.All(char.IsLetter) ? word.ToUpperInvariant() : char.ToUpperInvariant(word[0]) + word[1..]);
        return string.Join(' ', words);
    }

    private static string WeekLabel(string week)
    {
        var (monday, sunday) = ResultsStore.WeekRange(week);
        var range = monday.Month == sunday.Month
            ? $"{monday.Day}–{sunday.Day} {Months[sunday.Month - 1]}"
            : $"{monday.Day} {Months[monday.Month - 1]} – {sunday.Day} {Months[sunday.Month - 1]}";
        return $"Semana {week[6..].TrimStart('0')} · {range}";
    }

    private static string Score(float score) => score.ToString("0.0", CultureInfo.InvariantCulture);

    private static string Escape(string text)
    {
        var builder = new StringBuilder(text.Length);
        foreach (var c in text)
        {
            if ("\\*_`~|>".Contains(c)) builder.Append('\\');
            builder.Append(c);
        }
        return builder.ToString();
    }

    private static string Truncate(string text, int max) => text.Length <= max ? text : text[..(max - 1)] + "…";
}
