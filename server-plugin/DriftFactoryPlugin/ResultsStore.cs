using System.Globalization;
using System.Text.Json;
using Serilog;

namespace DriftFactoryPlugin;

public class BestEntry
{
    public string Driver { get; set; } = "";
    public string Car { get; set; } = "";
    public float Score { get; set; }
    public float Line { get; set; }
    public float Angle { get; set; }
    public float StyleSpeed { get; set; }
    public DateTime TimeUtc { get; set; }
}

public class StoreState
{
    /// <summary>week ("2026-W41") → track → driver key → best valid run that week.</summary>
    public Dictionary<string, Dictionary<string, Dictionary<string, BestEntry>>> Weeks { get; set; } = new();

    /// <summary>Discord message ids, so messages are edited in place instead of reposted.</summary>
    public string? StatusMessageId { get; set; }
    public Dictionary<string, string> LeaderboardMessageIds { get; set; } = new();

    /// <summary>Last week whose results were announced as final.</summary>
    public string? LastClosedWeek { get; set; }
}

public record RecordOutcome(bool NewWeeklyBest, int Position, bool NewLeader, string Week);

/// <summary>
/// Every run ever reported (runs.jsonl, append-only — the permanent record)
/// plus each driver's best valid run per track per week (state.json).
/// Weeks run Monday to Sunday in the configured time zone.
/// </summary>
public class ResultsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly object _lock = new();
    private readonly string _runsPath;
    private readonly string _statePath;
    private readonly TimeZoneInfo _timeZone;

    public StoreState State { get; }

    public ResultsStore(DriftFactoryConfiguration configuration)
    {
        var directory = Path.Combine(Directory.GetCurrentDirectory(), configuration.DataDirectory);
        Directory.CreateDirectory(directory);
        _runsPath = Path.Combine(directory, "runs.jsonl");
        _statePath = Path.Combine(directory, "state.json");
        _timeZone = FindTimeZone(configuration.TimeZone);
        State = Load(_statePath);
    }

    private static TimeZoneInfo FindTimeZone(string id)
    {
        // IANA ids ("Europe/Lisbon") work on Linux; Windows may only know its
        // own names ("GMT Standard Time"), so try the conversion too.
        var candidates = new List<string> { id };
        if (TimeZoneInfo.TryConvertIanaIdToWindowsId(id, out var windowsId)) candidates.Add(windowsId);
        foreach (var candidate in candidates)
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(candidate);
            }
            catch (Exception)
            {
                // try the next name
            }
        }

        Log.Warning("DriftFactoryPlugin: time zone {TimeZone} not found, weeks follow UTC", id);
        return TimeZoneInfo.Utc;
    }

    private static StoreState Load(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                return JsonSerializer.Deserialize<StoreState>(File.ReadAllText(path)) ?? new StoreState();
            }
        }
        catch (Exception ex)
        {
            Log.Error(ex, "DriftFactoryPlugin: could not read {Path}, starting a fresh leaderboard", path);
            File.Copy(path, path + ".broken-" + DateTime.UtcNow.ToString("yyyyMMddHHmmss"), true);
        }

        return new StoreState();
    }

    public DateTime LocalNow() => TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, _timeZone);

    public string WeekKey(DateTime utc)
    {
        var local = TimeZoneInfo.ConvertTimeFromUtc(utc, _timeZone);
        return $"{ISOWeek.GetYear(local)}-W{ISOWeek.GetWeekOfYear(local):00}";
    }

    public string CurrentWeek() => WeekKey(DateTime.UtcNow);

    /// <summary>Monday and Sunday of a week key, for headings like "6–12 out".</summary>
    public static (DateTime Monday, DateTime Sunday) WeekRange(string week)
    {
        var year = int.Parse(week[..4], CultureInfo.InvariantCulture);
        var number = int.Parse(week[6..], CultureInfo.InvariantCulture);
        var monday = ISOWeek.ToDateTime(year, number, DayOfWeek.Monday);
        return (monday, monday.AddDays(6));
    }

    public RecordOutcome Record(string track, string car, string driver, string driverKey, RunResultEvent run)
    {
        lock (_lock)
        {
            var now = DateTime.UtcNow;
            var week = WeekKey(now);
            AppendRun(new
            {
                timeUtc = now, week, track, car, driver, driverKey,
                score = run.Score, valid = run.Valid, line = run.Line, angle = run.Angle, styleSpeed = run.StyleSpeed
            });

            if (!run.Valid) return new RecordOutcome(false, 0, false, week);

            var board = Board(week, track);
            var previousLeader = Ranked(board).FirstOrDefault();
            if (board.TryGetValue(driverKey, out var existing) && existing.Score >= run.Score)
            {
                return new RecordOutcome(false, 0, false, week);
            }

            board[driverKey] = new BestEntry
            {
                Driver = driver, Car = car, Score = run.Score, Line = run.Line, Angle = run.Angle,
                StyleSpeed = run.StyleSpeed, TimeUtc = now
            };
            Save();

            var ranked = Ranked(board);
            var position = ranked.FindIndex(entry => entry == board[driverKey]) + 1;
            var newLeader = position == 1 && (previousLeader == null || previousLeader.Driver != driver);
            return new RecordOutcome(true, position, newLeader, week);
        }
    }

    public Dictionary<string, BestEntry> Board(string week, string track)
    {
        lock (_lock)
        {
            if (!State.Weeks.TryGetValue(week, out var tracks)) State.Weeks[week] = tracks = new();
            if (!tracks.TryGetValue(track, out var board)) tracks[track] = board = new();
            return board;
        }
    }

    /// <summary>Runs <paramref name="read"/> while no result can be recorded, for a consistent view.</summary>
    public T Read<T>(Func<StoreState, T> read)
    {
        lock (_lock) return read(State);
    }

    public static List<BestEntry> Ranked(Dictionary<string, BestEntry> board) =>
        board.Values.OrderByDescending(entry => entry.Score).ThenBy(entry => entry.TimeUtc).ToList();

    public void Save()
    {
        lock (_lock)
        {
            var temp = _statePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(State, JsonOptions));
            File.Move(temp, _statePath, true);
        }
    }

    private void AppendRun(object run)
    {
        File.AppendAllText(_runsPath, JsonSerializer.Serialize(run) + "\n");
    }
}
