import std/[json, os, times, streams, options, osproc]
import types

proc getFirstTimestampAndContextTokens*(transcriptPath: string): (Option[DateTime], Option[DateTime], int, int, int, int) =
  try:
    if not fileExists(transcriptPath):
      return (none(DateTime), none(DateTime), 0, 0, 0, 0)

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return (none(DateTime), none(DateTime), 0, 0, 0, 0)

    defer: stream.close()

    var firstTimestamp = none(DateTime)
    var lastTimestamp = none(DateTime)
    var tokensAfterLastSummary = 0
    var lastCacheReadTokens = 0
    var lastNewTokens = 0
    var messageCount = 0
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        if entry.hasKey("timestamp"):
          let ts = entry["timestamp"].getStr()
          let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
          if firstTimestamp.isNone:
            firstTimestamp = some(parsedTs)
          lastTimestamp = some(parsedTs)

        if entry.hasKey("type") and entry["type"].getStr() == "summary":
          tokensAfterLastSummary = 0
          messageCount = 0
          continue

        if entry.hasKey("type") and (entry["type"].getStr() == "user" or entry["type"].getStr() == "assistant"):
          messageCount += 1

        if entry.hasKey("message") and entry["message"].hasKey("usage"):
          let usage = entry["message"]["usage"]

          if usage.hasKey("cache_read_input_tokens"):
            lastCacheReadTokens = usage["cache_read_input_tokens"].getInt()

          lastNewTokens = 0
          if usage.hasKey("input_tokens"):
            lastNewTokens += usage["input_tokens"].getInt()
          if usage.hasKey("cache_creation_input_tokens"):
            lastNewTokens += usage["cache_creation_input_tokens"].getInt()
          if usage.hasKey("output_tokens"):
            lastNewTokens += usage["output_tokens"].getInt()

          tokensAfterLastSummary += lastNewTokens
      except:
        continue

    let contextTokens = lastCacheReadTokens + lastNewTokens

    return (firstTimestamp, lastTimestamp, contextTokens, lastCacheReadTokens, tokensAfterLastSummary, messageCount)
  except:
    return (none(DateTime), none(DateTime), 0, 0, 0, 0)

proc loadPlanConfig*(claudeConfigDir: string): PlanLimits =
  let configPath = claudeConfigDir / "heads_up_config.json"

  if not fileExists(configPath):
    return PlanLimits(name: "Free", fiveHourMessages: 10, weeklyHoursMin: 0, weeklyHoursMax: 0)

  try:
    let config = parseFile(configPath)
    result.fiveHourMessages = config.getOrDefault("five_hour_messages").getInt(10)
    result.weeklyHoursMin = config.getOrDefault("weekly_hours_min").getInt(0)

    # Set the plan name based on the plan type
    let planType = config.getOrDefault("plan").getStr("free")
    case planType
    of "free":
      result.name = "Free"
      result.weeklyHoursMax = 0
    of "pro":
      result.name = "Pro"
      result.weeklyHoursMax = 80
    of "max5":
      result.name = "Max 5"
      result.weeklyHoursMax = 280
    of "max20":
      result.name = "Max 20"
      result.weeklyHoursMax = 480
    else:
      result.name = "Pro"
      result.weeklyHoursMax = 80
  except:
    result.name = "Free"
    result.fiveHourMessages = 10
    result.weeklyHoursMin = 0
    result.weeklyHoursMax = 0

proc estimateUsageFromTranscripts*(projectsDir: string, limits: PlanLimits): (int, int, string, float, int, string) =
  var messages5hr = 0
  var percent5hr = 0
  var time5hr = ""
  var hoursWeekly = 0.0
  var percentWeekly = 0
  var timeWeekly = ""

  if not dirExists(projectsDir):
    return (0, 0, "", 0.0, 0, "")

  let now = now().utc()
  let fiveHoursAgo = now - initDuration(hours = 5)
  let sevenDaysAgo = now - initDuration(days = 7)

  var recentMessages = 0
  var weeklyTokens = 0
  var oldestRecentTime = none(DateTime)
  var oldestWeeklyTime = none(DateTime)

  try:
    for kind, path in walkDir(projectsDir):
      if kind == pcDir:
        for transcript in walkFiles(path / "*.jsonl"):
          let (firstTs, lastTs, _, _, _, msgCount) = getFirstTimestampAndContextTokens(transcript)

          if lastTs.isSome:
            let lastTime = lastTs.get()

            if lastTime >= fiveHoursAgo:
              recentMessages += msgCount
              if oldestRecentTime.isNone or firstTs.get() < oldestRecentTime.get():
                oldestRecentTime = firstTs

            if lastTime >= sevenDaysAgo:
              if firstTs.isSome and firstTs.get() >= sevenDaysAgo:
                let duration = lastTime - firstTs.get()
                weeklyTokens += int(duration.inMinutes)
                if oldestWeeklyTime.isNone or firstTs.get() < oldestWeeklyTime.get():
                  oldestWeeklyTime = firstTs
  except:
    discard

  percent5hr = min(100, int((recentMessages.float / limits.fiveHourMessages.float) * 100.0))
  messages5hr = recentMessages

  if oldestRecentTime.isSome:
    let resetTime = oldestRecentTime.get() + initDuration(hours = 5)
    if resetTime > now:
      let remaining = resetTime - now
      let hoursLeft = remaining.inHours
      let minsLeft = remaining.inMinutes mod 60
      if hoursLeft > 0:
        time5hr = $hoursLeft & "h" & $minsLeft & "m"
      else:
        time5hr = $minsLeft & "m"

  if limits.weeklyHoursMin > 0:
    hoursWeekly = weeklyTokens.float / 60.0
    percentWeekly = min(100, int((hoursWeekly / limits.weeklyHoursMin.float) * 100.0))

    if oldestWeeklyTime.isSome:
      let resetTime = oldestWeeklyTime.get() + initDuration(days = 7)
      if resetTime > now:
        let remaining = resetTime - now
        let daysLeft = remaining.inDays
        let hoursLeft = remaining.inHours mod 24
        if daysLeft > 0:
          timeWeekly = $daysLeft & "d" & $hoursLeft & "h"
        else:
          timeWeekly = $hoursLeft & "h"

  return (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly)

const
  CACHE_TTL_SECONDS = 60  # Cache valid for 60 seconds
  LOCK_STALE_SECONDS = 90  # Consider lock stale after 90 seconds (expect script timeout + buffer)

proc isLockStale(lockPath: string): bool =
  ## Check if lock directory exists and is stale (too old)
  let lockDir = lockPath & ".d"
  if not dirExists(lockDir):
    return false
  try:
    let lockInfo = getFileInfo(lockDir)
    let age = now().utc() - lockInfo.lastWriteTime.utc()
    return age.inSeconds > LOCK_STALE_SECONDS
  except:
    return false

proc cleanStaleLock(lockPath: string) =
  ## Remove lock directory if it's stale
  let lockDir = lockPath & ".d"
  if isLockStale(lockPath):
    try:
      removeDir(lockDir)
    except:
      discard

proc readCache(cachePath: string): (int, string, int, string, bool) =
  ## Read cached usage data. Returns (session%, sessionReset, weekly%, weeklyReset, isValid)
  if not fileExists(cachePath):
    return (0, "", 0, "", false)

  try:
    let cacheInfo = getFileInfo(cachePath)
    let age = now().utc() - cacheInfo.lastWriteTime.utc()
    let isValid = age.inSeconds < CACHE_TTL_SECONDS

    let cache = parseFile(cachePath)
    return (
      cache["sessionPercent"].getInt(),
      cache["sessionResetTime"].getStr(),
      cache["weeklyPercent"].getInt(),
      cache["weeklyResetTime"].getStr(),
      isValid
    )
  except:
    return (0, "", 0, "", false)

proc spawnBackgroundRefresh(scriptPath, cachePath, lockPath: string) =
  ## Spawn a background process to refresh the cache without blocking.
  ## Uses startProcess with poDaemon to fully detach.
  try:
    # Create a shell script with timeout protection and atomic locking
    let refreshScript = getTempDir() / "heads-up-claude" / "refresh.sh"
    let script = """#!/bin/bash
TIMEOUT=60  # Kill expect script after 60 seconds

# Atomic lock using mkdir (atomic on POSIX)
# mkdir fails if dir already exists, so only one process wins
LOCK_DIR="$2.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0  # Another process has the lock
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# Run expect script with timeout
if command -v timeout &> /dev/null; then
  output=$(timeout $TIMEOUT "$1" 2>/dev/null)
else
  # macOS fallback: use perl for timeout
  output=$(perl -e 'alarm shift; exec @ARGV' $TIMEOUT "$1" 2>/dev/null)
fi

if [ $? -ne 0 ]; then
  exit 1
fi

# Parse session percentage
session_pct=$(echo "$output" | grep -A1 "Current session" | tail -1 | grep -oE '[0-9]+' | head -1)
session_pct=${session_pct:-0}

# Parse weekly percentage
weekly_pct=$(echo "$output" | grep -A1 "Current week" | tail -1 | grep -oE '[0-9]+' | head -1)
weekly_pct=${weekly_pct:-0}

# Write cache atomically (write to temp, then move)
tmp_cache="$3.tmp.$$"
cat > "$tmp_cache" << EOF
{"sessionPercent":$session_pct,"sessionResetTime":"","weeklyPercent":$weekly_pct,"weeklyResetTime":""}
EOF
mv "$tmp_cache" "$3"
"""
    writeFile(refreshScript, script)
    setFilePermissions(refreshScript, {fpUserExec, fpUserWrite, fpUserRead})

    # Fire and forget - startProcess returns immediately, we don't wait
    discard startProcess(
      refreshScript,
      args = [scriptPath, lockPath, cachePath],
      options = {poUsePath, poDaemon}
    )
  except:
    discard

proc getRealUsageData*(): (int, string, int, string) =
  ## Get real usage data from claude /config - NON-BLOCKING.
  ##
  ## Always returns immediately with cached data (even if stale).
  ## If cache is stale, spawns a background daemon to refresh it.
  ## Next statusline update will get fresh data.
  ##
  ## Guards against stacking:
  ## - Lock file prevents multiple concurrent fetches
  ## - Stale locks (>90s) are automatically cleaned up
  ## - 60s timeout kills hung expect scripts

  let scriptPath = getAppDir() / "get_usage.exp"
  if not fileExists(scriptPath):
    return (0, "", 0, "")

  let cacheDir = getTempDir() / "heads-up-claude"
  let cachePath = cacheDir / "usage_cache.json"
  let lockPath = cacheDir / "usage.lock"

  # Ensure cache directory exists
  try:
    createDir(cacheDir)
  except:
    return (0, "", 0, "")

  # Clean up stale locks (from crashed/timed-out processes)
  cleanStaleLock(lockPath)

  # Read cache (may be stale or missing)
  let (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, cacheValid) = readCache(cachePath)

  # If cache is stale and no refresh in progress, spawn background refresh
  # Lock is a directory (for atomic creation via mkdir)
  if not cacheValid and not dirExists(lockPath & ".d"):
    spawnBackgroundRefresh(scriptPath, cachePath, lockPath)

  # Always return immediately with whatever we have
  return (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset)
