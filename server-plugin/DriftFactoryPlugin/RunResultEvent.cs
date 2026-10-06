using AssettoServer.Network.ClientMessages;

namespace DriftFactoryPlugin;

/// <summary>
/// The run result the online script broadcasts after every run
/// (src/leaderboard.lua). Field names and types must match the Lua layout
/// exactly: AssettoServer derives the message type from them the same way
/// CSP does.
/// </summary>
[OnlineEvent(Key = "driftFactoryJudgeApp_runResult")]
public class RunResultEvent : OnlineEvent<RunResultEvent>
{
    [OnlineEventField(Name = "score")]
    public float Score;

    [OnlineEventField(Name = "valid")]
    public bool Valid;

    [OnlineEventField(Name = "line")]
    public float Line;

    [OnlineEventField(Name = "angle")]
    public float Angle;

    [OnlineEventField(Name = "styleSpeed")]
    public float StyleSpeed;
}
