## Shared types for hucd daemon and huc statusline
## These types map directly to JSON structures for status.json, transcripts.json, and hucd.json

import std/[times, options, tables, json]

# ─────────────────────────────────────────────────────────────────
# Status types (status.json)
# ─────────────────────────────────────────────────────────────────

type
  ApiStatus* = object
    configured*: bool
    fetchedAt*: Option[DateTime]
    sessionPercent*: Option[int]
    sessionReset*: Option[string]
    weeklyPercent*: Option[int]
    weeklyReset*: Option[string]
    error*: Option[string]

  EstimateStatus* = object
    calculatedAt*: DateTime
    messages5hr*: int
    sessionPercent*: int
    sessionReset*: string
    hoursWeekly*: float
    weeklyPercent*: int
    weeklyReset*: string

  ContextStatus* = object
    transcriptPath*: Option[string]
    tokens*: int
    cacheReadTokens*: int
    percentUsed*: int

  PlanStatus* = object
    name*: string
    fiveHourMessages*: int
    weeklyHoursMin*: int

  ErrorStatus* = object
    api*: Option[string]
    transcripts*: Option[string]
    daemon*: Option[string]

  Status* = object
    version*: int
    updatedAt*: DateTime
    configDir*: string
    api*: ApiStatus
    estimates*: EstimateStatus
    context*: ContextStatus
    plan*: PlanStatus
    errors*: ErrorStatus

# ─────────────────────────────────────────────────────────────────
# Transcript cache types (transcripts.json)
# ─────────────────────────────────────────────────────────────────

type
  TranscriptEntry* = object
    size*: int64                    ## File size for truncation detection
    offset*: int64                  ## Byte offset for incremental reads
    mtime*: Time                    ## Modification time for staleness check
    lastChecked*: DateTime          ## When we last checked this file
    tokensAfterSummary*: int        ## CURRENT context tokens (replaces on each message, NOT accumulated)
                                    ## This is input_tokens + output_tokens from last usage entry
    messagesAfterSummary*: int      ## Count of user+assistant messages since last summary
    lastCacheReadTokens*: int       ## cache_read_input_tokens from last usage entry
    incompleteLineBuffer*: string   ## Partial JSON line from previous incremental read

  TranscriptCache* = object
    version*: int
    lastPruned*: DateTime
    transcripts*: Table[string, TranscriptEntry]

# ─────────────────────────────────────────────────────────────────
# Daemon config types (hucd.json)
# ─────────────────────────────────────────────────────────────────

type
  DaemonConfig* = object
    version*: int
    configDirs*: seq[string]
    scanIntervalMinutes*: int
    apiIntervalMinutes*: int
    pruneIntervalMinutes*: int
    debug*: bool

# ─────────────────────────────────────────────────────────────────
# API credentials (from heads_up_config.json)
# ─────────────────────────────────────────────────────────────────

type
  ApiCredentials* = object
    sessionKey*: string
    organizationId*: string

# ─────────────────────────────────────────────────────────────────
# Plan limits (static lookup)
# ─────────────────────────────────────────────────────────────────

type
  PlanLimits* = object
    name*: string
    fiveHourMessages*: int
    weeklyHoursMin*: int
    weeklyHoursMax*: int

const
  PLAN_INFO* = [
    PlanLimits(name: "Free", fiveHourMessages: 10, weeklyHoursMin: 0, weeklyHoursMax: 0),
    PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80),
    PlanLimits(name: "Max 5", fiveHourMessages: 225, weeklyHoursMin: 140, weeklyHoursMax: 280),
    PlanLimits(name: "Max 20", fiveHourMessages: 900, weeklyHoursMin: 240, weeklyHoursMax: 480)
  ]

# ─────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────

type
  LogLevel* = enum
    DEBUG, INFO, WARN, ERROR

var debugMode* = false

proc log*(level: LogLevel, msg: string) =
  if level == DEBUG and not debugMode:
    return
  let timestamp = now().format("yyyy-MM-dd HH:mm:ss")
  let levelStr = case level
    of DEBUG: "DEBUG"
    of INFO: "INFO"
    of WARN: "WARN"
    of ERROR: "ERROR"
  stderr.writeLine("[" & timestamp & "] [" & levelStr & "] " & msg)
  stderr.flushFile()

# ─────────────────────────────────────────────────────────────────
# JSON serialization/deserialization
# ─────────────────────────────────────────────────────────────────

proc toJson*(status: Status): JsonNode =
  result = %*{
    "version": status.version,
    "updated_at": status.updatedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "config_dir": status.configDir,
    "api": {
      "configured": status.api.configured,
      "fetched_at": if status.api.fetchedAt.isSome: %status.api.fetchedAt.get().format("yyyy-MM-dd'T'HH:mm:ss'Z'") else: newJNull(),
      "session_percent": if status.api.sessionPercent.isSome: %status.api.sessionPercent.get() else: newJNull(),
      "session_reset": if status.api.sessionReset.isSome: %status.api.sessionReset.get() else: newJNull(),
      "weekly_percent": if status.api.weeklyPercent.isSome: %status.api.weeklyPercent.get() else: newJNull(),
      "weekly_reset": if status.api.weeklyReset.isSome: %status.api.weeklyReset.get() else: newJNull(),
      "error": if status.api.error.isSome: %status.api.error.get() else: newJNull()
    },
    "estimates": {
      "calculated_at": status.estimates.calculatedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "messages_5hr": status.estimates.messages5hr,
      "session_percent": status.estimates.sessionPercent,
      "session_reset": status.estimates.sessionReset,
      "hours_weekly": status.estimates.hoursWeekly,
      "weekly_percent": status.estimates.weeklyPercent,
      "weekly_reset": status.estimates.weeklyReset
    },
    "context": {
      "transcript_path": if status.context.transcriptPath.isSome: %status.context.transcriptPath.get() else: newJNull(),
      "tokens": status.context.tokens,
      "cache_read_tokens": status.context.cacheReadTokens,
      "percent_used": status.context.percentUsed
    },
    "plan": {
      "name": status.plan.name,
      "five_hour_messages": status.plan.fiveHourMessages,
      "weekly_hours_min": status.plan.weeklyHoursMin
    },
    "errors": {
      "api": if status.errors.api.isSome: %status.errors.api.get() else: newJNull(),
      "transcripts": if status.errors.transcripts.isSome: %status.errors.transcripts.get() else: newJNull(),
      "daemon": if status.errors.daemon.isSome: %status.errors.daemon.get() else: newJNull()
    }
  }

proc parseOptString(n: JsonNode): Option[string] =
  if n == nil: return none(string)
  if n.kind == JNull: return none(string)
  return some(n.getStr())

proc parseOptInt(n: JsonNode): Option[int] =
  if n == nil: return none(int)
  if n.kind == JNull: return none(int)
  return some(n.getInt())

proc parseOptDateTime(n: JsonNode): Option[DateTime] =
  if n == nil: return none(DateTime)
  if n.kind == JNull: return none(DateTime)
  try:
    return some(parse(n.getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc()))
  except:
    return none(DateTime)

proc parseStatus*(j: JsonNode): Status =
  result.version = j["version"].getInt()
  result.updatedAt = parse(j["updated_at"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())
  result.configDir = j["config_dir"].getStr()

  let api = j["api"]
  result.api = ApiStatus(
    configured: api["configured"].getBool(),
    fetchedAt: parseOptDateTime(api.getOrDefault("fetched_at")),
    sessionPercent: parseOptInt(api.getOrDefault("session_percent")),
    sessionReset: parseOptString(api.getOrDefault("session_reset")),
    weeklyPercent: parseOptInt(api.getOrDefault("weekly_percent")),
    weeklyReset: parseOptString(api.getOrDefault("weekly_reset")),
    error: parseOptString(api["error"])
  )

  let est = j["estimates"]
  result.estimates = EstimateStatus(
    calculatedAt: parse(est["calculated_at"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'", utc()),
    messages5hr: est["messages_5hr"].getInt(),
    sessionPercent: est["session_percent"].getInt(),
    sessionReset: est["session_reset"].getStr(),
    hoursWeekly: est["hours_weekly"].getFloat(),
    weeklyPercent: est["weekly_percent"].getInt(),
    weeklyReset: est["weekly_reset"].getStr()
  )

  let ctx = j["context"]
  result.context = ContextStatus(
    transcriptPath: parseOptString(ctx["transcript_path"]),
    tokens: ctx["tokens"].getInt(),
    cacheReadTokens: ctx["cache_read_tokens"].getInt(),
    percentUsed: ctx["percent_used"].getInt()
  )

  let plan = j["plan"]
  result.plan = PlanStatus(
    name: plan["name"].getStr(),
    fiveHourMessages: plan["five_hour_messages"].getInt(),
    weeklyHoursMin: plan["weekly_hours_min"].getInt()
  )

  let errors = j["errors"]
  result.errors = ErrorStatus(
    api: parseOptString(errors["api"]),
    transcripts: parseOptString(errors["transcripts"]),
    daemon: parseOptString(errors["daemon"])
  )

proc defaultDaemonConfig*(): DaemonConfig =
  result = DaemonConfig(
    version: 1,
    configDirs: @[],
    scanIntervalMinutes: 5,
    apiIntervalMinutes: 5,
    pruneIntervalMinutes: 30,
    debug: false
  )

proc toJson*(config: DaemonConfig): JsonNode =
  result = %*{
    "version": config.version,
    "config_dirs": config.configDirs,
    "scan_interval_minutes": config.scanIntervalMinutes,
    "api_interval_minutes": config.apiIntervalMinutes,
    "prune_interval_minutes": config.pruneIntervalMinutes,
    "debug": config.debug
  }

proc parseDaemonConfig*(j: JsonNode): DaemonConfig =
  result = defaultDaemonConfig()
  result.version = j.getOrDefault("version").getInt(1)
  if j.hasKey("config_dirs"):
    for dir in j["config_dirs"]:
      result.configDirs.add(dir.getStr())
  result.scanIntervalMinutes = j.getOrDefault("scan_interval_minutes").getInt(5)
  result.apiIntervalMinutes = j.getOrDefault("api_interval_minutes").getInt(5)
  result.pruneIntervalMinutes = j.getOrDefault("prune_interval_minutes").getInt(30)
  result.debug = j.getOrDefault("debug").getBool(false)
