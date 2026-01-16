import unittest
import std/[times, options, tables, json]
import ../src/shared/types

suite "Shared Types":
  test "Status can be serialized to JSON":
    let status = Status(
      version: 1,
      updatedAt: now().utc(),
      configDir: "/home/test/.claude",
      api: ApiStatus(configured: true, error: none(string)),
      estimates: EstimateStatus(
        calculatedAt: now().utc(),
        messages5hr: 10,
        sessionPercent: 22,
        sessionReset: "4h30m",
        hoursWeekly: 5.5,
        weeklyPercent: 5,
        weeklyReset: "6d12h"
      ),
      context: ContextStatus(tokens: 50000, cacheReadTokens: 40000, percentUsed: 31),
      plan: PlanStatus(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40),
      errors: ErrorStatus()
    )
    let j = status.toJson()
    check j["version"].getInt() == 1
    check j["config_dir"].getStr() == "/home/test/.claude"
    check j["api"]["configured"].getBool() == true
    check j["estimates"]["messages_5hr"].getInt() == 10

  test "Status can be deserialized from JSON":
    let j = %*{
      "version": 1,
      "updated_at": "2026-01-16T12:00:00Z",
      "config_dir": "/home/test/.claude",
      "api": {"configured": true, "error": nil},
      "estimates": {
        "calculated_at": "2026-01-16T12:00:00Z",
        "messages_5hr": 10,
        "session_percent": 22,
        "session_reset": "4h30m",
        "hours_weekly": 5.5,
        "weekly_percent": 5,
        "weekly_reset": "6d12h"
      },
      "context": {"transcript_path": nil, "tokens": 50000, "cache_read_tokens": 40000, "percent_used": 31},
      "plan": {"name": "Pro", "five_hour_messages": 45, "weekly_hours_min": 40},
      "errors": {"api": nil, "transcripts": nil, "daemon": nil}
    }
    let status = parseStatus(j)
    check status.version == 1
    check status.api.configured == true
    check status.estimates.messages5hr == 10

  test "TranscriptEntry tracks incremental state":
    var entry = TranscriptEntry(
      size: 1000,
      offset: 500,
      mtime: getTime(),
      lastChecked: now().utc(),
      tokensAfterSummary: 1000,
      messagesAfterSummary: 5,
      lastCacheReadTokens: 800,
      incompleteLineBuffer: ""
    )
    check entry.offset == 500
    check entry.tokensAfterSummary == 1000

  test "DaemonConfig has sensible defaults":
    let config = defaultDaemonConfig()
    check config.version == 1
    check config.scanIntervalMinutes == 5
    check config.apiIntervalMinutes == 5
    check config.pruneIntervalMinutes == 30
    check config.debug == false

  test "PLAN_INFO contains all plan types":
    check PLAN_INFO.len == 4
    check PLAN_INFO[0].name == "Free"
    check PLAN_INFO[1].name == "Pro"
    check PLAN_INFO[2].name == "Max 5"
    check PLAN_INFO[3].name == "Max 20"

  test "Pro plan has correct limits":
    let pro = PLAN_INFO[1]
    check pro.fiveHourMessages == 45
    check pro.weeklyHoursMin == 40
    check pro.weeklyHoursMax == 80

  test "TranscriptCache can hold multiple transcripts":
    var cache = TranscriptCache(
      version: 1,
      lastPruned: now().utc(),
      transcripts: initTable[string, TranscriptEntry]()
    )
    let entry = TranscriptEntry(
      size: 1000,
      offset: 500,
      mtime: getTime(),
      lastChecked: now().utc(),
      tokensAfterSummary: 1000,
      messagesAfterSummary: 5,
      lastCacheReadTokens: 800,
      incompleteLineBuffer: ""
    )
    cache.transcripts["/path/to/transcript.jsonl"] = entry
    check cache.transcripts.len == 1
    check cache.transcripts["/path/to/transcript.jsonl"].size == 1000

  test "ApiCredentials holds session key and org ID":
    let creds = ApiCredentials(
      sessionKey: "sk-ant-test123",
      organizationId: "org-12345"
    )
    check creds.sessionKey == "sk-ant-test123"
    check creds.organizationId == "org-12345"

  test "DaemonConfig toJson serializes correctly":
    let config = DaemonConfig(
      version: 1,
      configDirs: @["/home/test/.claude"],
      scanIntervalMinutes: 10,
      apiIntervalMinutes: 3,
      pruneIntervalMinutes: 60,
      debug: true
    )
    let j = config.toJson()
    check j["version"].getInt() == 1
    check j["config_dirs"].len == 1
    check j["scan_interval_minutes"].getInt() == 10
    check j["debug"].getBool() == true

  test "parseDaemonConfig deserializes correctly":
    let j = %*{
      "version": 1,
      "config_dirs": ["/home/test/.claude", "/work/.claude"],
      "scan_interval_minutes": 10,
      "api_interval_minutes": 3,
      "prune_interval_minutes": 60,
      "debug": true
    }
    let config = parseDaemonConfig(j)
    check config.version == 1
    check config.configDirs.len == 2
    check config.scanIntervalMinutes == 10
    check config.debug == true
