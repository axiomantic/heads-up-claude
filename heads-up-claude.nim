# Recompile with:
#   cd ~/.claude && nim c statusline.nim
#
# Input JSON format (from stdin):
# {
#   "session_id": "a2ada66d-94d4-4a1a-82a3-e1aae6a0c868",
#   "transcript_path": "/Users/user/.claude/projects/-Users-user-Development-project/session-id.jsonl",
#   "cwd": "/Users/user/.claude",  # Where the statusline script runs from
#   "model": {
#     "id": "claude-sonnet-4-5-20250929",
#     "display_name": "Sonnet 4.5"
#   },
#   "workspace": {
#     "current_dir": "/Users/user/.claude",  # Where the script runs
#     "project_dir": "/Users/user/Development/project"  # Actual project directory
#   },
#   "version": "2.0.25",
#   "output_style": {"name": "default"},
#   "cost": {
#     "total_cost_usd": 2.05,
#     "total_duration_ms": 2611417,
#     "total_api_duration_ms": 559530,
#     "total_lines_added": 294,
#     "total_lines_removed": 124
#   },
#   "exceeds_200k_tokens": false
# }

import std/[json, os, strutils, osproc, terminal, times, streams, options, tables, md5, parseopt]

type
  PlanType = enum
    Pro, Max5x, Max20x

  PlanLimits = object
    name: string
    fiveHourMessages: int  # Approximate messages per 5-hour window
    weeklyHoursMin: int    # Minimum weekly hours
    weeklyHoursMax: int    # Maximum weekly hours

  FileCache = object
    modTime: Time
    contextTokens: int  # Approximate current context size
    cacheReadTokens: int  # Cache read tokens
    apiTokens: int  # Total API tokens for 5-hour window tracking
    firstTimestamp: Option[DateTime]
    lastTimestamp: Option[DateTime]
    messageCount: int  # Number of messages in session

const
  PLAN_INFO = [
    PlanLimits(name: "Pro", fiveHourMessages: 45, weeklyHoursMin: 40, weeklyHoursMax: 80),
    PlanLimits(name: "Max 5x", fiveHourMessages: 225, weeklyHoursMin: 140, weeklyHoursMax: 280),
    PlanLimits(name: "Max 20x", fiveHourMessages: 900, weeklyHoursMin: 240, weeklyHoursMax: 480)
  ]

  # Default weekly reset: Wednesday at 6pm Central (23:00 UTC)
  DEFAULT_WEEKLY_RESET_DAY = 2  # Wednesday (0=Monday in Nim's WeekDay enum)
  DEFAULT_WEEKLY_RESET_HOUR_UTC = 23  # 6pm Central = 11pm UTC (CST) or 12am UTC (CDT)

# Global variables for configuration (set from command line)
var gWeeklyResetDay = DEFAULT_WEEKLY_RESET_DAY
var gWeeklyResetHourUTC = DEFAULT_WEEKLY_RESET_HOUR_UTC
var gUseEmoji = true  # Default to using emoji

proc getGitBranch(dir: string): string =
  try:
    let (output, exitCode) = execCmdEx("git -C " & quoteShell(dir) & " rev-parse --abbrev-ref HEAD 2>/dev/null")
    if exitCode == 0:
      result = output.strip()
    else:
      result = ""
  except:
    result = ""

proc formatTokenCount(count: int): string =
  if count >= 1000:
    result = formatFloat(count.float / 1000.0, ffDecimal, 1) & "K"
  else:
    result = $count

proc getFirstTimestampAndContextTokens(transcriptPath: string): (Option[DateTime], Option[DateTime], int, int, int, int) =
  ## Read the first and last timestamps and calculate token usage from the transcript file
  ## Returns (firstTimestamp, lastTimestamp, contextTokens, cacheReadTokens, totalApiTokens, messageCount)
  ## - firstTimestamp: Time of first message in session
  ## - lastTimestamp: Time of most recent message in session
  ## - contextTokens: Approximate current context size (from last message's cache_read + new tokens)
  ## - cacheReadTokens: Cache hits from last message
  ## - totalApiTokens: Sum of all API tokens after last summary (for 5-hour window tracking)
  ## - messageCount: Number of messages after last summary
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

        # Get first and last timestamps
        if entry.hasKey("timestamp"):
          let ts = entry["timestamp"].getStr()
          let parsedTs = parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc())
          if firstTimestamp.isNone:
            firstTimestamp = some(parsedTs)
          lastTimestamp = some(parsedTs)

        # Reset counters when we hit a summary (compact marker)
        if entry.hasKey("type") and entry["type"].getStr() == "summary":
          tokensAfterLastSummary = 0
          messageCount = 0
          continue

        # Count messages after last summary
        if entry.hasKey("type") and (entry["type"].getStr() == "user" or entry["type"].getStr() == "assistant"):
          messageCount += 1

        # Sum tokens from usage field (for API usage tracking / 5-hour window)
        if entry.hasKey("message") and entry["message"].hasKey("usage"):
          let usage = entry["message"]["usage"]

          # Track cache read tokens from last message (this approximates context size)
          if usage.hasKey("cache_read_input_tokens"):
            lastCacheReadTokens = usage["cache_read_input_tokens"].getInt()

          # Track new tokens from last message
          lastNewTokens = 0
          if usage.hasKey("input_tokens"):
            lastNewTokens += usage["input_tokens"].getInt()
          if usage.hasKey("cache_creation_input_tokens"):
            lastNewTokens += usage["cache_creation_input_tokens"].getInt()
          if usage.hasKey("output_tokens"):
            lastNewTokens += usage["output_tokens"].getInt()

          # Sum all API tokens for 5-hour window tracking
          tokensAfterLastSummary += lastNewTokens
      except:
        continue

    # Context size is approximately: cache_read (existing context) + new tokens from last exchange
    let contextTokens = lastCacheReadTokens + lastNewTokens

    return (firstTimestamp, lastTimestamp, contextTokens, lastCacheReadTokens, tokensAfterLastSummary, messageCount)
  except:
    return (none(DateTime), none(DateTime), 0, 0, 0, 0)

proc roundToHour(dt: DateTime): DateTime =
  ## Round timestamp down to the nearest hour (like claude-code-monitor)
  result = dt
  result.minute = 0
  result.second = 0
  result.nanosecond = 0

proc calculateWindowEnd(firstTimestamp: DateTime): DateTime =
  ## Round to hour and add 5 hours (matching claude-code-monitor behavior)
  let startTime = roundToHour(firstTimestamp)
  result = startTime + initDuration(hours = 5)

proc getCacheDir(): string =
  ## Get cache directory path, creating it if needed
  let home = getEnv("HOME")
  result = home / ".cache" / "claude-statusline"
  if not dirExists(result):
    createDir(result)

proc getCacheKey(filePath: string, modTime: Time): string =
  ## Generate cache key from file path and mod time
  result = getMD5(filePath & $modTime.toUnix())

proc loadCache(): Table[string, FileCache] =
  ## Load cache from disk
  result = initTable[string, FileCache]()
  let cacheFile = getCacheDir() / "file-cache.json"
  if not fileExists(cacheFile):
    return

  try:
    let cacheData = parseJson(readFile(cacheFile))
    for key, val in cacheData.pairs:
      var cache = FileCache()
      cache.modTime = fromUnix(val["modTime"].getInt())
      cache.contextTokens = val.getOrDefault("contextTokens").getInt()
      cache.cacheReadTokens = val.getOrDefault("cacheReadTokens").getInt()
      cache.apiTokens = val.getOrDefault("apiTokens").getInt()
      cache.messageCount = val.getOrDefault("messageCount").getInt()
      if val.hasKey("firstTimestamp") and val["firstTimestamp"].kind != JNull:
        let ts = val["firstTimestamp"].getStr()
        cache.firstTimestamp = some(parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))
      else:
        cache.firstTimestamp = none(DateTime)
      if val.hasKey("lastTimestamp") and val["lastTimestamp"].kind != JNull:
        let ts = val["lastTimestamp"].getStr()
        cache.lastTimestamp = some(parse(ts, "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'", utc()))
      else:
        cache.lastTimestamp = none(DateTime)
      result[key] = cache
  except:
    discard

proc saveCache(cache: Table[string, FileCache]) =
  ## Save cache to disk
  let cacheFile = getCacheDir() / "file-cache.json"
  var cacheData = newJObject()

  for key, val in cache.pairs:
    var entry = newJObject()
    entry["modTime"] = newJInt(val.modTime.toUnix())
    entry["contextTokens"] = newJInt(val.contextTokens)
    entry["cacheReadTokens"] = newJInt(val.cacheReadTokens)
    entry["apiTokens"] = newJInt(val.apiTokens)
    entry["messageCount"] = newJInt(val.messageCount)
    if val.firstTimestamp.isSome:
      entry["firstTimestamp"] = newJString(format(val.firstTimestamp.get(), "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"))
    else:
      entry["firstTimestamp"] = newJNull()
    if val.lastTimestamp.isSome:
      entry["lastTimestamp"] = newJString(format(val.lastTimestamp.get(), "yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'"))
    else:
      entry["lastTimestamp"] = newJNull()
    cacheData[key] = entry

  try:
    writeFile(cacheFile, $cacheData)
  except:
    discard

proc getNextWeeklyReset(): DateTime =
  ## Calculate next weekly reset time using configured reset day/hour
  let now = now().utc()

  # Start with today at the reset hour
  var resetTime = now
  resetTime.hour = gWeeklyResetHourUTC
  resetTime.minute = 0
  resetTime.second = 0
  resetTime.nanosecond = 0

  # Calculate days until next reset day
  let currentWeekday = now.weekday.ord  # 0=Monday, 1=Tuesday, etc.
  let daysUntilReset = (gWeeklyResetDay - currentWeekday + 7) mod 7

  if daysUntilReset == 0:
    # Today IS the reset day
    if now.hour >= gWeeklyResetHourUTC:
      # Past reset time today, next reset is 7 days from now
      resetTime = resetTime + initDuration(days = 7)
    # else: reset is later today, use resetTime as-is
  else:
    # Not reset day, add the days until next reset
    resetTime = resetTime + initDuration(days = daysUntilReset)

  return resetTime

proc getFileTokensAndTimestamp(filePath: string, cache: var Table[string, FileCache]): FileCache =
  ## Get all session data from file, using cache if possible
  try:
    var result = FileCache()
    if not fileExists(filePath):
      return result

    let modTime = getLastModificationTime(filePath)
    let cacheKey = getCacheKey(filePath, modTime)

    # Check if cached
    if cache.hasKey(cacheKey):
      return cache[cacheKey]

    # Not cached - calculate
    let (firstTs, lastTs, contextTokens, cacheReadTokens, apiTokens, messageCount) = getFirstTimestampAndContextTokens(filePath)

    # Store in cache
    result.modTime = modTime
    result.contextTokens = contextTokens
    result.cacheReadTokens = cacheReadTokens
    result.apiTokens = apiTokens
    result.firstTimestamp = firstTs
    result.lastTimestamp = lastTs
    result.messageCount = messageCount
    cache[cacheKey] = result

    return result
  except:
    return FileCache()

proc calculate5HourAndWeeklyUsage(projectsDir: string, cache: var Table[string, FileCache], currentPlan: PlanType): (int, int, string, float, int, string) =
  ## Calculate both 5-hour window and weekly usage
  ## Returns: (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly)
  let now = now().utc()

  # Calculate the most recent weekly reset time
  let nextReset = getNextWeeklyReset()
  let lastReset = nextReset - initDuration(days = 7)

  var messages5hr = 0
  var hoursWeekly = 0.0
  var latestWindowEnd = none(DateTime)
  var earliestThisWeek = none(DateTime)

  # Find all JSONL files in project directory
  try:
    for file in walkFiles(projectsDir / "*.jsonl"):
      let sessionData = getFileTokensAndTimestamp(file, cache)

      if sessionData.firstTimestamp.isSome:
        let firstTs = sessionData.firstTimestamp.get()

        # 5-hour window tracking (message count)
        let windowEnd = calculateWindowEnd(firstTs)
        if windowEnd > now:
          messages5hr += sessionData.messageCount
          # Track the LATEST window end (the one that expires last)
          if latestWindowEnd.isNone or windowEnd > latestWindowEnd.get():
            latestWindowEnd = some(windowEnd)

        # Weekly tracking (usage hours) - only count sessions within current week
        if sessionData.lastTimestamp.isSome:
          let lastTs = sessionData.lastTimestamp.get()
          # Check if any part of the session falls within the current week
          if lastTs >= lastReset:
            # Calculate duration, but only count the portion within the current week
            let effectiveStart = if firstTs < lastReset: lastReset else: firstTs
            let duration = (lastTs - effectiveStart).inSeconds.float / 3600.0  # Convert to hours
            if duration > 0:
              hoursWeekly += duration

              if earliestThisWeek.isNone or effectiveStart < earliestThisWeek.get():
                earliestThisWeek = some(effectiveStart)
  except:
    discard

  # Get plan limits
  let limits = PLAN_INFO[ord(currentPlan)]

  # 5-hour percentage (messages)
  let percent5hr = if messages5hr > 0: (messages5hr * 100) div limits.fiveHourMessages else: 0

  # Weekly percentage (hours - use minimum as threshold)
  let percentWeekly = if hoursWeekly > 0: int((hoursWeekly * 100.0) / limits.weeklyHoursMin.float) else: 0

  # Format time remaining for 5-hour window
  var time5hr = ""
  if latestWindowEnd.isSome:
    let remaining = latestWindowEnd.get() - now
    if remaining.inSeconds > 0:
      let hoursLeft = remaining.inHours
      let minsLeft = remaining.inMinutes mod 60
      if hoursLeft > 0:
        time5hr = $hoursLeft & "h" & $minsLeft & "m"
      else:
        time5hr = $minsLeft & "m"

  # Format time remaining for weekly window (until next reset)
  var timeWeekly = ""
  let remaining = nextReset - now
  if remaining.inSeconds > 0:
    let daysLeft = remaining.inDays
    let hoursLeft = remaining.inHours mod 24
    if daysLeft > 0:
      timeWeekly = $daysLeft & "d" & $hoursLeft & "h"
    else:
      timeWeekly = $hoursLeft & "h"

  return (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly)

proc detectPlan(projectsDir: string): PlanType =
  ## Auto-detect plan by analyzing message counts in 5-hour windows
  var cache = loadCache()
  defer: saveCache(cache)

  let now = now().utc()
  var maxMessages5hr = 0

  # Find the highest message count in any 5-hour window
  try:
    for file in walkFiles(projectsDir / "*.jsonl"):
      let sessionData = getFileTokensAndTimestamp(file, cache)
      if sessionData.firstTimestamp.isSome:
        let windowEnd = calculateWindowEnd(sessionData.firstTimestamp.get())
        if windowEnd > now:
          if sessionData.messageCount > maxMessages5hr:
            maxMessages5hr = sessionData.messageCount
  except:
    discard

  # Infer plan based on observed message counts
  # If we've seen more than 225 messages, likely Max 20x
  # If we've seen more than 45 messages, likely Max 5x or Max 20x
  if maxMessages5hr > 225:
    return Max20x
  elif maxMessages5hr > 45:
    return Max5x
  else:
    return Pro

proc parseResetTime(input: string): Option[(int, int)] =
  ## Parse reset time from user input
  ## Returns (weekday, hour_utc) where weekday is 0=Monday, 6=Sunday
  ## Accepts formats like:
  ##   "Wed 5:59 PM"
  ##   "Resets Wed 5:59 PM"
  ##   "Wednesday 17:59"

  let normalized = input.toLowerAscii().strip()

  # Extract day of week
  var weekday = -1
  if "mon" in normalized: weekday = 0
  elif "tue" in normalized: weekday = 1
  elif "wed" in normalized: weekday = 2
  elif "thu" in normalized: weekday = 3
  elif "fri" in normalized: weekday = 4
  elif "sat" in normalized: weekday = 5
  elif "sun" in normalized: weekday = 6

  if weekday == -1:
    return none((int, int))

  # Try to extract time - look for patterns like "5:59 PM" or "17:59"
  var hour = -1
  var minute = 0
  var isPM = false

  # Check for AM/PM
  if " pm" in normalized or "pm" in normalized:
    isPM = true

  # Find time pattern HH:MM
  var timeStr = ""
  var foundColon = false
  for i, c in normalized:
    if c in {'0'..'9', ':'}:
      timeStr.add(c)
      if c == ':':
        foundColon = true
    elif foundColon and timeStr.len > 0:
      break

  if foundColon and timeStr.len > 0:
    let parts = timeStr.split(':')
    if parts.len == 2:
      try:
        hour = parseInt(parts[0])
        minute = parseInt(parts[1])

        # Convert to 24-hour if PM
        if isPM and hour < 12:
          hour += 12
        elif not isPM and hour == 12:
          hour = 0
      except:
        return none((int, int))

  if hour < 0 or hour > 23 or minute < 0 or minute > 59:
    return none((int, int))

  # For now, assume US Central time (UTC-6 in winter, UTC-5 in summer)
  # Convert to UTC by adding 6 hours (approximate - doesn't handle DST perfectly)
  var hourUTC = hour + 6
  if hourUTC >= 24:
    hourUTC -= 24

  return some((weekday, hourUTC))

proc formatResetTime(weekday: int, hourUTC: int): string =
  ## Format reset time in human-readable format
  let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
  let dayName = days[weekday]

  # Convert UTC to Central time (approximate)
  var hourCentral = hourUTC - 6
  if hourCentral < 0:
    hourCentral += 24

  let hour12 = if hourCentral == 0: 12
               elif hourCentral > 12: hourCentral - 12
               else: hourCentral
  let ampm = if hourCentral < 12: "AM" else: "PM"

  return dayName & " " & $hour12 & ":00 " & ampm & " Central (" & $hourUTC & ":00 UTC)"

proc promptResetTime(): DateTime =
  ## Prompt user for weekly reset time, returns next reset DateTime in UTC
  echo ""
  echo "Weekly Reset Time"
  echo "================="
  echo "Visit https://claude.ai/settings/usage to see your reset time."
  echo "Copy and paste the reset time (e.g., \"Resets Wed 5:59 PM\"),"
  echo "or enter it in a format like \"Wed 5:59 PM\" or \"Wednesday 17:59\"."
  echo ""

  while true:
    stdout.write("Reset time (default: Wed 6:00 PM Central): ")
    stdout.flushFile()

    let input = stdin.readLine().strip()

    var weekday, hourUTC: int

    # Default to Wednesday 6 PM Central
    if input.len == 0:
      weekday = 2  # Wednesday
      hourUTC = 23  # 23:00 UTC (6 PM Central in winter)
    else:
      let parsed = parseResetTime(input)
      if parsed.isNone:
        echo "Could not parse reset time. Please try again."
        echo "Examples: \"Wed 5:59 PM\", \"Wednesday 17:59\", \"Resets Thu 6:00 PM\""
        echo ""
        continue

      (weekday, hourUTC) = parsed.get()
      echo ""
      echo "Parsed as: ", formatResetTime(weekday, hourUTC)
      stdout.write("Is this correct? [Y/n]: ")
      stdout.flushFile()

      let confirm = stdin.readLine().strip().toLowerAscii()
      if confirm.len > 0 and confirm[0] != 'y':
        echo "Let's try again."
        echo ""
        continue

    # Build a DateTime for the next reset
    let now = now().utc()
    var resetTime = now
    resetTime.hour = hourUTC
    resetTime.minute = 0
    resetTime.second = 0
    resetTime.nanosecond = 0

    let currentWeekday = now.weekday.ord
    let daysUntilReset = (weekday - currentWeekday + 7) mod 7

    if daysUntilReset == 0:
      if now.hour >= hourUTC:
        resetTime = resetTime + initDuration(days = 7)
    else:
      resetTime = resetTime + initDuration(days = daysUntilReset)

    return resetTime

proc promptPlanSelection(detectedPlan: PlanType): PlanType =
  ## Interactive plan selection with auto-detected default
  echo "Claude Code Plan"
  echo "================"
  echo ""
  echo "Select your Claude plan:"
  echo "  1. Pro (45 msgs/5hr, 40-80 hrs/week)"
  echo "  2. Max 5x (225 msgs/5hr, 140-280 hrs/week)"
  echo "  3. Max 20x (900 msgs/5hr, 240-480 hrs/week)"
  echo ""
  echo "Auto-detected: ", PLAN_INFO[ord(detectedPlan)].name, " (option ", ord(detectedPlan) + 1, ")"
  stdout.write("Enter choice [1-3, default=", ord(detectedPlan) + 1, "]: ")
  stdout.flushFile()

  let input = stdin.readLine().strip()
  if input.len == 0:
    return detectedPlan

  try:
    let choice = parseInt(input)
    case choice
    of 1: return Pro
    of 2: return Max5x
    of 3: return Max20x
    else:
      echo "Invalid choice, using detected plan"
      return detectedPlan
  except:
    echo "Invalid input, using detected plan"
    return detectedPlan

proc installStatusLine(selectedPlan: PlanType, resetTime: DateTime, useEmoji: bool) =
  ## Install statusline configuration to settings.json
  let settingsPath = getEnv("HOME") / ".claude" / "settings.json"
  let statuslinePath = getEnv("HOME") / ".claude" / "statusline"

  # Read existing settings
  var settings: JsonNode
  if fileExists(settingsPath):
    try:
      settings = parseJson(readFile(settingsPath))
    except:
      settings = newJObject()
  else:
    settings = newJObject()

  # Update statusLine configuration with plan and reset time parameters
  let planArg = case selectedPlan
    of Pro: "pro"
    of Max5x: "max5x"
    of Max20x: "max20x"

  # Format reset time as ISO string
  let resetISO = format(resetTime, "yyyy-MM-dd'T'HH:mm:sszzz")

  # Build command with optional --no-emoji flag
  var command = statuslinePath & " --plan=" & planArg & " --reset-time=\"" & resetISO & "\""
  if not useEmoji:
    command.add(" --no-emoji")

  settings["statusLine"] = %* {
    "type": "command",
    "command": command
  }

  # Write back to settings.json
  writeFile(settingsPath, settings.pretty())

  echo ""
  echo "✓ Installed statusline to ", settingsPath
  echo "✓ Plan configured: ", PLAN_INFO[ord(selectedPlan)].name
  echo "✓ Reset time: ", formatResetTime(resetTime.weekday.ord, resetTime.hour)
  echo "✓ Display style: ", if useEmoji: "emoji" else: "text"
  echo ""
  echo "Restart Claude Code to see the new statusline!"
  echo ""
  echo "To change your plan or reset time later, run:"
  echo "  ~/.claude/statusline --install"

proc showHelp() =
  ## Display help message
  echo "Claude Code Statusline"
  echo "======================"
  echo ""
  echo "A custom statusline for Claude Code that shows token usage, rate limits, and weekly usage."
  echo ""
  echo "Usage:"
  echo "  statusline [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --install               Run interactive installer to configure settings.json"
  echo "  --plan=PLAN             Set plan tier: pro, max5x, or max20x"
  echo "  --reset-time=DATETIME   Set weekly reset time (ISO format with timezone)"
  echo "                          Example: --reset-time=\"2025-10-30T18:00:00-05:00\""
  echo "  --no-emoji              Use descriptive text instead of emoji"
  echo "  --help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  # Run installer"
  echo "  ~/.claude/statusline --install"
  echo ""
  echo "  # Use in settings.json with custom options"
  echo "  ~/.claude/statusline --plan=max20x --reset-time=\"2025-10-30T23:00:00+00:00\" --no-emoji"
  echo ""
  echo "For more information, see ~/Development/heads-up-claude/README.md"

proc runInstall(projectsDir: string) =
  ## Run the installation process
  echo "Claude Code Statusline Installer"
  echo "================================="
  echo ""

  # Detect plan
  let detected = detectPlan(projectsDir)

  # Prompt for confirmation/selection
  let selected = promptPlanSelection(detected)

  # Prompt for reset time
  let resetTime = promptResetTime()

  # Prompt for emoji preference
  echo ""
  echo "Display Style"
  echo "============="
  echo ""
  echo "Choose display style:"
  echo ""
  echo "1. With emoji (default):"
  echo "   💬 104.6K 65% 🟢 104.0K cached | 🕐 178/900 19% (3h22m) | 📅 19.3h/240h 8% (5d23h)"
  echo ""
  echo "2. No emoji (descriptive text):"
  echo "   CTX 104.6K 65% CACHE 104.0K | 5HR 178/900 19% (3h22m) | WK 19.3h/240h 8% (5d23h)"
  echo ""
  stdout.write("Use emoji? [Y/n]: ")
  stdout.flushFile()

  let emojiInput = stdin.readLine().strip().toLowerAscii()
  let useEmoji = emojiInput.len == 0 or emojiInput[0] == 'y'

  # Install
  installStatusLine(selected, resetTime, useEmoji)

proc main() =
  # Parse command line arguments
  var planArg = ""
  var installMode = false
  var showHelpMode = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "plan":
        planArg = p.val
      of "install":
        installMode = true
      of "help", "h":
        showHelpMode = true
      of "no-emoji":
        gUseEmoji = false
      of "reset-time":
        # Parse ISO format datetime string
        var parsed = false
        try:
          # Try parsing with timezone
          let resetTime = parse(p.val, "yyyy-MM-dd'T'HH:mm:sszzz")
          let resetUTC = resetTime.utc()
          gWeeklyResetDay = resetUTC.weekday.ord
          gWeeklyResetHourUTC = resetUTC.hour
          parsed = true
        except CatchableError:
          discard

        if not parsed:
          try:
            # Try parsing without timezone (assume local time, convert to UTC)
            let resetTimeLocal = parse(p.val, "yyyy-MM-dd'T'HH:mm:ss")
            let resetUTC = resetTimeLocal.utc()
            gWeeklyResetDay = resetUTC.weekday.ord
            gWeeklyResetHourUTC = resetUTC.hour
            parsed = true
          except CatchableError:
            discard

        if not parsed:
          echo "Error: Could not parse --reset-time value: ", p.val
          echo "Expected ISO format like: 2025-10-30T18:00:00-05:00 or 2025-10-30T18:00:00"
          quit(1)
      else:
        discard
    else:
      discard

  # Handle help mode
  if showHelpMode:
    showHelp()
    return

  # Handle install mode
  if installMode:
    # Find a project directory to scan
    let home = getEnv("HOME")
    let claudeProjects = home / ".claude" / "projects"

    # Find first project directory with JSONL files
    var projectsDir = ""
    if dirExists(claudeProjects):
      for kind, path in walkDir(claudeProjects):
        if kind == pcDir:
          projectsDir = path
          break

    if projectsDir.len > 0:
      runInstall(projectsDir)
    else:
      echo "Error: Could not find Claude projects directory"
      echo "Expected at: ", claudeProjects
    return

  # Determine current plan
  var currentPlan = Max20x  # default
  if planArg.len > 0:
    case planArg.toLowerAscii()
    of "pro":
      currentPlan = Pro
    of "max5x", "max5", "max-5x":
      currentPlan = Max5x
    of "max20x", "max20", "max-20x":
      currentPlan = Max20x
    else:
      discard  # use default

  # Read JSON from stdin
  let input = stdin.readAll()
  # Debug: write input to file
  writeFile("/tmp/statusline-input.json", input)
  let data = parseJson(input)

  # Extract data
  let transcriptPath = data["transcript_path"].getStr()
  let cwd = data["workspace"]["current_dir"].getStr()
  let projectDir = data["workspace"]["project_dir"].getStr()
  let model = data["model"]["display_name"].getStr()

  # Get project directory (relative to home if applicable)
  let home = getEnv("HOME")
  let displayProjectDir =
    if projectDir.startsWith(home):
      "~" & projectDir[home.len..^1]
    else:
      projectDir

  # Get git branch (use project_dir, not cwd which may be where the statusline script runs)
  let branch = getGitBranch(projectDir)

  # Calculate current conversation context size and cache usage
  let (_, _, conversationTokens, cacheReadTokens, _, _) = getFirstTimestampAndContextTokens(transcriptPath)

  # Calculate percentage until auto-compact (threshold: from env or 160K tokens)
  let compactThreshold = try:
    parseInt(getEnv("CLAUDE_AUTO_COMPACT_THRESHOLD", "160000"))
  except:
    160000
  let conversationPercentUsed = if conversationTokens > 0: (conversationTokens * 100) div compactThreshold else: 0

  # Calculate 5-hour and weekly window usage across all sessions
  let projectsDir = parentDir(transcriptPath)
  var cache = loadCache()
  defer: saveCache(cache)
  let (messages5hr, percent5hr, time5hr, hoursWeekly, percentWeekly, timeWeekly) = calculate5HourAndWeeklyUsage(projectsDir, cache, currentPlan)

  # Get plan info
  let limits = PLAN_INFO[ord(currentPlan)]

  # Output with colors (left-justified, simple)
  stdout.write("\x1b[34m", displayProjectDir, "\x1b[0m")

  if branch.len > 0:
    stdout.write(" | ")
    stdout.write("\x1b[35m", branch, "\x1b[0m")

  stdout.write(" | ")

  # Show plan
  stdout.write("\x1b[35m", limits.name, "\x1b[0m")

  # Check for thinking mode (extended thinking)
  var modelDisplay = model
  if data.hasKey("model") and data["model"].hasKey("thinking"):
    let thinkingEnabled = data["model"]["thinking"].getBool()
    if thinkingEnabled:
      modelDisplay = "\xf0\x9f\xa7\xa0 " & model  # 🧠 emoji

  stdout.write(" | ")
  stdout.write("\x1b[36m", modelDisplay, "\x1b[0m")

  # Show current conversation context
  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x92\xac ")  # 💬 emoji for conversation
  else:
    stdout.write("CTX ")
  let conversationTokenDisplay = formatTokenCount(conversationTokens)

  # Color based on how close to compact (using percentUsed)
  if conversationPercentUsed >= 100:
    stdout.write("\x1b[1;91m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ compact imminent\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN compact imminent\x1b[0m")
  elif conversationPercentUsed >= 90:
    stdout.write("\x1b[1;91m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", conversationPercentUsed, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", conversationPercentUsed, "%\x1b[0m")
  elif conversationPercentUsed >= 80:
    stdout.write("\x1b[31m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", conversationPercentUsed, "%\x1b[0m")
  else:
    stdout.write("\x1b[33m", conversationTokenDisplay, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[33m", conversationPercentUsed, "%\x1b[0m")

  # Show cache read tokens
  if cacheReadTokens > 0:
    let cacheDisplay = formatTokenCount(cacheReadTokens)
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\xf0\x9f\x9f\xa2 ")  # 🟢 emoji
    else:
      stdout.write("CACHE ")
    stdout.write("\x1b[32m", cacheDisplay)
    if not gUseEmoji:
      stdout.write(" cached")
    stdout.write("\x1b[0m")

  # Show 5-hour window usage
  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x95\x90 ")  # 🕐 emoji for 5-hour window
  else:
    stdout.write("5HR ")

  # Color based on how close to limit (using percent5hr = percent USED)
  if percent5hr >= 100:
    stdout.write("\x1b[1;91m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ limit exceeded\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN limit exceeded\x1b[0m")
  elif percent5hr >= 90:
    stdout.write("\x1b[1;91m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", percent5hr, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", percent5hr, "%\x1b[0m")
  elif percent5hr >= 80:
    stdout.write("\x1b[31m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", percent5hr, "%\x1b[0m")
  else:
    stdout.write("\x1b[36m", messages5hr, "/", limits.fiveHourMessages, "\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[36m", percent5hr, "%\x1b[0m")

  # Add time remaining for 5-hour window
  if time5hr.len > 0:
    stdout.write(" (")
    stdout.write("\x1b[36m", time5hr, "\x1b[0m")
    stdout.write(")")

  # Show weekly usage
  stdout.write(" | ")
  if gUseEmoji:
    stdout.write("\xf0\x9f\x93\x85 ")  # 📅 emoji for weekly
  else:
    stdout.write("WK ")

  # Format hours with 1 decimal place
  let hoursDisplay = formatFloat(hoursWeekly, ffDecimal, 1)

  # Color based on how close to limit (using percentWeekly = percent USED)
  if percentWeekly >= 100:
    stdout.write("\x1b[1;91m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ limit exceeded\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN limit exceeded\x1b[0m")
  elif percentWeekly >= 90:
    stdout.write("\x1b[1;91m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    if gUseEmoji:
      stdout.write("\x1b[1;91m⚠️ ", percentWeekly, "%\x1b[0m")
    else:
      stdout.write("\x1b[1;91mWARN ", percentWeekly, "%\x1b[0m")
  elif percentWeekly >= 80:
    stdout.write("\x1b[31m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[31m", percentWeekly, "%\x1b[0m")
  else:
    stdout.write("\x1b[36m", hoursDisplay, "h/", limits.weeklyHoursMin, "h\x1b[0m")
    stdout.write(" ")
    stdout.write("\x1b[36m", percentWeekly, "%\x1b[0m")

  # Add time remaining for weekly window
  if timeWeekly.len > 0:
    stdout.write(" (")
    stdout.write("\x1b[36m", timeWeekly, "\x1b[0m")
    stdout.write(")")

when isMainModule:
  main()
