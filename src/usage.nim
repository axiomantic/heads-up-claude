import std/[json, os, times, streams, options, osproc, strutils]
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

proc countMessagesInWindow(transcriptPath: string, windowStart: DateTime): int =
  ## Count messages (user/assistant) with timestamps >= windowStart
  try:
    if not fileExists(transcriptPath):
      return 0

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return 0

    defer: stream.close()

    var count = 0
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        # Only count user/assistant messages with timestamps in the window
        if entry.hasKey("type") and entry.hasKey("timestamp"):
          let msgType = entry["type"].getStr()
          if msgType == "user" or msgType == "assistant":
            let ts = entry["timestamp"].getStr()
            let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
            if parsedTs >= windowStart:
              count += 1
      except:
        continue

    return count
  except:
    return 0

proc getSessionDurationInWindow(transcriptPath: string, windowStart: DateTime): int =
  ## Get session duration in minutes for activity within the time window
  try:
    if not fileExists(transcriptPath):
      return 0

    let stream = newFileStream(transcriptPath, fmRead)
    if stream.isNil:
      return 0

    defer: stream.close()

    var firstInWindow = none(DateTime)
    var lastInWindow = none(DateTime)
    var line: string

    while stream.readLine(line):
      try:
        let entry = parseJson(line)

        if entry.hasKey("timestamp"):
          let ts = entry["timestamp"].getStr()
          let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
          if parsedTs >= windowStart:
            if firstInWindow.isNone:
              firstInWindow = some(parsedTs)
            lastInWindow = some(parsedTs)
      except:
        continue

    if firstInWindow.isSome and lastInWindow.isSome:
      let duration = lastInWindow.get() - firstInWindow.get()
      return int(duration.inMinutes)
    return 0
  except:
    return 0

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
  var weeklyMinutes = 0
  var oldestRecentTime = none(DateTime)
  var oldestWeeklyTime = none(DateTime)

  try:
    for kind, path in walkDir(projectsDir):
      if kind == pcDir:
        for transcript in walkFiles(path / "*.jsonl"):
          # Count messages actually sent in the last 5 hours
          let msgCount = countMessagesInWindow(transcript, fiveHoursAgo)
          if msgCount > 0:
            recentMessages += msgCount
            # Track oldest message time for reset calculation
            let (firstTs, _, _, _, _, _) = getFirstTimestampAndContextTokens(transcript)
            if firstTs.isSome:
              let clampedFirst = if firstTs.get() < fiveHoursAgo: fiveHoursAgo else: firstTs.get()
              if oldestRecentTime.isNone or clampedFirst < oldestRecentTime.get():
                oldestRecentTime = some(clampedFirst)

          # Get session duration within the last 7 days
          let sessionMinutes = getSessionDurationInWindow(transcript, sevenDaysAgo)
          if sessionMinutes > 0:
            weeklyMinutes += sessionMinutes
            let (firstTs, _, _, _, _, _) = getFirstTimestampAndContextTokens(transcript)
            if firstTs.isSome:
              let clampedFirst = if firstTs.get() < sevenDaysAgo: sevenDaysAgo else: firstTs.get()
              if oldestWeeklyTime.isNone or clampedFirst < oldestWeeklyTime.get():
                oldestWeeklyTime = some(clampedFirst)
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
    hoursWeekly = weeklyMinutes.float / 60.0
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
  CACHE_VERY_STALE_SECONDS = 5 * 60 * 60  # 5 hours - show warning if cache is this old

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
  ## Remove lock directory if it's stale and kill any orphaned processes
  let lockDir = lockPath & ".d"
  if isLockStale(lockPath):
    try:
      # First, try to kill any orphaned process from this lock
      let pidFile = lockDir / "pid"
      if fileExists(pidFile):
        let pidStr = readFile(pidFile).strip()
        if pidStr.len > 0:
          # Kill the process and its children
          # Use SIGTERM first, then SIGKILL
          discard execCmdEx("pkill -TERM -P " & pidStr & " 2>/dev/null; kill -TERM " & pidStr & " 2>/dev/null")
          sleep(500)
          discard execCmdEx("pkill -KILL -P " & pidStr & " 2>/dev/null; kill -KILL " & pidStr & " 2>/dev/null")
      removeDir(lockDir)
    except:
      # Even if process kill fails, try to remove the lock dir
      try:
        removeDir(lockDir)
      except:
        discard

proc readCache(cachePath: string): (int, string, int, string, bool, int64) =
  ## Read cached usage data. Returns (session%, sessionReset, weekly%, weeklyReset, isValid, ageSeconds)
  if not fileExists(cachePath):
    return (0, "", 0, "", false, -1)

  try:
    let cacheInfo = getFileInfo(cachePath)
    let age = now().utc() - cacheInfo.lastWriteTime.utc()
    let ageSeconds = age.inSeconds
    let isValid = ageSeconds < CACHE_TTL_SECONDS

    let cache = parseFile(cachePath)
    return (
      cache["sessionPercent"].getInt(),
      cache["sessionResetTime"].getStr(),
      cache["weeklyPercent"].getInt(),
      cache["weeklyResetTime"].getStr(),
      isValid,
      ageSeconds
    )
  except:
    return (0, "", 0, "", false, -1)

proc spawnBackgroundRefresh(scriptPath, cachePath, lockPath: string) =
  ## Spawn a background process to refresh the cache without blocking.
  ## Uses startProcess with poDaemon to fully detach.
  try:
    # Create a shell script with timeout protection and atomic locking
    let refreshScript = getTempDir() / "heads-up-claude" / "refresh.sh"
    let script = """#!/bin/bash
set -o pipefail
TIMEOUT=30  # Kill expect script after 30 seconds
KILL_AFTER=5  # Force kill 5 seconds after SIGTERM

# PID file for tracking (allows cleanup of orphans)
PID_DIR="$2.d"
PID_FILE="$PID_DIR/pid"

# Atomic lock using mkdir (atomic on POSIX)
# mkdir fails if dir already exists, so only one process wins
if ! mkdir "$PID_DIR" 2>/dev/null; then
  exit 0  # Another process has the lock
fi

# Write our PID for potential external cleanup
echo $$ > "$PID_FILE"

# Cleanup function: kills entire process group and removes lock
cleanup() {
  # Kill any remaining child processes in our process group
  pkill -P $$ 2>/dev/null || true
  # Also kill by PID file in case process group kill missed something
  if [ -f "$PID_FILE" ]; then
    child_pids=$(pgrep -P $$ 2>/dev/null || true)
    for pid in $child_pids; do
      kill -TERM "$pid" 2>/dev/null || true
      sleep 0.5
      kill -KILL "$pid" 2>/dev/null || true
    done
  fi
  rm -rf "$PID_DIR"
}

# Trap all exit signals to ensure cleanup
trap cleanup EXIT INT TERM HUP

# Run expect script with timeout and process group kill
# Use setsid to create new session so timeout can kill the whole group
if command -v timeout &> /dev/null; then
  # GNU timeout (Linux): use --kill-after to SIGKILL if SIGTERM ignored
  # Run in foreground mode so signals propagate correctly
  output=$(timeout --foreground --kill-after=$KILL_AFTER $TIMEOUT "$1" 2>/dev/null)
  exit_code=$?
else
  # macOS: no timeout command, use explicit signal handling
  # Use a temp file for output since we need to run in background
  tmp_output="$3.out.$$"

  # Run expect script in background, redirect output to temp file
  "$1" > "$tmp_output" 2>/dev/null &
  expect_pid=$!

  # Set up watchdog timer
  (
    sleep $TIMEOUT
    # First try SIGTERM
    kill -TERM $expect_pid 2>/dev/null
    sleep $KILL_AFTER
    # Then SIGKILL if still running
    kill -KILL $expect_pid 2>/dev/null
  ) &
  watchdog_pid=$!

  # Wait for expect script to finish
  wait $expect_pid 2>/dev/null
  exit_code=$?

  # Kill watchdog (it's no longer needed)
  kill $watchdog_pid 2>/dev/null
  wait $watchdog_pid 2>/dev/null

  # Read output from temp file
  if [ -f "$tmp_output" ]; then
    output=$(cat "$tmp_output")
    rm -f "$tmp_output"
  fi
fi

if [ $exit_code -ne 0 ]; then
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

proc getRealUsageData*(): (int, string, int, string, bool) =
  ## Get real usage data from claude /config - NON-BLOCKING.
  ##
  ## Always returns immediately with cached data (even if stale).
  ## If cache is stale, spawns a background daemon to refresh it.
  ## Next statusline update will get fresh data.
  ##
  ## Returns: (session%, sessionReset, weekly%, weeklyReset, isVeryStale)
  ## isVeryStale is true if cache is >5 hours old or missing
  ##
  ## Guards against stacking:
  ## - Lock file prevents multiple concurrent fetches
  ## - Stale locks (>90s) are automatically cleaned up
  ## - 30s timeout kills hung expect scripts

  let scriptPath = getAppDir() / "get_usage.exp"
  if not fileExists(scriptPath):
    return (0, "", 0, "", true)

  let cacheDir = getTempDir() / "heads-up-claude"
  let cachePath = cacheDir / "usage_cache.json"
  let lockPath = cacheDir / "usage.lock"

  # Ensure cache directory exists
  try:
    createDir(cacheDir)
  except:
    return (0, "", 0, "", true)

  # Clean up stale locks (from crashed/timed-out processes)
  cleanStaleLock(lockPath)

  # Read cache (may be stale or missing)
  let (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, cacheValid, ageSeconds) = readCache(cachePath)

  # Determine if data is very stale (>5 hours old or missing)
  let isVeryStale = ageSeconds < 0 or ageSeconds > CACHE_VERY_STALE_SECONDS

  # If cache is stale and no refresh in progress, spawn background refresh
  # Lock is a directory (for atomic creation via mkdir)
  if not cacheValid and not dirExists(lockPath & ".d"):
    spawnBackgroundRefresh(scriptPath, cachePath, lockPath)

  # Always return immediately with whatever we have
  return (cachedSession, cachedSessionReset, cachedWeekly, cachedWeeklyReset, isVeryStale)
